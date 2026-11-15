-- A survivor assigned a real bed must end up in it, and the assign surface may
-- only offer what vanilla's own sleep transition would animate. The owner saw
-- two things on the sleep schedule: someone standing beside the assigned bed,
-- and someone idle after a night roughly a day in. This drives the real
-- admission rule (Needs.sleepAdmissible), the install's own adjacency predicate
-- (Needs.bedAdjacent) and the real wake clock (Controller.sleepWakeDue).
local A = assert(rawget(_G, "codecSleepNeed"), "the sleep admission owner is loaded")
local W = assert(rawget(_G, "codecSleepWake"), "the wake clock is loaded")

local function object(properties)
    return {
        getProperties = function()
            return {
                get = function(_, key) return properties[key] end,
            }
        end,
    }
end

-- A bed declares BedType, the exact property vanilla's sleep path applies to
-- setBedType, so it is the thing a player really sleeps on.
local bed = object({ BedType = "averageBed" })
local okBed, bedType = A.sleepAdmissible(bed)
assert(okBed == true and bedType == "averageBed", "a declared bed is admissible")

-- A couch that declares BedType runs the same animation and is admitted.
assert(A.sleepAdmissible(object({ BedType = "badBed" })) == true,
    "a couch with a BedType sleeps like a bed")

-- A chair declares no BedType, so vanilla would never sleep there.
assert(A.sleepAdmissible(object({ CustomName = "Chair" })) == false,
    "a chair is not a bed assignment")

-- A tent or shelter is vanilla's own named special case.
assert(A.sleepAdmissible(object({ CustomName = "Tent" })) == true,
    "a tent is sleepable")

-- Nothing readable is not a bed.
assert(A.sleepAdmissible(nil) == false, "no object is not a bed")
assert(A.sleepAdmissible({}) == false, "an object without properties is not a bed")

-- Vanilla admits sleep from a square that is tile-or-adjacent to the bed; the
-- predicate is the install's own, so the harness lends it a stand-in only.
local previousFinder = rawget(_G, "AdjacentFreeTileFinder")
local adjacentAnswer = true
AdjacentFreeTileFinder = {
    isTileOrAdjacent = function() return adjacentAnswer end,
}
local character = {
    getCurrentSquare = function() return {} end,
}
local nearBed = { getSquare = function() return {} end }
assert(A.bedAdjacent(character, nearBed) == true,
    "standing beside the bed sleeps at once, like the player")
adjacentAnswer = false
assert(A.bedAdjacent(character, nearBed) == false,
    "a far square is not admitted")
assert(A.bedAdjacent(character, nil) == false, "no bed is not adjacent")
assert(A.bedAdjacent(nil, nearBed) == false, "no body is not adjacent")
AdjacentFreeTileFinder = previousFinder

-- The wake clock: planned hours, a night that crosses midnight, and a clock we
-- cannot read.
assert(W.sleepWakeDue(22, 8, 6) == true, "past the planned hour wakes")
assert(W.sleepWakeDue(22, 8, 5) == false, "before the planned hour keeps sleeping")
assert(W.sleepWakeDue(2, 10, 13) == true, "a night crossing midnight still ends")
assert(W.sleepWakeDue(8, 4, 11) == false, "a short nap never wraps early")
assert(W.sleepWakeDue(nil, 8, 6) == false, "an unreadable start never grants a wake")
assert(W.sleepWakeDue(22, nil, 6) == false, "an unreadable plan never grants a wake")
assert(W.sleepWakeDue(22, 0, 6) == false, "a zero plan is not a wake")

print("Sleep admission PASS bed=true couch=true chair=false tent=true wakeClock=true")
