-- Counting harness for Nameplates.update: one survivor-to-viewer relation per
-- pass, reused by both the colour line and the tag write. KS_PASS is the real
-- production update (and classify) extracted from KS_SurvivorNameplates.
local savedGlobals = {
    KnoxPersistence = KnoxPersistence, KnoxSettings = KnoxSettings,
    KnoxSurvivorRuntime = KnoxSurvivorRuntime, SurvivorNames = SurvivorNames,
    getNumActivePlayers = getNumActivePlayers, getSpecificPlayer = getSpecificPlayer,
    getGameTime = getGameTime, ColorInfo = ColorInfo,
}

local affiliationReads, tagged = 0, 0
local square = {
    getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end,
}
local characters = {}
for i = 1, 2 do
    characters["s" .. i] = {
        getCurrentSquare = function() return square end,
        setUsername = function() tagged = tagged + 1 end,
        setDisplayName = function() end,
        setTagColor = function() end,
        setShowTag = function() end,
    }
end
local player = {
    getPlayerNum = function() return 0 end,
    getCurrentSquare = function() return square end,
    CanSee = function() return true end,
    getZ = function() return 0 end, getX = function() return 0 end,
    getY = function() return 0 end,
}
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return player end
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
ColorInfo = { new = function() return {} end }
KnoxSettings = {
    showSurvivorNameplates = function() return true end,
    survivorNameplateDistance = function() return 12 end,
}
KnoxSurvivorRuntime = {
    activeIds = function() return { "s1", "s2" } end,
    getCharacter = function(id) return characters[id] end,
}
SurvivorNames = {
    companyName = function() return nil end,
    companyPlace = function() return nil end,
}
KnoxPersistence = {
    ensurePlayerId = function() return "p1" end,
    getSurvivorAffiliation = function(id)
        affiliationReads = affiliationReads + 1
        if id == "s1" then return { kind = "player", ownerId = "p1" } end
        return { kind = "npc" }
    end,
    isSurvivorHostileToPlayer = function(id) return id == "s2" end,
    getPlayerFaction = function() return nil end,
    getFactionRelationship = function() return nil end,
    getPlayerRelationship = function() return nil end,
    survivorCompany = function() return nil end,
    recordPlayerProximity = function() end,
}

KS_PASS(15)

-- Two survivors, one viewer: the pre-change shape classified each survivor for
-- the colour line and again for the tag write (4 reads); the pass now does it
-- once per pair (2).
assert(affiliationReads == 2,
    "classify runs once per survivor per viewer, got " .. tostring(affiliationReads))
assert(tagged == 2,
    "both visible survivors keep their native tag write, got " .. tostring(tagged))
local passLabels = KS_PASS_STATE()
assert(#passLabels == 2,
    "the pass still builds one label per visible survivor, got " .. tostring(#passLabels))
assert(passLabels[1].colors[0] ~= nil and passLabels[2].colors[0] ~= nil,
    "both labels keep their per-viewer colour")

KnoxPersistence = savedGlobals.KnoxPersistence
KnoxSettings = savedGlobals.KnoxSettings
KnoxSurvivorRuntime = savedGlobals.KnoxSurvivorRuntime
SurvivorNames = savedGlobals.SurvivorNames
getNumActivePlayers = savedGlobals.getNumActivePlayers
getSpecificPlayer = savedGlobals.getSpecificPlayer
getGameTime = savedGlobals.getGameTime
ColorInfo = savedGlobals.ColorInfo

KS_NAMEPLATE_PASS_RECEIPT = "classify_old=4 classify_new=" .. tostring(affiliationReads)
    .. " survivors=2 viewers=1 tags=" .. tostring(tagged)
