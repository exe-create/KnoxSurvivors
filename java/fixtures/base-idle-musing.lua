-- The idle rotation used to end in reading, which is why a base full of
-- survivors looked like a library. These assertions drive the real choice and
-- voice functions, not stubs of them.
local C = assert(KnoxAutonomyController)

local counts, muse, social, total = {}, 0, 0, 0
for ticks = 0, 120000, 90 do
    local choice = C.baseIdleChoice(ticks, "resident-" .. tostring(ticks % 7), 4)
    counts[choice] = (counts[choice] or 0) + 1
    total = total + 1
    if choice == "muse" then muse = muse + 1 end
    if choice == "socialize" then social = social + 1 end
end
assert(muse > 0, "the idle rotation selects walk-and-muse")
assert(social > 0, "the idle rotation still selects company")
assert(counts.read == nil, "reading is not a selectable idle")
-- Curiosity replaced the tail, so resting must be a minority of idle time.
assert((counts.rest or 0) < total / 2, "resting is no longer the default idle")

-- Musing expresses the mood the resident actually has.
assert(C.musingEvent({ pain = 3 }) == "base_musing_hurt")
assert(C.musingEvent({ hunger = 0, hungry = 3 }) == "base_musing_hungry")
assert(C.musingEvent({ tired = 3 }) == "base_musing_tired")
assert(C.musingEvent({ panic = 2 }) == "base_musing_frightened")
assert(C.musingEvent({}) == "base_musing", "a settled resident muses without a complaint")
assert(C.musingEvent({ pain = 1, hungry = 1 }) == "base_musing",
    "a passing discomfort does not become a complaint")

-- Greeting the player: close, on cooldown, silent in combat.
assert(C.greetDecision(9, 100, nil) == "wave", "a resident near the player greets them")
assert(C.greetDecision(9, 100, 200) == nil, "the greeting respects its cooldown")
assert(C.greetDecision(64, 0, nil) == nil, "distance silences the greeting")
assert(C.greetDecision(nil, 0, nil) == nil, "no measured distance means no greeting")
