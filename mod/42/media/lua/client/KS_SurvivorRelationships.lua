require "KS_Persistence"
require "KS_FactionBaseScouting"
require "KS_FactionSafehouse"
require "KS_ActivityFeed"
require "KS_Settings"
pcall(function() require "KS_DebugLog" end)

-- Group-vs-group and faction-vs-faction conflict telemetry. Encounters are
-- frequent; only hostile turns, ally call-ups and faction consequences log,
-- throttled per pair inside KnoxDebugLog.
local function diagConflict(pairId, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log("faction", pairId, event, details) end)
    end
end

local Relationships = rawget(_G, "KnoxSurvivorRelationships") or {}
_G.KnoxSurvivorRelationships = Relationships

local TAG = "[KnoxSurvivors][Relationships]"
-- Social awareness reaches a little beyond arm's length so independent
-- survivors can converge before they pass one another. Native LOS, same-floor
-- checks and the existing cooldown still gate every encounter.
-- Human contact needs a little more lead time than combat range.  Keep this
-- bounded and same-floor/LOS-gated so survivors can converge naturally without
-- gaining wall- or map-wide awareness.
local AWARENESS_RADIUS = 32
local CAUTIOUS_APPROACH_RADIUS = 20
local NEUTRAL_AVOID_COOLDOWN_HOURS = 1.5
local GREETING_COOLDOWN_HOURS = 6
local ABORT_COOLDOWN_HOURS = 0.5
local GROUP_DEFENSE_RADIUS = 12
local pairStates = {}
local pendingMeetings = {}
local lastGroupAssignmentTick = -60
local groupAssignmentRefreshRequested = false
local lastFactionEvaluationTick = -600
local lastBaseScoutingTick = -600

local ENCOUNTER_LINES = {
    hostile = {
        { "Drop the bag and walk away.", "Take it. Just back off." },
        { "Leave the supplies. Nobody gets hurt.", "Fine. They're yours." },
        { "Don't make this harder than it needs to be.", "All right. Easy." },
    },
    lure = {
        { "I know a quiet place nearby. Come with me.", "I am not following you anywhere." },
        { "There is a safe house past those buildings.", "Keep your distance." },
        { "You look like you could use a better route through town.", "I will find my own way." },
    },
    decline = {
        { "Just passing through.", "Same here. Stay safe." },
        { "I'm better off alone for now.", "Fair enough. Take care." },
        { "Not looking for company.", "Understood. Good luck." },
    },
    greet = {
        { "You all right out here?", "Managing. Stay safe." },
        { "Haven't seen anyone alive in a while.", "Same. Keep your head down." },
        { "Area been quiet for you?", "Quiet enough. For now." },
        { "Need anything before I move on?", "I'm all right. Thanks." },
    },
    recruit = {
        { "We've got room, if you can pull your weight.", "I can. Let's move." },
        { "You'd be safer travelling with us.", "Yeah. I'll come with you." },
        { "We watch each other's backs. Interested?", "Sounds better than being alone." },
    },
    join = {
        { "Hey. You travelling alone?", "Yeah. Safer if we stick together." },
        { "Want to move together for a while?", "All right. Lead on." },
        { "Two sets of eyes beat one.", "Can't argue with that." },
    },
}

local function encounterLine(meeting, response)
    local kind = meeting.outcome
    if meeting.outcome == "join" then
        kind = meeting.joinGroupId ~= nil and "recruit" or "join"
    end
    local bank = ENCOUNTER_LINES[kind] or ENCOUNTER_LINES.greet
    local hash = 0
    local key = tostring(meeting.firstId) .. tostring(meeting.secondId)
        .. tostring(meeting.startedAt or 0)
    for index = 1, #key do hash = (hash * 31 + string.byte(key, index)) % 2147483647 end
    local pair = bank[(hash % #bank) + 1]
    return pair[response and 2 or 1]
end

local function availableForNpcSocial(id, controller)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(id)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    if affiliation ~= nil and affiliation.kind == "player" then
        return false
    end
    if duty == nil or duty.mode == nil then
        return true
    end
    if duty.mode == "companion" then
        return false
    end
    if duty.mode == "base" then
        -- NPC faction residents may make a bounded human contact while they
        -- are genuinely idle. Active work, security and player-owned base
        -- duties remain authoritative and cannot be pulled into encounters.
        return affiliation ~= nil and affiliation.kind == "faction"
            and controller ~= nil
            and (controller.state == "BASE_IDLE"
                or controller.state == "BASE_AMBIENT_REST")
    end
    return true
end

local function pairKey(firstId, secondId)
    return firstId < secondId
        and firstId .. "::" .. secondId
        or secondId .. "::" .. firstId
end

local function fullName(character)
    local descriptor = character:getDescriptor()
    local forename = tostring(descriptor:getForename() or "")
    local surname = tostring(descriptor:getSurname() or "")
    return forename, surname, forename .. " " .. surname
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function canPerceiveHuman(first, second)
    if first == nil or second == nil then
        return false
    end
    local firstSquare = first:getCurrentSquare()
    local secondSquare = second:getCurrentSquare()
    if firstSquare == nil or secondSquare == nil
        or firstSquare:getZ() ~= secondSquare:getZ()
        or distanceSquared(firstSquare, secondSquare) > AWARENESS_RADIUS * AWARENESS_RADIUS then
        return false
    end
    local firstSuccess, firstVisible = pcall(function()
        return first:CanSee(second)
    end)
    if firstSuccess and firstVisible == true then
        return true
    end
    local secondSuccess, secondVisible = pcall(function()
        return second:CanSee(first)
    end)
    return secondSuccess and secondVisible == true
end

function Relationships.canPerceiveHuman(first, second)
    return canPerceiveHuman(first, second)
end

local function counterDelta(current, previous, name)
    return math.max(0, (current[name] or 0) - (previous[name] or 0))
end

local function copyCounters(controller)
    return {
        roam = controller.counts.roam + controller.counts.groupTravel,
        loot = controller.counts.loot,
        combat = controller.counts.combat,
    }
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function pairRoll(firstId, secondId, meetingNumber)
    local text = pairKey(firstId, secondId) .. ":" .. tostring(meetingNumber or 0)
    local value = 23
    for index = 1, #text do
        value = (value * 37 + string.byte(text, index)) % 10007
    end
    return value % 100
end

local function relationshipDisposition(firstId, secondId)
    if KnoxPersistence.getSurvivorDisposition ~= nil then
        return KnoxPersistence.getSurvivorDisposition(firstId, secondId)
    end
    local record = KnoxPersistence.getRelationship(firstId, secondId)
    return record ~= nil and record.disposition or "neutral"
end

local function personalityFor(id)
    if KnoxPersistence.getSurvivorPersonality ~= nil then
        local profile = KnoxPersistence.getSurvivorPersonality(id)
        if profile ~= nil then return profile.personality end
    end
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    return identity.personality
end

-- Encounter results are intentionally modest.  First contact may be a cautious
-- greeting or no interaction at all; it must not turn every pair inside view
-- into an instant travelling party.  Existing aggression can still create the
-- established robbery outcome, while already-hostile people stop socializing.
local function decideEncounterOutcome(firstId, secondId, record)
    local disposition = relationshipDisposition(firstId, secondId)
    if disposition == "self" or disposition == "allied" then
        return "none"
    end
    if disposition == "hostile" then
        return "avoid_hostile"
    end
    local firstIdentity = KnoxPersistence.getSurvivorIdentity(firstId) or {}
    local secondIdentity = KnoxPersistence.getSurvivorIdentity(secondId) or {}
    local firstPersonality = personalityFor(firstId)
    local secondPersonality = personalityFor(secondId)
    local sociability = ((firstIdentity.sociability or 50)
        + (secondIdentity.sociability or 50)) / 2
    local aggression = ((firstIdentity.aggression or 35)
        + (secondIdentity.aggression or 35)) / 2
    local hostileChance = clamp(7 + (aggression - 45) * 0.35, 4, 22)
    if firstPersonality == "predatory" or secondPersonality == "predatory"
        or firstPersonality == "gunner" or secondPersonality == "gunner" then
        hostileChance = clamp(hostileChance + 8, 8, 30)
    end
    local cautiousGreetingChance = clamp(42 + (sociability - 50) * 0.30, 25, 58)
    local hasFamiliarity = record ~= nil and (tonumber(record.meetings) or 0) >= 2
    local sharedActivity = record ~= nil and ((tonumber(record.sharedRoam) or 0)
        + (tonumber(record.sharedLoot) or 0) + (tonumber(record.sharedCombat) or 0))
        or 0
    -- A faction leader may recruit an eligible loner on first contact.  The
    -- old shared-activity gate made this impossible: a loner could never
    -- have shared activity with the group before joining it.  Keep the chance
    -- modest and only enable it for an established faction group; ordinary
    -- two-person groups still need familiarity/shared survival first.
    local firstGroup = KnoxPersistence.getTravelGroupFor(firstId)
    local secondGroup = KnoxPersistence.getTravelGroupFor(secondId)
    local factionGroup = firstGroup ~= nil and firstGroup.factionId ~= nil
        and secondGroup == nil and firstGroup
        or secondGroup ~= nil and secondGroup.factionId ~= nil
        and firstGroup == nil and secondGroup
        or nil
    local nowHours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local factionRecruitment = factionGroup ~= nil
        and nowHours >= (tonumber(factionGroup.recruitmentNextHours) or 0)
    local joinChance = factionRecruitment
        and clamp(24 + (sociability - 50) * 0.22
            + math.min(6, math.max(0, #(factionGroup.memberIds or {}) - 3) * 0.8), 18, 42)
        or (hasFamiliarity and sharedActivity > 0
            and clamp(32 + (sociability - 50) * 0.35, 20, 50)
            or 0)
    local roll = pairRoll(firstId, secondId, record ~= nil and record.meetings or 0)
    if KnoxSettings.allowHostileEncounters() and roll < hostileChance then
        return "hostile"
    end
    local socialRoll = roll - (KnoxSettings.allowHostileEncounters() and hostileChance or 0)
    local lureChance = (firstPersonality == "opportunist" or secondPersonality == "opportunist")
        and 10 or 0
    if lureChance > 0 and socialRoll < lureChance then
        return "lure"
    end
    socialRoll = socialRoll - lureChance
    if joinChance > 0 and socialRoll < joinChance then
        return "join"
    end
    if socialRoll < joinChance + cautiousGreetingChance then
        return "greet"
    end
    return "avoid"
end

function Relationships.classifyEncounter(firstId, secondId)
    return relationshipDisposition(firstId, secondId)
end

function Relationships.decideEncounterOutcome(firstId, secondId, record)
    return decideEncounterOutcome(firstId, secondId, record)
end

function Relationships.isEncounterCooldownComplete(record, worldAge)
    return record == nil or (tonumber(record.nextEncounterHours) or 0)
        <= (tonumber(worldAge) or 0)
end

local function aggressionFor(id)
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    return tonumber(identity.aggression) or 35
end

Relationships.PENDING_MEET_FRESH_HOURS = 72

local function readPendingMeet(id)
    if KnoxPersistence.getUnloadedSurvivalState == nil then return nil end
    local ok, state = pcall(KnoxPersistence.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.pendingMeet) ~= "table" then
        return nil
    end
    return state.pendingMeet
end

local function pendingMeetToken(intent)
    if type(intent) ~= "table" then return nil end
    return {
        pairPhase = intent.pairPhase,
        kind = intent.kind,
        atHours = tonumber(intent.atHours) or 0,
    }
end

local function clearPendingMeet(id, otherId, token)
    if KnoxPersistence.getUnloadedSurvivalState == nil
        or KnoxPersistence.setUnloadedSurvivalState == nil then
        return
    end
    local ok, state = pcall(KnoxPersistence.getUnloadedSurvivalState, id)
    local intent = ok and type(state) == "table" and state.pendingMeet or nil
    if type(intent) == "table"
        and tostring(intent.with) == tostring(otherId)
        and type(token) == "table"
        and intent.pairPhase == token.pairPhase
        and intent.kind == token.kind
        and (tonumber(intent.atHours) or 0) == token.atHours then
        state.pendingMeet = nil
        pcall(KnoxPersistence.setUnloadedSurvivalState, id, state)
    end
end

--- Map a fresh offscreen meet intent to a loaded encounter outcome.
-- Returns the forced outcome (rob->hostile runs the robbery path with real
-- transfers, tail->lure runs the ambush path, befriend/greet->greet) or nil
-- when no fresh mutual intent exists. Never consumes: consumption happens
-- once the loaded engine accepts the encounter below.
function Relationships.pendingMeetOutcome(firstId, secondId, worldAge)
    if firstId == nil or secondId == nil then return nil end
    local now = tonumber(worldAge) or 0
    local first = readPendingMeet(firstId)
    local second = readPendingMeet(secondId)
    local intent = nil
    if first ~= nil and tostring(first.with) == tostring(secondId) then intent = first end
    if intent == nil and second ~= nil and tostring(second.with) == tostring(firstId) then
        intent = second
    end
    if intent == nil then return nil end
    local age = now - (tonumber(intent.atHours) or 0)
    if age < 0 then return nil end
    if age > Relationships.PENDING_MEET_FRESH_HOURS then
        local token = pendingMeetToken(intent)
        clearPendingMeet(firstId, secondId, token)
        clearPendingMeet(secondId, firstId, token)
        return nil
    end
    local token = pendingMeetToken(intent)
    if intent.kind == "rob" then return "hostile", token end
    if intent.kind == "tail" then return "lure", token end
    if intent.kind == "befriend" or intent.kind == "greet" then
        return "greet", token
    end
    return nil
end

function Relationships.consumePendingMeet(firstId, secondId, pairPhase)
    if type(pairPhase) ~= "table" then return false end
    clearPendingMeet(firstId, secondId, pairPhase)
    clearPendingMeet(secondId, firstId, pairPhase)
    return true
end

-- A nearby ally may defend a threatened member for this loaded encounter.
-- This is a short runtime combat permission rather than a permanent
-- group-wide hostility rewrite. Persistence separately records direct and,
-- when appropriate, faction-level hostility.
local function activateLocalAllyDefense(controllers, aggressor, victim, ticks)
    local function squareFor(controller)
        return controller ~= nil and controller.character ~= nil
            and controller.character:getCurrentSquare() or nil
    end
    local aggressorSquare, victimSquare = squareFor(aggressor), squareFor(victim)
    if aggressorSquare == nil or victimSquare == nil
        or aggressorSquare:getZ() ~= victimSquare:getZ() then return end
    local expiresAt = (tonumber(ticks) or 0) + 900
    local forAggressor, forVictim = 0, 0
    for id, controller in pairs(controllers or {}) do
        local square = squareFor(controller)
        if controller ~= nil and square ~= nil and not controller.character:isDead()
            and square:getZ() == aggressorSquare:getZ() then
            if KnoxPersistence.areSurvivorsAllied(id, aggressor.id)
                and distanceSquared(square, aggressorSquare)
                    <= GROUP_DEFENSE_RADIUS * GROUP_DEFENSE_RADIUS then
                controller:registerAllyDefenseThreat(victim.id, expiresAt)
                forAggressor = forAggressor + 1
            elseif KnoxPersistence.areSurvivorsAllied(id, victim.id)
                and distanceSquared(square, victimSquare)
                    <= GROUP_DEFENSE_RADIUS * GROUP_DEFENSE_RADIUS then
                controller:registerAllyDefenseThreat(aggressor.id, expiresAt)
                forVictim = forVictim + 1
            end
        end
    end
    if forAggressor > 0 or forVictim > 0 then
        diagConflict(tostring(aggressor.id) .. ">" .. tostring(victim.id),
            "ally_defense_called_up", {
                forAggressor = forAggressor, forVictim = forVictim,
            })
    end
end

local function coordinateFactionBaseScouting(controllers, orderedIds, ticks)
    if not KnoxSettings.allowNPCFactions() then
        return
    end
    if ticks - lastBaseScoutingTick < 600 or getGameTime() == nil then
        return
    end
    lastBaseScoutingTick = ticks
    local handled = {}
    for _, id in ipairs(orderedIds) do
        local controller = controllers[id]
        local group = KnoxPersistence.getTravelGroupFor(id)
        local faction = group ~= nil and group.factionId ~= nil
            and KnoxPersistence.getFaction(group.factionId)
            or nil
        if controller ~= nil and (faction == nil or faction.kind == "player"
            or faction.leaderId ~= id) then
            controller:clearFactionBaseCandidate()
        end
        if faction ~= nil and faction.kind ~= "player" and not handled[faction.id] then
            handled[faction.id] = true
            local leader = controllers[faction.leaderId]
            if faction.homeBase == nil and leader ~= nil and leader.character ~= nil then
                local candidate = KnoxPersistence.getFactionBaseCandidate(faction.id)
                if candidate ~= nil and KnoxPersistence.expireFactionBaseCandidate(
                    faction.id,
                    getGameTime():getWorldAgeHours(),
                    72
                ) then
                    candidate = nil
                    leader:clearFactionBaseCandidate()
                    print(TAG .. " faction-base-candidate-expired=" .. faction.id)
                end
                if candidate == nil then
                    local found = KnoxFactionBaseScouting.findBestCandidate(
                        leader.character,
                        faction.id,
                        getGameTime():getWorldAgeHours()
                    )
                    if found ~= nil then
                        candidate = KnoxPersistence.recordFactionBaseCandidate(
                            faction.id,
                            found,
                            getGameTime():getWorldAgeHours()
                        )
                        print(
                            TAG .. " faction-base-candidate=" .. faction.id
                                .. " building=" .. tostring(found.buildingId)
                                .. " score=" .. tostring(found.score)
                                .. " rooms=" .. tostring(found.rooms)
                                .. " area=" .. tostring(found.area)
                                .. " water=" .. tostring(found.water)
                        )
                    end
                end
                if candidate ~= nil then
                    leader:setFactionBaseCandidate(faction.id, candidate)
                end
            elseif leader ~= nil then
                leader:clearFactionBaseCandidate()
                if faction.homeBase ~= nil then
                    KnoxFactionSafehouse.ensure(faction)
                end
            end
        end
    end
end

local function socialInitiator(id)
    local group = KnoxPersistence.getTravelGroupFor(id)
    return group == nil or group.leaderId == id
end

local function recordEncounterCooldown(firstId, secondId, disposition, worldAge, delay)
    KnoxPersistence.setRelationshipDisposition(
        firstId,
        secondId,
        disposition,
        (tonumber(worldAge) or 0) + (tonumber(delay) or 0)
    )
end

local function recordFinalizedEncounter(firstId, secondId, outcome, worldAge)
    local stories = rawget(_G, "KnoxOffscreenStories")
    if stories == nil or stories.recordLoadedEncounter == nil then return end
    -- Each survivor's canonical ledger is written independently. The story
    -- owner deduplicates each side so a repeated completion cannot grow memory.
    pcall(stories.recordLoadedEncounter, firstId, secondId, outcome, worldAge)
    pcall(stories.recordLoadedEncounter, secondId, firstId, outcome, worldAge)
end

local function observePair(first, second, worldAge, ticks, participants)
    local key = pairKey(first.id, second.id)
    local state = pairStates[key] or {
        near = false,
        lastWorldAge = worldAge,
        firstCounters = copyCounters(first),
        secondCounters = copyCounters(second),
        firstPending = { roam = 0, loot = 0, combat = 0 },
        secondPending = { roam = 0, loot = 0, combat = 0 },
    }
    local firstSquare = first.character:getCurrentSquare()
    local secondSquare = second.character:getCurrentSquare()
    local sameLevel = firstSquare ~= nil and secondSquare ~= nil
        and firstSquare:getZ() == secondSquare:getZ()
    local pairDistance = sameLevel and distanceSquared(firstSquare, secondSquare) or math.huge
    local perceived = pairDistance <= AWARENESS_RADIUS * AWARENESS_RADIUS
        and canPerceiveHuman(first.character, second.character)
    local near = perceived
    local cautiouslyClose = perceived
        and pairDistance <= CAUTIOUS_APPROACH_RADIUS * CAUTIOUS_APPROACH_RADIUS
    local elapsed = math.max(0, worldAge - state.lastWorldAge)

    if near then
        local firstCurrent = copyCounters(first)
        local secondCurrent = copyCounters(second)
        local firstRoam = counterDelta(firstCurrent, state.firstCounters, "roam")
        local secondRoam = counterDelta(secondCurrent, state.secondCounters, "roam")
        local firstLoot = counterDelta(firstCurrent, state.firstCounters, "loot")
        local secondLoot = counterDelta(secondCurrent, state.secondCounters, "loot")
        local firstCombat = counterDelta(firstCurrent, state.firstCounters, "combat")
        local secondCombat = counterDelta(secondCurrent, state.secondCounters, "combat")
        state.firstPending = state.firstPending or { roam = 0, loot = 0, combat = 0 }
        state.secondPending = state.secondPending or { roam = 0, loot = 0, combat = 0 }
        state.firstPending.roam = state.firstPending.roam + firstRoam
        state.secondPending.roam = state.secondPending.roam + secondRoam
        state.firstPending.loot = state.firstPending.loot + firstLoot
        state.secondPending.loot = state.secondPending.loot + secondLoot
        state.firstPending.combat = state.firstPending.combat + firstCombat
        state.secondPending.combat = state.secondPending.combat + secondCombat
        local sharedRoam = math.min(state.firstPending.roam, state.secondPending.roam)
        local sharedLoot = math.min(state.firstPending.loot, state.secondPending.loot)
        local sharedCombat = math.min(state.firstPending.combat, state.secondPending.combat)
        state.firstPending.roam = state.firstPending.roam - sharedRoam
        state.secondPending.roam = state.secondPending.roam - sharedRoam
        state.firstPending.loot = state.firstPending.loot - sharedLoot
        state.secondPending.loot = state.secondPending.loot - sharedLoot
        state.firstPending.combat = state.firstPending.combat - sharedCombat
        state.secondPending.combat = state.secondPending.combat - sharedCombat
        local began = not state.near
        local record = KnoxPersistence.recordEncounter(first.id, second.id, {
            worldAgeHours = worldAge,
            began = began,
            nearbyHours = state.near and elapsed or 0,
            sharedRoam = sharedRoam,
            sharedLoot = sharedLoot,
            sharedCombat = sharedCombat,
        })
        if began then
            local _, _, firstName = fullName(first.character)
            local _, _, secondName = fullName(second.character)
            print(
                TAG .. " meeting=" .. first.id .. "," .. second.id
                    .. " names=\"" .. firstName .. "\",\"" .. secondName .. "\""
                    .. " meetings=" .. tostring(record.meetings)
            )
        end
    elseif state.near then
        local record = KnoxPersistence.getRelationship(first.id, second.id)
        print(
            TAG .. " separated=" .. first.id .. "," .. second.id
                .. " nearbyHours=" .. tostring(record ~= nil and record.nearbyHours or 0)
        )
    end

    if cautiouslyClose and pendingMeetings[key] == nil
        and not participants[first.id] and not participants[second.id]
        and socialInitiator(first.id) and socialInitiator(second.id) then
        local firstGroup = KnoxPersistence.getTravelGroupFor(first.id)
        local secondGroup = KnoxPersistence.getTravelGroupFor(second.id)
        -- Only group leaders initiate social contact.  Different groups may
        -- still meet, but this pass must not silently merge two established
        -- groups; group/faction progression owns that decision later.
        local sameGroup = firstGroup ~= nil and secondGroup ~= nil
            and firstGroup.id == secondGroup.id
        local oneGroupOnly = (firstGroup ~= nil) ~= (secondGroup ~= nil)
        local canMeet = not sameGroup
        local record = KnoxPersistence.getRelationship(first.id, second.id)
        local cooldownComplete = Relationships.isEncounterCooldownComplete(record, worldAge)
        if canMeet and cooldownComplete then
            -- Offscreen history takes priority: a pair that met out there
            -- resolves that intent first when both load near each other.
            local pendingOverride, pendingMeetToken = Relationships.pendingMeetOutcome(
                first.id, second.id, worldAge
            )
            local outcome = pendingOverride
                or decideEncounterOutcome(first.id, second.id, record)
            if pendingOverride ~= nil then
                print(TAG .. " pending-meet-override=" .. first.id .. "," .. second.id
                    .. " outcome=" .. tostring(pendingOverride))
            end
            if firstGroup ~= nil and secondGroup ~= nil and outcome == "join" then
                -- Joining is defined for a loner joining an existing group.
                -- Keep two established groups as a bounded greeting here so
                -- we never pass an invalid group/loner pair to resolution.
                outcome = "greet"
            end
            if outcome == "avoid" or outcome == "avoid_hostile" then
                local disposition = outcome == "avoid_hostile" and "hostile" or "neutral"
                recordEncounterCooldown(
                    first.id,
                    second.id,
                    disposition,
                    worldAge,
                    NEUTRAL_AVOID_COOLDOWN_HOURS
                )
                participants[first.id] = true
                participants[second.id] = true
                print(TAG .. " encounter-kept-distance=" .. first.id .. "," .. second.id
                    .. " disposition=" .. disposition)
            elseif outcome ~= "none" then
                local firstPersonality = personalityFor(first.id)
                local secondPersonality = personalityFor(second.id)
                local aggressorId = firstPersonality == "opportunist"
                    and first.id
                    or secondPersonality == "opportunist"
                    and second.id
                    or aggressionFor(first.id) >= aggressionFor(second.id)
                    and first.id or second.id
                local joinGroupId = oneGroupOnly
                    and (firstGroup ~= nil and firstGroup.id
                        or (secondGroup ~= nil and secondGroup.id or nil))
                    or nil
                local lonerId = oneGroupOnly
                    and (firstGroup ~= nil and second.id
                        or (secondGroup ~= nil and first.id or nil))
                    or nil
                pendingMeetings[key] = {
                    firstId = first.id,
                    secondId = second.id,
                    phase = "REQUESTED",
                    startedAt = ticks,
                    outcome = outcome,
                    pendingMeetToken = pendingMeetToken,
                    aggressorId = aggressorId,
                    firstGroupId = firstGroup ~= nil and firstGroup.id or nil,
                    secondGroupId = secondGroup ~= nil and secondGroup.id or nil,
                    joinGroupId = joinGroupId,
                    lonerId = lonerId,
                }
                participants[first.id] = true
                participants[second.id] = true
                print(
                    TAG .. " noticed=" .. first.id .. "," .. second.id
                        .. " distance=" .. tostring(math.sqrt(pairDistance))
                        .. " outcome=" .. outcome
                )
            end
        end
    end

    state.near = near
    state.lastWorldAge = worldAge
    state.firstCounters = copyCounters(first)
    state.secondCounters = copyCounters(second)
    pairStates[key] = state
end

function Relationships.observe(controllers, orderedIds, ticks)
    if getGameTime() == nil then
        return
    end
    local worldAge = getGameTime():getWorldAgeHours()
    local participants = {}
    for _, meeting in pairs(pendingMeetings) do
        participants[meeting.firstId] = true
        participants[meeting.secondId] = true
    end
    for index = 1, #orderedIds do
        local first = controllers[orderedIds[index]]
        if first ~= nil and first.character ~= nil
            and availableForNpcSocial(first.id, first) then
            local forename, surname = fullName(first.character)
            KnoxPersistence.ensureSurvivorIdentity(first.id, forename, surname, worldAge)
            for otherIndex = index + 1, #orderedIds do
                local second = controllers[orderedIds[otherIndex]]
                if second ~= nil and second.character ~= nil
                    and availableForNpcSocial(second.id, second) then
                    local secondForename, secondSurname = fullName(second.character)
                    KnoxPersistence.ensureSurvivorIdentity(
                        second.id,
                        secondForename,
                        secondSurname,
                        worldAge
                    )
                    observePair(first, second, worldAge, ticks or 0, participants)
                end
            end
        end
    end
end

local function resumeMeetingController(controller, ticks)
    if controller ~= nil and (controller.state == "MEETING_WAIT"
        or controller.state == "MEETING_APPROACH"
        or controller.state == "MEETING_READY"
        or controller.state == "GREETING") then
        controller:resumeAfterGreeting(ticks)
    end
end

local function meetingOwnsControllers(meeting, first, second)
    if meeting.phase == "REQUESTED" then return true end
    if meeting.phase == "APPROACHING" then
        return (first.state == "MEETING_APPROACH" or first.state == "MEETING_READY")
            and second.state == "MEETING_WAIT"
    end
    return meeting.phase == "GREETING"
        and first.state == "GREETING" and second.state == "GREETING"
end

local function abortMeeting(key, meeting, first, second, ticks, reason)
    resumeMeetingController(first, ticks)
    resumeMeetingController(second, ticks)
    pendingMeetings[key] = nil
    if getGameTime() ~= nil then
        recordEncounterCooldown(
            meeting.firstId,
            meeting.secondId,
            (meeting.outcome == "hostile" or meeting.outcome == "lure")
                and "hostile" or "neutral",
            getGameTime():getWorldAgeHours(),
            ABORT_COOLDOWN_HOURS
        )
    end
    if pairStates[key] ~= nil then
        pairStates[key].near = false
    end
    print(TAG .. " greeting-aborted=" .. meeting.firstId .. "," .. meeting.secondId
        .. " reason=" .. tostring(reason))
end

local function assignGroupLeaders(controllers, orderedIds, ticks, forceReadOnly)
    if not forceReadOnly and ticks - lastGroupAssignmentTick < 60 then
        return
    end
    lastGroupAssignmentTick = ticks
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    for _, id in ipairs(orderedIds) do
        local controller = controllers[id]
        if controller ~= nil then
            local scavenging = rawget(_G, "KnoxGroupScavenge")
            if scavenging ~= nil and scavenging.ownsController ~= nil
                and scavenging.ownsController(id, controller, controllers) then
                -- Temporary settlement expeditions own formation until their
                -- lease ends. They are not persistent social travel groups.
            elseif not availableForNpcSocial(id, controller) then
                controller:clearGroupLeader()
                controller:setGroupMembers({})
            else
            local group = KnoxPersistence.getTravelGroupFor(id)
            local objective = group ~= nil
                and KnoxPersistence.getTravelGroupObjective(group.id) or nil
            local leaderOrder = group ~= nil
                and KnoxPersistence.getTravelGroupLeaderOrder ~= nil
                and KnoxPersistence.getTravelGroupLeaderOrder(group.id, now) or nil
            if group ~= nil and group.leaderId ~= id then
                local leader = controllers[group.leaderId]
                local members = {}
                for _, memberId in ipairs(group.memberIds or {}) do
                    local member = controllers[memberId]
                    if member ~= nil and member.character ~= nil then
                        members[#members + 1] = member.character
                    end
                end
                local formationSlot = 1
                local nextSlot = 0
                for _, memberId in ipairs(group.memberIds or {}) do
                    if memberId ~= group.leaderId then
                        nextSlot = nextSlot + 1
                        if memberId == id then
                            formationSlot = nextSlot
                            break
                        end
                    end
                end
                controller:setGroupLeader(
                    group.leaderId,
                    leader ~= nil and leader.character or nil,
                    formationSlot,
                    #(group.memberIds or {}),
                    objective,
                    leaderOrder,
                    forceReadOnly
                )
                controller:setGroupMembers(members)
            elseif group ~= nil then
                if not forceReadOnly then
                    if controller.lifeIntent ~= nil then
                        KnoxPersistence.setTravelGroupObjective(
                            group.id,
                            id,
                            controller.lifeIntent,
                            now
                        )
                    else
                        KnoxPersistence.clearTravelGroupObjective(group.id, id)
                    end
                end
                if not forceReadOnly then
                    objective = KnoxPersistence.getTravelGroupObjective(group.id)
                end
                local members = {}
                for _, memberId in ipairs(group.memberIds or {}) do
                    local member = controllers[memberId]
                    if member ~= nil and member.character ~= nil then
                        members[#members + 1] = member.character
                    end
                end
                controller:clearGroupLeader()
                controller:setGroupMembers(members)
                controller:setGroupObjective(objective, forceReadOnly)
                if controller.setGroupLeaderOrder ~= nil then
                    controller:setGroupLeaderOrder(leaderOrder)
                end
            else
                controller:clearGroupLeader()
                controller:setGroupMembers({})
            end
            end
        end
    end
end

-- Persistence owns membership and asks the existing coordinator to refresh
-- loaded projections on its next tick. This request is transient and contains
-- no group state of its own.
function Relationships.requestGroupAssignmentRefresh()
    groupAssignmentRefreshRequested = true
    return true
end

function Relationships.coordinate(controllers, orderedIds, ticks)
    if groupAssignmentRefreshRequested then
        groupAssignmentRefreshRequested = false
        assignGroupLeaders(controllers, orderedIds, ticks, true)
    else
        assignGroupLeaders(controllers, orderedIds, ticks)
    end
    if KnoxSettings.allowNPCFactions()
        and ticks - lastFactionEvaluationTick >= 600 and getGameTime() ~= nil then
        lastFactionEvaluationTick = ticks
        local evaluated = {}
        for _, id in ipairs(orderedIds) do
            if availableForNpcSocial(id, controllers[id]) then
            local group = KnoxPersistence.getTravelGroupFor(id)
            if group ~= nil and not evaluated[group.id] then
                evaluated[group.id] = true
                local faction, result = KnoxPersistence.evaluateTravelGroupFaction(
                    group.id,
                    getGameTime():getWorldAgeHours(),
                    KnoxSettings.npcFactionMinimumMembers()
                )
                if faction ~= nil and result == "created" then
                    local leader = controllers[faction.leaderId]
                    if leader ~= nil and leader.character ~= nil
                        and leader.state ~= "COMBAT" then
                        KnoxActivityFeed.speak(leader.character, "We should find somewhere to settle.")
                    end
                    KnoxActivityFeed.event(
                        tostring(faction.name or faction.id or "A survivor faction")
                            .. " has formed."
                    )
                    print(
                        TAG .. " faction-formed=" .. faction.id
                            .. " group=" .. group.id
                            .. " members=" .. table.concat(group.memberIds, ",")
                    )
                end
            end
            end
        end
    end
    coordinateFactionBaseScouting(controllers, orderedIds, ticks)
    for key, meeting in pairs(pendingMeetings) do
        local first = controllers[meeting.firstId]
        local second = controllers[meeting.secondId]
        local firstGroup = first ~= nil and KnoxPersistence.getTravelGroupFor(first.id) or nil
        local secondGroup = second ~= nil and KnoxPersistence.getTravelGroupFor(second.id) or nil
        local currentFirstGroupId = firstGroup ~= nil and firstGroup.id or nil
        local currentSecondGroupId = secondGroup ~= nil and secondGroup.id or nil
        local invalidMembership
        if meeting.joinGroupId == nil then
            invalidMembership = currentFirstGroupId ~= meeting.firstGroupId
                or currentSecondGroupId ~= meeting.secondGroupId
        else
            invalidMembership = (currentFirstGroupId ~= meeting.joinGroupId
                    and not (meeting.lonerId == meeting.firstId and currentFirstGroupId == nil))
                or (currentSecondGroupId ~= meeting.joinGroupId
                    and not (meeting.lonerId == meeting.secondId and currentSecondGroupId == nil))
        end
        if first == nil or second == nil then
            resumeMeetingController(first, ticks)
            resumeMeetingController(second, ticks)
            pendingMeetings[key] = nil
        elseif not availableForNpcSocial(first.id, first)
            or not availableForNpcSocial(second.id, second) then
            abortMeeting(key, meeting, first, second, ticks, "player_recruited")
        elseif invalidMembership then
            abortMeeting(key, meeting, first, second, ticks, "membership_changed")
        elseif ticks - meeting.startedAt > 1200 then
            abortMeeting(key, meeting, first, second, ticks, "timeout")
        elseif not meetingOwnsControllers(meeting, first, second) then
            -- Escape, treatment and explicit orders release social ownership
            -- just as combat does. Only the still-waiting partner is resumed.
            abortMeeting(key, meeting, first, second, ticks, "activity_changed")
        elseif meeting.phase == "REQUESTED" then
            if first:canInterruptForMeeting() and second:canInterruptForMeeting()
                and first:interruptForMeeting() and second:interruptForMeeting() then
                if first:beginMeetingApproach(second.character) then
                    meeting.phase = "APPROACHING"
                    print(TAG .. " greeting-approach=" .. first.id .. "->" .. second.id)
                else
                    abortMeeting(key, meeting, first, second, ticks, "no_approach")
                end
            end
        elseif meeting.phase == "APPROACHING" and first.state == "MEETING_READY" then
            first:beginGreeting()
            second:beginGreeting()
            first.character:faceLocationF(second.character:getX(), second.character:getY())
            second.character:faceLocationF(first.character:getX(), first.character:getY())
            if meeting.outcome == "hostile" or meeting.outcome == "lure" then
                local aggressor = meeting.aggressorId == first.id and first or second
                KnoxActivityFeed.speak(aggressor.character, encounterLine(meeting, false))
            elseif meeting.outcome == "decline" then
                KnoxActivityFeed.speak(first.character, encounterLine(meeting, false))
            elseif meeting.outcome == "greet" then
                KnoxActivityFeed.speak(first.character, encounterLine(meeting, false))
            elseif meeting.joinGroupId ~= nil then
                local recruiter = meeting.lonerId == first.id and second or first
                KnoxActivityFeed.speak(recruiter.character, encounterLine(meeting, false))
            else
                KnoxActivityFeed.speak(first.character, encounterLine(meeting, false))
            end
            meeting.phase = "GREETING"
            meeting.greetingAt = ticks
            print(TAG .. " greeting-started=" .. first.id .. "," .. second.id)
        elseif meeting.phase == "GREETING" then
            if not meeting.responseSpoken and ticks - meeting.greetingAt >= 90 then
                if meeting.outcome == "hostile" or meeting.outcome == "lure" then
                    local victim = meeting.aggressorId == first.id and second or first
                    KnoxActivityFeed.speak(victim.character, encounterLine(meeting, true))
                elseif meeting.outcome == "decline" then
                    KnoxActivityFeed.speak(second.character, encounterLine(meeting, true))
                elseif meeting.outcome == "greet" then
                    KnoxActivityFeed.speak(second.character, encounterLine(meeting, true))
                elseif meeting.joinGroupId ~= nil then
                    local loner = meeting.lonerId == first.id and first or second
                    KnoxActivityFeed.speak(loner.character, encounterLine(meeting, true))
                else
                    KnoxActivityFeed.speak(second.character, encounterLine(meeting, true))
                end
                meeting.responseSpoken = true
            end
            if ticks - meeting.greetingAt >= 240 then
                local group = nil
                local joinResult = nil
                local worldAge = getGameTime():getWorldAgeHours()
                if meeting.outcome == "hostile" or meeting.outcome == "lure" then
                    local aggressor = meeting.aggressorId == first.id and first or second
                    local victim = meeting.aggressorId == first.id and second or first
                    local conflict, scope = KnoxPersistence.escalateSurvivorConflict(
                        first.id, second.id, worldAge,
                        "encounter_" .. meeting.outcome
                    )
                    if conflict ~= nil then
                        recordFinalizedEncounter(first.id, second.id, "hostile", worldAge)
                    end
                    diagConflict(tostring(aggressor.id) .. ">" .. tostring(victim.id),
                        "hostile_" .. tostring(meeting.outcome), {
                            scope = tostring(scope or "failed"),
                        })
                    activateLocalAllyDefense(controllers, aggressor, victim, ticks)
                    local signals = rawget(_G, "KnoxOrderSignals")
                    if signals ~= nil and signals.play ~= nil then
                        pcall(function() signals.play(aggressor.character, "insult") end)
                        pcall(function() signals.play(victim.character, "surrender") end)
                    end
                    victim:holdForRobbery(aggressor, ticks)
                    local robberyStarted = aggressor:beginRobbery(victim, ticks)
                    if not robberyStarted then
                        victim:releaseRobberyHold(aggressor.character, ticks, "no_transfer")
                        aggressor:resumeAfterGreeting(ticks)
                    end
                    if conflict ~= nil or robberyStarted then
                        Relationships.consumePendingMeet(
                            first.id, second.id, meeting.pendingMeetToken
                        )
                    else
                        -- Keep the durable offscreen intent for a later
                        -- attempt, but do not re-elect the same failed
                        -- loaded handoff on every coordinator tick.
                        recordEncounterCooldown(
                            first.id, second.id, "neutral", worldAge, ABORT_COOLDOWN_HOURS
                        )
                    end
                    pendingMeetings[key] = nil
                    print(
                        TAG .. " encounter-outcome=" .. meeting.outcome .. " robber=" .. aggressor.id
                            .. " victim=" .. victim.id
                    )
                    KnoxActivityFeed.event(meeting.outcome == "lure"
                        and "A survivor encounter became an ambush."
                        or "A survivor encounter turned hostile.")
                elseif meeting.outcome == "decline" then
                    local dispositionRecord = KnoxPersistence.setRelationshipDisposition(
                        first.id,
                        second.id,
                        "declined",
                        worldAge + 6
                    )
                    if dispositionRecord ~= nil then
                        recordFinalizedEncounter(first.id, second.id, "declined", worldAge)
                    end
                    if dispositionRecord ~= nil then
                        Relationships.consumePendingMeet(
                            first.id, second.id, meeting.pendingMeetToken
                        )
                    end
                    first:resumeAfterGreeting(ticks)
                    second:resumeAfterGreeting(ticks)
                    pendingMeetings[key] = nil
                    print(TAG .. " encounter-outcome=decline " .. first.id .. "," .. second.id)
                    KnoxActivityFeed.event("Two survivors part ways.")
                elseif meeting.outcome == "greet" then
                    recordEncounterCooldown(
                        first.id,
                        second.id,
                        "neutral",
                        worldAge,
                        GREETING_COOLDOWN_HOURS
                    )
                    recordFinalizedEncounter(first.id, second.id, "friendly", worldAge)
                    Relationships.consumePendingMeet(
                        first.id, second.id, meeting.pendingMeetToken
                    )
                    local greetSignals = rawget(_G, "KnoxOrderSignals")
                    if greetSignals ~= nil and greetSignals.play ~= nil then
                        pcall(function() greetSignals.play(first.character, "wavehi") end)
                        pcall(function() greetSignals.play(second.character, "wavehi") end)
                    end
                    first:resumeAfterGreeting(ticks)
                    second:resumeAfterGreeting(ticks)
                    pendingMeetings[key] = nil
                    print(TAG .. " encounter-outcome=greet " .. first.id .. "," .. second.id)
                    KnoxActivityFeed.event("Two survivors exchange a few cautious words.")
                elseif meeting.joinGroupId ~= nil then
                    group, joinResult = KnoxPersistence.addTravelGroupMember(
                        meeting.joinGroupId,
                        meeting.lonerId
                    )
                    if group ~= nil and group.factionId ~= nil then
                        -- Keep faction growth organic. The cooldown is stored on
                        -- the existing travel-group record, so reloads do not
                        -- reset it and no second social system is introduced.
                        group.recruitmentNextHours = worldAge + 12
                    end
                else
                    group = KnoxPersistence.createTravelGroup(
                        { first.id, second.id },
                        getGameTime():getWorldAgeHours()
                    )
                end
                if meeting.outcome == "join" then
                    if group == nil then
                        -- A faction can reach its configured size, lose its
                        -- leader, or otherwise become unavailable while a
                        -- greeting is in progress. Do not report a join or
                        -- mark the pair allied when the membership mutation
                        -- was rejected.
                        recordEncounterCooldown(
                            first.id,
                            second.id,
                            "neutral",
                            worldAge,
                            ABORT_COOLDOWN_HOURS
                        )
                        first:resumeAfterGreeting(ticks)
                        second:resumeAfterGreeting(ticks)
                        pendingMeetings[key] = nil
                        recordFinalizedEncounter(first.id, second.id, "parted", worldAge)
                        Relationships.consumePendingMeet(
                            first.id, second.id, meeting.pendingMeetToken
                        )
                        print(
                            TAG .. " encounter-outcome=join-rejected "
                                .. first.id .. "," .. second.id
                                .. " reason=" .. tostring(joinResult)
                        )
                        KnoxActivityFeed.event("The survivors decide to keep travelling separately.")
                        meeting.outcome = "join_rejected"
                    end
                    if meeting.outcome == "join" then
                        KnoxPersistence.setRelationshipDisposition(
                            first.id,
                            second.id,
                            "allied",
                            worldAge
                        )
                        if group ~= nil then
                        recordFinalizedEncounter(first.id, second.id, "joined", worldAge)
                        Relationships.consumePendingMeet(
                            first.id, second.id, meeting.pendingMeetToken
                        )
                        end
                        first:resumeAfterGreeting(ticks)
                        second:resumeAfterGreeting(ticks)
                        pendingMeetings[key] = nil
                        print(
                            TAG .. " travel-group=" .. tostring(group ~= nil and group.id or "none")
                                .. " members=" .. first.id .. "," .. second.id
                                .. " faction=" .. tostring(group ~= nil and group.factionId or false)
                                .. (group ~= nil and group.factionId == nil
                                    and " requires=" .. tostring(KnoxSettings.npcFactionMinimumMembers())
                                    or "")
                        )
                        KnoxActivityFeed.event("Survivors have agreed to travel together.")
                        lastGroupAssignmentTick = ticks - 60
                    end
                end
            end
        end
    end
end

function Relationships.resetRuntime()
    pairStates = {}
    pendingMeetings = {}
    lastGroupAssignmentTick = -60
    groupAssignmentRefreshRequested = false
    lastFactionEvaluationTick = -600
    lastBaseScoutingTick = -600
end
