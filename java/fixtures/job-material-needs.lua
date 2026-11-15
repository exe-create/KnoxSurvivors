local P, Jobs, C = assert(KnoxBaseSupplyPlanner), assert(KnoxBaseJobs), assert(KnoxAutonomyController)
local stock = { ["Base.Nails"] = 0, ["Base.Saw"] = 0 }
local tasks = {
    { id = "window", type = "barricade", state = "queued",
        requirements = { items = { ["Base.Nails"] = 2 } } },
}
local goals = P.taskItemGoals(tasks, function(t) return stock[t] or 0 end)
assert(#goals == 1 and goals[1].key == "item:Base.Nails" and goals[1].missing == 2,
    "a queued barricade creates one exact nails goal with the real count")
stock["Base.Nails"] = 2
assert(#P.taskItemGoals(tasks, function(t) return stock[t] or 0 end) == 0,
    "delivered nails clear the job goal without changing stock")
for i = 2, 6 do tasks[i] = { state = "queued", requirements = {
    items = { ["Base.Saw"] = 1 }, itemRules = { ["Base.Saw"] = { usable = true } } } } end
goals = P.taskItemGoals(tasks, function(t) return stock[t] or 0 end)
assert(#goals == 1 and goals[1].fullType == "Base.Saw" and goals[1].target == 1,
    "five jobs share one usable saw instead of hoarding five")
local saw = { getFullType = function() return "Base.Saw" end, isBroken = function() return false end }
stock["Base.Saw"] = 1
local function count(t, req)
    if t == "Base.Saw" then return P.matchesRequirement(saw, req) and 1 or 0 end
    return stock[t] or 0
end
assert(#P.taskItemGoals(tasks, count) == 0, "an intact shared saw satisfies the queued work")
saw.isBroken = function() return true end
assert(P.taskItemGoals(tasks, count)[1].missing == 1, "a broken saw brings the tool goal back")
assert(#P.taskItemGoals(tasks, function() error("unloaded") end) == 0,
    "an unreadable stock reader never claims an empty cupboard")
assert(#P.taskItemGoals({ { state = "complete", requirements = tasks[1].requirements } }, count) == 0,
    "finished work creates no demand")

-- Discovery and stock are world boundaries. Keep all production preparation,
-- demand and election logic; suppress unrelated engine discovery in this world.
local names = { "KnoxBaseFarming", "KnoxBaseWoodcutting", "KnoxBaseCorpseHandling",
    "KnoxBaseRepairs", "KnoxBaseCooking", "KnoxGroupScavenge", "KnoxJobTestSupplies" }
local saved = {}
for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
for _, name in ipairs(names) do _G[name] = { findTask = function() return nil end } end
_G.KnoxGroupScavenge = nil
_G.KnoxJobTestSupplies = nil
local storage, persistence, runtime = KnoxBaseStorage, KnoxPersistence, rawget(_G, "KnoxSurvivorRuntime")
local oldStorage = storage.summarize
local oldCell = getCell
local oldIds, oldDuty = persistence.getBaseResidentIds, persistence.getSurvivorDuty
local oldReconcile, oldClock = persistence.reconcileBaseTaskClaims, getGameTime
storage.summarize = function() return { loadedPolicies = 1, totals = {} } end
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local container = { getType = function() return "crate" end, isExistYet = function() return true end }
container.getItems = function()
    local items = {}
    if stock["Base.Nails"] > 0 then items[#items + 1] = {
        getFullType = function() return "Base.Nails" end,
        getCount = function() return stock["Base.Nails"] end,
    } end
    if stock["Base.Saw"] > 0 then items[#items + 1] = saw end
    return list(items)
end
local object, square = {}, {}
object.getContainerCount = function() return 1 end
object.getContainerByIndex = function() return container end
object.getObjectIndex = function() return 0 end
object.getSquare = function() return square end
square.getObjects = function() return list({ object }) end
square.getX = function() return 76000 end
square.getY = function() return 76000 end
square.getZ = function() return 0 end
local cell = { getGridSquare = function() return square end }
getCell = function() return cell end
persistence.reconcileBaseTaskClaims = function() end
persistence.getBaseResidentIds = function() return {} end
persistence.getSurvivorDuty = function() return nil end
_G.KnoxSurvivorRuntime = nil
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
stock["Base.Nails"] = 0
local base = { id = "job-material-fixture", zones = {}, tasks = { tasks[1] },
    settings = { autoBarricade = false },
    territory = { minX = 76000, minY = 76000, width = 1, height = 1, z = 0 } }
local prepared, ready = Jobs.prepareWorkforce(base, nil, 10)
assert(prepared and #ready == 1 and ready[1].fullType == "Base.Nails",
    "workforce preparation exposes the current job material goal")
stock["Base.Nails"] = 2
assert(#Jobs.materialGoals(base) == 0, "real storage contents clear job demand")
stock["Base.Nails"] = 0
local controller = setmetatable({ id = "job-runner", baseId = base.id, base = base }, { __index = C })
assert(controller:baseSupplyNeed(100) == "find_materials",
    "job materials win automatic election before a generic food floor")
base.tasks = { tasks[2], tasks[3], tasks[4], tasks[5], tasks[6] }
assert(Jobs.materialGoals(base)[1].target == 1,
    "real storage rejects a broken saw shared by five jobs")
saw.isBroken = function() return false end
assert(#Jobs.materialGoals(base) == 0, "real storage accepts one intact shared saw")
base.tasks = { tasks[1] }

-- Extracted production beginWorldSearch, with only its world-search boundary
-- doubled. Observe the candidate types its supplied matcher actually accepts.
local accepted = {}
local search = jobMaterialSearchFactory(function(_, _, _, matcher)
    for _, t in ipairs({ "Base.Nails", "Base.Plank", "Base.Saw" }) do
        local item = { getFullType = function() return t end }
        if matcher == nil or matcher(item) then accepted[#accepted + 1] = t end
    end
    return nil
end)
local searching = setmetatable({ base = base, baseSupplyTrip = true, nextWorldSearch = 0,
    setLifeIntent = function() end }, { __index = search })
searching:beginWorldSearch("find_materials", 100)
assert(#accepted == 1 and accepted[1] == "Base.Nails",
    "the real world-search entry passes only the job's exact item to search")
accepted = {}
searching.nextWorldSearch = 0
searching.baseSupplyOrder = { kind = "find_materials", item = "Base.Plank" }
searching:beginWorldSearch("find_materials", 200)
assert(#accepted == 1 and accepted[1] == "Base.Plank", "an explicit fetch item wins over job demand")

storage.summarize = oldStorage
getCell = oldCell
persistence.getBaseResidentIds, persistence.getSurvivorDuty = oldIds, oldDuty
persistence.reconcileBaseTaskClaims, getGameTime = oldReconcile, oldClock
_G.KnoxSurvivorRuntime = runtime
for _, name in ipairs(names) do _G[name] = saved[name] end
print("Job material needs PASS exactNails=true sharedTool=true brokenTool=true prepare=true realStorageCount=true election=true searchMatcher=true nativeGameplay=false")
