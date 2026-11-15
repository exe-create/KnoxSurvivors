-- Spoken diagnosis and triage: a trained survivor names the worst injury and
-- who is treated first. Drives the real triage reading and ordering, the real
-- training gate, and the real dialogue selection and naming. Only the native
-- body, the perk lookup, the activity feed and the personality store are stubbed
-- at their boundary, and each is put back before this fixture returns.
local M = assert(rawget(_G, "KnoxMedicalActions"), "the medical owner is loaded")
local D = assert(rawget(_G, "KnoxSurvivorDialogue"), "the dialogue owner is loaded")

local realFeed = rawget(_G, "KnoxActivityFeed")
local realPerks = rawget(_G, "Perks")
local said = {}
KnoxActivityFeed = { speak = function(_, line) said[#said + 1] = line; return true end }
if realPerks == nil then Perks = { Doctor = "Doctor" } end

local function part(opts)
    return {
        HasInjury = function() return opts.injury == true end,
        bleeding = function() return opts.bleeding == true end,
        bandaged = function() return opts.bandaged == true end,
        getBandageLife = function() return opts.life or 100 end,
        isInfectedWound = function() return opts.infected == true end,
        getFractureTime = function() return opts.fracture or 0 end,
        getSplintFactor = function() return opts.splint or 0 end,
        getAlcoholLevel = function() return 0 end,
    }
end
local function body(parts)
    return { getBodyDamage = function()
        return { getBodyParts = function()
            return { size = function() return #parts end,
                get = function(_, index) return parts[index + 1] end }
        end }
    end }
end
local function person(parts, name, level)
    local character = body(parts)
    character.getDisplayName = function() return name or "them" end
    character.getPerkLevel = function(_, perk) return level or 0 end
    return character
end

-- 1. What the body says, in the order a person treats it.
local bleeder = person({ part({ injury = true, bleeding = true }) }, "Mara")
local broken = person({ part({ injury = true, fracture = 200 }) }, "Dale")
local infected = person({ part({ injury = true, infected = true }) }, "Ruth")
local hurt = person({ part({ injury = true }) }, "Sam")
local dressed = person({ part({ bandaged = true, life = 0 }) }, "Ada")
local healthy = person({})

assert(M.triageKind(bleeder) == "bleeding", "an unstopped bleed is the worst thing read")
assert(M.triageKind(broken) == "fracture", "an unsplinted break is read as a break")
assert(M.triageKind(infected) == "infection", "an infected wound is read as infected")
assert(M.triageKind(hurt) == "wound", "a plain injury is read as a wound")
assert(M.triageKind(dressed) == "dressing", "a spent dressing is read as one")
assert(M.triageKind(healthy) == nil, "a whole body yields no diagnosis")

local order = M.triageOrder({ hurt, infected, broken, bleeder })
assert(#order == 4, "every casualty is ranked")
assert(order[1].patient == bleeder and order[1].kind == "bleeding",
    "the bleeding patient is treated first")
assert(order[2].patient == broken, "the break comes next")
assert(order[3].patient == infected, "then the infection")
assert(order[4].patient == hurt, "the plain wound last")
local stable = M.triageOrder({ hurt, infected })
assert(stable[1].patient == infected, "equal teams still rank by real urgency")

-- 2. Training is the price of saying it out loud.
assert(M.triageBriefing(person({}, "Kit", 2), { bleeder }) == nil,
    "an untrained survivor gives no clinical briefing")
local briefing = M.triageBriefing(person({}, "Kit", 5), { hurt, infected, broken, bleeder })
assert(briefing ~= nil and briefing.patient == bleeder and briefing.kind == "bleeding",
    "a trained survivor briefs the worst casualty first")
assert(briefing.team == 4 and #briefing.order == 4, "the briefing carries the whole team order")
assert(M.triageBriefing(person({}, "Kit", 5), {}) == nil,
    "a healthy team is never diagnosed")

-- 3. The words: the named patient, no placeholder, and one real spoken line.
local realPersonality = nil
local persistence = rawget(_G, "KnoxPersistence")
if persistence ~= nil then
    realPersonality = persistence.getSurvivorPersonality
    persistence.getSurvivorPersonality = function() return nil end
end
D.resetRuntime()
said = {}
local spoke, line = D.sayDiagnosis(person({}, "Kit", 5), "medic", "bleeding", "Mara", 100, 3600)
assert(spoke == true, "the diagnosis is actually spoken")
assert(type(line) == "string" and string.find(line, "Mara", 1, true) ~= nil,
    "the spoken line names the patient")
assert(string.find(line, "{name}", 1, true) == nil, "no placeholder reaches the player")
assert(said[1] == line, "the real feed received the line")

said = {}
D.resetRuntime()
local again, unnamed = D.sayDiagnosis(person({}, "Kit", 5), "medic", "wound", nil, 200, 3600)
assert(again == true and string.find(unnamed, "them", 1, true) ~= nil,
    "a patient with no readable name is not invented")

if persistence ~= nil and realPersonality ~= nil then
    persistence.getSurvivorPersonality = realPersonality
end
KnoxActivityFeed = realFeed
if realPerks == nil then Perks = nil end

print("Spoken triage PASS read=true order=true training=true spoken=true named=true")
