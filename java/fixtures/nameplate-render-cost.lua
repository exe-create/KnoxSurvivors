-- Counting harness for the nameplate render hoist. KS_RENDER is the real
-- Nameplates.render extracted from KS_SurvivorNameplates, with the module locals
-- it closes over supplied by the harness.
-- The gate shares one Lua environment, so every stub installed here is put
-- back before the fixture returns; later fixtures keep their own world.
local savedGlobals = {
    getNumActivePlayers = getNumActivePlayers, getSpecificPlayer = getSpecificPlayer,
    IsoCamera = IsoCamera, getCore = getCore, UIFont = UIFont,
    getTextManager = getTextManager, KnoxSettings = KnoxSettings,
    KnoxPersistence = KnoxPersistence, KnoxSurvivorRuntime = KnoxSurvivorRuntime,
}

local measures, factionReads, textCalls, drawn = 0, 0, 0, {}
local square = {
    getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end,
}
local player = {
    getCurrentSquare = function() return square end,
    getZ = function() return 0 end, getX = function() return 0 end,
    getY = function() return 0 end, getPlayerNum = function() return 0 end,
    CanSee = function() return true end,
}
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return player end
IsoCamera = {
    getScreenLeft = function() return 0 end, getScreenTop = function() return 0 end,
    getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end,
}
getCore = function() return { getZoom = function() return 1 end } end
UIFont = { Small = 1 }
getTextManager = function()
    textCalls = textCalls + 1
    return {
        MeasureStringX = function(self, font, text) measures = measures + 1 return 20 end,
        getFontHeight = function() return 12 end,
        DrawStringCentre = function(self, font, x, y, text) drawn[#drawn + 1] = tostring(text) end,
    }
end
KnoxSettings = {
    showSurvivorNameplates = function() return true end,
    survivorNameplateDistance = function() return 12 end,
}
KnoxPersistence = {
    getFactionForSurvivor = function(id) factionReads = factionReads + 1 return nil end,
    getSurvivorFactionId = function(id) return "alpha" end,
}
local characters = {}
KnoxSurvivorRuntime = { getCharacter = function(id) return characters[id] end }

for i = 1, 2 do
    local character = {
        getCurrentSquare = function() return square end,
        getZ = function() return 0 end, getX = function() return 0 end,
        getY = function() return 0 end, getAlpha = function() return 1 end,
        isDead = function() return false end,
    }
    characters["s" .. i] = character
    KS_LABELS[#KS_LABELS + 1] = {
        id = "s" .. i, character = character, name = "Person " .. i,
        company = { headline = "With Ana" }, colors = { [0] = { 1, 1, 1 } },
    }
end

-- Old path: every frame measured the name, the household line and the status
-- word, and re-read the faction. Forcing a refresh each frame reproduces that.
for frame = 1, 3 do
    for _, label in ipairs(KS_LABELS) do
        label.nameHalfWidth = nil
        label.companyChecked = nil
        label.companyText = nil
        label.companyWidth = nil
        label.statusWidthText = nil
        label.factionChecked = nil
        label.faction = nil
    end
    KS_RENDER()
end
local oldMeasures, oldFaction = measures, factionReads
assert(oldMeasures == 18, "old path measured three strings per label per frame, got "
    .. tostring(oldMeasures))
assert(oldFaction == 6, "old path read the faction per label per frame, got "
    .. tostring(oldFaction))

-- Current path: three frames over two labels, measured once per label.
measures, factionReads, textCalls = 0, 0, 0
for _, label in ipairs(KS_LABELS) do
    label.nameHalfWidth = nil
    label.companyChecked = nil
    label.companyText = nil
    label.companyWidth = nil
    label.statusWidthText = nil
    label.factionChecked = nil
    label.faction = nil
end
for frame = 1, 3 do KS_RENDER() end
assert(measures == 6, "text is measured once per label refresh, got " .. tostring(measures))
assert(factionReads == 2, "the faction is resolved once per label refresh, got "
    .. tostring(factionReads))
assert(textCalls == 3, "the text manager is fetched once per frame, got "
    .. tostring(textCalls) .. " (the pre-change path fetched it per label: 6)")

-- Freshness: the label object is not rebuilt here, exactly as between two
-- refreshes. A faction changed inside that lifetime must paint on the same frame
-- and keep the expensive lookup off the frames where nothing moved.
local factionId = "alpha"
local faction = { name = "Alpha", accent = { 1, 0, 0 }, formationNoticed = true }
KnoxPersistence.getFactionForSurvivor = function(id)
    factionReads = factionReads + 1
    return factionId ~= nil and faction or nil
end
KnoxPersistence.getSurvivorFactionId = function(id) return factionId end
for _, label in ipairs(KS_LABELS) do
    label.factionChecked = nil
    label.faction = nil
    label.factionKey = nil
end
local function paintTags()
    drawn = {}
    KS_RENDER()
    return table.concat(drawn, ",")
end

local first = paintTags()
assert(first:find("Alpha", 1, true) ~= nil,
    "the first frame paints the faction it resolved, got " .. first)

-- Joining another faction happens mid-lifetime: no refresh, no rebuilt label.
local resolvesBeforeChange = factionReads
factionId = "bravo"
faction = { name = "Bravo", accent = { 0, 1, 0 }, formationNoticed = true }
local second = paintTags()
local sameFrameResolves = factionReads - resolvesBeforeChange
assert(sameFrameResolves == 2,
    "the mid-refresh faction re-resolve is counted once per label, got "
        .. tostring(sameFrameResolves) .. " (the harness missed it)")
assert(second:find("Bravo", 1, true) ~= nil and second:find("Alpha", 1, true) == nil,
    "a faction change inside one label lifetime paints on the same frame, got " .. second)

-- A renamed faction is the same live table: it must paint without a re-lookup.
local beforeRename = factionReads
faction.name = "Bravo Company"
local third = paintTags()
assert(third:find("Bravo Company", 1, true) ~= nil,
    "a renamed faction paints immediately from the live record, got " .. third)
assert(factionReads == beforeRename,
    "a rename costs no faction lookup, got " .. tostring(factionReads - beforeRename))

KS_SAME_FRAME_RESOLVES = sameFrameResolves
KS_FACTION_TOTAL = factionReads

getNumActivePlayers = savedGlobals.getNumActivePlayers
getSpecificPlayer = savedGlobals.getSpecificPlayer
IsoCamera = savedGlobals.IsoCamera
getCore = savedGlobals.getCore
UIFont = savedGlobals.UIFont
getTextManager = savedGlobals.getTextManager
KnoxSettings = savedGlobals.KnoxSettings
KnoxPersistence = savedGlobals.KnoxPersistence
KnoxSurvivorRuntime = savedGlobals.KnoxSurvivorRuntime

KS_NAMEPLATE_RECEIPT = "measures_old=18 measures_new=6 faction_old=6"
    .. " faction_new=2 same_frame_resolves=" .. tostring(KS_SAME_FRAME_RESOLVES)
    .. " faction_total=" .. tostring(KS_FACTION_TOTAL)
    .. " text_manager_new=3 text_manager_old=6"
    .. " frames=3 labels=2"
