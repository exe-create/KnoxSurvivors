-- Bed visibility reads the existing assignedBed records; no world bed scan.
local B = assert(codecBedRoster, "bed roster source is loaded")
local previousPersistence = KnoxPersistence
local reads = {}
local policies = {
    ["resident-a"] = { assignedBed = { x = 10, y = 20, z = 0, objectIndex = 4 } },
    ["resident-b"] = { assignedBed = { x = 11, y = 21, z = 1, objectIndex = 2 } },
    ["resident-dead"] = { assignedBed = { x = 12, y = 22, z = 0, objectIndex = 1 } },
    ["companion-bed"] = { assignedBed = { x = 30, y = 40, z = 0, objectIndex = 7 } },
    ["companion-free"] = {},
}
local identities = {
    ["resident-a"] = { forename = "Alice", surname = "Reed" },
    ["resident-b"] = { forename = "Bob", surname = "Stone" },
    ["resident-dead"] = { forename = "Dead", surname = "Resident" },
    ["companion-bed"] = { forename = "Cara", surname = "Vale" },
    ["companion-free"] = { forename = "Free", surname = "Companion" },
}
KnoxPersistence = {
    getBaseResidentIds = function(baseId)
        assert(baseId == "home", "bed roster asks for the selected base")
        return { "resident-b", "resident-a", "resident-dead", "resident-a" }
    end,
    getCompanionIds = function(playerId)
        assert(playerId == "player", "bed roster asks for the owning player")
        return { "companion-bed", "companion-free" }
    end,
    isSurvivorAlive = function(id) return id ~= "resident-dead" end,
    getSurvivorIdentity = function(id) return identities[id] end,
    getSurvivorPolicies = function(id)
        reads[id] = (reads[id] or 0) + 1
        return policies[id]
    end,
}
local base = { id = "home", ownerKind = "player", ownerId = "player" }
local rows = B.bedRoster(base, "player")
assert(#rows == 3, "two living residents and one assigned companion are listed")
assert(rows[1].id == "resident-a" and rows[1].name == "Alice Reed"
    and rows[1].bed.x == 10 and rows[1].bed.y == 20
    and rows[1].bed.z == 0 and rows[1].bed.objectIndex == 4,
    "a resident's real bed coordinates are projected")
assert(rows[2].id == "resident-b" and rows[2].name == "Bob Stone"
    and rows[2].bed.x == 11 and rows[2].bed.z == 1,
    "the second resident keeps their own bed")
assert(rows[3].id == "companion-bed" and rows[3].name == "Cara Vale"
    and rows[3].bed.x == 30,
    "a companion is listed only when a bed is already assigned")
assert(reads["resident-dead"] == nil, "a dead base resident is not materialised")
assert(reads["companion-free"] == 1,
    "an unassigned companion is read once to discover the missing bed")
for _, row in ipairs(rows) do
    assert(row.id ~= "companion-free", "an unassigned companion is not listed")
end
rows[1].bed.x = 999
assert(policies["resident-a"].assignedBed.x == 10, "the roster returns copies, not live records")

policies["resident-b"].assignedBed = { x = 1 }
rows = B.bedRoster(base, "player")
assert(rows[2].bed == nil, "an incomplete saved bed is shown as no bed, not a crash")
assert(reads["resident-b"] == 2, "invalid saved data is read once per projection")

assert(#B.bedRoster({ id = "home", ownerKind = "faction", ownerId = "faction" }, "player") == 0,
    "a faction base is never shown as the player's bed roster")
assert(#B.bedRoster(base, "someone-else") == 0,
    "another player's base is never shown")
assert(#B.bedRoster(nil, "player") == 0, "a missing base has no roster")

KnoxPersistence = previousPersistence
print("Bed roster PASS assigned=true missing=true companion=false dead=false copy=true")
