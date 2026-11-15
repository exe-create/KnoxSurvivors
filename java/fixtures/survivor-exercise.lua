local E = assert(KnoxSurvivorExercise)
local saved = { queue = ISTimedActionQueue, runtime = KnoxSurvivorRuntime,
    service = KnoxCompanionService, fitness = ISFitnessAction, definitions = FitnessExercises,
    moodles = MoodleType, ui = ISFitnessUI, instance = instanceof }
codecInstallExerciseQueue()
instanceof = function() return false end
MoodleType = { ENDURANCE = "endurance", HEAVY_LOAD = "load", PAIN = "pain" }
ISFitnessUI = { enduranceLevelThreshold = 2 }
FitnessExercises = { exercisesType = { squats = { name = "Squats", type = "squats" } } }
local nativeBusy, dead, loaded, permitted, refusal, mode = false, false, true, true, nil, "accept"
local character = {
    isDead = function() return dead end, getVehicle = function() return nil end,
    isClimbing = function() return false end, isSittingOnFurniture = function() return false end,
    isCurrentState = function() return false end, setMetabolicTarget = function() end,
    getMoodles = function() return { getMoodleLevel = function() return 0 end } end,
    getCharacterActions = function() return { isEmpty = function() return not nativeBusy end } end }
KnoxSurvivorRuntime = { getCharacter = function() return loaded and character or nil end }
KnoxCompanionService = { orderContact = function() return permitted, refusal end }
local action
ISFitnessAction = { new = function(_, body, kind, minutes, data, nativeKind)
    action = { character = body, exercise = kind, minutes = minutes,
        begin = function(self) self.began = true end }
    return action
end }
local player = {}
local started = E.start(player, "exercise-person", "squats")
assert(started == true and action.began == true
    and ISTimedActionQueue.queues[character].queue[1] == action,
    "exercise reaches the installed native queue on the survivor body")
assert(E.refusal(player, "exercise-person") == "busy",
    "a queued Lua action prevents another exercise")
ISTimedActionQueue.queues[character].queue = {}
nativeBusy = true
assert(E.refusal(player, "exercise-person") == "busy",
    "native character actions also prevent another exercise")
nativeBusy = false
permitted, refusal = false, "not_your_survivor"
assert(select(2, E.start(player, "exercise-person", "squats")) == refusal,
    "inspection does not grant authority over another person's survivor")
permitted, refusal = false, "hostile"
assert(E.refusal(player, "exercise-person") == "hostile", "hostility blocks the order")
permitted, refusal = false, "too_far_away"
assert(E.refusal(player, "exercise-person") == "too_far_away", "contact is checked at execution")
permitted, refusal = true, nil
local nativeAdd = ISTimedActionQueue.add
ISTimedActionQueue.add = function() return nil end
assert(E.start(player, "exercise-person", "squats") == false,
    "native queue refusal cannot be reported as exercise starting")
ISTimedActionQueue.add = nativeAdd
assert(select(2, E.start(player, "exercise-person", "barbell")) == "unknown_exercise",
    "unavailable equipment exercise is refused")
loaded = false
assert(E.refusal(player, "exercise-person") == "unloaded", "unloaded survivor cannot exercise")
loaded, dead = true, true
assert(E.refusal(player, "exercise-person") == "dead", "dead survivor cannot exercise")
loaded, dead = true, false
-- a shell-like body that cannot answer the native tick path
local shellBody = { isDead = function() return false end,
    getMoodles = function() return nil end }
KnoxSurvivorRuntime = { getCharacter = function() return shellBody end }
assert(E.refusal(player, "shell-person") == "unavailable",
    "a body without moodles is refused cleanly")
assert(select(2, E.start(player, "shell-person", "squats")) == "unavailable",
    "no native action is queued for an incompatible body")
local noState = { isDead = function() return false end,
    getMoodles = function() return { getMoodleLevel = function() return 0 end } end,
    setMetabolicTarget = function() end }
KnoxSurvivorRuntime = { getCharacter = function() return noState end }
assert(E.refusal(player, "nostate-person") == "unavailable",
    "a body without the player state machine is refused cleanly")
ISTimedActionQueue, KnoxSurvivorRuntime, KnoxCompanionService = saved.queue, saved.runtime, saved.service
ISFitnessAction, FitnessExercises, MoodleType, ISFitnessUI, instanceof =
    saved.fitness, saved.definitions, saved.moodles, saved.ui, saved.instance
print("Survivor exercise PASS installedQueue=true busy=true authority=true admissionReceipt=true")
