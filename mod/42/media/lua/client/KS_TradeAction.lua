require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISTransferAction"
require "KS_TradeValuation"
require "KS_SurvivorRuntime"
require "KS_Persistence"

local Trade = {}
_G.KnoxTradeActions = Trade
local Action = ISBaseTimedAction:derive("KnoxTradeAction")

local function safe(call, fallback)
    local ok, result = pcall(call)
    if ok then return result end
    return fallback
end

local function localOnly()
    return not isClient() and not isServer()
end

local function reachable(player, npc)
    if player == nil or npc == nil or player:isDead() or npc:isDead()
        or player:getVehicle() ~= nil or npc:getVehicle() ~= nil then return false end
    local p, n = player:getCurrentSquare(), npc:getCurrentSquare()
    if p == nil or n == nil or p:getZ() ~= n:getZ()
        or math.abs(p:getX() - n:getX()) > 1 or math.abs(p:getY() - n:getY()) > 1 then return false end
    return p == n or (not p:isSomethingTo(n) and not n:isSomethingTo(p))
end

local function danger(character)
    return character:hasHitReaction() or character:getSurroundingAttackingZombies() > 0
        or character:isAttacking() or character:isAiming()
end

local function pendingActions(character)
    if not character:getCharacterActions():isEmpty() then return true end
    local queue = ISTimedActionQueue.queues[character]
    return queue ~= nil and #queue.queue > 0
end

local function retireAction(action)
    -- The exchange is queued on the real player, not on its NPC attention
    -- owner. Retire only this exact action; a mixed current queue drains with
    -- permission revoked instead of deleting the player's other work.
    local queue = ISTimedActionQueue.queues[action.character]
    if queue == nil or type(queue.queue) ~= "table" then return end
    local found, onlyOwned = false, #queue.queue > 0
    for _, queued in ipairs(queue.queue) do
        if queued == action then found = true else onlyOwned = false end
    end
    if not found then return end
    if onlyOwned then
        safe(function() ISTimedActionQueue.clear(action.character) end, false)
    elseif queue.current ~= action then
        safe(function()
            action:forceCancel()
            queue:removeFromQueue(action)
        end, false)
    end
end

local function physicalCheck(action)
    if not localOnly() or Trade.failedExchange ~= nil then return false, "trading_unavailable" end
    if action.cancelled or action.finished then return false, action.cancelled or "finished" end
    if KnoxSurvivorRuntime.canInteract ~= nil
        and not KnoxSurvivorRuntime.canInteract(action.survivorId) then
        return false, "survivor_unavailable"
    end
    local identity = action.character:getModData().KnoxSurvivors
    if identity == nil or identity.playerId ~= action.playerId then return false, "player_changed" end
    if KnoxSurvivorRuntime.getCharacter(action.survivorId) ~= action.npc
        or not KnoxPersistence.isSurvivorAlive(action.survivorId) then return false, "survivor_changed" end
    if not reachable(action.character, action.npc) then return false, "out_of_reach" end
    if danger(action.character) or danger(action.npc) then return false, "danger" end
    if action.browsing and pendingActions(action.character) then return false, "player_busy" end
    if pendingActions(action.npc) then return false, "survivor_busy" end
    if action.knoxTradeGuard ~= nil and action.knoxTradeGuard(action) ~= true then
        return false, "exchange_permission_changed"
    end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(action.survivorId) or {}
    if affiliation.kind == "player" or KnoxPersistence.isSurvivorHostileToPlayer(action.survivorId, action.playerId) then
        return false, "relationship_changed"
    end
    return true
end

local function finiteWeight(item)
    local weight = item:getUnequippedWeight()
    if type(weight) ~= "number" or weight ~= weight or weight < 0 or weight == math.huge then return nil end
    return weight
end

local function journalFor(action)
    local journal, ids, incoming, outgoingRoot = {}, {}, {}, {}
    local function add(items, owner, receiver)
        local destination = receiver:getInventory()
        for _, item in ipairs(items) do
            local source, weight, id = item:getContainer(), finiteWeight(item), item:getID()
            if source == nil or weight == nil or id == nil or ids[id] or destination:containsID(id)
                or not source:isRemoveItemAllowed(item) or not destination:isItemAllowed(item)
                or destination:isInside(item) then return false end
            ids[id] = true
            journal[#journal + 1] = { item = item, source = source, destination = destination,
                owner = owner, receiver = receiver }
            incoming[receiver] = (incoming[receiver] or 0) + weight
            -- Nested bag weight reduction is engine-owned. Only credit root items
            -- here; nested outgoing contents can free extra room, never less.
            if source == owner:getInventory() then outgoingRoot[owner] = (outgoingRoot[owner] or 0) + weight end
        end
        return true
    end
    if not add(action.giving, action.character, action.npc)
        or not add(action.taking, action.npc, action.character) then return nil, "inventory_rules_or_id_conflict" end
    for _, actor in ipairs({ action.character, action.npc }) do
        local delta = (incoming[actor] or 0) - (outgoingRoot[actor] or 0)
        if not actor:getInventory():hasRoomFor(actor, delta) then return nil, "not_enough_capacity" end
    end
    return journal
end

local function at(item, container)
    return item:getContainer() == container and container:getItems():contains(item)
end

local function rollback(journal)
    local success = true
    for index = #journal, 1, -1 do
        local entry = journal[index]
        local ok = safe(function()
            if not at(entry.item, entry.source) then
                -- AddItem(instance) natively detaches the same object from its
                -- current container, including a partially completed transfer.
                entry.source:AddItem(entry.item)
            end
            return at(entry.item, entry.source) and not entry.destination:getItems():contains(entry.item)
        end, false)
        success = ok and success
    end
    return success
end

local function capture(id)
    return safe(function() return KnoxPersistence.captureActiveSurvivor(id) end, false) == true
end

local function commit(action)
    local valid, reason = physicalCheck(action)
    if not valid then return false, reason end
    local quote
    if action.mode == "gift" then
        quote, reason = KnoxTradeValuation.quoteGift(action.character, action.survivorId, action.giving)
    else
        quote, reason = KnoxTradeValuation.quote(action.character, action.survivorId, action.giving, action.taking)
    end
    if quote == nil or not quote.acceptable then return false, reason or "offer_no_longer_fair" end
    local journal
    journal, reason = journalFor(action)
    if journal == nil then return false, reason end
    -- Snapshot capability is proven before touching either inventory. The final
    -- snapshot and transfer happen in this one non-yielding completion callback.
    if not capture(action.survivorId) then return false, "capture_unavailable" end
    local previousRecord = KnoxPersistence.getRecord(action.survivorId)
    local ok, failure = pcall(function()
        for _, entry in ipairs(journal) do
            if not at(entry.item, entry.source) then error("source_changed") end
            local result = ISTransferAction:transferItem(entry.owner, entry.item, entry.source, entry.destination, nil)
            if result ~= entry.item or not at(entry.item, entry.destination)
                or entry.source:getItems():contains(entry.item) then error("transfer_receipt_failed") end
        end
        for _, entry in ipairs(journal) do
            if not at(entry.item, entry.destination) or entry.source:getItems():contains(entry.item) then
                error("final_receipt_failed")
            end
        end
        if not capture(action.survivorId) then error("capture_after_exchange_failed") end
    end)
    if not ok then
        local restored = rollback(journal)
        local recorded = restored and capture(action.survivorId)
        if restored and not recorded then
            -- The before-snapshot represents these restored real item owners.
            recorded = safe(function() return KnoxPersistence.setRecord(action.survivorId, previousRecord) end, false)
        end
        if not restored or not recorded then
            -- Keep all original object references for diagnosis/recovery; never
            -- clone replacement items or silently discard a detached item.
            Trade.failedExchange = { survivorId = action.survivorId, journal = journal, reason = tostring(failure) }
            print("[KnoxSurvivors][Trade] RECOVERY_REQUIRED id=" .. action.survivorId .. " reason=" .. tostring(failure))
            return false, "recovery_required"
        end
        print("[KnoxSurvivors][Trade] rolled_back id=" .. action.survivorId .. " reason=" .. tostring(failure))
        return false, "exchange_rolled_back"
    end
    -- Reward failures must not roll back an already captured, verified exchange.
    local rewardOk, rewardError = pcall(function()
        local reward = KnoxPersistence.recordPlayerContribution(action.playerId, action.survivorId,
            action.mode == "gift" and "gift" or "trade", getGameTime():getWorldAgeHours())
        if reward ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.reputation ~= nil then
            KnoxActivityFeed.reputation(action.npc, reward.trustGain)
        end
        return reward
    end)
    if not rewardOk then print("[KnoxSurvivors][Trade] reward_failed id=" .. action.survivorId .. " " .. tostring(rewardError)) end
    print("[KnoxSurvivors][Trade] completed id=" .. action.survivorId .. " mode=" .. tostring(action.mode or "barter")
        .. " given=" .. #action.giving .. " received=" .. #action.taking)
    return true, action.mode == "gift" and "gift_completed" or "completed"
end

function Action:isValid()
    return type(self.knoxTradeGuard) == "function"
        and KnoxSurvivorRuntime.ownsTrade(self.survivorId, self) and safe(function()
        return physicalCheck(self)
    end, false)
end

function Action:waitToStart()
    self.character:faceThisObject(self.npc)
    return self.character:shouldBeTurning()
end

function Action:start()
    self:setActionAnim("Loot")
    self:setAnimVariable("LootPosition", "Mid")
    self:setOverrideHandModels(nil, nil)
end

function Action:finish(success, reason)
    if self.finished then return end
    self.finished, self.success, self.result = true, success, reason
    KnoxSurvivorRuntime.releaseTrade(self.survivorId, self)
    if not success then retireAction(self) end
    if rawget(_G, "ISInventoryPage") ~= nil then ISInventoryPage.renderDirty = true end
end

function Action:stop()
    self:finish(false, self.cancelled or "cancelled")
    ISBaseTimedAction.stop(self)
end

function Action:forceCancel()
    self:finish(false, "queue_cancelled")
end

function Action:perform()
    if self.finished then return end
    local ok, reason = false, "lease_lost"
    if self:isValid() then
        local ran, result, detail = pcall(commit, self)
        ok, reason = ran and result == true, ran and detail or "validation_failed"
        if not ran then print("[KnoxSurvivors][Trade] validation_failed " .. tostring(result)) end
    end
    self:finish(ok, reason)
    ISBaseTimedAction.perform(self)
end

function Trade.beginBrowse(player, survivorId)
    if not localOnly() or Trade.failedExchange ~= nil then return nil, "trading_unavailable" end
    local partner, reason = KnoxTradeValuation.partner(player, survivorId)
    if partner == nil then return nil, reason end
    local queue = ISTimedActionQueue.queues[player]
    if not player:getCharacterActions():isEmpty() or (queue ~= nil and #queue.queue > 0) then return nil, "player_busy" end
    local session = { character = player, npc = partner.npc, survivorId = survivorId,
        playerId = partner.playerId, browsing = true, openedAt = getTimestampMs() }
    function session:isValid()
        return not self.finished and getTimestampMs() >= self.openedAt
            and getTimestampMs() - self.openedAt < 120000
            and type(self.knoxTradeGuard) == "function"
            and KnoxSurvivorRuntime.ownsTrade(self.survivorId, self)
            and safe(function() return physicalCheck(self) end, false)
    end
    local valid
    valid, reason = physicalCheck(session)
    if not valid then return nil, reason end
    if not KnoxSurvivorRuntime.beginTrade(survivorId, session) then return nil, "survivor_busy_or_threatened" end
    return session, "browsing"
end

function Trade.endBrowse(session, reason)
    if session == nil or not session.browsing or session.finished then return end
    session.finished, session.cancelled = true, reason or "closed"
    KnoxSurvivorRuntime.releaseTrade(session.survivorId, session)
end

function Trade.queue(player, survivorId, giving, taking, session, mode)
    if not localOnly() or Trade.failedExchange ~= nil then return nil, "trading_unavailable" end
    if mode ~= nil and mode ~= "gift" then return nil, "invalid_exchange_mode" end
    local quote, reason
    if mode == "gift" then quote, reason = KnoxTradeValuation.quoteGift(player, survivorId, giving)
    else quote, reason = KnoxTradeValuation.quote(player, survivorId, giving, taking) end
    if quote == nil or not quote.acceptable then return nil, reason or "offer_too_low" end
    local queue = ISTimedActionQueue.queues[player]
    if not player:getCharacterActions():isEmpty() or (queue ~= nil and #queue.queue > 0) then return nil, "player_busy" end
    local action = ISBaseTimedAction.new(Action, player)
    action.npc, action.survivorId = KnoxSurvivorRuntime.getCharacter(survivorId), survivorId
    action.playerId = player:getModData().KnoxSurvivors.playerId
    action.giving, action.taking, action.mode, action.maxTime = {}, {}, mode, 90
    for i, item in ipairs(giving) do action.giving[i] = item end
    for i, item in ipairs(taking) do action.taking[i] = item end
    local valid
    valid, reason = physicalCheck(action)
    if not valid then return nil, reason end
    local journal
    journal, reason = journalFor(action)
    if journal == nil then return nil, reason end
    if session ~= nil then
        if not session.browsing or session.character ~= player or session.survivorId ~= survivorId
            or session.npc ~= action.npc or not session:isValid() then return nil, "browsing_expired" end
        Trade.endBrowse(session, "exchange_started")
    end
    if not KnoxSurvivorRuntime.beginTrade(survivorId, action) then return nil, "survivor_busy_or_threatened" end
    local queued, admitted = pcall(ISTimedActionQueue.add, action)
    local present = false
    if queued and admitted ~= nil and admitted == ISTimedActionQueue.queues[player] then
        for _, entry in ipairs(admitted.queue or {}) do
            if entry == action then present = true break end
        end
    end
    if not queued or admitted == nil or admitted ~= ISTimedActionQueue.queues[player]
        or (not present and not (action.finished and action.success))
        or (action.finished and not action.success)
        or (not action.finished and not KnoxSurvivorRuntime.ownsTrade(survivorId, action)) then
        local failure = not queued and "queue_failed" or action.result or "queue_refused"
        action:finish(false, failure)
        retireAction(action)
        return nil, failure
    end
    return action, "queued"
end

return Trade
