-- D2a: a base's residents service a loaded generator by the square it stands
-- on, not by a saved object index. These are the real base membership and
-- selection functions plus the real petrol predicate; only the loaded world
-- objects, fluid container and clock-free state are fixture boundaries.
local M = assert(codecBaseGenerator, "base generator owner is extracted")
local B = assert(M.base, "base membership owner is present")
local S = assert(M.storage, "storage owner is present")
local belongs = assert(B.generatorBelongsToBase, "association must exist")
local targetOf = assert(B.generatorMaintenanceTarget, "selection must exist")
local hasPetrol = assert(S.hasPetrol, "petrol proof must exist")

local function square(x, y, z)
    return {
        x = x, y = y, z = z or 0,
        getX = function(self) return self.x end,
        getY = function(self) return self.y end,
        getZ = function(self) return self.z end,
    }
end

local function generator(x, y, fuel, connected, index)
    return {
        square = square(x, y),
        fuel = fuel,
        connected = connected,
        index = index,
        getSquare = function(self) return self.square end,
        getFuelPercentage = function(self) return self.fuel end,
        isConnected = function(self) return self.connected end,
        getObjectIndex = function(self) return self.index end,
    }
end

local base = { id = "home", territory = { minX = 10, minY = 10, maxX = 20, maxY = 20, z = 0 } }
local outside = generator(30, 30, 1, true, 1)
local disconnected = generator(12, 12, 2, false, 2)
local unloaded = generator(13, 13, 0, true, -1)
local emptiest = generator(12, 18, 10, true, 4)
local fuller = generator(18, 18, 40, true, 3)

assert(belongs(base, emptiest) == true, "a loaded generator inside the territory belongs")
assert(belongs(base, outside) == false, "a generator outside the territory does not belong")
assert(belongs(base, unloaded) == false, "an unloaded object is not a generator target")
assert(belongs(base, generator(10, 10, 20, true, 8)) == true,
    "the territory edge is inside the base")
assert(belongs(base, generator(9, 10, 20, true, 9)) == false,
    "one tile outside the edge is not inside the base")

local all = { outside, disconnected, unloaded, emptiest, fuller }
assert(targetOf(base, all) == emptiest,
    "intended red: the emptiest connected generator in the territory wins")
assert(targetOf(base, { outside }) == nil,
    "a base with only an outside generator has no maintenance target")
assert(targetOf(base, { disconnected }) == nil,
    "a disconnected generator is not a maintenance target")
assert(targetOf(base, { unloaded }) == nil,
    "an unloaded generator is unknown, not a target")
assert(targetOf(base, {}) == nil, "no candidates means no target")
assert(targetOf(nil, all) == nil, "no base means no target")

-- Same fuel: the one nearer the base-home centre wins.
local near = generator(14, 15, 30, true, 9)
local far = generator(18, 18, 30, true, 5)
assert(targetOf(base, { far, near }) == near,
    "same fuel prefers the generator nearest the base-home centre")

-- Same fuel and same distance: the lower object index is the deterministic
-- final tie-break, and it is never saved as an identity.
local northwest = generator(12, 12, 30, true, 7)
local southeast = generator(18, 18, 30, true, 5)
assert(targetOf(base, { northwest, southeast }) == southeast,
    "same fuel and distance uses the lower object index only as a tie-break")

-- The base's stored home fallback is the same membership the base owner uses.
local legacy = { id = "legacy", home = { minX = 0, minY = 0, width = 5, height = 5, z = 0 } }
assert(belongs(legacy, generator(4, 4, 20, true, 10)) == true,
    "the home fallback still associates a loaded generator")
assert(belongs(legacy, generator(5, 4, 20, true, 11)) == false,
    "the home fallback does not widen the base")

-- Real petrol is a fluid-container fact, not a display category or fuel tag.
local petrol = {
    getFluidContainer = function()
        return { contains = function(_, fluid) return fluid == "Petrol" end,
            getAmount = function() return 1.5 end }
    end,
}
local water = {
    getFluidContainer = function()
        return { contains = function(_, fluid) return fluid == "Water" end,
            getAmount = function() return 1.5 end }
    end,
}
local categoryOnly = {
    getDisplayCategory = function() return "Fuel" end,
    getFullType = function() return "Base.EmptyGasCan" end,
}
local emptyPetrol = {
    getFluidContainer = function()
        return { contains = function(_, fluid) return fluid == "Petrol" end,
            getAmount = function() return 0 end }
    end,
}
assert(hasPetrol(petrol) == true, "a real petrol container is fuel")
assert(hasPetrol(water) == false, "a fuel-looking can of water is not petrol")
assert(hasPetrol(categoryOnly) == false,
    "display category Fuel is not petrol proof")
assert(hasPetrol(emptyPetrol) == false, "an empty petrol container is not fuel")
assert(hasPetrol(nil) == false, "no item is not fuel")

print("D2a generator PASS in=true out=false edge=true connected_only=true "
    .. "emptiest=true nearest=true tie_index=true petrol_only=true")
