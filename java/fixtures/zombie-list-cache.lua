-- Counting harness for the shared per-tick zombie list. KS_ZOMBIE_LIST is the
-- real production cache function extracted from KS_ZombieAwareness.
local list = { size = function() return 2 end }
local reads = 0
local cell = { getZombieList = function(self) reads = reads + 1 return list end }

local a = KS_ZOMBIE_LIST(cell, 10)
local b = KS_ZOMBIE_LIST(cell, 10)
local c = KS_ZOMBIE_LIST(cell, 10)
assert(reads == 1, "one cell read per tick, got " .. tostring(reads))
assert(a == b and b == c, "every consumer in the same tick sees the same list")

KS_ZOMBIE_LIST(cell, 11)
assert(reads == 2, "a new tick reads the cell again, got " .. tostring(reads))

local otherList = { size = function() return 0 end }
local other = { getZombieList = function(self) reads = reads + 1 return otherList end }
local d = KS_ZOMBIE_LIST(other, 11)
assert(reads == 3, "another cell is never served the old cell's list")
assert(d == otherList, "each cell keeps its own list handle")

-- Old path, counted for the record: three consumers asking the cell directly in
-- one tick cost three reads.
local before = 0
local counter = { getZombieList = function(self) before = before + 1 return list end }
counter:getZombieList()
counter:getZombieList()
counter:getZombieList()

KS_ZOMBIE_RECEIPT = "reads_per_tick=1 old_path_reads=3 shared_consumers=3"
    .. " tick_invalidation=true cell_key=true"
