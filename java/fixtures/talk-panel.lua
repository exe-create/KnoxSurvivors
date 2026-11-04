-- The crosshair Talk panel used to show the same four tone tabs to everybody:
-- a stranger and a companion both got "Trade", "Ask to Join You" and "Insult",
-- and no tab ever said what the current orders or tactics were. This fixture
-- drives the real tab plan, the real state line, the real cycle read-out and
-- the real Ask answers, with no window involved.
local tabPlan = assert(KS_TAB_PLAN, "the tab plan must be exported")
local stateLine = assert(KS_STATE_LINE, "the state line must be exported")
local nextCycle = assert(KS_NEXT_CYCLE, "the cycle order must be exported")
local cycleLabel = assert(KS_CYCLE_LABEL, "the cycle wording must be exported")
local actionLabel = assert(KS_ACTION_LABEL, "the action wording must be exported")
local ask = assert(KS_ASK, "the Ask answers must be exported")

local function keys(plan)
    local list = {}
    for _, entry in ipairs(plan) do list[#list + 1] = entry.key end
    return table.concat(list, ",")
end

local function actions(plan, key)
    for _, entry in ipairs(plan) do
        if entry.key == key then return entry.actions end
    end
    return nil
end

local function hasLabel(list, needle)
    for _, action in ipairs(list or {}) do
        if action.label == needle then return true end
    end
    return false
end

local function character(values)
    values = values or {}
    return {
        getHealth = function() return values.health or 100 end,
        getStats = function()
            return { get = function(_, stat) return values[stat] or 0 end }
        end,
    }
end

-- 1. A stranger gets conversation, never orders they cannot receive.
local stranger = tabPlan({ owned = false })
assert(keys(stranger) == "friendly,ask,neutral,mean,hostile",
    "stranger tabs: " .. keys(stranger))
assert(actions(stranger, "orders") == nil and actions(stranger, "tactics") == nil,
    "a stranger cannot be given orders or policies")
assert(hasLabel(actions(stranger, "neutral"), "Trade")
    and hasLabel(actions(stranger, "neutral"), "Give an Item")
    and hasLabel(actions(stranger, "neutral"), "Ask to Join You")
    and hasLabel(actions(stranger, "neutral"), "Invite to Base"),
    "the stranger offer tab keeps trade, gift, recruitment and the base invitation")
assert(#actions(stranger, "ask") == 6 and #actions(stranger, "friendly") == 6,
    "six questions and six warm actions")
assert(stateLine({ owned = false, standing = "Cautious" }) == "Standing: Cautious",
    "a stranger shows their standing")

-- 2. A companion gets orders, policies and work, and no recruitment.
local companion = tabPlan({
    owned = true, resident = false,
    tactics = { order = "follow", stance = "defensive", formation = "paired", spacing = 2 },
})
assert(keys(companion) == "friendly,ask,orders,tactics,jobs,mean",
    "companion tabs: " .. keys(companion))
-- Talk is the only way in: the questions are a hidden page like the stranger's,
-- so an owned survivor never grows a tab the layout has to cramp.
local companionAsk = nil
for _, entry in ipairs(companion) do
    if entry.key == "ask" then companionAsk = entry end
end
assert(companionAsk ~= nil and companionAsk.hidden == true,
    "companion questions stay behind Talk instead of taking a tab")
assert(#actions(companion, "ask") == 6,
    "an owned survivor answers the same six questions")
local orders = actions(companion, "orders")
for _, label in ipairs({ "Follow", "Hold", "Relax", "Return Home", "Dismiss" }) do
    assert(hasLabel(orders, label), "companion order missing: " .. label)
end
assert(actions(companion, "neutral") == nil, "a companion is not offered recruitment")
assert(hasLabel(actions(companion, "friendly"), "Manage Inventory"),
    "your own survivor's pack is reachable from their panel")
local cycles = {}
for _, action in ipairs(actions(companion, "tactics")) do
    if action.cycle ~= nil then cycles[#cycles + 1] = action.cycle end
end
assert(table.concat(cycles, ",") == "stance,formation,weapon,doors,climbing,pickup",
    "companion tactics cycles: " .. table.concat(cycles, ","))
assert(hasLabel(actions(companion, "jobs"), "Find Food"),
    "a companion's jobs tab searches through the existing orders")
assert(hasLabel(actions(companion, "orders"), "Move Into Base"),
    "a follower can be offered a home")

-- 3. A resident is never offered companion-only policies.
local resident = tabPlan({
    owned = true, resident = true,
    tactics = { order = "guard", stance = "aggressive", weapon = "melee",
        work = "guard", lootRuns = false },
})
assert(keys(resident) == "friendly,ask,orders,tactics,jobs,mean",
    "resident tabs: " .. keys(resident))
-- A resident answers the same questions as anyone else: asking is a
-- conversation, and their panel reaches it through Talk too.
local residentAsk = nil
for _, entry in ipairs(resident) do
    if entry.key == "ask" then residentAsk = entry end
end
assert(residentAsk ~= nil and residentAsk.hidden == true,
    "resident questions stay behind Talk instead of taking a tab")
assert(#actions(resident, "ask") == 6, "a resident answers the same six questions")
for _, action in ipairs(actions(resident, "tactics")) do
    assert(action.cycle ~= "doors" and action.cycle ~= "climbing" and action.cycle ~= "pickup",
        "a resident cannot take a companion-only policy")
end
assert(hasLabel(actions(resident, "orders"), "Recall to Party")
    and hasLabel(actions(resident, "orders"), "Cancel Supply Order"),
    "resident orders are recall and supply, not follow")
assert(not hasLabel(actions(resident, "orders"), "Move Into Base"),
    "a resident is not offered a move they already made")
assert(not hasLabel(actions(companion, "orders"), "Recall to Party"),
    "a follower is not offered resident orders")

-- 4. Work preferences page in two halves and every tab fits the panel.
local pageOne = tabPlan({ owned = true, resident = true, tactics = {}, jobPage = 1 })
local pageTwo = tabPlan({ owned = true, resident = true, tactics = {}, jobPage = 2 })
local jobsOne, jobsTwo = actions(pageOne, "jobs"), actions(pageTwo, "jobs")
assert(hasLabel(jobsOne, "Automatic") and hasLabel(jobsOne, "More..."),
    "the first work page offers the common roles and a way forward")
assert(hasLabel(jobsTwo, "Farming") and hasLabel(jobsTwo, "Back"),
    "the second work page offers the rest and a way back")
assert(not hasLabel(jobsOne, "Barricading"), "the halves do not repeat each other")
for _, plan in ipairs({ stranger, companion, resident, pageOne, pageTwo }) do
    for _, entry in ipairs(plan) do
        assert(#entry.actions <= 6, entry.key .. " exceeded the six-action budget")
    end
end

-- 5. Every setting names its live value and cycles to the next real option.
local marked = {
    order = "hold", stance = "defensive", formation = "single_file", spacing = 3,
    weapon = "auto", doors = false, climbing = true, loot = true, lootRuns = true,
    work = "guard",
}
assert(cycleLabel(marked, "stance") == "Stance: Defensive")
assert(cycleLabel(marked, "formation") == "Formation: Single File 3")
assert(cycleLabel(marked, "weapon") == "Weapon: Any")
assert(cycleLabel(marked, "doors") == "Doors: Closed")
assert(cycleLabel(marked, "climbing") == "Climbing: Allowed")
assert(cycleLabel(marked, "pickup") == "Pick Up: On")
assert(cycleLabel(marked, "supplyruns") == "Supply Runs: On")
assert(nextCycle(marked, "stance").value == "passive", "stance cycles forward")
assert(nextCycle({ stance = "passive" }, "stance").value == "aggressive",
    "the stance cycle wraps instead of dead-ending")
assert(nextCycle(marked, "formation").spacing == 1,
    "formation and spacing cycle together, back to the first pair")
assert(nextCycle(marked, "doors").value == true, "closed doors cycle to allowed")
assert(nextCycle(marked, "climbing").value == false, "allowed climbing cycles to closed")
assert(nextCycle(marked, "pickup").value == false, "picking up cycles to off")
assert(actionLabel(marked, { label = "Hold", kind = "hold" }) == "Hold (active)",
    "the current order is marked")
assert(actionLabel(marked, { label = "Follow", kind = "follow" }) == "Follow",
    "a different order is not marked")
assert(actionLabel(marked, { label = "Guard", work = "guard" }) == "Guard (active)",
    "the current work preference is marked")
assert(stateLine({ owned = true, resident = false, tactics = marked })
    == "Hold  -  Defensive  -  Single File 3", "companion state line")
assert(stateLine({ owned = true, resident = true,
    tactics = { order = "guard", stance = "aggressive", work = "cooking" } })
    == "Guard  -  Aggressive  -  Cooking duty", "resident state line")
assert(stateLine({ owned = true, tactics = {} }) == "No orders  -  Defensive  -  Paired 2",
    "an unset survivor still reports the real defaults")

-- 6. Ask answers come from the clock, the weather, affiliation, group and body.
local realPersistence = KnoxPersistence
local hour = 3
getGameTime = function() return { getHour = function() return hour end } end
getClimateManager = function()
    return { isRaining = function() return false end, isSnowing = function() return false end }
end
CharacterStat = { HUNGER = "hunger", THIRST = "thirst", FATIGUE = "fatigue" }
assert(ask.day(character(), "someone"):find("Middle of the night", 1, true) == 1,
    "the answer follows the real clock")
hour = 14
assert(ask.day(character(), "someone"):find("Afternoon", 1, true) == 1,
    "the answer changes with the hour")
getClimateManager = function()
    return { isRaining = function() return true end, isSnowing = function() return false end }
end
assert(ask.day(character(), "someone"):find("rain", 1, true) ~= nil,
    "rain is reported when it is really raining")

KnoxPersistence = {
    getSurvivorAffiliation = function(id)
        if id == "owner" then return { kind = "player" } end
        if id == "settled" then return { kind = "faction", baseId = "b1" } end
        if id == "loose" then return { kind = "independent" } end
        return nil
    end,
    getBase = function(id) return id == "b1" and { name = "The Crib" } or nil end,
    getFactionForSurvivor = function(id)
        if id == "settled" then
            return { name = "420X", memberIds = { "a", "b", "c", "d" } }
        end
        return nil
    end,
    getTravelGroupFor = function() return nil end,
    getBaseStorageProblems = function(id)
        return id == "b1" and { { cause = "full" } } or {}
    end,
}
assert(ask.home(character(), "owner"):find("with you", 1, true) ~= nil,
    "somebody who works for you says so")
assert(ask.home(character(), "settled"):find("The Crib", 1, true) ~= nil,
    "a settled survivor names the real base")
assert(ask.home(character(), "loose"):find("Nowhere", 1, true) ~= nil
    or ask.home(character(), "loose"):find("No walls", 1, true) ~= nil,
    "an independent survivor has no invented home")
assert(ask.group(character(), "settled"):find("4 of us", 1, true) ~= nil,
    "the group answer counts the real roster")
assert(ask.group(character(), "owner"):find("with you", 1, true) ~= nil,
    "your own survivor does not report a stranger's group")
assert(ask.home(character(), "unknown"):find("No walls", 1, true) ~= nil,
    "an unknown affiliation falls back to the honest answer")
assert(ask.need(character(), "settled"):find("stores are full", 1, true) ~= nil,
    "what they need names the base's real storage problem")
assert(ask.health(character({ health = 20 }), "x"):find("hurt", 1, true) ~= nil,
    "low health is reported")
assert(ask.health(character({ hunger = 0.9 }), "x"):find("Hungry", 1, true) ~= nil,
    "hunger is reported")
assert(ask.health(character({ thirst = 0.9 }), "x"):find("Thirsty", 1, true) ~= nil,
    "thirst is reported")
assert(ask.health(character({}), "x"):find("Still standing", 1, true) ~= nil,
    "a healthy survivor says so instead of inventing a problem")
assert(ask.travels ~= nil, "the recorded-history question must be exported")
assert(ask.need(character(), "loose"):find("Nothing right now", 1, true) ~= nil,
    "no problem means no problem")
KnoxPersistence = realPersistence

print("Talk panel PASS strangerTabs=5 companionTabs=5 residentPolicies=3 status=1e")
