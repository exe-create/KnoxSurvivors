-- The wheel offers stances, formations, permissions and pickup/gear policies but
-- had no way to say which one is currently set; the right-click menu derived its
-- own defaults. This fixture drives the shared read-out and the real radial fill.
local service = assert(KnoxCompanionService, "companion service must be loaded")
local radial = assert(KnoxRadialOrders, "radial must be loaded")

-- 1. The real setters write the fields the read-out reads.
local id = "codec-person"
local owner = "codec-owner"
assert(KnoxPersistence.setCompanionCombatStance(id, owner, "aggressive", 12))
assert(KnoxPersistence.setCompanionFormation(id, owner, "single_file", 3, 12))
assert(KnoxPersistence.setCompanionWeaponPreference(id, owner, "melee", 12))
assert(KnoxPersistence.setCompanionClimbing(id, owner, false, 12))
assert(KnoxPersistence.setCompanionDoorOpening(id, owner, false, 12))
assert(KnoxPersistence.setCompanionAutoLoot(id, owner, true, 12))
assert(KnoxPersistence.setPlayerAutoEquipment(id, owner, false, 12))

local tactics = assert(service.survivorTactics(id), "a real companion must have a read-out")
assert(tactics.mode == "companion" and tactics.order == "follow", "duty order is reported")
assert(tactics.stance == "aggressive" and tactics.formation == "single_file"
    and tactics.spacing == 3, "stance and formation follow the setters")
assert(tactics.weapon == "melee" and tactics.climbing == false and tactics.doors == false,
    "weapon and traversal permissions follow the setters")
assert(tactics.loot == true and tactics.equipment == false,
    "pickup and upgrade policies follow the setters")
assert(service.survivorTactics("no-such-survivor") == nil,
    "an unknown survivor has no invented state")

-- 2. Shared settings: agreed values survive, a mixed value disappears.
local getCompanionIds = function() return { "codec-person" } end
service.getCompanionIds = getCompanionIds
local common, read, owned = service.commonTactics({})
assert(read == 1 and owned == 1, "common settings count the members it read")
assert(common.stance == "aggressive" and common.spacing == 3,
    "one companion contributes every setting")

local fakeDuty = {
    ["a"] = { mode = "companion", order = "follow", combatStance = "defensive",
        followerFormation = "paired", followerSpacing = 2, jobPreference = "auto" },
    ["b"] = { mode = "companion", order = "follow", combatStance = "aggressive",
        followerFormation = "paired", followerSpacing = 2, jobPreference = "auto" },
}
local fakePolicies = {
    ["a"] = { allowClimbing = true, allowDoorOpening = true, weaponPreference = "auto",
        autoLoot = false, autoEquipment = true },
    ["b"] = { allowClimbing = true, allowDoorOpening = true, weaponPreference = "auto",
        autoLoot = false, autoEquipment = true },
}
local realPersistence, realSettings = KnoxPersistence, rawget(_G, "KnoxSettings")
KnoxPersistence = {
    getSurvivorDuty = function(survivorId) return fakeDuty[survivorId] end,
    getSurvivorPolicies = function(survivorId) return fakePolicies[survivorId] end,
}
service.getCompanionIds = function() return { "a", "b" } end

local mixed = service.commonTactics({})
assert(mixed.order == "follow" and mixed.formation == "paired" and mixed.spacing == 2,
    "agreed settings are reported for the party")
assert(mixed.stance == nil, "a split stance is not reported as one person's value")
assert(mixed.loot == false and mixed.equipment == true,
    "agreed booleans survive the merge")

-- 3. Sandbox door default is resolved by the read-out, not by each menu.
_G.KnoxSettings = { allowSurvivorDoorWindowOpening = function() return false end }
fakePolicies["a"] = { allowDoorOpening = nil }
fakePolicies["b"] = { allowDoorOpening = nil }
assert(service.survivorTactics("a").doors == false,
    "the sandbox default to forbid doors is honoured")
_G.KnoxSettings = { allowSurvivorDoorWindowOpening = function() return true end }
assert(service.survivorTactics("a").doors == true,
    "the sandbox default to allow doors is honoured")
fakeDuty["a"].followerSpacing = 9
assert(service.survivorTactics("a").spacing == 3, "an out-of-range spacing is clamped")
fakeDuty["a"].followerSpacing = 2
fakePolicies["a"] = { allowDoorOpening = false, allowClimbing = true }

-- 4. Presentation helpers.
assert(radial.markedLabel("Stance: Aggressive", false) == "Stance: Aggressive",
    "an inactive entry is unchanged")
assert(radial.markedLabel("Stance: Aggressive", true) == "Stance: Aggressive (active)",
    "the active entry says so")
assert(radial.markedLabel("Doors On", true, " (on)") == "Doors On (on)",
    "toggles can carry their own suffix")
assert(radial.tacticsSummary({}) == "Party Tactics",
    "an unknown party has no invented summary")
assert(radial.tacticsSummary({ stance = "passive", formation = "paired", spacing = 1,
    doors = true }):find("Passive", 1, true) ~= nil,
    "the summary names the current stance")

-- 5. The real wheel: one marked entry per page, read from live state.
fakeDuty["a"] = { mode = "companion", order = "follow", combatStance = "aggressive",
    followerFormation = "single_file", followerSpacing = 3, jobPreference = "auto" }
fakePolicies["a"] = { allowClimbing = false, allowDoorOpening = false,
    weaponPreference = "melee", autoLoot = true, autoEquipment = false }
service.getCompanionIds = function() return { "a" } end

local labels, entries = {}, {}
local menu = {
    clear = function(self) labels, entries = {}, {} end,
    addSlice = function(self, text, icon, callback, ...)
        labels[#labels + 1] = tostring(text)
        entries[#entries + 1] = { text = tostring(text), callback = callback, args = { ... } }
    end,
    addToUIManager = function(self) end,
}
getPlayerRadialMenu = function() return menu end
getSpecificPlayer = function() return {} end
local radialSelf = { playerNum = 0 }

local function fill(key)
    radial.fillKnox(radialSelf, key)
    return labels
end

local function marked(labels, needle)
    for _, label in ipairs(labels) do
        if label:find(needle, 1, true) ~= nil and label:find("(active)", 1, true) ~= nil then
            return label
        end
    end
    return nil
end

local function countSuffix(labels, suffix)
    local count = 0
    for _, label in ipairs(labels) do
        if label:find(suffix, 1, true) ~= nil then count = count + 1 end
    end
    return count
end

local stances = fill("pm:stance")
assert(marked(stances, "Aggressive"), "the current stance is marked on the wheel")
assert(countSuffix(stances, "(active)") == 1, "only the current stance is marked")

local access = fill("pm:access")
assert(marked(access, "Climbing Off"), "the refused climb permission is marked")
assert(marked(access, "Doors Off"), "the refused door permission is marked")
assert(countSuffix(access, "(active)") == 2,
    "only the two refused permissions are marked")

local weapons = fill("pm:weapons")
assert(marked(weapons, "Melee"), "the current weapon preference is marked")

local function labelWith(labels, needle)
    for _, label in ipairs(labels) do
        if label:find(needle, 1, true) ~= nil then return label end
    end
    return nil
end

local gear = fill("pm:utility")
assert(#gear >= 4, "the gear page still offers pickup and upgrade")
local pickUp = labelWith(gear, "Pick Up Useful")
assert(pickUp ~= nil and pickUp:find("(active)", 1, true) ~= nil,
    "picking items up reads as the live choice")
local noPickup = labelWith(gear, "Do Not Pick Up")
assert(noPickup ~= nil and noPickup:find("(active)", 1, true) == nil,
    "the other pickup choice is not also marked")
local keepGear = labelWith(gear, "Keep Current")
assert(keepGear ~= nil and keepGear:find("(active)", 1, true) ~= nil,
    "keeping current gear reads as the live choice")
local upgradeGear = labelWith(gear, "Upgrade Better")
assert(upgradeGear ~= nil and upgradeGear:find("(active)", 1, true) == nil,
    "the upgrade choice is not also marked")

local formation = fill("pm:formation")
assert(marked(formation, "Single File - spacing 3") ~= nil,
    "the live formation and spacing are marked")
assert(countSuffix(formation, "(active)") == 1, "only one formation pair is marked")

local orders = fill("knox_party")
assert(marked(orders, "Follow"), "the standing follow order is marked")
assert(countSuffix(orders, "(active)") == 1, "hold and relax are not also marked")

local tact = fill("pm:tactics")
assert(tact[1]:find("Now:", 1, true) == 1, "the tactics page states the current settings")
assert(tact[1]:find("Aggressive", 1, true) and tact[1]:find("Single File 3", 1, true)
    and tact[1]:find("Doors Off", 1, true),
    "the summary names stance, formation and door policy")

-- A page that used to exist twice now lands on the one gear page.
radial.orderPartyMore(radialSelf, "equipment")
assert(#labels >= 4 and labelWith(labels, "Keep Current") ~= nil,
    "a stale equipment callback reaches the merged gear page")

-- 6. A mixed party shows no false single answer.
service.getCompanionIds = function() return { "a", "b" } end
fakeDuty["b"] = { mode = "companion", order = "follow", combatStance = "defensive",
    followerFormation = "paired", followerSpacing = 2, jobPreference = "auto" }
fakePolicies["b"] = { allowClimbing = true, allowDoorOpening = true,
    weaponPreference = "auto", autoLoot = false, autoEquipment = true }
local splitStances = fill("pm:stance")
assert(countSuffix(splitStances, "(active)") == 0,
    "a split party does not claim one stance")
local splitFormation = fill("pm:formation")
assert(countSuffix(splitFormation, "(active)") == 0,
    "a split party does not claim one formation")

KnoxPersistence = realPersistence
_G.KnoxSettings = realSettings
service.getCompanionIds = getCompanionIds

print("Tactical read-out PASS shared_owner=true wheel_marks=stance/access/weapon/pickup/formation/orders mixed_party=unmarked summary=true")
