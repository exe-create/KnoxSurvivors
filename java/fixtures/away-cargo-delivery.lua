-- A returned mission haul must reach permitted base storage through real
-- transfers. This exercises the marker that starts that chain: only an item
-- that really left the searched container is marked, only for the member's own
-- base, and the mark exists so the ordinary base deposit path can shelve it.
local C = KnoxAutonomyController
local Looting = KnoxSurvivorLooting
assert(type(C) == "table" and type(Looting) == "table",
    "the controller and the loot planner must both be loaded")

local function newItem(fullType, favorite)
    local modData = {}
    return {
        fullType = fullType,
        favorite = favorite == true,
        getFullType = function(self) return self.fullType end,
        getModData = function(self) return modData end,
        isBroken = function() return false end,
        IsFood = function() return false end,
        isFavorite = function(self) return self.favorite end,
        getContainer = function(self) return self.container end,
        isContainer = function() return false end,
        getInventory = function() return nil end,
    }
end

local function newContainer(entries)
    local items = entries or {}
    local list = {
        size = function(self) return #items end,
        get = function(self, index) return items[index + 1] end,
    }
    return {
        entries = items,
        getItems = function(self) return list end,
        contains = function(self, candidate)
            for _, entry in ipairs(items) do
                if entry == candidate then return true end
            end
            return false
        end,
        add = function(self, entry) items[#items + 1] = entry end,
        remove = function(self, entry)
            for index, candidate in ipairs(items) do
                if candidate == entry then
                    table.remove(items, index)
                    return true
                end
            end
            return false
        end,
    }
end

local function newCharacter()
    local inventory = newContainer({})
    local character = {
        inventory = inventory,
        getInventory = function(self) return self.inventory end,
        isEquipped = function() return false end,
        isHandItem = function() return false end,
        isAttachedItem = function() return false end,
    }
    return character, inventory
end

-- Real transfer: the item left the searched container and is in the survivor's
-- inventory, which is exactly what the search receipt just verified.
local character, inventory = newCharacter()
local searched = newContainer({})
local cargo = newItem("Base.CannedBeans")
searched:add(cargo)
assert(Looting.markSettlementDelivery(character, cargo, searched, "base-1", "cargo-1") == false,
    "carrying-nothing yet: an item still in the container cannot be marked")
assert(Looting.settlementDeliveryMatches(cargo, "base-1") == false,
    "a refused mark leaves no provenance")
searched:remove(cargo)
inventory:add(cargo)
cargo.container = inventory
assert(Looting.markSettlementDelivery(character, cargo, searched, "base-1", "cargo-1") == true,
    "a real transfer can be marked for the settlement")
assert(Looting.settlementDeliveryMatches(cargo, "base-1", "cargo-1"),
    "the mark names the base and the survivor")
assert(Looting.settlementDeliveryMatches(cargo, "base-2") == false,
    "another base never inherits the cargo")
assert(Looting.findSettlementDelivery(character, "base-1", "cargo-1") == cargo,
    "the base deposit owner can discover the marked cargo")
assert(Looting.findSettlementDelivery(character, "base-2", "cargo-1") == nil,
    "discovery is scoped to the member's own base")

-- The controller only marks what the mission actually brought back.
local originalDuty = KnoxPersistence.getSurvivorDuty
KnoxPersistence.getSurvivorDuty = function()
    return { mode = "away", previousDuty = { mode = "base", baseId = "base-1" } }
end
local controller = setmetatable({ id = "cargo-1", character = character }, C)

local second = newItem("Base.CannedSoup")
inventory:add(second)
second.container = inventory
local supply = { container = searched, items = { { item = second } } }
assert(controller:markAwayCargoDelivery(supply) == 1,
    "a transferred mission item is marked for the member's base")
assert(Looting.settlementDeliveryMatches(second, "base-1", "cargo-1"),
    "the mission cargo carries the durable delivery marker")

assert(Looting.findSettlementDelivery(character, "base-1", "cargo-1") == second,
    "the delivery owner picks the marked cargo up")

-- A favorite is the survivor's own kit. The marker records a real transfer,
-- so the pickup step is what refuses it and drops the provenance.
local favorite = newItem("Base.CannedPeaches", true)
inventory:add(favorite)
favorite.container = inventory
assert(controller:markAwayCargoDelivery({ container = searched,
    items = { { item = favorite } } }) == 1,
    "the marker itself only records that the item really moved")
assert(Looting.findSettlementDelivery(character, "base-1", "cargo-1") ~= favorite,
    "a favorite never becomes a settlement delivery candidate")
assert(Looting.settlementDeliveryMatches(favorite, "base-1") == false,
    "the pickup step drops provenance from a favorite")

-- An item the search did not actually take cannot be marked.
local untouched = newItem("Base.Log")
searched:add(untouched)
assert(controller:markAwayCargoDelivery({ container = searched,
    items = { { item = untouched } } }) == 0,
    "an item still in the container is not mission cargo")

-- A single-item supply shape is honoured too.
local single = newItem("Base.Nails")
inventory:add(single)
single.container = inventory
assert(controller:markAwayCargoDelivery({ container = searched, item = single }) == 1,
    "the single-item supply shape is marked the same way")

-- A companion has no base to deliver to, so nothing is marked.
KnoxPersistence.getSurvivorDuty = function()
    return { mode = "away", previousDuty = { mode = "companion", order = "follow" } }
end
local loose = newItem("Base.Screws")
inventory:add(loose)
loose.container = inventory
assert(controller:markAwayCargoDelivery({ container = searched,
    items = { { item = loose } } }) == 0,
    "cargo with no settlement to deliver to stays unmarked")
assert(Looting.settlementDeliveryMatches(loose, "base-1") == false,
    "nothing is attributed to an unrelated base")

KnoxPersistence.getSurvivorDuty = originalDuty

-- The mark is what the delivery acknowledgement clears, so a shelved item
-- leaves no stale provenance behind.
assert(Looting.clearSettlementDelivery(second, "base-1", "cargo-1") == true,
    "the delivery acknowledgement clears the mark")
assert(Looting.settlementDeliveryMatches(second, "base-1") == false,
    "a shelved item loses its provenance")
assert(Looting.findSettlementDelivery(character, "base-1", "cargo-1") ~= second,
    "a shelved item is no longer pending delivery")
assert(Looting.clearSettlementDelivery(second, "base-1", "cargo-1") == false,
    "a repeated acknowledgement cannot clear an already-shelved item")

print("Away cargo delivery PASS real_transfer_only=true base_scoped=true favorites_kept=true "
    .. "no_base_unmarked=true mark_cleared=true")
