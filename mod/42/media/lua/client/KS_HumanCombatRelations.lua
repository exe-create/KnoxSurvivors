require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_ActivityFeed"
pcall(function() require "KS_DebugLog" end)

local HumanCombat = rawget(_G, "KnoxHumanCombatRelations") or {}
_G.KnoxHumanCombatRelations = HumanCombat
local creditedKills = setmetatable({}, { __mode = "k" })

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

local function localPlayerId(character)
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and player == character then
            return KnoxPersistence.ensurePlayerId(player)
        end
    end
    return nil
end

local function diagCombat(event, id, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log ~= nil and log.log ~= nil then
        pcall(function() log.log("combat", id, event, details) end)
    end
end

local function targetHealth(target)
    -- Never chain target:getBodyDamage():getHealth(): zombies have no
    -- BodyDamage, so the intermediate null indexed with :getHealth throws a
    -- Java RuntimeException that Kahlua pcall cannot catch (live spam 33x).
    if target == nil then return nil end
    local damage = nil
    pcall(function() damage = target:getBodyDamage() end)
    if damage ~= nil then
        local ok, value = pcall(function() return damage:getHealth() end)
        if ok and tonumber(value) ~= nil then return tonumber(value) end
    end
    local okSimple, simple = pcall(function() return target:getHealth() end)
    return okSimple and tonumber(simple) or nil
end

local function woundFlags(target)
    if target == nil then return {} end
    local flags = {}
    local damage = nil
    pcall(function() damage = target:getBodyDamage() end)
    if damage == nil then return flags end
    pcall(function()
        if damage.getBleedingTime ~= nil then
            flags.bleeding = tonumber(damage:getBleedingTime())
        end
    end)
    local parts = nil
    pcall(function() parts = damage:getBodyParts() end)
    if parts ~= nil then
        local count = nil
        pcall(function() count = parts:size() end)
        for index = 0, (tonumber(count) or 0) - 1 do
            local part = nil
            pcall(function() part = parts:get(index) end)
            if part ~= nil then
                local okBitten, bitten = pcall(function()
                    if part.isBitten ~= nil then return part:isBitten() end
                    return false
                end)
                if okBitten and bitten then flags.bitten = true end
                local okCut, cut = pcall(function() return part:isCut() end)
                if okCut and cut then flags.cut = true end
                local okFrac, frac = pcall(function() return part:getFractureTime() end)
                if okFrac and tonumber(frac) ~= nil and tonumber(frac) > 0 then
                    flags.fracture = true
                end
            end
        end
    end
    return flags
end

-- One projection for a faction's answer to a witnessed first strike. The
-- caller supplies only loaded candidates and a perception test, so a group
-- cannot learn about a blow nobody saw. The victim, player-owned people and
-- anyone already hostile are never re-counted.
function HumanCombat.factionWitnesses(victimId, factionId, candidates, perceives)
    local witnesses = {}
    if type(factionId) ~= "string" or factionId == ""
        or type(candidates) ~= "table" then
        return witnesses
    end
    for _, candidate in ipairs(candidates) do
        if type(candidate) == "table" and candidate.id ~= nil
            and tostring(candidate.id) ~= tostring(victimId)
            and tostring(candidate.factionId or "") == factionId
            and candidate.playerOwned ~= true
            and candidate.hostile ~= true
            and (perceives == nil or perceives(candidate) == true) then
            witnesses[#witnesses + 1] = candidate.id
        end
    end
    return witnesses
end

-- Native damage remains authoritative. This hook only records the social
-- consequence after Build 42 confirms that a player actually hit a survivor.
function HumanCombat.onWeaponHitCharacter(attacker, target, weapon)
    -- Telemetry must never throw inside a native damage event. Every lookup
    -- is pcall-guarded; a nil attacker, missing runtime, or renamed vanilla
    -- API degrades to a skipped log line, never a Lua error in console.txt.
    local attackerId, targetId = nil, nil
    pcall(function()
        if KnoxSurvivorRuntime.idForCharacter ~= nil then
            attackerId = KnoxSurvivorRuntime.idForCharacter(attacker)
            targetId = KnoxSurvivorRuntime.idForCharacter(target)
        end
    end)
    -- General survivor-involved damage telemetry (survivor vs survivor,
    -- zombie vs survivor, gunshots). Throttled inside KnoxDebugLog.
    pcall(function()
        if attackerId ~= nil or targetId ~= nil then
            local kind = "unknown"
            if instanceof ~= nil and attacker ~= nil then
                local okZombie, isZombie = pcall(function()
                    return instanceof(attacker, "IsoZombie")
                end)
                if okZombie and isZombie then
                    kind = "zombie_on_survivor"
                elseif attackerId ~= nil and targetId ~= nil then
                    kind = "survivor_on_survivor"
                elseif attackerId ~= nil then
                    kind = "survivor_on_other"
                elseif targetId ~= nil then
                    kind = "other_on_survivor"
                end
            elseif attackerId ~= nil and targetId ~= nil then
                kind = "survivor_on_survivor"
            elseif attackerId ~= nil then
                kind = "survivor_on_other"
            elseif targetId ~= nil then
                kind = "other_on_survivor"
            end
            local flags = target ~= nil and woundFlags(target) or {}
            flags.health = target ~= nil and targetHealth(target) or nil
            if weapon ~= nil then
                local okWeapon, weaponType = pcall(function() return weapon:getFullType() end)
                if okWeapon then flags.weapon = weaponType end
            end
            flags.kind = kind
            diagCombat("damage", attackerId or targetId or "unknown", flags)
        end
    end)
    if not KnoxSettings.allowSurvivorPlayerCombat() then return end
    local playerId = localPlayerId(attacker)
    if playerId == nil then return end
    local survivorId = targetId
    if survivorId == nil then return end
    -- The Java bridge should already have blocked protected targets. Keep the
    -- Lua consequence path defensive as well so a stale lease or native event
    -- can never turn a companion, owned resident, or ally hostile.
    if not HumanCombat.canPlayerAttack(playerId, survivorId) then return end
    local alreadyHostile = KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId)
    if KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
        and not alreadyHostile then
        KnoxPersistence.recordPlayerAggression(playerId, survivorId, worldAge())
        local faction = KnoxPersistence.getFactionForSurvivor(survivorId)
        KnoxActivityFeed.event(faction ~= nil and faction.kind ~= "player"
            and "Your attack has made an NPC faction hostile."
            or "A survivor has turned hostile.")
        -- A faction answers for its own, but only the people who actually
        -- saw the first blow. Self-defence against an already-hostile
        -- member never reaches this branch, and player-owned or allied
        -- people were excluded by canPlayerAttack above.
        if faction ~= nil and faction.kind ~= "player" then
            local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
            local runtime = rawget(_G, "KnoxSurvivorRuntime")
            local relationships = rawget(_G, "KnoxSurvivorRelationships")
            if affiliation ~= nil and affiliation.factionId ~= nil
                and runtime ~= nil and runtime.getCharacter ~= nil
                and runtime.activeIds ~= nil
                and relationships ~= nil
                and relationships.canPerceiveHuman ~= nil then
                local candidates = {}
                for _, witnessId in ipairs(runtime.activeIds()) do
                    local witness = runtime.getCharacter(witnessId)
                    if witness ~= nil then
                        local peer = KnoxPersistence.getSurvivorAffiliation(witnessId)
                        candidates[#candidates + 1] = {
                            id = witnessId,
                            factionId = peer ~= nil and peer.factionId or nil,
                            playerOwned = peer ~= nil and peer.kind == "player",
                            hostile = KnoxPersistence.isSurvivorHostileToPlayer(
                                witnessId, playerId),
                            character = witness,
                        }
                    end
                end
                local witnesses = HumanCombat.factionWitnesses(
                    survivorId, affiliation.factionId, candidates,
                    function(candidate)
                        return relationships.canPerceiveHuman(candidate.character, attacker)
                            or relationships.canPerceiveHuman(candidate.character, target)
                    end
                )
                local joined = false
                for _, witnessId in ipairs(witnesses) do
                    if KnoxPersistence.setSurvivorHostileToPlayer(
                        witnessId, playerId, true) then joined = true end
                end
                if joined then
                    KnoxActivityFeed.event(
                        "Their group saw it and turned hostile.")
                end
            end
            -- A witnessed attack is a war with the player's own group, not a
            -- permanent sentence: the two factions are hostile on sight for a
            -- bounded stretch of days and then lapse back to strangers.
            local playerFaction = KnoxPersistence.getPlayerFaction(playerId)
            if playerFaction ~= nil
                and KnoxPersistence.setFactionRelationshipDisposition ~= nil then
                local relation = KnoxPersistence.setFactionRelationshipDisposition(
                    faction.id, playerFaction.id, "hostile", worldAge(),
                    "player_attacked_member", KnoxPersistence.FACTION_WAR_HOURS)
                if relation ~= nil then
                    KnoxActivityFeed.event("They are at war with your group for now.")
                end
            end
        end
    end
end

-- Read the existing relationship state; no hostility is created by swinging or missing.
function HumanCombat.canPlayerAttack(playerId, survivorId)
    if not KnoxSettings.enabled() or not KnoxSettings.allowSurvivorPlayerCombat() then return false end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if affiliation == nil or affiliation.kind == "player" then return false end
    if KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId) then return true end
    local faction = KnoxPersistence.getPlayerFaction(playerId)
    if faction ~= nil and affiliation.factionId ~= nil then
        if faction.id == affiliation.factionId then return false end
        local relation = KnoxPersistence.getFactionRelationship(affiliation.factionId, faction.id)
        if relation ~= nil and relation.disposition == "allied" then return false end
    end
    -- Independent and neutral survivors remain valid player combat targets.
    -- Their response is owned by the existing hostile-human controller after
    -- an actual hit; relationship history does not grant friendly-fire safety.
    return true
end

function HumanCombat.onWeaponSwing(attacker)
    local playerId = localPlayerId(attacker)
    if playerId == nil then return end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil or bridge.beginPlayerHumanAttack == nil
        or bridge.setPlayerHumanAttackTarget == nil then return end
    if not bridge:beginPlayerHumanAttack(attacker) then return end
    -- Active bodies only, at native attack events, not a world/per-frame scan.
    for _, survivorId in ipairs(KnoxSurvivorRuntime.activeIds()) do
        bridge:setPlayerHumanAttackTarget(attacker, survivorId,
            HumanCombat.canPlayerAttack(playerId, survivorId))
    end
end

-- Native onKilled emits OnZombieDead before DoDeath. Only its actual player
-- attacker and current nearby survivor target count; there is no radius-wide XP.
function HumanCombat.onZombieDead(zombie)
    if zombie == nil or creditedKills[zombie] or not KnoxSettings.enabled() then return end
    local ok, attacker, target = pcall(function()
        if not zombie:isDead() then return nil, nil end
        return zombie:getAttackedBy(), zombie:getTarget()
    end)
    if not ok or attacker == nil or target == nil then return end
    local playerId = localPlayerId(attacker)
    if playerId == nil then return end
    local survivorId = KnoxSurvivorRuntime.idForCharacter(target)
    if survivorId == nil then return end
    local relevant, close = pcall(function()
        if target:isDead() or target:getCurrentSquare() == nil or zombie:getCurrentSquare() == nil
            or attacker:getCurrentSquare() == nil or target:getZ() ~= zombie:getZ()
            or attacker:getZ() ~= target:getZ() then return false end
        local threatDistance = (target:getX() - zombie:getX()) ^ 2 + (target:getY() - zombie:getY()) ^ 2
        local playerDistance = (target:getX() - attacker:getX()) ^ 2 + (target:getY() - attacker:getY()) ^ 2
        return threatDistance <= 64 and playerDistance <= 400
    end)
    if not relevant or not close then return end
    creditedKills[zombie] = true
    local result = KnoxPersistence.recordPlayerContribution(playerId, survivorId, "defense", worldAge())
    if result ~= nil then
        KnoxActivityFeed.speak(target, "Thanks for covering me.")
        if KnoxActivityFeed.reputation ~= nil then KnoxActivityFeed.reputation(target, result.trustGain) end
    end
end

if Events.OnWeaponHitCharacter ~= nil then
    Events.OnWeaponHitCharacter.Add(HumanCombat.onWeaponHitCharacter)
end

if Events.OnZombieDead ~= nil then Events.OnZombieDead.Add(HumanCombat.onZombieDead) end

if Events.OnWeaponSwing ~= nil then Events.OnWeaponSwing.Add(HumanCombat.onWeaponSwing) end
-- Recheck immediately before native collision; recruiting/peace during the windup wins.
if Events.OnWeaponSwingHitPoint ~= nil then Events.OnWeaponSwingHitPoint.Add(HumanCombat.onWeaponSwing) end

return HumanCombat
