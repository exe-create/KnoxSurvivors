-- Switched-off nameplates must cost nothing per pass.
--
-- The pass runs four times a second. It used to read one survivor identity,
-- resolve one name and write one native tag per active survivor just to decide
-- that nothing should be drawn, and Nameplates.clear did the same walk again.
-- This fixture counts that work: identity reads and native tag writes are the
-- two costs the player pays in stutter when the feature is off.
--
-- Every global replaced here is restored: the harness runs later fixtures in
-- the same state, so a leaked stub is a false failure somewhere else.
local STUBBED = {
    "KnoxSettings", "KnoxPersistence", "KnoxSurvivorRuntime", "KnoxSurvivorNames",
    "getNumActivePlayers", "getSpecificPlayer", "getGameTime",
}
local saved = {}
for _, name in ipairs(STUBBED) do saved[name] = rawget(_G, name) end

local Nameplates = assert(rawget(_G, "KnoxSurvivorNameplates"),
    "nameplate owner missing")

local identityReads, tagWrites, tagsOn = 0, 0, 0
local state = { enabled = false }

local ids, characters = {}, {}
for index = 1, 5 do
    local id = "s" .. index
    ids[#ids + 1] = id
    characters[id] = {
        setShowTag = function(_, value)
            tagWrites = tagWrites + 1
            tagsOn = value == true and tagsOn + 1 or tagsOn - 1
        end,
        getCurrentSquare = function() return nil end,
    }
end

_G.KnoxSettings = {
    showSurvivorNameplates = function() return state.enabled end,
    survivorNameplateDistance = function() return 12 end,
}
_G.KnoxPersistence = {
    getSurvivorIdentity = function(id)
        identityReads = identityReads + 1
        return { forename = "N", surname = tostring(id) }
    end,
    ensurePlayerId = function() return "player-1" end,
    getSurvivorAffiliation = function() return { kind = "npc" } end,
    isSurvivorHostileToPlayer = function() return false end,
    getPlayerFaction = function() return nil end,
    getPlayerRelationship = function() return nil end,
}
_G.KnoxSurvivorRuntime = {
    activeIds = function() return ids end,
    getCharacter = function(id) return characters[id] end,
}
_G.getNumActivePlayers = function() return 1 end
_G.getSpecificPlayer = function() return nil end
_G.getGameTime = function()
    return { getWorldAgeHours = function() return 0 end }
end

-- 1. A switched-off pass does no per-survivor work at all.
Nameplates.update(15)
assert(identityReads == 0,
    "a switched-off pass reads no identities, got " .. tostring(identityReads))
assert(tagWrites == 0,
    "a switched-off pass writes no tags, got " .. tostring(tagWrites))

-- 2. Repeated off passes stay free.
Nameplates.update(45)
Nameplates.update(75)
assert(identityReads == 0 and tagWrites == 0,
    "off passes stay free, got reads=" .. tostring(identityReads)
        .. " writes=" .. tostring(tagWrites))

-- 3. Off-cadence ticks do nothing at all.
Nameplates.update(76)
assert(identityReads == 0 and tagWrites == 0, "an off-cadence tick costs nothing")

-- 4. A clear with nothing showing writes nothing. The old clear walked every
--    active survivor and wrote a tag for each.
Nameplates.clear()
assert(tagWrites == 0,
    "clearing nothing writes no tags, got " .. tostring(tagWrites))
assert(tagsOn == 0, "nothing is left showing")

for _, name in ipairs(STUBBED) do _G[name] = saved[name] end

print("Nameplate off-cost PASS reads=0 writes=0 clear=0")
