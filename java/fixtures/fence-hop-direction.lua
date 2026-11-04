local direction = assert(codecFenceHopDirection, "the hop direction rule is loaded")

-- Mirrors ISClimbOverFence:getFacingDirection for a hoppable-north square: the
-- character faces the fence, so standing north of it means facing south.
assert(direction(true, 10, 4, 10, 5) == "S", "north of a north edge faces south")
assert(direction(true, 10, 6, 10, 5) == "N", "south of a north edge faces north")
assert(direction(true, 10, 5, 10, 5) == "N", "standing on the edge faces north")

-- East/west edges follow the character's side of the square.
assert(direction(false, 4, 10, 5, 10) == "E", "west of a side edge faces east")
assert(direction(false, 6, 10, 5, 10) == "W", "east of a side edge faces west")

-- An unknown edge never invents a vertical hop.
assert(direction(nil, 4, 10, 5, 10) == "E", "a missing north flag falls to the side rule")

print("Fence hop PASS directions=true edge_only=true")
