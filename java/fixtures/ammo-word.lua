-- The card's ammo row is a pure projection over the engine's own round count and
-- chamber flag; the dry-gun call is the same state said once in the speaker's
-- voice. This fixture proves the projection and the selection rules; it does not
-- fire a weapon, render a card or observe a line in game.
local word = assert(codecAmmoWord, "ammo word source is loaded")

assert(word(12, false) == "12 rounds", "a loaded magazine counts its rounds")
assert(word(2, false) == "2 rounds", "a plural count reads as rounds")
assert(word(1, false) == "1 round", "one round is singular")
assert(word(0, true) == "1 chambered", "a chambered round is still a shot")
assert(word(0, false) == "Empty", "no rounds and no chamber is empty")
assert(word(nil, false) == nil, "an unreadable count spends no row")
assert(word(-3, false) == "Empty", "a negative count cannot invent rounds")
assert(word(2.8, false) == "2 rounds", "a fractional count floors to whole rounds")
assert(word(0, "true") == "Empty", "a string flag is not a chambered round")
assert(word(0 / 0, false) == nil, "a NaN count is unknown, not empty")

-- The firearm owner exposes the same read for the card and the call. A broken
-- or non-ranged item is not ammunition information.
local F = assert(rawget(_G, "KnoxFirearmSupport"), "firearm owner missing")
local gun = { ammo = 0, chambered = false, ranged = true }
function gun:IsWeapon() return true end
function gun:isRanged() return self.ranged end
function gun:isBroken() return false end
function gun:isSelectFire() return false end
function gun:getCurrentAmmoCount() return self.ammo end
function gun:isRoundChambered() return self.chambered end
local character = { getPrimaryHandItem = function() return gun end }

local state, rounds = F.ammoState(character)
assert(state == "dry" and rounds == 0, "an empty gun reads dry")
gun.ammo = 1
state = F.ammoState(character)
assert(state == "loaded", "a loaded gun reads loaded")
gun.ammo = 0
gun.chambered = true
state = F.ammoState(character)
assert(state == "loaded", "a chambered round keeps the gun loaded")
gun.chambered = false
gun.ranged = false
assert(F.ammoState(character) == "not_firearm", "a melee item is not a gun")
gun.ranged = true
gun.getCurrentAmmoCount = function() return nil end
assert(F.ammoState(character) == "unknown", "a missing count is unknown")

-- The call is said in the speaker's own voice. Every line obeys the same rules
-- as the other reaction banks: short, first person, no system explanation.
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")
local realPersistence = rawget(_G, "KnoxPersistence")

local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end

KnoxPersistence = nil
local shared = D.linesFor("s1", "ammo_dry")
assert(type(shared) == "table" and #shared >= 3, "the shared ammo bank exists")
assert(shared[1] == "I'm dry. Reloading.", "the shared ammo bank has its own words")
local broken = D.linesFor("s1", "weapon_broken")
assert(table.concat(shared, "|") ~= table.concat(broken or {}, "|"),
    "a dry gun is not a broken weapon")

local signatures = {}
for _, key in ipairs({ "brave", "guarded", "sociable", "frightened", "loner" }) do
    KnoxPersistence = { getSurvivorPersonality = function()
        return { personality = key }
    end }
    local lines, voice = D.linesFor("s1", "ammo_dry")
    assert(voice == key, "the ammo voice answers: " .. key)
    assert(lines ~= shared, "a voice does not reuse the shared words: " .. key)
    local signature = table.concat(lines, "|")
    assert(signatures[signature] == nil, "two voices do not share a dry line")
    signatures[signature] = key
    for _, line in ipairs(lines) do
        assert(wordCount(line) <= 18, "inside the budget (" .. key .. "): " .. line)
        local lower = line:lower()
        assert(lower:find("i ", 1, true) ~= nil or lower:find(" i", 1, true) ~= nil
            or lower:find("i'", 1, true) ~= nil
            or lower:find("me", 1, true) ~= nil or lower:find("my", 1, true) ~= nil,
            "spoken in the first person (" .. key .. "): " .. line)
        assert(lower:find("durab", 1, true) == nil and lower:find("condition", 1, true) == nil
            and lower:find("mod", 1, true) == nil,
            "never explains the system: " .. line)
    end
end

KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "unknown_type" }
end }
local fallback, voice = D.linesFor("s1", "ammo_dry")
assert(fallback == shared and voice == "unknown_type", "an unknown label falls back")

KnoxPersistence = realPersistence
print("AmmoWord PASS rounds=true chambered=true empty=true unknown=true voices=true")
