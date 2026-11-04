-- Ambient re-shelving must reach the misfiled item, not just the first forty
-- items of a full shelf. This fixture drives the real `KnoxBaseOrganize.find`
-- with fake policies, containers and items, and proves the two-budget scan:
-- accepted items cannot hide a misfiled one, the expensive tier comparison stays
-- bounded, and settled bases stay settled.
local Organize = KnoxBaseOrganize
assert(type(Organize) == "table" and type(Organize.find) == "function",
    "the base organize owner must be loaded")

local previousStorage = KnoxBaseStorage
local previousCell = getCell
getCell = function() return {} end

local function item(id, kind, favorite)
    return {
        id = id, kind = kind, favorite = favorite == true,
        getID = function(self) return self.id end,
        isFavorite = function(self) return self.favorite end,
    }
end

local function containerOf(list)
    return {
        getItems = function()
            return {
                size = function() return #list end,
                get = function(_, index) return list[index + 1] end,
            }
        end,
    }
end

local square = { getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end }
local character = { getCurrentSquare = function() return square end }
local base = { id = "base-1" }

-- Each test builds its own shelves. A shelf accepts only its own kind, so a
-- foreign item in it is "misfiled" exactly like the overflow case.
local function setup(shelves)
    local policies, containers = {}, {}
    for _, shelf in ipairs(shelves) do
        policies[#policies + 1] = {
            key = shelf.key, x = 0, y = 0, z = 0,
            storageRole = shelf.accepts, rank = shelf.rank or 2,
            transientContainer = shelf.transient or nil,
        }
        containers[shelf.key] = containerOf(shelf.items)
    end
    KnoxBaseStorage = {
        operationalPolicies = function() return policies end,
        resolvePolicy = function(policy)
            return { container = containers[policy.key], policy = policy }
        end,
        acceptsDeposit = function(policy, it)
            return policy.storageRole == it.kind
        end,
        canReceiveItem = function(container, _, it)
            if container == nil or it == nil then return false end
            for _, shelf in ipairs(shelves) do
                if containers[shelf.key] == container then
                    return shelf.full ~= true
                end
            end
            return false
        end,
        priorityRank = function(policy) return policy.rank or 2 end,
        classifyItem = function(it) return it.kind end,
    }
    return policies
end

local function find(...)
    local plan, reason = Organize.find(base, character, ...)
    return plan, reason
end

-- A hundred accepted items in a full food shelf must not consume the scan.
local fullShelf, misfiledItems = {}, {}
for i = 1, 100 do fullShelf[i] = item("food-" .. i, "food") end
misfiledItems[1] = item("tool-1", "tool")
misfiledItems[2] = item("food-late", "food")
setup({
    { key = "food", accepts = "food", items = fullShelf },
    { key = "tools", accepts = "tool", items = misfiledItems },
})
local plan, reason = find()
assert(plan ~= nil and reason == "found",
    "the misfiled food behind a full shelf is still found, got " .. tostring(reason))
assert(plan.item.id == "food-late", "the misfiled item is the plan's item")
assert(plan.sourcePolicy.key == "tools" and plan.destinationPolicy.key == "food",
    "the plan carries the shelf it is in and the shelf that accepts it")
assert(plan.phase == "prepare" and plan.baseId == "base-1",
    "the plan starts in its prepare phase for this base")

-- A settled base never shuffles items between equal shelves.
setup({
    { key = "food", accepts = "food", items = { item("food-1", "food") } },
    { key = "tools", accepts = "tool", items = { item("tool-1", "tool") } },
})
local settled, settledReason = find()
assert(settled == nil and settledReason == "shelves_settled",
    "a settled base produces no work")

-- A favorite item is never taken, even from the wrong shelf.
setup({
    { key = "food", accepts = "food", items = { item("food-1", "food") } },
    { key = "tools", accepts = "tool", items = { item("food-fav", "food", true) } },
})
settled, settledReason = find()
assert(settled == nil and settledReason == "shelves_settled",
    "a favorite item stays where the player put it")

-- Caller filters still win: a blocked item is not taken.
setup({
    { key = "food", accepts = "food", items = { item("food-1", "food") } },
    { key = "tools", accepts = "tool", items = { item("food-blocked", "food") } },
})
settled = find(function() return false end)
assert(settled == nil, "an unavailable item is left alone")

-- A full destination refuses the move instead of pretending it can happen.
setup({
    { key = "food", accepts = "food", items = { item("food-1", "food") }, full = true },
    { key = "tools", accepts = "tool", items = { item("food-late", "food") } },
})
settled, settledReason = find()
assert(settled == nil and settledReason == "shelves_settled",
    "a misfiled item with no room anywhere is not a plan")

-- A demoted item still moves up a tier, and that expensive path stays small.
setup({
    { key = "food", accepts = "food", items = { item("food-1", "food") }, rank = 3 },
    { key = "food-high", accepts = "food", items = {}, rank = 1 },
})
local demoted = find()
assert(demoted ~= nil and demoted.item.id == "food-1",
    "an accepted item in a low-tier shelf still moves to the high tier")
assert(demoted.destinationPolicy.key == "food-high", "it moves to the higher tier")

-- The scan itself is bounded: a huge accepted shelf and no destination settles.
local huge = {}
for i = 1, 500 do huge[i] = item("bulk-" .. i, "food") end
setup({ { key = "food", accepts = "food", items = huge } })
local bounded, boundedReason = find()
assert(bounded == nil and boundedReason == "shelves_settled",
    "an enormous shelf settles instead of scanning forever")

-- An auto-discovered shelf is itself misplaced ground: its items move to an
-- explicit filter, never between two unfiltered containers.
setup({
    { key = "loose", accepts = "food", items = { item("food-loose", "food") }, transient = true },
    { key = "food", accepts = "food", items = {} },
})
local fromLoose = find()
assert(fromLoose ~= nil and fromLoose.item.id == "food-loose"
    and fromLoose.destinationPolicy.key == "food",
    "an item in an unfiltered container moves to a real filter")

KnoxBaseStorage = previousStorage
getCell = previousCell
print("Base organize misfiled PASS fullShelf=true settled=true favorite=true "
    .. "bounded=true transient=true")
