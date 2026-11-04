-- The Talk panel's Ask tab composes speech from real state, and the panel
-- fixture only covers its answer functions. This drives the real askAbout:
-- the topic whitelist, a body-less survivor, hostility, contact, the real
-- question spoken by the player, the answer spoken once by the survivor, and
-- the fact that asking never touches trust.
local service = assert(CompanionService, "the ask owner must be loaded")
-- The health answer reads the real infection rule; lend it the production module
-- and put back whatever was there so later fixtures do not inherit it.
local previousNeeds = rawget(_G, "KnoxSurvivorNeeds")
KnoxSurvivorNeeds = assert(rawget(_G, "codecIllnessNeeds"), "the illness reader is loaded")
local ask = assert(KS_ASK, "the answers must be exported")
local setState = assert(KS_ASK_SET, "the state hook must be exported")
local spoken = assert(KS_ASK_SPOKEN, "the speech hook must be exported")
local reset = assert(KS_ASK_RESET, "the reset hook must be exported")

local said = nil
local player = { Say = function(_, text) said = text end }
local character = {
    getHealth = function() return 100 end,
    getStats = function()
        return { get = function(_, stat) return 0 end }
    end,
}

local realPersistence = KnoxPersistence
KnoxPersistence = {
    getSurvivorAffiliation = function() return { kind = "independent" } end,
    getBase = function() return nil end,
    getFactionForSurvivor = function() return nil end,
    getTravelGroupFor = function() return nil end,
    getBaseStorageProblems = function() return {} end,
    -- Asking is free. If any path tried to move trust this would fail the
    -- fixture instead of quietly rewarding a player for interrogation.
    recordPlayerConversation = function() error("asking must not move trust") end,
}
getGameTime = function() return { getHour = function() return 9 end } end
getClimateManager = function()
    return { isRaining = function() return true end, isSnowing = function() return false end }
end
CharacterStat = { HUNGER = "hunger", THIRST = "thirst", FATIGUE = "fatigue" }
local realDialogue = rawget(_G, "KnoxSurvivorDialogue")
KnoxSurvivorDialogue = { recountLines = function(id)
    if id == "s1" then
        return { "Ran into Ada out past the farm.", "We talked and walked on." }
    end
    return {}
end }
assert(not pcall(KnoxPersistence.recordPlayerConversation), "the trust tripwire must be armed")

-- 1. No body, no answer, no speech.
reset()
setState({ character = nil, hostile = false, hearing = true })
said = nil
local ok, reason = service.askAbout(player, "s1", "day")
assert(ok == false and reason == "survivor_unavailable",
    "a missing body refuses with its own reason: " .. tostring(reason))
assert(spoken() == nil and said == nil, "nothing may be spoken without a survivor")

-- 2. Only the known questions exist.
reset()
setState({ character = character })
ok, reason = service.askAbout(player, "s1", "weather")
assert(ok == false and reason == "unknown_question", "an unknown topic is refused")
assert(spoken() == nil, "an unknown topic says nothing")

-- 3. A hostile survivor does not answer questions.
reset()
setState({ character = character, hostile = true })
ok, reason = service.askAbout(player, "s1", "day")
assert(ok == false and reason == "hostile", "hostility refuses before any answer")
assert(spoken() == nil, "a hostile survivor stays silent")

-- 4. A question needs the same clear contact an order does.
reset()
setState({ character = character, hostile = false, hearing = false })
ok, reason = service.askAbout(player, "s1", "day")
assert(ok == false and reason == "too_far_away", "no contact refuses the question")
assert(spoken() == nil and said == nil, "a question through a wall is not asked")

-- 5. A real answer is composed, asked and spoken once.
reset()
setState({ character = character, hearing = true })
said = nil
local answered, answer = service.askAbout(player, "s1", "day")
assert(answered == true and type(answer) == "string" and answer ~= "",
    "a clear conversation answers")
assert(answer:find("rain", 1, true) ~= nil, "the answer uses the real weather")
assert(said == "How's the day treating you?", "the player really asks the question")
assert(spoken() ~= nil and spoken().event == "player_ask_day"
    and spoken().text == answer, "the survivor speaks the answer once")

-- 6. Each topic asks its own question and speaks its own answer.
for _, topic in ipairs({ "day", "home", "group", "health", "need", "travels" }) do
    reset()
    setState({ character = character })
    said = nil
    local fine, text = service.askAbout(player, "s1", topic)
    assert(fine == true and type(text) == "string" and text ~= "",
        topic .. " must answer")
    assert(said ~= nil and said ~= "", topic .. " must be asked out loud")
    assert(spoken() ~= nil and spoken().event == "player_ask_" .. topic,
        topic .. " must speak through its own event")
    assert(spoken().text == text, topic .. " speaks the text it returned")
    if topic == "travels" then
        assert(text:find("Ada", 1, true) ~= nil,
            "their travels retell a recorded encounter, not an invented one")
        assert(text:find("walked on", 1, true) ~= nil,
            "a second recorded line may follow the first")
    end
end

-- 6a. A bitten survivor answers with the bite, and only when it is real.
local bitten = false
character.getBodyDamage = function()
    return { IsInfected = function() return bitten end }
end
bitten = true
reset()
setState({ character = character })
local biteOk, biteText = service.askAbout(player, "s1", "health")
assert(biteOk == true and biteText:find("bit", 1, true) ~= nil,
    "a bitten survivor reports it: " .. tostring(biteText))
bitten = false
reset()
setState({ character = character })
local soundOk, soundText = service.askAbout(player, "s1", "health")
assert(soundOk == true and soundText:find("bit", 1, true) == nil,
    "a clean survivor does not claim a bite: " .. tostring(soundText))

-- 6b. With no recorded history they say so, rather than inventing a story.
reset()
setState({ character = character })
KnoxSurvivorDialogue = { recountLines = function() return {} end }
local emptyOk, emptyText = service.askAbout(player, "s1", "travels")
assert(emptyOk == true and emptyText:find("Nothing worth telling", 1, true) ~= nil,
    "an empty ledger answers honestly")
assert(spoken() ~= nil and spoken().event == "player_ask_travels",
    "the honest answer is still spoken as their travels")
KnoxSurvivorDialogue = realDialogue

-- 7. A second ask is a second answer, not a cached one.
reset()
setState({ character = character })
getClimateManager = function()
    return { isRaining = function() return false end, isSnowing = function() return false end }
end
local _, dry = service.askAbout(player, "s1", "day")
assert(dry:find("rain", 1, true) == nil, "a dry answer does not remember the rain")

KnoxSurvivorNeeds = previousNeeds
KnoxPersistence = realPersistence
print("Talk ask PASS topics=6 hostileRefused=true contactRefused=true trustUntouched=true travelsGrounded=true")
