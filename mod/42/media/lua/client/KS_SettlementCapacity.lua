-- Settlement carrying capacity.
--
-- A settlement is as large as the beds, food and water it actually holds, not
-- as large as a sandbox number (design/SOCIETY_AND_AUTONOMY.md, owner revision
-- 2026-11-04: "The model is a capacity, not a cap"). This owner measures that
-- from state other owners already produce and answers one question for growth:
-- does this settlement have room for one more person?
--
-- It adds no registry or state of its own. A bounded ground-footprint
-- readability check precedes the existing bed scan. Beds come from the
-- base's own loaded bed discovery; food and water are passed in from the
-- settlement summary the base jobs owner already builds, because a stock total
-- per requirement type is not a serving count and guessing one would invent
-- room that does not exist.
local Capacity = rawget(_G, "KnoxSettlementCapacity") or {}
_G.KnoxSettlementCapacity = Capacity

local function count(value)
    if type(value) ~= "number" or value ~= value then return nil end
    if value < 0 then return 0 end
    return math.floor(value)
end

-- Pure. Beds are the hard physical limit and the one fact a loaded scan always
-- produces; a missing food or water read makes the settlement no larger, never
-- smaller and never larger than the beds it can actually lay out.
function Capacity.measure(facts)
    if type(facts) ~= "table" then return nil end
    local beds = count(facts.beds)
    if beds == nil then return nil end
    local food = count(facts.food)
    local water = count(facts.water)
    local capacity = beds
    if food ~= nil and food < capacity then capacity = food end
    if water ~= nil and water < capacity then capacity = water end
    return { beds = beds, food = food, water = water, capacity = capacity }
end

-- Pure. Residents already living there occupy their own beds, so room is what
-- is left over after them.
function Capacity.admits(measured, residents, count_)
    if type(measured) ~= "table" or type(measured.capacity) ~= "number" then
        return false, "no_capacity_read"
    end
    local occupied = tonumber(residents) or 0
    local arrivals = tonumber(count_) or 1
    if arrivals < 1 then return false, "no_arrivals" end
    if occupied < 0 then occupied = 0 end
    local free = measured.capacity - occupied
    if free >= arrivals then return true, "room" end
    return false, "at_capacity"
end

-- Reads the settlement's own state. `facts` may carry already-measured food and
-- water; beds are discovered from the base itself unless supplied.
function Capacity.forBase(base, faction, facts)
    facts = type(facts) == "table" and facts or {}
    local beds = count(facts.beds)
    if beds == nil then
        local manager = rawget(_G, "KnoxBaseManager")
        if manager ~= nil and type(manager.discoverFactionBeds) == "function" then
            local area = base ~= nil and (base.home or (faction ~= nil and faction.homeBase) or base) or nil
            local cell = getCell ~= nil and getCell() or nil
            local x = area ~= nil and tonumber(area.minX) or nil
            local y = area ~= nil and tonumber(area.minY) or nil
            local width = area ~= nil and tonumber(area.width) or nil
            local height = area ~= nil and tonumber(area.height) or nil
            local buildingId = area ~= nil and area.buildingId or nil
            -- Empty discovery is meaningful only when the location is readable.
            if cell ~= nil and type(buildingId) == "string" and buildingId ~= ""
                and x ~= nil and y ~= nil and width ~= nil and height ~= nil
                and width >= 1 and height >= 1 and width * height <= 4096 then
                local readable = true
                for sx = x, x + width - 1 do
                    for sy = y, y + height - 1 do
                        local ok, square = pcall(cell.getGridSquare, cell, sx, sy, 0)
                        if not ok or square == nil then readable = false; break end
                    end
                    if not readable then break end
                end
                if readable then
                    local scanned, found = pcall(manager.discoverFactionBeds, base, faction)
                    if scanned and type(found) == "table" then beds = #found end
                end
            end
        end
    end
    return Capacity.measure({ beds = beds, food = facts.food, water = facts.water })
end

-- The growth gate. An unmeasured settlement is not refused: before this owner
-- existed every move worked, and a missing read must not silently freeze a
-- faction's membership.
function Capacity.admitsMember(faction, count_)
    if type(faction) ~= "table" then return false, "no_faction" end
    local home = faction.homeBase or faction.homeSafehouse
    if home == nil then return true, "unsettled" end
    local measured = Capacity.forBase(home, faction)
    if measured == nil then return true, "capacity_unknown" end
    local residents = type(faction.memberIds) == "table" and #faction.memberIds or 0
    return Capacity.admits(measured, residents, count_ or 1)
end

-- Residents already counted by the base's own workforce read. Unknown is not
-- zero: a base whose residents cannot be read has not proven it is full.
function Capacity.residents(base)
    local jobs = rawget(_G, "KnoxBaseJobs")
    if jobs ~= nil and type(jobs.workforceSummary) == "function" then
        local ok, summary = pcall(jobs.workforceSummary, base)
        if ok and type(summary) == "table" then
            return tonumber(summary.residents)
        end
    end
    return nil
end

-- Expansion is earned, not chosen: a settlement that has filled its own beds
-- has people to spare for a second site, and one with room left has none.
function Capacity.expansionEarned(base, faction, facts)
    local measured = Capacity.forBase(base, faction, facts)
    if measured == nil then return true, "capacity_unknown" end
    local residents = Capacity.residents(base)
    if residents == nil then return true, "residents_unknown" end
    if residents >= measured.capacity then return true, "settlement_full" end
    return false, "settlement_has_room"
end

-- Provisions are measured, never counted. Food support is the remaining hunger
-- relief native food already reports (installed Food.getHungChange()), and that
-- value is never multiplied again by hunger, uses or a portion factor. Water
-- support is the actual remaining fluid amount, read only after the item passes
-- every existing safety check; a failed check contributes nothing and the item
-- is never repaired. Stock whose item state cannot be read authoritatively
-- contributes nothing and refuses the gate, so unreadable provisions can never
-- be the evidence that supports a group.
Capacity.PROVISION_FOOD_PER_PERSON = 0.60
Capacity.PROVISION_WATER_PER_PERSON = 2.00

local function finiteValue(value)
    local number = tonumber(value)
    if number == nil or number ~= number
        or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

-- Three-state accessor read. "absent" (this build has no such accessor) is a
-- different answer from "failed" (the accessor exists but its state cannot be
-- read): only the second one makes an entry unreadable stock.
local function read(object, name, ...)
    if object == nil then return nil, "absent" end
    local ok, method = pcall(function() return object[name] end)
    if not ok or type(method) ~= "function" then return nil, "absent" end
    local called, value = pcall(method, object, ...)
    if not called then return nil, "failed" end
    return value, "read"
end

function Capacity.itemProvisions(item)
    if item == nil then return nil, "unreadable_item" end
    local food, water, unsafe = 0, 0, false
    local hasFood, hasFluid = false, false
    local hungerChange, hungerState = read(item, "getHungChange")
    if hungerState == "failed" then return nil, "unreadable_food" end
    if hungerState == "read" then
        hasFood = true
        local relief = finiteValue(hungerChange)
        if relief == nil then return nil, "unreadable_food" end
        -- Already the remaining relief: take its magnitude once, never scale it.
        if relief < 0 then relief = -relief end
        local rotten, rottenState = read(item, "isRotten")
        if rottenState == "failed" then return nil, "unreadable_food" end
        if rotten == true then unsafe, relief = true, 0 end
        food = relief
    end
    local fluid, fluidState = read(item, "getFluidContainer")
    if fluidState == "failed" then return nil, "unreadable_fluid" end
    if fluidState == "read" and fluid ~= nil then
        hasFluid = true
        local amount, amountState = read(fluid, "getAmount")
        local measured = finiteValue(amount)
        if amountState ~= "read" or measured == nil then
            return nil, "unreadable_fluid"
        end
        if measured < 0 then measured = 0 end
        -- Safety is only credited when an accessor answers; a failed answer is
        -- unreadable, and a proven-unsafe one contributes nothing.
        local safe = true
        local tainted, taintState = read(fluid, "isTainted")
        if taintState == "failed" then return nil, "unreadable_fluid" end
        if taintState == "read" and tainted == true then safe = false end
        local poisonous, poisonState = read(fluid, "isPoisonous")
        if poisonState == "failed" then return nil, "unreadable_fluid" end
        if poisonState == "read" and poisonous == true then safe = false end
        local primary, primaryState = read(fluid, "getPrimaryFluid")
        if primaryState == "failed" then return nil, "unreadable_fluid" end
        if primaryState == "read" then
            local isPure, pureState = read(fluid, "isPureFluid", primary)
            if pureState == "failed" then return nil, "unreadable_fluid" end
            if pureState == "read" and isPure == false then safe = false end
        end
        if not safe then unsafe, measured = true, 0 end
        water = measured
    end
    if not hasFood and not hasFluid then
        -- Not a provision at all: readable, and worth nothing to either axis.
        return { food = 0, water = 0, unsafe = false }, "not_a_provision"
    end
    return { food = food, water = water, unsafe = unsafe }, "measured"
end

-- One accumulation point for every measured item, whichever owner found it:
-- assigned container storage and the home's own floor squares share it.
function Capacity.addItem(totals, item)
    if type(totals) ~= "table" then return totals end
    totals.items = (totals.items or 0) + 1
    local measured = Capacity.itemProvisions(item)
    if measured == nil then
        totals.unreadable = (totals.unreadable or 0) + 1
    else
        totals.food = (totals.food or 0) + (measured.food or 0)
        totals.water = (totals.water or 0) + (measured.water or 0)
        if measured.unsafe == true then
            totals.unsafe = (totals.unsafe or 0) + 1
        end
    end
    return totals
end

function Capacity.provisions(containers)
    local totals = { food = 0, water = 0, unreadable = 0, unsafe = 0,
        items = 0, containers = 0 }
    local storage = rawget(_G, "KnoxBaseStorage")
    local walk = storage ~= nil and storage.walkItems or nil
    if type(walk) ~= "function" then
        totals.unreadable = 1
        totals.reason = "storage_traversal_unavailable"
        return totals
    end
    for _, container in ipairs(containers or {}) do
        totals.containers = totals.containers + 1
        walk(container, function(item) Capacity.addItem(totals, item) end)
    end
    return totals
end

-- Pure sufficiency decision over measured quantities. Unreadable input refuses:
-- it is not a zero and not a pass.
function Capacity.support(totals, population, requirements)
    local people = math.max(1, math.floor(tonumber(population) or 0))
    local perFood = finiteValue(requirements ~= nil and requirements.food)
        or Capacity.PROVISION_FOOD_PER_PERSON
    local perWater = finiteValue(requirements ~= nil and requirements.water)
        or Capacity.PROVISION_WATER_PER_PERSON
    if type(totals) ~= "table" then return nil, "provisions_unreadable" end
    local unreadable = finiteValue(totals.unreadable)
    local food = finiteValue(totals.food)
    local water = finiteValue(totals.water)
    if unreadable == nil or unreadable > 0 or food == nil or water == nil then
        return nil, "provisions_unreadable"
    end
    local foodNeed = people * perFood
    local waterNeed = people * perWater
    local reason = "supported"
    if food < foodNeed then reason = "food_short"
    elseif water < waterNeed then reason = "water_short" end
    return {
        supported = reason == "supported",
        reason = reason,
        population = people,
        food = food, water = water,
        foodNeed = foodNeed, waterNeed = waterNeed,
        unsafe = finiteValue(totals.unsafe) or 0,
        items = finiteValue(totals.items) or 0,
        containers = finiteValue(totals.containers) or 0,
    }, reason
end

-- A base's own assigned storage, read through that owner's traversal. No
-- readable container means no authoritative stock: unknown, not empty.
function Capacity.baseProvisions(base)
    local totals = { food = 0, water = 0, unreadable = 0, unsafe = 0,
        items = 0, containers = 0 }
    local storage = rawget(_G, "KnoxBaseStorage")
    if base == nil or storage == nil or type(storage.policies) ~= "function"
        or type(storage.resolvePolicy) ~= "function" then
        totals.unreadable = 1
        totals.reason = "storage_unavailable"
        return totals
    end
    local ok, policies = pcall(storage.policies, base)
    if not ok or type(policies) ~= "table" then
        totals.unreadable = 1
        totals.reason = "storage_unreadable"
        return totals
    end
    local containers = {}
    for _, policy in ipairs(policies) do
        local resolved = storage.resolvePolicy(policy)
        if resolved ~= nil and resolved.container ~= nil then
            containers[#containers + 1] = resolved.container
        end
    end
    local totals = Capacity.provisions(containers)
    totals.containers = #containers
    -- The home's own squares are stock too: food and water lying on the floor
    -- of THIS home count, a neighbour's floor does not, and an unreadable square
    -- makes the read unknown instead of quietly smaller.
    local walkFloor = storage.walkFloorItems
    if type(walkFloor) ~= "function" then
        totals.unreadable = totals.unreadable + 1
        totals.reason = "floor_traversal_unavailable"
        return totals
    end
    local okFloor, readable = pcall(walkFloor, base, function(item)
        Capacity.addItem(totals, item)
    end)
    if not okFloor or readable ~= true then
        totals.unreadable = totals.unreadable + 1
        totals.reason = "floor_unreadable"
    end
    return totals
end

-- The fresh boundary read. Nothing persisted can authorize support: this call
-- re-measures the real items every time it is asked.
function Capacity.supportsFormation(base, population, provisions, requirements)
    if base == nil then return nil, "no_home" end
    local totals = provisions
    if type(totals) ~= "table" then totals = Capacity.baseProvisions(base) end
    return Capacity.support(totals, population, requirements)
end

Capacity.loaded = true
