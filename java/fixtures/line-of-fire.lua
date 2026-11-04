-- A companion must not fire through the player. This drives the pure corridor
-- test over real coordinates and the voice selection rule; it does not fire a
-- weapon, run a combat tick or prove native ballistics.
local F = assert(rawget(_G, "KnoxFirearmSupport"), "firearm owner missing")

local function body(x, y, z)
    local value = { x = x, y = y, z = z }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    return value
end

local shooter = body(0, 0, 0)
local target = body(10, 0, 0)

assert(F.friendlyInLineOfFire(shooter, target, {}) == nil,
    "an empty corridor is clear")

local middle = body(5, 0.2, 0)
assert(F.friendlyInLineOfFire(shooter, target, { middle }) == middle,
    "a friend between muzzle and target blocks the shot")

local edge = body(5, 0.85, 0)
assert(F.friendlyInLineOfFire(shooter, target, { edge }) == edge,
    "a friend at the corridor edge still blocks")

local offAxis = body(5, 1.2, 0)
assert(F.friendlyInLineOfFire(shooter, target, { offAxis }) == nil,
    "a friend outside the corridor does not block")

local behind = body(-2, 0, 0)
assert(F.friendlyInLineOfFire(shooter, target, { behind }) == nil,
    "a friend behind the shooter does not block")

local beyond = body(12, 0, 0)
assert(F.friendlyInLineOfFire(shooter, target, { beyond }) == nil,
    "a friend past the target does not block")

local otherFloor = body(5, 0, 1)
assert(F.friendlyInLineOfFire(shooter, target, { otherFloor }) == nil,
    "a friend on another floor does not block")

local atMuzzle = body(0.05, 0, 0)
assert(F.friendlyInLineOfFire(shooter, target, { atMuzzle }) == nil,
    "a body at the muzzle is not a corridor blocker")

assert(F.friendlyInLineOfFire(shooter, target,
    { shooter, target, middle }) == middle,
    "the shooter and the target are never their own blockers")
assert(F.friendlyInLineOfFire(nil, target, { middle }) == nil,
    "a missing shooter has no line")
assert(F.friendlyInLineOfFire(shooter, nil, { middle }) == nil,
    "a missing target has no line")

-- The refusal is said in the speaker's own voice, and never pretends the gun
-- fired or jammed. Every line obeys the shared reaction rules.
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "dialogue owner missing")
local realPersistence = rawget(_G, "KnoxPersistence")

local function wordCount(line)
    local count = 0
    for _ in tostring(line):gmatch("%S+") do count = count + 1 end
    return count
end

KnoxPersistence = nil
local shared = D.linesFor("s1", "no_clear_shot")
assert(type(shared) == "table" and #shared >= 3, "the shared refusal bank exists")
assert(shared[1] == "You're in my line. Move.",
    "the shared refusal has its own words")
local dry = D.linesFor("s1", "ammo_dry")
assert(table.concat(shared, "|") ~= table.concat(dry or {}, "|"),
    "a refused shot is not an empty magazine")

local signatures = {}
for _, key in ipairs({ "brave", "guarded", "sociable", "frightened", "loner" }) do
    KnoxPersistence = { getSurvivorPersonality = function()
        return { personality = key }
    end }
    local lines, voice = D.linesFor("s1", "no_clear_shot")
    assert(voice == key, "the refusal voice answers: " .. key)
    assert(lines ~= shared, "a voice does not reuse the shared words: " .. key)
    local signature = table.concat(lines, "|")
    assert(signatures[signature] == nil, "two voices do not share a refusal")
    signatures[signature] = key
    for _, line in ipairs(lines) do
        assert(wordCount(line) <= 18, "inside the budget (" .. key .. "): " .. line)
        local lower = line:lower()
        assert(lower:find("i ", 1, true) ~= nil or lower:find(" i", 1, true) ~= nil
            or lower:find("i'", 1, true) ~= nil
            or lower:find("me", 1, true) ~= nil or lower:find("my", 1, true) ~= nil,
            "spoken in the first person (" .. key .. "): " .. line)
        assert(lower:find("jam", 1, true) == nil and lower:find("durab", 1, true) == nil
            and lower:find("condition", 1, true) == nil,
            "a refusal is not a jam: " .. line)
    end
end

KnoxPersistence = { getSurvivorPersonality = function()
    return { personality = "unknown_type" }
end }
local fallback, voice = D.linesFor("s1", "no_clear_shot")
assert(fallback == shared and voice == "unknown_type", "an unknown label falls back")

KnoxPersistence = realPersistence
print("LineOfFire PASS corridor=true behind=false floors=true voices=true")
