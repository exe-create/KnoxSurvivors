local needs=KnoxBaseNeeds
assert(needs~=nil,"production needs owner loaded")
local summary={loadedPolicies=1,totals={food=0,water=0,building=0},misplacedItems=0}

local tasks={{id="cook",type="cook",state="queued",priority=50}}
needs.apply(tasks,summary,3)
assert(tasks[1].basePriority==50 and tasks[1].priority==70,
    "shortage bonus layers over the persisted task priority")
assert(tasks[1].appliedPriority==70,"the pass records the value it wrote")

needs.apply(tasks,summary,3)
assert(tasks[1].basePriority==50 and tasks[1].priority==70,
    "a repeat pass does not stack the same shortage bonus")

-- The player, the task board or a work-area edit can change a job priority
-- between passes. That edit is the new baseline and must not be overwritten
-- by the cached pre-shortage value.
tasks[1].priority=95
needs.apply(tasks,summary,3)
assert(tasks[1].basePriority==95 and tasks[1].priority==100,
    "an edited priority becomes the new base instead of being reverted")

-- Reload shape: priority already carries the last bonus and the marker agrees.
local reloaded={{id="guard",type="guard",priority=56,basePriority=50,appliedPriority=56}}
needs.apply(reloaded,summary,3)
assert(reloaded[1].priority==56,"reload does not stack the persisted shortage bonus twice")

-- Older saves have no marker. The saved base is still authoritative, so the
-- first pass must not add the same bonus again.
local legacy={{id="guard-2",type="guard",priority=56,basePriority=50}}
needs.apply(legacy,summary,3)
assert(legacy[1].priority==56 and legacy[1].appliedPriority==56,
    "legacy save keeps its base and starts tracking edits")

-- Streamed-out or unassigned storage is unknown stock, not a shortage.
local unknown={{id="chop-3",type="chop_tree",priority=64,basePriority=64,appliedPriority=64}}
needs.apply(unknown,{loadedPolicies=0,totals={}},2)
assert(unknown[1].priority==64,"unknown storage leaves the persisted priority untouched")

-- Exercise the real automatic-job handoff, including the unchanged metadata.
local jobs = assert(KnoxBaseJobs)
local oldPrepare, oldSelect = jobs.prepareWorkforce, jobs.selectEligibleTask
local oldStorage, oldBoard, oldPersistence = KnoxBaseStorage, KnoxBaseTaskBoard, KnoxPersistence
local queued = {{id="floor-cook",type="cook",priority=50},
    {id="sort",type="sort_depot",priority=40}}
local storageSummary = {loadedPolicies=1, totals={food=2}, floorTotals={food=4}, misplacedItems=1}
jobs.prepareWorkforce = function() end
jobs.selectEligibleTask = function() return nil end
KnoxBaseStorage = {summarize=function() return storageSummary end}
KnoxBaseTaskBoard = {queued=function() return queued end}
KnoxPersistence = {getBaseResidentIds=function() return {1, 2} end}
jobs.ensureAutomaticTask({id="floor-base",settings={}}, nil, "resident")
assert(queued[1].priority==50, "floor food prevents an unnecessary cooking priority bonus")
assert(queued[2].priority==58, "misplaced-item metadata still drives sorting priority")
assert(storageSummary.totals.food==2 and storageSummary.floorTotals.food==4,
    "automatic priority calculation does not mutate the shared storage summary")
storageSummary.loadedPolicies=0
queued[1].priority=50
queued[1].basePriority=50
queued[1].appliedPriority=50
storageSummary.floorTotals.food=0
jobs.ensureAutomaticTask({id="floor-base",settings={}}, nil, "resident")
assert(queued[1].priority==50, "unknown storage still leaves automatic priorities unchanged")
jobs.prepareWorkforce, jobs.selectEligibleTask = oldPrepare, oldSelect
KnoxBaseStorage, KnoxBaseTaskBoard, KnoxPersistence = oldStorage, oldBoard, oldPersistence

print("Base priority cache PASS layered=true no_stacking=true edit_wins=true legacy_safe=true unknown_stock_safe=true")
