-- Survivor exercise (2026-11-04)
-- The native player surface is ISFitnessUI, and it is bound to the local
-- player: asking a survivor to work out cannot reuse that window. What it can
-- reuse is the native timed action the player's own button queues -
-- ISFitnessAction (install: media/lua/shared/TimedActions/ISFitnessAction.lua) -
-- which is written against self.character rather than the local player, and
-- drives body state, metabolics and fitness regularity through the engine.
-- This module is the one owner of "can this survivor exercise now" and "start
-- that exercise". The talk panel and the survivor card are its entry points;
-- it keeps no state of its own, because the action queue already owns the
-- activity and cancels it exactly as it does for the player.
require "TimedActions/ISFitnessAction"
require "TimedActions/ISTimedActionQueue"
require "ISUI/ISFitnessUI"

local Exercise = rawget(_G, "KnoxSurvivorExercise") or {}
_G.KnoxSurvivorExercise = Exercise

-- Same default the player's own window shows.
Exercise.MINUTES = 10

-- Bodyweight only. The barbell and dumbbell types need the item in hand; that
-- is an equipment problem for the supply owner, not something this module
-- should quietly equip onto somebody.
Exercise.ORDERED = { "squats", "pushups", "situp" }

local REASON_TEXT = {
    dead = "They are dead.",
    unloaded = "They are not loaded in this area.",
    vehicle = "Not in a vehicle.",
    climbing = "They are climbing.",
    sitting = "They need to stand up first.",
    endurance = "They are too exhausted.",
    load = "They are carrying too much.",
    pain = "They are in too much pain.",
    busy = "They are already busy.",
    unknown_exercise = "That exercise is unavailable.",
    unavailable = "They cannot exercise right now.",
}

function Exercise.refusalText(reason)
    local text = REASON_TEXT[tostring(reason or "")]
    if text ~= nil then return text end
    local catalog = rawget(_G, "KnoxOrderCatalog")
    return catalog ~= nil and catalog.failureText ~= nil
        and catalog.failureText(reason) or REASON_TEXT.unavailable
end

local function definitions()
    local table_ = type(FitnessExercises) == "table" and FitnessExercises.exercisesType or nil
    return type(table_) == "table" and table_ or nil
end

-- The catalogue the picker offers: only exercises this build defines and that
-- need nothing in hand.
function Exercise.exercises()
    local defs = definitions()
    local rows = {}
    for _, key in ipairs(Exercise.ORDERED) do
        local data = defs ~= nil and defs[key] or nil
        if type(data) == "table" and data.item == nil then
            rows[#rows + 1] = {
                type = key,
                label = tostring(data.name or key),
                data = data,
            }
        end
    end
    return rows
end

function Exercise.exerciseByType(kind)
    for _, row in ipairs(Exercise.exercises()) do
        if row.type == kind then return row end
    end
    return nil
end

local function characterFor(survivorId)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local getter = runtime ~= nil and runtime.getCharacter or nil
    if type(getter) ~= "function" then return nil end
    local ok, character = pcall(getter, survivorId)
    return ok and character or nil
end

local function moodleLevel(character, moodle)
    if character == nil or character.getMoodles == nil then return 0 end
    local ok, moodles = pcall(character.getMoodles, character)
    if not ok or moodles == nil or moodles.getMoodleLevel == nil then return 0 end
    local read, level = pcall(moodles.getMoodleLevel, moodles, moodle)
    return read and tonumber(level) or 0
end

local function queueBusy(character)
    if ISTimedActionQueue == nil or ISTimedActionQueue.getTimedActionQueue == nil then
        return nil
    end
    local read, nativeBusy = pcall(function()
        return not character:getCharacterActions():isEmpty()
    end)
    if not read then return nil end
    if nativeBusy then return true end
    local ok, queue = pcall(ISTimedActionQueue.getTimedActionQueue, character)
    if not ok or queue == nil or type(queue.queue) ~= "table" then return nil end
    return #queue.queue > 0
end

-- The native player gates (install: media/lua/client/ISUI/ISFitnessUI.lua,
-- ISFitnessUI:updateButtons): exhaustion, heavy load, pain, sitting, vehicle,
-- climbing. A refusal is a sentence, not a silent no-op, so both entry points
-- can say the same thing.
function Exercise.refusal(player, survivorId)
    local character = characterFor(survivorId)
    if character == nil then return "unloaded" end
    -- The native fitness action runs unguarded on the queue tick
    -- (isValidStart, waitToStart, update): a body that cannot answer what the
    -- tick needs is refused here with a sentence instead of erroring there.
    if character.isCurrentState == nil or character.setMetabolicTarget == nil then
        return "unavailable"
    end
    local okMoodles, moodles = pcall(function() return character:getMoodles() end)
    if not okMoodles or moodles == nil then return "unavailable" end
    if character.isDead ~= nil then
        local ok, dead = pcall(character.isDead, character)
        if ok and dead == true then return "dead" end
    end
    -- A card is an inspection surface, not command authority. Reuse the same
    -- ownership, willingness and physical contact gates as ordinary orders.
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.orderContact == nil then return "unavailable" end
    local checked, accepted, reason = pcall(service.orderContact, player, survivorId)
    if not checked then return "unavailable" end
    if accepted ~= true then return reason or "unavailable" end
    if character.getVehicle ~= nil then
        local ok, vehicle = pcall(character.getVehicle, character)
        if ok and vehicle ~= nil then return "vehicle" end
    end
    if character.isClimbing ~= nil then
        local ok, climbing = pcall(character.isClimbing, character)
        if ok and climbing == true then return "climbing" end
    end
    if character.isSittingOnFurniture ~= nil then
        local ok, sitting = pcall(character.isSittingOnFurniture, character)
        if ok and sitting == true then return "sitting" end
    end
    local threshold = ISFitnessUI ~= nil and tonumber(ISFitnessUI.enduranceLevelThreshold) or 2
    if moodleLevel(character, MoodleType.ENDURANCE) > threshold then return "endurance" end
    if moodleLevel(character, MoodleType.HEAVY_LOAD) > 2 then return "load" end
    if moodleLevel(character, MoodleType.PAIN) > 3 then return "pain" end
    local busy = queueBusy(character)
    if busy == nil then return "unavailable" end
    if busy then return "busy" end
    return nil
end

-- Queue the same action the player's own Exercise button queues, on the
-- survivor's body. Returns true, or false plus the reason code above.
function Exercise.start(player, survivorId, kind, minutes)
    local reason = Exercise.refusal(player, survivorId)
    if reason ~= nil then return false, reason end
    local row = Exercise.exerciseByType(kind or Exercise.ORDERED[1])
    if row == nil then return false, "unknown_exercise" end
    local character = characterFor(survivorId)
    if character == nil then return false, "unloaded" end
    local length = tonumber(minutes) or Exercise.MINUTES
    if length < 1 then length = Exercise.MINUTES end
    local made, action = pcall(function()
        return ISFitnessAction:new(character, row.type, length, row.data, row.data.type)
    end)
    if not made or action == nil then return false, "unavailable" end
    -- Installed ISTimedActionQueue.add(action) returns the registered queue;
    -- addToQueue is an instance method, and a skipped add returns nil.
    local queued, queue = pcall(ISTimedActionQueue.add, action)
    if not queued or queue == nil or ISTimedActionQueue.queues == nil
        or queue ~= ISTimedActionQueue.queues[character] then return false, "unavailable" end
    return true
end

return Exercise
