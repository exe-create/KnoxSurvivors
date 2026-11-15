require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFromBottle"
require "TimedActions/ISTakeWaterAction"
require "TimedActions/ISTimedActionQueue"
require "KS_SurvivalMedical"
require "KS_SurvivorMedicalActions"
require "KS_SurvivorInventoryActions"
pcall(function() require "KS_DebugLog" end)

local Needs = rawget(_G, "KnoxSurvivorNeeds") or {}
_G.KnoxSurvivorNeeds = Needs

Needs.thresholds = {
    bleeding = 1,
    -- Needs are normalized 0..1 in Build 42. Starting recovery just below
    -- half-full prevents workers from waiting until a task has already made
    -- them visibly desperate, while the completion checks still use hysteresis.
    thirst = 0.45,
    hunger = 0.45,
    lowEndurance = 0.45,
    fatigue = 0.72,
}

function Needs.isMedicalCare(kind)
    return kind == "bandage" or kind == "improvise_medical" or kind == "disinfect"
        or kind == "antibiotic" or kind == "replace_bandage"
        or kind == "remove_healed_bandage" or kind == "splint"
end

local NEED_CHANGE_EPSILON = 0.001

-- Throttled self-care telemetry (1st + every 10th per survivor/kind):
-- queue rejections and sleep transitions are rare enough to always matter,
-- successful meals are frequent but confirm the loop works.
local function diagNeed(character, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log == nil or log.log == nil then return end
    local id = "unknown"
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.idForCharacter ~= nil then
        local ok, found = pcall(function() return runtime.idForCharacter(character) end)
        if ok and found ~= nil then id = tostring(found) end
    end
    pcall(function() log.log("needs", id, event, details) end)
end

-- Read actual transition evidence only. Missing posture/square APIs are
-- reported as unavailable, never used to grant sleep or manufacture posture.
local function diagSleep(character, event, details)
    local log = rawget(_G, "KnoxDebugLog")
    if log == nil or log.log == nil then return end
    if log.diagnosticsEnabled ~= nil then
        local ok, enabled = pcall(log.diagnosticsEnabled)
        if not ok or not enabled then return end
    end
    local function read(getter)
        local ok, value = pcall(getter)
        if not ok or value == nil then return "unavailable" end
        return value
    end
    details = details or {}
    details.asleep = read(function() return character:isAsleep() end)
    details.sitOnGround = read(function() return character:isSitOnGround() end)
    details.sittingOnFurniture = read(function() return character:isSittingOnFurniture() end)
    details.square = read(function()
        local square = character:getCurrentSquare()
        if square == nil then return "unloaded" end
        return tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())
    end)
    details.fatigue = read(function() return character:getStats():get(CharacterStat.FATIGUE) end)
    details.visibleZombies = read(function() return character:getStats():getNumVisibleZombies() end)
    details.chasingZombies = read(function() return character:getStats():getNumChasingZombies() end)
    details.closeZombies = read(function() return character:getStats():getNumVeryCloseZombies() end)
    diagNeed(character, event, details)
end

local function walkInventory(container, visitor)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if visitor(item, container) == true then return true end
        if item:IsInventoryContainer() then
            if walkInventory(item:getInventory(), visitor) == true then return true end
        end
    end
end

local function isSafeFood(item)
    if item == nil or not item:IsFood() or item:getHungerChange() >= -0.01 then
        return false
    end
    if item:isRotten() or item:isPoison() or item:getPoisonPower() > 0 then
        return false
    end
    if item:isbDangerousUncooked() and not item:isCooked() then
        return false
    end
    return true
end

local function foodScore(item)
    local hunger = math.abs(item:getHungerChange())
    local unhappinessPenalty = math.max(0, item:getUnhappyChange()) / 100
    return hunger - unhappinessPenalty
end

local function waterState(item)
    if item == nil or item:getFluidContainer() == nil then
        return nil
    end
    local fluid = item:getFluidContainer()
    if fluid:isEmpty() or not fluid:isWaterSource() then
        return nil
    end
    -- Unknown fluid state is not potable by default. Native drinking checks
    -- this same tag and can apply sickness/poison, so a missing enum or failed
    -- accessor must not be treated as clean water.
    local success, result = pcall(function()
        if Fluid == nil or Fluid.TaintedWater == nil then return nil end
        return fluid:contains(Fluid.TaintedWater)
    end)
    if not success or type(result) ~= "boolean" then return nil end
    local tainted = result
    return { item = item, tainted = tainted, amount = fluid:getAmount() }
end

function Needs.findBestFood(character, available)
    local best = nil
    local bestScore = -math.huge
    walkInventory(character:getInventory(), function(item)
        if isSafeFood(item) and (available == nil or available(item)) then
            local score = foodScore(item)
            if score > bestScore then
                best = item
                bestScore = score
            end
        end
    end)
    return best
end

function Needs.isSafeFood(item)
    return isSafeFood(item)
end

function Needs.isWaterItem(item, allowTainted)
    local state = waterState(item)
    return state ~= nil and (allowTainted or not state.tainted)
end

-- Loaded IsoObjects expose the same real fluid/taint facts used by vanilla's
-- ISTakeWaterAction. Missing accessors and unreadable taint fail closed.
function Needs.waterSourceState(source)
    if source == nil then return nil end
    local ok, hasFluid, amount, tainted = pcall(function()
        if source.hasFluid == nil or source.getFluidAmount == nil
            or source.isTaintedWater == nil then return nil, nil, nil end
        return source:hasFluid(), source:getFluidAmount(), source:isTaintedWater()
    end)
    amount = ok and tonumber(amount) or nil
    if not ok or type(hasFluid) ~= "boolean" or amount == nil or amount < 0
        or amount ~= amount or amount == math.huge or amount == -math.huge
        or type(tainted) ~= "boolean" then return nil end
    return { source = source, amount = amount,
        available = hasFluid and amount > 0, tainted = tainted }
end

-- A square can hold a clean tap and a tainted barrel. Vanilla orders the
-- drink menu by what is under the cursor, not by safety, so the first
-- admissible source won and a desperate survivor drank from the barrel
-- beside a working sink. Clean always outranks fuller.
function Needs.betterWaterSource(best, candidate)
    if candidate == nil or candidate.available ~= true then return best end
    if best == nil then return candidate end
    if best.tainted == true and candidate.tainted ~= true then return candidate end
    if best.tainted ~= candidate.tainted then return best end
    local bestAmount = tonumber(best.amount) or 0
    local candidateAmount = tonumber(candidate.amount) or 0
    return candidateAmount > bestAmount and candidate or best
end

local function isSmokeItem(item)
    local ok, supported = pcall(function()
        return item ~= nil and item:IsFood() and ItemTag ~= nil
            and ItemTag.SMOKABLE ~= nil and item:hasTag(ItemTag.SMOKABLE)
    end)
    return ok and supported == true
end

function Needs.isSmokeItem(item) return isSmokeItem(item) end

-- Ask the native action for the same ignition sources it will use at start.
function Needs.smokeIgnitionAvailable(character, item)
    local ok, available = pcall(function()
        if not isSmokeItem(item) then return false end
        local action = ISEatFoodAction:new(character, item, 1.0)
        return (action.carLighter or action.openFlame or action:getRequiredItem() ~= nil) and true or false
    end)
    return ok and available == true
end

-- Build 42 uses tagged Food cigarettes/cigars, not unopened drainable packs.
-- Native Eat and its timed action own consumption, relief and ignition use.
function Needs.findSmokeItem(character, available)
    if character == nil or character.getInventory == nil then return nil end
    local inventory = character:getInventory()
    if inventory == nil then return nil end
    local found = nil
    pcall(function()
        walkInventory(inventory, function(item)
            if isSmokeItem(item) and (available == nil or available(item)) then found = item; return true end
        end)
    end)
    return found
end

local function smokeState(character)
    local function read(getter)
        local ok, value = pcall(getter)
        if ok and type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge and value >= 0 then return value end
    end
    local state = {
        elapsed = read(function() return character:getStats():getTimeSinceLastSmoke() end),
        stress = read(function() return character:getStats():get(CharacterStat.STRESS) end),
        unhappy = read(function() return character:getStats():get(CharacterStat.UNHAPPINESS) end),
    }
    if state.elapsed == nil and state.stress == nil and state.unhappy == nil then return nil end
    return state
end

function Needs.smokeMotive(character)
    if character == nil then return false end
    local smoker = false
    pcall(function()
        local traits = character.getTraits and character:getTraits()
        if traits ~= nil and traits.contains ~= nil then
            smoker = traits:contains("Smoker") == true
        end
    end)
    if smoker then return true end
    local stressed, unhappy = 0, 0
    pcall(function()
        local moodles = character:getMoodles()
        if moodles ~= nil and MoodleType ~= nil then
            stressed = tonumber(moodles:getMoodleLevel(MoodleType.STRESS)) or 0
            unhappy = tonumber(moodles:getMoodleLevel(MoodleType.UNHAPPY)) or 0
        end
    end)
    return stressed >= 2 or unhappy >= 2
end

function Needs.findBestWater(character, allowTainted, available)
    local best = nil
    walkInventory(character:getInventory(), function(item)
        local state = waterState(item)
        if state ~= nil and (allowTainted or not state.tainted)
            and (available == nil or available(item)) then
            if best == nil
                or (best.tainted and not state.tainted)
                or (best.tainted == state.tainted and state.amount > best.amount) then
                best = state
            end
        end
    end)
    return best ~= nil and best.item or nil, best ~= nil and best.tainted or false
end

function Needs.snapshot(character)
    local stats = character:getStats()
    local bodyDamage = character:getBodyDamage()
    -- Pain is exposed by current Build 42 body damage, but older game builds
    -- and a few test doubles do not provide the accessor.  Keep it optional:
    -- native body state remains the source of truth and an unavailable value
    -- must never be reported as painless.
    local pain = nil
    if bodyDamage ~= nil and bodyDamage.getPain ~= nil then
        local ok, value = pcall(function() return bodyDamage:getPain() end)
        if ok and tonumber(value) ~= nil then pain = tonumber(value) end
    end
    return {
        hunger = stats:get(CharacterStat.HUNGER),
        thirst = stats:get(CharacterStat.THIRST),
        fatigue = stats:get(CharacterStat.FATIGUE),
        endurance = stats:get(CharacterStat.ENDURANCE),
        bleedingParts = bodyDamage:getNumPartsBleeding(),
        health = bodyDamage:getHealth(),
        pain = pain,
        -- The card and party strip name an observed bite wound, not a diagnosis
        -- inferred from systemic infection. Unreadable wounds stay unknown.
        bitten = Needs.biteReading(character),
    }
end

-- PAIN BANDS AND HEAVY WORK
-- Native pain is a body value, and every surface that needs to know how much
-- something hurts asks this one table instead of inventing a threshold. An
-- unreadable value is nil, never "clear": a body we cannot read is not a body
-- without pain, and the caller decides which way to fail.
Needs.painBands = { hurting = 25, bad = 45, severe = 65 }

function Needs.painBand(snapshot)
    local pain = snapshot ~= nil and tonumber(snapshot.pain) or nil
    if pain == nil or pain ~= pain then return nil end
    if pain >= Needs.painBands.severe then return "severe" end
    if pain >= Needs.painBands.bad then return "bad" end
    if pain >= Needs.painBands.hurting then return "hurting" end
    return "clear"
end

-- The work that loads the arms and the back. Cooking, sorting a shelf, tending
-- a bed, a row of crops and keeping watch stay open to a hurt person: the point
-- is that pain changes what someone chooses to do, not that it stops them
-- living. Keys are the canonical base task types.
Needs.heavyWork = {
    chop_tree = true, saw_logs = true, barricade = true, repair = true,
    farm_plow = true, haul_corpse = true, burn_corpse = true,
    pile_corpses = true,
}

-- One reason a hurting person can give when heavy work comes up, or nil when
-- they can take it. Unreadable pain refuses nothing: work is not sleep, and an
-- unknown body state must never idle a settlement.
function Needs.heavyWorkRefusal(character, taskType)
    if character == nil or taskType == nil then return nil end
    if not Needs.heavyWork[tostring(taskType)] then return nil end
    -- A bitten person knows what it means. The reason is separate from pain so
    -- the surface that speaks it can say which body fact refused the work.
    -- Keep the existing refusal code for callers; only a real bite may select
    -- the dialogue that says "I got bit".
    if Needs.biteReading(character) == true then return "infected" end
    local ok, snapshot = pcall(Needs.snapshot, character)
    if not ok or snapshot == nil then return nil end
    local band = Needs.painBand(snapshot)
    if band == "bad" or band == "severe" then return "in_pain" end
    return nil
end

-- Is heavy work actually waiting? Speaking a refusal only makes sense when the
-- thing being refused is on the board; an idle camp owes the player no excuse.
function Needs.heavyWorkWaiting(queued)
    if type(queued) ~= "table" then return false end
    for _, task in ipairs(queued) do
        if type(task) == "table" and Needs.heavyWork[tostring(task.type or "")] then
            return true
        end
    end
    return false
end

-- WEATHER AND WARMTH
-- Rain is the one climate fact the game states plainly, and core temperature is
-- the one the body states plainly. Both are read defensively: an older build, a
-- stub or a half-restored shell yields nil, and an unknown sky is never a reason
-- to move somebody.
Needs.rainShelter = 0.15
Needs.coldCore = 35.5
-- Clothing wetness is 0..100 on the native body. Soaked is a product bound, not
-- a measured comfort threshold: wet enough that standing about in it is work.
Needs.soakedWetness = 45

function Needs.rainIntensity()
    local climate = rawget(_G, "getClimateManager")
    if climate == nil then return nil end
    local ok, value = pcall(function() return climate():getRainIntensity() end)
    if not ok or tonumber(value) == nil then return nil end
    return tonumber(value)
end

-- Clothing, not the sky: the engine tracks how wet what a person wears is, and
-- a body we cannot read is unknown rather than dry.
function Needs.clothingWetness(character)
    if character == nil then return nil end
    local ok, value = pcall(function() return character:getClothingWetness() end)
    if not ok or tonumber(value) == nil then return nil end
    return tonumber(value)
end

function Needs.coreTemperature(character)
    if character == nil or character.getBodyDamage == nil then return nil end
    local ok, value = pcall(function()
        local body = character:getBodyDamage()
        local thermo = body ~= nil and body.getThermoregulator ~= nil
            and body:getThermoregulator() or nil
        if thermo == nil or thermo.getCoreTemperature == nil then return nil end
        return thermo:getCoreTemperature()
    end)
    if not ok or tonumber(value) == nil then return nil end
    return tonumber(value)
end

-- Use the engine's player-facing thermal severity, not invented Celsius bands.
function Needs.thermalMoodle(character, kind)
    if character == nil or (kind ~= "heat" and kind ~= "cold") then return nil end
    local ok, level = pcall(function()
        local moodle = kind == "heat" and MoodleType.HYPERTHERMIA or MoodleType.HYPOTHERMIA
        return character:getMoodles():getMoodleLevel(moodle)
    end)
    return ok and tonumber(level) or nil
end

-- The reason a person steps out of the weather, or nil when there is none. Rain
-- is answered first because it is the thing a person can see; a cold core is
-- answered next. Anything unreadable is silence, not a guess.
function Needs.shelterReason(character)
    local rain = Needs.rainIntensity()
    if rain ~= nil and rain >= Needs.rainShelter then return "rain" end
    local hot, cold = Needs.thermalMoodle(character, "heat"), Needs.thermalMoodle(character, "cold")
    if hot ~= nil and hot > 0 then return "heat" end
    local core = Needs.coreTemperature(character)
    if (cold ~= nil and cold > 0) or (core ~= nil and core <= Needs.coldCore) then return "cold" end
    -- Rain soaks a person and the soaking outlasts the rain. A body still wet
    -- through keeps them inside after the sky clears, until it dries.
    local wet = Needs.clothingWetness(character)
    if wet ~= nil and wet >= Needs.soakedWetness then return "wet" end
    return nil
end

-- The reason decides which words are spoken, in one place: a new reason cannot
-- silently borrow another bank's line, and an unknown reason says nothing.
Needs.shelterBanks = { rain = "weather_rain", cold = "weather_cold",
    wet = "weather_wet", heat = "weather_heat" }

function Needs.shelterBank(reason)
    if reason == nil then return nil end
    return Needs.shelterBanks[tostring(reason)]
end

-- A change of weather is worth one remark, not a running commentary: the reason
-- is reported only when it is new. The caller keeps the last value it announced.
function Needs.shelterAnnouncement(previous, current)
    if current == nil then return nil end
    if previous == current then return nil end
    return current
end

-- An outdoor job is refused while the body is already soaked or out of
-- temperature. Rain on its own is not a refusal: the shelter walk already
-- answers the sky, and a person in light rain still works. The planner reads
-- this at its own gate, so a wet resident is deferred instead of claimed
-- for a job they would walk away from. An unread body refuses nothing.
function Needs.weatherWorkRefusal(character, outside)
    if character == nil or outside ~= true then return nil end
    local reason = Needs.shelterReason(character)
    if reason == nil or reason == "rain" then return nil end
    return reason
end

-- ILLNESS AND INFECTION

-- The engine already models infection on the BodyDamage blob this mod persists
-- whole, so this is a reader plus a decision, not a second simulation. An
-- unreadable body is nil, never "healthy": a settlement must not act on a
-- diagnosis nobody made.
function Needs.infectionReading(character)
    if character == nil or character.getBodyDamage == nil then return nil end
    local ok, infected = pcall(function()
        local body = character:getBodyDamage()
        if body == nil then return nil end
        -- Current bodies state the flag. Older or stubbed bodies may only state
        -- the apparent level, which is still the engine's own answer.
        local check = body.IsInfected or body.isInfected
        if check ~= nil then
            local value = check(body)
            if type(value) == "boolean" then return value end
        end
        local apparent = body.getApparentInfectionLevel
        if apparent == nil then return nil end
        local level = tonumber(apparent(body))
        if level == nil then return nil end
        return level >= 1
    end)
    if not ok or type(infected) ~= "boolean" then return nil end
    return infected
end

-- One word for what the body says, or nil when it says nothing readable.
-- Bite wounds are observable; infection and an unreadable body are not a
-- clean medical examination. Use vanilla BodyPart:bitten(), not its name alone.
function Needs.biteReading(character)
    if character==nil then return nil end
    local ok,result=pcall(function()
        local parts=character:getBodyDamage():getBodyParts()
        if parts==nil or parts:size()==0 then return nil end
        for index=0,parts:size()-1 do
            local bitten=parts:get(index):bitten()
            if type(bitten)~="boolean" then return nil end
            if bitten then return true end
        end
        return false
    end)
    if not ok then return nil end
    return result
end

function Needs.infectionBand(character)
    -- Legacy name consumed by nameplates and Ask > Health. The visible word is
    -- "bitten", so this band must describe wounds rather than hidden infection.
    local reading = Needs.biteReading(character)
    if reading == nil then return nil end
    return reading and "bitten" or "clear"
end

-- What killed them, read from the body while it is still readable. Only the
-- causes the facts support are returned: an infection the engine states, real
-- bleeding, a body at zero, or a named attacker. Nothing here names a killer -
-- the death line already has the attribution - so this answers why a person
-- died when nobody was standing there to say.
function Needs.deathCause(character, attributionKind)
    if character ~= nil and Needs.infectionReading(character) == true then
        return "infection"
    end
    local ok, snapshot = pcall(Needs.snapshot, character)
    if ok and snapshot ~= nil then
        if (tonumber(snapshot.bleedingParts) or 0) >= 1 then return "bled_out" end
        local health = tonumber(snapshot.health)
        if health ~= nil and health <= 0 then return "wounds" end
    end
    local kind = tostring(attributionKind or "")
    if kind == "zombie" or kind == "survivor" or kind == "player" then
        return "killed"
    end
    return nil
end

-- How the cause is written where there is no room for a sentence. An unknown
-- cause returns nil rather than a vague word: a card that says nothing is
-- honest, a row spent on "unknown" is not.
Needs.deathCauseLabels = {
    infection = "fever", bled_out = "bled out", wounds = "wounds", killed = "killed",
}

function Needs.deathCauseLabel(cause)
    if cause == nil then return nil end
    return Needs.deathCauseLabels[tostring(cause)]
end

-- Dialogue and durable intents must use the same native stat boundary as the
-- decision planner. This prevents an old `find_food` state from producing a
-- fresh hunger callout after the survivor has already recovered.
function Needs.isNeedCurrent(character, kind)
    if character == nil or kind == nil then return false end
    local success, snapshot = pcall(Needs.snapshot, character)
    if not success or snapshot == nil then return false end
    if kind == "find_food" or kind == "eat" then
        return (tonumber(snapshot.hunger) or 0) >= Needs.thresholds.hunger
    end
    if kind == "find_water" or kind == "drink" then
        return (tonumber(snapshot.thirst) or 0) >= Needs.thresholds.thirst
    end
    if kind == "find_medical" or kind == "bandage"
        or kind == "improvise_medical" then
        return (tonumber(snapshot.bleedingParts) or 0) >= Needs.thresholds.bleeding
    end
    if kind == "rest" then
        return (tonumber(snapshot.endurance) or 1) <= Needs.thresholds.lowEndurance
    end
    if kind == "sleep" then
        return (tonumber(snapshot.fatigue) or 0) >= Needs.thresholds.fatigue
    end
    -- Unknown or stale intents must not keep producing player-facing need
    -- callouts.  The planner owns the supported kinds above; an old save or
    -- interrupted action can otherwise make a survivor claim a need forever.
    return false
end

function Needs.sleepRequired()
    if not isClient() then
        return true
    end
    local options = getServerOptions()
    return options:getBoolean("SleepAllowed") and options:getBoolean("SleepNeeded")
end

function Needs.describe(snapshot)
    return "hunger=" .. tostring(snapshot.hunger)
        .. " thirst=" .. tostring(snapshot.thirst)
        .. " fatigue=" .. tostring(snapshot.fatigue)
        .. " endurance=" .. tostring(snapshot.endurance)
        .. " bleedingParts=" .. tostring(snapshot.bleedingParts)
        .. " health=" .. tostring(snapshot.health)
        .. " pain=" .. tostring(snapshot.pain)
end

function Needs.decide(character, threat)
    local state = Needs.snapshot(character)
    if threat ~= nil then
        return { kind = "fight", target = threat, state = state }
    end
    if state.bleedingParts >= Needs.thresholds.bleeding then
        local injury = KnoxMedicalActions.mostUrgentInjury(character)
        local treatment = KnoxMedicalSupplies.findTreatment(character)
        if treatment ~= nil then
            return {
                kind = "bandage",
                item = treatment,
                bodyPart = injury,
                state = state,
            }
        end
        local supplyPlan = KnoxMedicalSupplies.plan(character, 8)
        local canImprovise = supplyPlan.kind == "rip_owned_sheet"
            or supplyPlan.kind == "rip_owned_spare_clothing"
        return {
            kind = canImprovise and "improvise_medical" or "find_medical",
            supplyPlan = supplyPlan,
            state = state,
        }
    end
    if state.thirst >= Needs.thresholds.thirst then
        local water, tainted = Needs.findBestWater(character, state.thirst >= 0.90)
        return {
            kind = water ~= nil and "drink" or "find_water",
            item = water,
            tainted = tainted,
            state = state,
        }
    end
    if state.hunger >= Needs.thresholds.hunger then
        local food = Needs.findBestFood(character)
        return {
            kind = food ~= nil and "eat" or "find_food",
            item = food,
            state = state,
        }
    end
    if state.endurance <= Needs.thresholds.lowEndurance then
        return { kind = "rest", state = state }
    end
    if state.fatigue >= Needs.thresholds.fatigue and Needs.sleepRequired() then
        return { kind = "sleep", state = state }
    end
    local maintenance = KnoxMedicalActions.maintenancePlan ~= nil
        and KnoxMedicalActions.maintenancePlan(character, character) or nil
    if maintenance ~= nil then
        maintenance.state = state
        return maintenance
    end
    return { kind = "roam", state = state }
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function carriedIn(character, item, source)
    local found = false
    walkInventory(character:getInventory(), function(candidate, container)
        if candidate == item and (source == nil or container == source) then found = true; return true end
    end)
    return found
end

local function consumptionReceipt(character, intent)
    local after = Needs.snapshot(character)
    if intent.kind == "eat" then
        local remaining = math.abs(intent.item:getHungerChange())
        local consumed = not carriedIn(character, intent.item, nil)
            or (finite(remaining) and remaining < intent.foodAmount - NEED_CHANGE_EPSILON)
        return consumed and finite(after.hunger) and finite(intent.before.hunger)
            and after.hunger < intent.before.hunger - NEED_CHANGE_EPSILON
    elseif intent.kind == "drink" or intent.kind == "drink_world" then
        local amount
        if intent.kind == "drink" then
            if intent.item:getFluidContainer() ~= intent.fluid then return false end
            amount = intent.fluid:getAmount()
        else
            local state = Needs.waterSourceState(intent.source)
            amount = state ~= nil and state.amount or nil
        end
        return finite(amount) and amount < intent.sourceAmount - NEED_CHANGE_EPSILON
            and finite(after.thirst) and finite(intent.before.thirst)
            and after.thirst < intent.before.thirst - NEED_CHANGE_EPSILON
    elseif intent.kind == "smoke" then
        if carriedIn(character, intent.item, nil) then return false end
        local current = smokeState(character)
        if current == nil then return false end
        for _, key in ipairs({"elapsed", "stress", "unhappy"}) do
            if finite(intent.smokeBefore[key]) and finite(current[key])
                and current[key] < intent.smokeBefore[key] - NEED_CHANGE_EPSILON then return true end
        end
    elseif intent.kind == "disinfect" then
        local item = intent.item
        local remaining = item:hasComponent(ComponentType.FluidContainer)
            and item:getFluidContainer():getAmount() or item:getCurrentUsesFloat()
        return intent.bodyPart:getAlcoholLevel() > intent.alcoholBefore
            and (not carriedIn(character, item, nil) or remaining < intent.supplyBefore)
    elseif intent.kind == "antibiotic" then
        return not carriedIn(character, intent.item, nil)
            and character:getReduceInfectionPower() > intent.drugBefore
    elseif intent.kind == "bandage" then
        return intent.bodyPart ~= nil and intent.bodyPart:bandaged()
            and not carriedIn(character, intent.item, nil)
    elseif intent.kind == "improvise_medical" then
        local treatment = KnoxMedicalSupplies.findTreatment(character)
        return not carriedIn(character, intent.item, nil) and treatment ~= nil
            and treatment ~= intent.treatmentBefore
    end
    return false
end

-- This is permission around the existing native action, never replacement
-- consumption. Install before add: native begin/complete can run immediately.
local function bindNeedAction(character, action, intent, ownership)
    local item, source = intent.item, intent.source
    intent.character, intent.action = character, action
    if ownership ~= nil then ownership.action, ownership.intent, ownership.source = action, intent, source end
    local function allowed(candidate)
        local ok, valid = pcall(function()
            if candidate ~= action or candidate.character ~= character or intent.cancelled
                or intent.item ~= item or intent.source ~= source then return false end
            if ownership ~= nil and (ownership.cancelled or ownership.allowed(candidate, intent) ~= true) then return false end
            if intent.kind == "drink_world" then
                if candidate.waterObject ~= intent.source then return false end
                local state = Needs.waterSourceState(intent.source)
                local thirst = Needs.snapshot(character).thirst
                return state ~= nil and state.available
                    and (not state.tainted or (finite(thirst) and thirst >= 0.90))
            end
            if intent.kind == "improvise_medical" then
                -- Native start/serverStart constructs a fresh HandcraftLogic.
                -- The accepted recipe survives that transition; logic identity does not.
                return candidate.knoxMedicalSource == item and intent.craftRecipe ~= nil
                    and candidate.craftRecipe == intent.craftRecipe
                    and ((intent.recipeCompleted and intent.receipt == true)
                        or (carriedIn(character, item, source)
                            and KnoxMedicalSupplies.canImprovise(character, intent.supplyPlan) == true))
            end
            if intent.kind == "remove_healed_bandage" then
                return candidate.item == nil and candidate.doIt == false
                    and candidate.bodyPart == intent.bodyPart and candidate.otherPlayer == character
                    and intent.bodyPart:bandaged() and not intent.bodyPart:HasInjury()
            end
            if intent.kind == "replace_bandage" then
                return candidate.item == nil and candidate.doIt == false
                    and candidate.bodyPart == intent.bodyPart and candidate.otherPlayer == character
                    and carriedIn(character, item, source)
                    and KnoxMedicalActions.cleanBandageUsable(character, item)
                    and intent.bodyPart:HasInjury() and intent.bodyPart:bandaged()
                    and intent.bodyPart:getBandageLife() <= 0
            end
            if intent.kind == "splint" then
                return candidate.item == nil and candidate.doIt == true
                    and candidate.bodyPart == intent.bodyPart
                    and candidate.otherPlayer == character
                    and carriedIn(character, intent.item, intent.source)
                    and KnoxMedicalActions.selfSplintAllowed(
                        character, intent.item, intent.bodyPart)
            end
            if candidate.item ~= intent.item or not carriedIn(character, intent.item, intent.source) then return false end
            if intent.kind == "disinfect" or intent.kind == "antibiotic" then
                local plan = KnoxMedicalActions.maintenancePlan(character, character,
                    intent.replacementPart)
                return plan ~= nil and plan.kind == intent.kind and plan.item == item
                    and (intent.kind ~= "disinfect" or (candidate.alcohol == item
                        and candidate.bodyPart == intent.bodyPart and plan.bodyPart == intent.bodyPart))
            end
            if intent.kind == "bandage" then
                return candidate.bodyPart == intent.bodyPart and candidate.otherPlayer == character
                    and intent.bodyPart:HasInjury() and not intent.bodyPart:bandaged()
            end
            if intent.kind == "prepare_supply" then return true end
            if intent.kind == "eat" then return isSafeFood(intent.item) end
            if intent.kind == "smoke" then return isSmokeItem(intent.item) end
            if intent.kind == "drink" then
                local state = waterState(intent.item)
                local thirst = Needs.snapshot(character).thirst
                return state ~= nil and intent.item:getFluidContainer() == intent.fluid
                    and (not state.tainted or (finite(thirst) and thirst >= 0.90))
            end
            return false
        end)
        return ok and valid == true
    end
    intent.guard, action.knoxNeedGuard = allowed, allowed
    if ownership ~= nil then ownership.guard = allowed end
    local nativeValid = action.isValid
    action.isValid = function(candidate)
        return allowed(candidate) and nativeValid ~= nil and nativeValid(candidate)
    end
    local function wrapMutation(name, once)
        local native = action[name]
        if native == nil then return end
        local completedKey = name == "performRecipe" and "recipeCompleted" or "nativeCompleted"
        action[name] = function(candidate, ...)
            if not allowed(candidate) or (once and intent[completedKey]) then return false end
            if once then intent[completedKey] = true end
            local result = native(candidate, ...)
            if (intent.kind == "replace_bandage" or intent.kind == "remove_healed_bandage") and result == true
                and not intent.bodyPart:bandaged() then intent.removed = true end
            local ok, received = pcall(consumptionReceipt, character, intent)
            if ok and received then intent.receipt = true end
            return result
        end
    end
    if intent.kind ~= "prepare_supply" then
        wrapMutation("complete", true)
        -- Native stops/partial water updates can consume too. Revoked care
        -- must not eat/drink later while an unrelated current queue drains.
        if intent.kind == "eat" or intent.kind == "smoke" or intent.kind == "antibiotic" then wrapMutation("eat")
        elseif intent.kind == "drink" then wrapMutation("drink")
        elseif intent.kind == "drink_world" then wrapMutation("transferFluid")
        elseif intent.kind == "improvise_medical" then wrapMutation("performRecipe", true) end
    end
end

local function registeredNeedAction(character, action, admitted, intent)
    local registered = ISTimedActionQueue.queues and ISTimedActionQueue.queues[character]
    if admitted == nil or admitted ~= registered or intent.cancelled then return false end
    for _, candidate in ipairs(admitted.queue or {}) do if candidate == action then return true end end
    return intent.receipt == true or ((intent.kind == "replace_bandage" or intent.kind == "remove_healed_bandage") and intent.removed == true)
end

local function queueNeedAction(character, action, intent, ownership)
    bindNeedAction(character, action, intent, ownership)
    if not intent.guard(action) then intent.cancelled = true; return nil, "permission_changed" end
    local ok, admitted = pcall(ISTimedActionQueue.add, action)
    if not ok or not registeredNeedAction(character, action, admitted, intent)
        or (ownership ~= nil and ownership.cancelled) then
        intent.cancelled = true
        return nil, ok and "queue_refused" or "queue_failed"
    end
    intent.admitted = true
    return action
end

local function prepareBaggedSupply(character, decision, ownership)
    local inventory, source = character:getInventory(), nil
    walkInventory(inventory, function(item, container)
        if item == decision.item then source = container; return true end
    end)
    if source == nil then
        diagNeed(character, "need_action_failed", {
            kind = tostring(decision.kind), result = "supply_no_longer_carried",
        })
        return nil, "supply_no_longer_carried"
    end
    if source == inventory then return false end
    local intent = { kind = "prepare_supply", needKind = decision.kind,
        before = decision.state, item = decision.item, source = source, destination = inventory,
        bodyPart = decision.bodyPart }
    local guard
    guard = function(candidate, item)
        if intent.action == nil then
            bindNeedAction(character, candidate, intent, ownership)
            if ownership ~= nil then ownership.guard = guard end
        end
        return intent.guard(candidate) and item == intent.item
            and candidate.srcContainer == source and candidate.destContainer == inventory
    end
    if ownership ~= nil then ownership.guard, ownership.intent = guard, intent end
    local ok, action, reason = pcall(KnoxInventoryActions.queueTransfer,
        character, decision.item, source, inventory, nil, guard)
    if ok and action ~= nil then
        if intent.action == nil then bindNeedAction(character, action, intent, ownership) end
        if ownership ~= nil then ownership.guard = guard end
        intent.receipt = not carriedIn(character, intent.item, source)
            and carriedIn(character, intent.item, inventory)
    end
    local registered = ISTimedActionQueue.queues and ISTimedActionQueue.queues[character]
    if not ok or action == nil or not registeredNeedAction(character, action, registered, intent)
        or (ownership ~= nil and ownership.cancelled) then
        intent.cancelled = true
        diagNeed(character, "need_action_failed", {
            kind = tostring(decision.kind), result = "supply_transfer_rejected",
        })
        return nil, "supply_transfer_rejected"
    end
    intent.admitted = true
    return action, reason, intent
end

function Needs.execute(character, decision, ownership)
    if decision == nil then
        return nil, "missing_decision"
    end
    if (decision.kind == "eat" and (decision.state == nil or not finite(decision.state.hunger)))
        or ((decision.kind == "drink" or decision.kind == "drink_world")
            and (decision.state == nil or not finite(decision.state.thirst))) then
        return nil, "need_state_unavailable"
    end
    -- Report queue outcomes (success confirms the loop; rejections are the
    -- usual "won't eat/drink" evidence). Throttled per survivor/kind.
    local function report(action, result, intent)
        local okAction = action ~= nil and action ~= false
        local itemType = nil
        pcall(function()
            local item = decision.item
                or (intent ~= nil and intent.item)
                or (decision.supplyPlan ~= nil and decision.supplyPlan.item)
            if item ~= nil and item.getFullType ~= nil then
                itemType = item:getFullType()
            end
        end)
        diagNeed(character, okAction and "need_action_queued" or "need_action_failed", {
            kind = tostring(decision.kind),
            result = tostring(result),
            item = itemType,
        })
        return action, result, intent
    end
    if decision.kind == "splint" then
        local plan = KnoxMedicalActions.maintenancePlan(character, character)
        if plan == nil or plan.kind ~= "splint" or plan.item ~= decision.item
            or plan.bodyPart ~= decision.bodyPart then
            return report(nil, "self_splint_no_longer_needed")
        end
        local prepared, preparedResult, preparedIntent =
            prepareBaggedSupply(character, decision, ownership)
        if prepared ~= false then
            if prepared == nil then return nil, preparedResult end
            return report(prepared, preparedResult, preparedIntent)
        end
        local intent = { kind = "splint", before = decision.state,
            item = decision.item, bodyPart = decision.bodyPart,
            source = character:getInventory() }
        local action = KnoxMedicalActions.queueSelfSplint(
            character, decision.item, decision.bodyPart,
            function(actor, candidate)
                return queueNeedAction(actor, candidate, intent, ownership)
            end)
        return report(action, action ~= nil and "queued_self_splint"
            or "self_splint_queue_refused", intent)
    end
    if decision.kind == "remove_healed_bandage" then
        local plan = KnoxMedicalActions.maintenancePlan(character, character)
        if plan == nil or plan.kind ~= decision.kind or plan.bodyPart ~= decision.bodyPart then
            return report(nil, "removal_no_longer_needed")
        end
        local intent = { kind = decision.kind, before = decision.state, bodyPart = decision.bodyPart }
        local action = KnoxMedicalActions.queueBandageRemoval(character, decision.bodyPart, function(actor, candidate)
            return queueNeedAction(actor, candidate, intent, ownership)
        end)
        return report(action, action ~= nil and "queued_dressing_removal" or "removal_queue_refused", intent)
    end
    if decision.kind == "replace_bandage" then
        local plan = KnoxMedicalActions.maintenancePlan(character, character)
        if plan == nil or plan.kind ~= decision.kind or plan.item ~= decision.item
            or plan.bodyPart ~= decision.bodyPart then return report(nil, "replacement_no_longer_needed") end
        local intent = { kind = decision.kind, before = decision.state, item = decision.item,
            bodyPart = decision.bodyPart, source = character:getInventory() }
        local action = KnoxMedicalActions.queueBandageRemoval(character, decision.bodyPart, function(actor, candidate)
            return queueNeedAction(actor, candidate, intent, ownership)
        end)
        return report(action, action ~= nil and "queued_dressing_removal" or "removal_queue_refused", intent)
    end
    if decision.kind == "disinfect" or decision.kind == "antibiotic" then
        local plan = KnoxMedicalActions.maintenancePlan(character, character,
            decision.replacementPart)
        if plan == nil or plan.kind ~= decision.kind or plan.item ~= decision.item
            or plan.bodyPart ~= decision.bodyPart then return report(nil, "maintenance_no_longer_needed") end
        if decision.kind == "disinfect" then
            local prepared, preparedResult, preparedIntent =
                prepareBaggedSupply(character, decision, ownership)
            if prepared ~= false then
                if prepared == nil then return nil, preparedResult end
                return report(prepared, preparedResult, preparedIntent)
            end
        end
        local item = decision.item
        local intent = { kind = decision.kind, before = decision.state, item = item,
            bodyPart = decision.bodyPart, source = character:getInventory(),
            replacementItem = decision.replacementItem, replacementPart = decision.replacementPart }
        local action
        if decision.kind == "disinfect" then
            local ok, amount = pcall(function()
                return item:hasComponent(ComponentType.FluidContainer)
                    and item:getFluidContainer():getAmount() or item:getCurrentUsesFloat()
            end)
            if not ok or not finite(amount) then return report(nil, "disinfectant_unreadable") end
            intent.supplyBefore, intent.alcoholBefore = amount, decision.bodyPart:getAlcoholLevel()
            action = KnoxMedicalActions.queueDisinfect(character, item, decision.bodyPart, function(actor, candidate)
                return queueNeedAction(actor, candidate, intent, ownership)
            end)
        else
            intent.drugBefore = character:getReduceInfectionPower()
            action = ISEatFoodAction:new(character, item, 1)
            action = queueNeedAction(character, action, intent, ownership)
        end
        return report(action, action ~= nil and "queued_maintenance" or "maintenance_queue_refused", intent)
    end
    if decision.kind == "bandage" then
        -- A bandage chosen from a bag still has to come to hand. Use the same
        -- prepare_supply transfer owner as a bagged meal; on a full pack the
        -- controller hands the rejection to the existing cleanup owner.
        local prepared, preparedResult, preparedIntent =
            prepareBaggedSupply(character, decision, ownership)
        if prepared ~= false then
            if prepared == nil then return nil, preparedResult end
            return report(prepared, preparedResult, preparedIntent)
        end
        local intent = { kind = "bandage", before = decision.state,
            item = decision.item, bodyPart = decision.bodyPart }
        if ownership ~= nil then
            local action, result = KnoxMedicalActions.queueBandage(character,
                decision.item, decision.bodyPart, function(actor, candidate)
                    return queueNeedAction(actor, candidate, intent, ownership)
                end)
            return report(action, result or "queued_bandage", intent)
        end
        local action, result = KnoxMedicalActions.queueBandage(
            character,
            decision.item,
            decision.bodyPart
        )
        return report(action, result, {
            kind = "bandage",
            before = decision.state,
            item = decision.item,
            bodyPart = decision.bodyPart,
        })
    end
    if decision.kind == "smoke" then
        decision.item = decision.item or Needs.findSmokeItem(character)
        if not isSmokeItem(decision.item) then return report(nil, "no_smoke_carried") end
    end
    if decision.kind == "drink" or decision.kind == "eat" or decision.kind == "smoke" then
        local prepared, preparedResult, preparedIntent =
            prepareBaggedSupply(character, decision, ownership)
        if prepared ~= false then
            if prepared == nil then return nil, preparedResult end
            return report(prepared, preparedResult, preparedIntent)
        end
    end
    if decision.kind == "drink" then
        local thirst = decision.state.thirst
        local uses = math.max(1, math.ceil(math.max(0, thirst - 0.15) / 0.1))
        local state = waterState(decision.item)
        if state == nil or not finite(state.amount) then return report(nil, "water_state_unavailable") end
        local intent = { kind = "drink", before = decision.state, item = decision.item,
            source = character:getInventory(), fluid = decision.item:getFluidContainer(), sourceAmount = state.amount }
        local action = ISDrinkFromBottle:new(character, decision.item, uses)
        local accepted = queueNeedAction(character, action, intent, ownership)
        if accepted == nil then
            diagNeed(character, "need_action_failed", {
                kind = "drink", result = "drink_queue_rejected",
            })
            return nil, "drink_queue_rejected"
        end
        return report(action, "queued_drink", intent)
    end
    if decision.kind == "drink_world" then
        local sourceState = Needs.waterSourceState(decision.source)
        if sourceState == nil or not sourceState.available then
            return report(nil, "water_source_unavailable")
        end
        if sourceState.tainted and decision.state.thirst < 0.90 then
            return report(nil, "tainted_water_not_emergency_eligible")
        end
        -- Vanilla rejects this action when inventory is full even for direct
        -- drinking. Do not make room or bypass that native check.
        local fullOk, full = pcall(function() return character:hasFullInventory() end)
        if fullOk and full == true then
            return report(nil, "native_water_action_refused_full_inventory")
        end
        local action = ISTakeWaterAction:new(
            character, nil, decision.source, sourceState.tainted)
        local intent = { kind = "drink_world", before = decision.state, source = decision.source,
            sourceAmount = sourceState.amount, tainted = sourceState.tainted }
        local accepted = queueNeedAction(character, action, intent, ownership)
        if accepted == nil then
            return report(nil, "native_water_action_queue_rejected")
        end
        return report(action, "queued_native_water_drink", intent)
    end
    if decision.kind == "eat" then
        local benefit = math.max(0.01, math.abs(decision.item:getHungerChange()))
        local percentage = math.max(
            0.25,
            math.min(1.0, math.max(0, decision.state.hunger - 0.15) / benefit)
        )
        local action = ISEatFoodAction:new(character, decision.item, percentage)
        local intent = { kind = "eat", before = decision.state, item = decision.item,
            source = character:getInventory(), foodAmount = math.abs(decision.item:getHungerChange()) }
        local accepted = queueNeedAction(character, action, intent, ownership)
        if accepted == nil then
            diagNeed(character, "need_action_failed", {
                kind = "eat", result = "eat_queue_rejected",
            })
            return nil, "eat_queue_rejected"
        end
        return report(action, "queued_eat percentage=" .. tostring(percentage), intent)
    end
    if decision.kind == "improvise_medical" then
        if ownership ~= nil then
            local intent = { kind = "improvise_medical", before = decision.state,
                item = decision.supplyPlan ~= nil and decision.supplyPlan.item or nil,
                supplyPlan = decision.supplyPlan,
                treatmentBefore = KnoxMedicalSupplies.findTreatment(character) }
            local ok, action = KnoxMedicalSupplies.queueImprovisation(character,
                decision.supplyPlan, function(actor, candidate)
                    intent.craftRecipe = candidate.craftRecipe
                    return queueNeedAction(actor, candidate, intent, ownership)
                end)
            return report(ok and action or nil, ok and "queued_improvise_medical" or action, intent)
        end
        local action, result = KnoxMedicalSupplies.queueImprovisation(
            character,
            decision.supplyPlan
        )
        return report(action, result, {
            kind = "improvise_medical",
            before = decision.state,
            item = decision.supplyPlan ~= nil and decision.supplyPlan.item or nil,
        })
    end
    if decision.kind == "smoke" then
        local smoke = decision.item or Needs.findSmokeItem(character)
        if smoke == nil then
            diagNeed(character, "need_action_failed", {
                kind = "smoke", result = "no_smoke_carried",
            })
            return nil, "no_smoke_carried"
        end
        local smokeAction = ISEatFoodAction:new(character, smoke, 1.0)
        local ignitionOk, ignition = pcall(function()
            return smokeAction.carLighter or smokeAction.openFlame
                or smokeAction:getRequiredItem() ~= nil
        end)
        if not ignitionOk or not ignition then return report(nil, "smoke_ignition_unavailable") end
        local baseline = smokeState(character)
        if baseline == nil then return report(nil, "smoke_state_unavailable") end
        local intent = { kind = "smoke", before = decision.state, item = smoke,
            source = character:getInventory(), smokeBefore = baseline }
        local accepted = queueNeedAction(character, smokeAction, intent, ownership)
        if accepted == nil then
            diagNeed(character, "need_action_failed", {
                kind = "smoke", result = "smoke_queue_rejected",
            })
            return nil, "smoke_queue_rejected"
        end
        return report(smokeAction, "queued_smoke", intent)
    end
    diagNeed(character, "need_action_failed", {
        kind = tostring(decision.kind), result = "decision_requires_world_action",
    })
    return nil, "decision_requires_world_action=" .. tostring(decision.kind)
end

-- Removal is a handoff, not a completed treatment. Prefer disinfection only
-- while bleeding is controlled, then the ordinary need planner can bandage.
function Needs.replacementFollowup(character, intent)
    local ok, decision = pcall(function()
        if character == nil or intent == nil or intent.cancelled or intent.admitted ~= true then return nil end
        local item, part
        if intent.kind == "replace_bandage" and intent.removed == true then
            item, part = intent.item, intent.bodyPart
        elseif intent.kind == "disinfect" and intent.receipt == true then
            item, part = intent.replacementItem, intent.replacementPart
        end
        if part == nil or part:bandaged() or not part:HasInjury()
            or not KnoxMedicalActions.cleanBandageUsable(character, item) then return nil end
        local state = Needs.snapshot(character)
        if intent.kind == "replace_bandage" and state.bleedingParts < Needs.thresholds.bleeding then
            local plan = KnoxMedicalActions.maintenancePlan(character, character, part)
            if plan ~= nil and plan.kind == "disinfect" and plan.bodyPart == part then
                plan.state = state
                plan.replacementItem, plan.replacementPart = item, part
                return plan
            end
        end
        return { kind = "bandage", item = item, bodyPart = part, state = state }
    end)
    if ok then return decision end
    return nil
end

-- An empty timed-action queue proves only that native ownership ended. These
-- checks prove that the authoritative game state actually changed before the
-- controller records self-care as successful.
function Needs.verify(character, intent)
    if character == nil or intent == nil or intent.before == nil then
        return false, "missing_intent"
    end
    if intent.kind == "replace_bandage" then return false, "replacement_not_yet_applied" end
    if intent.kind == "remove_healed_bandage" then
        local removed = not intent.cancelled and intent.admitted == true and intent.removed == true
            and intent.bodyPart ~= nil and not intent.bodyPart:bandaged()
        return removed, removed and "healed_dressing_removed" or "removal_unconfirmed"
    end
    if intent.kind == "eat" or intent.kind == "drink" or intent.kind == "drink_world"
        or intent.kind == "smoke" or intent.kind == "prepare_supply"
        or intent.kind == "disinfect" or intent.kind == "antibiotic"
        or ((intent.kind == "bandage" or intent.kind == "improvise_medical") and intent.action ~= nil) then
        if intent.cancelled or intent.action == nil or intent.admitted ~= true then
            return false, "need_action_unconfirmed"
        end
        if intent.kind ~= "prepare_supply" and intent.receipt ~= true then
            return false, "native_consumption_unconfirmed"
        end
    end
    if intent.kind == "disinfect" or intent.kind == "antibiotic" then
        return intent.receipt == true, intent.receipt == true and "maintenance_received" or "maintenance_unconfirmed"
    end
    local after = Needs.snapshot(character)
    if intent.kind == "smoke" then
        local carriedOk, carried = pcall(function()
            local found = false
            walkInventory(character:getInventory(), function(item)
                if item == intent.item then found = true; return true end
            end)
            return found
        end)
        if not carriedOk or type(carried) ~= "boolean" or carried or intent.item == nil then
            return false, "smoke_consumption_unconfirmed"
        end
        local baseline, current = intent.smokeBefore, smokeState(character)
        if type(baseline) ~= "table" or current == nil then return false, "smoke_state_unavailable" end
        for _, key in ipairs({"elapsed", "stress", "unhappy"}) do
            if type(baseline[key]) == "number" and type(current[key]) == "number"
                and current[key] < baseline[key] - NEED_CHANGE_EPSILON then
                return true, "smoke_consumed " .. key .. "=" .. tostring(baseline[key]) .. "->" .. tostring(current[key])
            end
        end
        return false, "smoke_no_observed_change"
    end
    if intent.kind == "prepare_supply" then
        local ok, received = pcall(function()
            return intent.source ~= nil and not carriedIn(character, intent.item, intent.source)
                and carriedIn(character, intent.item, character:getInventory())
        end)
        return ok and received == true, "supply_main_inventory"
    end
    if intent.kind == "eat" then
        local ok, received = pcall(consumptionReceipt, character, intent)
        return ok and received == true,
            "hunger=" .. tostring(intent.before.hunger) .. "->" .. tostring(after.hunger)
    end
    if intent.kind == "drink" then
        local ok, received = pcall(consumptionReceipt, character, intent)
        return ok and received == true,
            "thirst=" .. tostring(intent.before.thirst) .. "->" .. tostring(after.thirst)
    end
    if intent.kind == "drink_world" then
        local sourceState = Needs.waterSourceState(intent.source)
        local thirstChanged = after.thirst < intent.before.thirst - NEED_CHANGE_EPSILON
        local sourceChanged = sourceState ~= nil
            and sourceState.amount < intent.sourceAmount - NEED_CHANGE_EPSILON
        return thirstChanged and sourceChanged,
            "thirst=" .. tostring(intent.before.thirst) .. "->" .. tostring(after.thirst)
                .. " sourceAmount=" .. tostring(intent.sourceAmount) .. "->"
                .. tostring(sourceState ~= nil and sourceState.amount or "unavailable")
    end
    if intent.kind == "bandage" then
        local treated = intent.bodyPart ~= nil
            and (intent.bodyPart:bandaged() or not intent.bodyPart:bleeding())
        return treated,
            "bleedingParts=" .. tostring(intent.before.bleedingParts)
                .. "->" .. tostring(after.bleedingParts)
    end
    if intent.kind == "improvise_medical" then
        local treatment = KnoxMedicalSupplies.findTreatment(character)
        return treatment ~= nil, treatment ~= nil
            and "treatment_created=" .. tostring(treatment:getFullType())
            or "no_treatment_created"
    end
    return false, "unsupported_intent=" .. tostring(intent.kind)
end

function Needs.verifyRecovery(character, intent)
    if character == nil or intent == nil or intent.before == nil then
        return false, "missing_recovery_intent"
    end
    local after = Needs.snapshot(character)
    if intent.kind == "rest" then
        return after.endurance > intent.before.endurance + NEED_CHANGE_EPSILON,
            "endurance=" .. tostring(intent.before.endurance)
                .. "->" .. tostring(after.endurance)
    end
    if intent.kind == "sleep" then
        return after.fatigue < intent.before.fatigue - NEED_CHANGE_EPSILON,
            "fatigue=" .. tostring(intent.before.fatigue)
                .. "->" .. tostring(after.fatigue)
    end
    return false, "unsupported_recovery=" .. tostring(intent.kind)
end

function Needs.sleepHours(character, fatigue, bedType)
    local value = tonumber(fatigue) or 0
    -- Installed onSleepWalkToComplete order, preserving fractional hours.
    local hours = ZombRand(value * 10, value * 13) + 1
    local quality = tostring(bedType or "averageBed")
    if string.find(quality, "goodBed", 1, true) ~= nil then hours = hours - 1 end
    if string.find(quality, "badBed", 1, true) ~= nil then hours = hours + 1 end
    if string.find(quality, "floor", 1, true) ~= nil then hours = hours * 0.7 end
    if character:hasTrait(CharacterTrait.INSOMNIAC) then
        hours = hours * 0.5
    end
    if character:hasTrait(CharacterTrait.NEEDS_LESS_SLEEP) then
        hours = hours * 0.75
    end
    if character:hasTrait(CharacterTrait.NEEDS_MORE_SLEEP) then
        hours = hours * 1.18
    end
    return math.max(3, math.min(16, hours))
end

-- SLEEP ADMISSION (pure)
-- Install truth, 42.21: the whole sleep interaction keys off one furniture
-- property. getBedQuality reads properties:get("BedType") and the sleep
-- transition applies that same value to setBedType
-- (pzHome/media/lua/client/ISUI/ISWorldObjectContextMenu.lua:1034-1090 and
-- 2949-2951). A bed, and a couch that declares BedType, run the animation
-- the player runs; a tent or shelter is vanilla's own CustomName special
-- case. A vehicle is a different native path with a seat
-- (ISVehicleMenu.onSleep), not a BedType object, so it is not a bed
-- reference. One admissibility rule, read here by the assign surface and by
-- the rest search.
local function declaredBedType(object)
    if object == nil or object.getProperties == nil then return nil end
    local ok, properties = pcall(function() return object:getProperties() end)
    if not ok or properties == nil or properties.get == nil then return nil end
    local okType, value = pcall(function() return properties:get("BedType") end)
    if not okType or value == nil then return nil end
    local text = tostring(value)
    if text == "" then return nil end
    return text
end

local function declaredCustomName(object)
    if object == nil or object.getProperties == nil then return "" end
    local name = nil
    pcall(function()
        local properties = object:getProperties()
        name = properties ~= nil and properties.get ~= nil
            and properties:get("CustomName") or nil
    end)
    return name ~= nil and string.lower(tostring(name)) or ""
end

function Needs.sleepAdmissible(object)
    if object == nil then return false, "no_object" end
    local bedType = declaredBedType(object)
    if bedType ~= nil then return true, bedType end
    local name = declaredCustomName(object)
    if name == "tent" or name == "shelter" then
        return true, "averageBed"
    end
    return false, "not_a_bed"
end

-- Vanilla sleeps from a square that is tile-or-adjacent to the bed and only
-- walks when it is not (onConfirmSleep). The same install predicate answers
-- here, so the survivor takes the step the player would skip and never
-- repeats a walk to a second approach square it cannot reach.
function Needs.bedAdjacent(character, bed)
    if character == nil or bed == nil or bed.getSquare == nil then return false end
    local ok, adjacent = pcall(function()
        local square = bed:getSquare()
        local current = character:getCurrentSquare()
        if square == nil or current == nil then return false end
        return AdjacentFreeTileFinder.isTileOrAdjacent(current, square) == true
    end)
    return ok and adjacent == true
end
-- END SLEEP ADMISSION
-- This is the same native sleep transition used by Build 42's world context
-- menu, without touching local-player UI or time controls for the off-slot NPC.
function Needs.startSleep(character, bed, bedType)
    if character == nil or character:isAsleep() then
        return false, "sleep_unavailable"
    end
    -- Recheck at arrival, just as the installed Build 42 context-menu sleep
    -- transition does. Conditions may have changed while walking to the bed.
    -- Unreadable native state cannot authorize sleep.
    local inspected, blocker = pcall(function()
        local stats = character:getStats()
        if stats:getNumVisibleZombies() > 0 or stats:getNumChasingZombies() > 0
            or stats:getNumVeryCloseZombies() > 0 then
            return "sleep_not_safe"
        end
        if character:getSleepingTabletEffect() < 2000 then
            local moodles = character:getMoodles()
            if moodles:getMoodleLevel(MoodleType.PAIN) >= 2
                and stats:get(CharacterStat.FATIGUE) <= 0.85 then
                return "sleep_pain"
            end
            if moodles:getMoodleLevel(MoodleType.PANIC) >= 1 then
                return "sleep_panic"
            end
        end
        return nil
    end)
    if not inspected or blocker ~= nil then
        local result = inspected and blocker or "sleep_state_unavailable"
        diagSleep(character, "sleep_blocked", { result = result })
        return false, result
    end
    local state = Needs.snapshot(character)
    local sleepBedType = bedType or (bed ~= nil and "averageBed" or "floor")
    local hours = Needs.sleepHours(character, state.fatigue, sleepBedType)
    local wakeAt = GameTime.getInstance():getTimeOfDay() + hours
    if wakeAt >= 24 then
        wakeAt = wakeAt - 24
    end
    character:setVariable("ExerciseStarted", false)
    character:setVariable("ExerciseEnded", true)
    local ok, reason = pcall(function()
        character:setBed(bed)
        character:setBedType(sleepBedType)
        character:setForceWakeUpTime(wakeAt)
        character:setAsleepTime(0.0)
        character:setAsleep(true)
        getSleepingEvent():setPlayerFallAsleep(character, hours)
    end)
    if not ok then
        -- A streamed or partially restored shell may lack the sleep event for
        -- one tick. Leave the controller recoverable and retry later instead
        -- of keeping a false SLEEPING_RECOVERY state forever.
        pcall(function() character:setAsleep(false) end)
        pcall(function() character:setBed(nil) end)
        diagSleep(character, "sleep_failed", {
            result = "native_sleep_error", bedType = tostring(sleepBedType),
        })
        return false, "native_sleep_error:" .. tostring(reason)
    end
    diagSleep(character, "sleep_started", {
        hours = hours, bedType = tostring(sleepBedType), wakeAt = wakeAt,
    })
    return true, "native_sleep hours=" .. tostring(hours), hours
end

-- GIVING FOOD AWAY WITH A SELF RESERVE (2026-11-06)
-- A hungry survivor is noticed from the same native hunger value every other
-- need read uses; the giver's own reserve is the existing eat threshold, so
-- food is only offered when it leaves the giver still fed. The native
-- remaining-hunger value of one item is read once and never multiplied, and an
-- unreadable hunger reading is never a need, a safe donation or a receipt.
local function shareNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function hungerOf(character)
    if character == nil or character.getStats == nil then return nil end
    local ok, value = pcall(function()
        return character:getStats():get(CharacterStat.HUNGER)
    end)
    if not ok then return nil end
    value = tonumber(value)
    if not shareNumber(value) then return nil end
    return value
end

function Needs.shareFoodOffer(giver, target)
    if giver == nil or target == nil or giver == target then
        return nil, "missing_people"
    end
    local mine, theirs = hungerOf(giver), hungerOf(target)
    if mine == nil or theirs == nil then return nil, "unreadable_need" end
    if theirs < Needs.thresholds.hunger then return nil, "no_need" end
    if mine >= Needs.thresholds.hunger then return nil, "keeping_own_reserve" end
    local food = Needs.findBestFood(giver)
    if food == nil then return nil, "no_safe_food" end
    local okChange, change = pcall(function() return food:getHungerChange() end)
    if not okChange then change = nil end
    change = tonumber(change)
    if not shareNumber(change) or change >= -0.01 then return nil, "unreadable_food" end
    -- One item, one native value. A part-eaten portion is its own remaining
    -- hunger; it is never a count multiplied into a larger meal.
    local bite = math.abs(change)
    if mine + bite > Needs.thresholds.hunger then return nil, "reserve_too_thin" end
    return food, "share"
end

-- The one line that names why the offer is being made. Selection, cooldown and
-- the speaker's own voice stay with the dialogue owner.
Needs.shareLines = { "Here - you need this more than I do." }

function Needs.queueFoodShare(giver, target, survivorId, ticks, duration)
    local food, reason = Needs.shareFoodOffer(giver, target)
    if food == nil then return nil, reason end
    local actions = rawget(_G, "KnoxInventoryActions")
    if actions == nil or actions.queueTransfer == nil then
        return nil, "transfer_unavailable"
    end
    if giver.getInventory == nil or target.getInventory == nil then
        return nil, "missing_people"
    end
    local ok, action = pcall(actions.queueTransfer, giver, food,
        giver:getInventory(), target:getInventory(), duration or 60)
    if not ok or action == nil then return nil, "transfer_refused" end
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    if dialogue ~= nil and dialogue.sayLines ~= nil then
        pcall(dialogue.sayLines, giver, survivorId or "survivor",
            "share_food", Needs.shareLines, ticks or 0, 1800)
    end
    return action, "share"
end

-- WATER AND MEDICAL SHARING (2026-11-06)
-- Water is measured from the container's actual fluid amount after the same
-- safety checks drinking uses: an empty, non-water, unreadable or tainted
-- container is never offered, and a nominal count is never a measurement. The
-- giver keeps a bottle of their own. Medical supply is whatever the existing
-- MedicalSupplies.plan already admits as a treatment; a plan that cannot name
-- a safe treatment is never evidence that one exists.
local function thirstOf(character)
    if character == nil or character.getStats == nil then return nil end
    local ok, value = pcall(function()
        return character:getStats():get(CharacterStat.THIRST)
    end)
    if not ok then return nil end
    value = tonumber(value)
    if not shareNumber(value) then return nil end
    return value
end

local function bleedingOf(character)
    if character == nil or character.getBodyDamage == nil then return nil end
    local ok, value = pcall(function()
        return character:getBodyDamage():getNumPartsBleeding()
    end)
    if not ok then return nil end
    value = tonumber(value)
    if not shareNumber(value) or value < 0 then return nil end
    return value
end

-- The item-side counterpart of Needs.waterSourceState: the actual amount in
-- the bottle after the same taint/emptiness/readability checks vanilla drinking
-- applies, never the item's stack count or a nominal capacity.
local function potableState(item)
    if item == nil or item.getFluidContainer == nil then return nil end
    local ok, fluid = pcall(function() return item:getFluidContainer() end)
    if not ok or fluid == nil then return nil end
    local okRead, empty, waterSource, amount = pcall(function()
        return fluid:isEmpty(), fluid:isWaterSource(), fluid:getAmount()
    end)
    amount = okRead and tonumber(amount) or nil
    if not okRead or empty ~= false or waterSource ~= true
        or not shareNumber(amount) or amount <= 0 then return nil end
    local okTaint, tainted = pcall(function()
        if Fluid == nil or Fluid.TaintedWater == nil then return nil end
        return fluid:contains(Fluid.TaintedWater)
    end)
    if not okTaint or type(tainted) ~= "boolean" or tainted then return nil end
    return { item = item, amount = amount }
end

function Needs.shareWaterOffer(giver, target)
    if giver == nil or target == nil or giver == target then
        return nil, "missing_people"
    end
    local mine, theirs = thirstOf(giver), thirstOf(target)
    if mine == nil or theirs == nil then return nil, "unreadable_need" end
    if theirs < Needs.thresholds.thirst then return nil, "no_need" end
    if mine >= Needs.thresholds.thirst then return nil, "keeping_own_reserve" end
    -- A pack that cannot be read is not an empty pack and not a safe offer:
    -- the scan fails closed instead of propagating a native accessor error.
    local okFind, water = pcall(Needs.findBestWater, giver, false)
    if not okFind then return nil, "unreadable_water" end
    if water == nil then return nil, "no_safe_water" end
    local state = potableState(water)
    if state == nil then return nil, "unreadable_water" end
    local okSpare, spare = pcall(Needs.findBestWater, giver, false,
        function(item) return item ~= water end)
    if not okSpare then return nil, "unreadable_water" end
    if spare == nil then return nil, "last_bottle" end
    return water, "share"
end

Needs.shareWaterLines = { "You look parched - take my spare bottle." }

function Needs.queueWaterShare(giver, target, survivorId, ticks, duration)
    local water, reason = Needs.shareWaterOffer(giver, target)
    if water == nil then return nil, reason end
    local actions = rawget(_G, "KnoxInventoryActions")
    if actions == nil or actions.queueTransfer == nil then
        return nil, "transfer_unavailable"
    end
    if giver.getInventory == nil or target.getInventory == nil then
        return nil, "missing_people"
    end
    local ok, action = pcall(actions.queueTransfer, giver, water,
        giver:getInventory(), target:getInventory(), duration or 60)
    if not ok or action == nil then return nil, "transfer_refused" end
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    if dialogue ~= nil and dialogue.sayLines ~= nil then
        pcall(dialogue.sayLines, giver, survivorId or "survivor",
            "share_water", Needs.shareWaterLines, ticks or 0, 1800)
    end
    return action, "share"
end

function Needs.shareMedicalOffer(giver, target)
    if giver == nil or target == nil or giver == target then
        return nil, "missing_people"
    end
    local theirBleeding = bleedingOf(target)
    if theirBleeding == nil then return nil, "unreadable_need" end
    if theirBleeding < 1 then return nil, "no_need" end
    local mine = bleedingOf(giver)
    if mine == nil then return nil, "unreadable_need" end
    if mine >= 1 then return nil, "keeping_own_reserve" end
    local supplies = rawget(_G, "KnoxMedicalSupplies")
    if supplies == nil or supplies.plan == nil then return nil, "supply_unreadable" end
    local ok, plan = pcall(supplies.plan, giver, 8)
    -- Only a named, safe treatment is a supply. Search, improvisation and an
    -- unreadable plan are not evidence that medicine exists.
    if not ok or plan == nil or plan.kind ~= "use_treatment" or plan.item == nil then
        return nil, "no_safe_supply"
    end
    return plan.item, "share"
end

Needs.shareMedicalLines = { "Let me see that - take this." }

function Needs.queueMedicalShare(giver, target, survivorId, ticks, duration)
    local item, reason = Needs.shareMedicalOffer(giver, target)
    if item == nil then return nil, reason end
    local actions = rawget(_G, "KnoxInventoryActions")
    if actions == nil or actions.queueTransfer == nil then
        return nil, "transfer_unavailable"
    end
    if giver.getInventory == nil or target.getInventory == nil then
        return nil, "missing_people"
    end
    local ok, action = pcall(actions.queueTransfer, giver, item,
        giver:getInventory(), target:getInventory(), duration or 60)
    if not ok or action == nil then return nil, "transfer_refused" end
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    if dialogue ~= nil and dialogue.sayLines ~= nil then
        pcall(dialogue.sayLines, giver, survivorId or "survivor",
            "share_medical", Needs.shareMedicalLines, ticks or 0, 1800)
    end
    return action, "share"
end

function Needs.wakeForDanger(character)
    if character == nil or not character:isAsleep() then
        return false
    end
    getSleepingEvent():wakeUp(character)
    diagSleep(character, "sleep_woken", { result = "requested_wake" })
    return true
end
