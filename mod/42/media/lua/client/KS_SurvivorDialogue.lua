require "KS_ActivityFeed"
require "KS_Settings"

local Dialogue = rawget(_G, "KnoxSurvivorDialogue") or {}
_G.KnoxSurvivorDialogue = Dialogue

local DEFAULT_COOLDOWN = 1800
local GLOBAL_COOLDOWN = 240
local states = {}

local BANKS = {
    roam_building = {
        "I'm checking that building.", "Might be something useful in there.",
        "Let's see what they left behind.",
    },
    roam_area = {
        "I'm moving on.", "Nothing keeping me here.", "I'll check farther out.",
    },
    search = {
        "Let me check this.", "I'll have a quick look.", "See what's left.",
    },
    loot_found = {
        "This'll help.", "Worth carrying.", "We can use this.",
    },
    no_supplies = {
        "Nothing useful here.", "Place is picked clean.", "No luck here.",
    },
    share_supply = {
        "Take this. I have enough.",
        "Here. You need this more than I do.",
        "I've got a spare. Take it.",
    },
    need_food = {
        "I need to find something to eat.", "I'm running low on food.",
    },
    need_water = {
        "I need water soon.", "I'm getting thirsty.",
    },
    need_medical = {
        "I need something for this wound.", "I could use medical supplies.",
    },
    rest = {
        "I need a minute.", "I'm catching my breath.", "Let me rest a little.",
    },
    regroup = {
        "Wait up.", "Stay together.", "I'm coming back to you.",
    },
    combat = {
        "Contact!", "Got one here!", "Watch yourself!",
    },
    flee = {
        "Too many—move!", "We need to get clear!", "Fall back!",
    },
    base_work = {
        "I'll get this handled.", "I've got work to do.", "I'll take care of it.",
    },
    -- Said when heavy work is waiting and the body has refused it. A refusal
    -- names the reason, without describing the mod or asking for sympathy.
    cant_lift = {
        "Not that. My shoulder's done in.",
        "I can't lift it today. Ribs.",
        "Ask me again when these hands stop shaking.",
        "That's a two-person job and I'm not one of them right now.",
    },
    -- Said once when the weather turns them around. Concrete, short, no weather
    -- report: a person mentions the rain because it is on them.
    weather_rain = {
        "Rain. I'm not standing in it.",
        "Going in before it soaks me.",
        "That's rain. I'll be inside.",
    },
    weather_cold = {
        "Too cold out here. Going in.",
        "My hands are stiff. I'll be inside.",
        "I need to get warm.",
    },
    -- Wet clothing outlasts the rain that caused it, so the remark is about
    -- being soaked rather than about the sky.
    weather_wet = {
        "Soaked through. I need to dry off.",
        "My clothes are wringing wet. I'm going in.",
        "I can't work like this. I'm wet to the skin.",
    },
    -- A broken weapon is a small, concrete loss. The line says what happened;
    -- it does not explain durability or promise a repair.
    weapon_broken = {
        "My weapon's done. I need another.",
        "That was the last of it. I need another.",
        "The handle's gone. I'm down to my hands.",
    },
    -- A dry gun is a fact in the hand, not a lesson in ammunition. Short,
    -- first person, and no promise that a reload is coming.
    ammo_dry = {
        "I'm dry. Reloading.",
        "Empty. Give me a second.",
        "That's my last round. Reloading.",
    },
    -- A refused shot is a warning, not a misfire. The line asks the body in
    -- the corridor to move and never pretends the gun fired.
    no_clear_shot = {
        "You're in my line. Move.",
        "I can't shoot through you.",
        "No clear shot. I need you clear.",
    },
    base_idle = {
        "Quiet for now. I should check on everyone.",
        "We have a roof. Next we make this place livable.",
        "I keep thinking about what we still need.",
        "Anyone need a hand before I settle down?",
        "I might walk the yard and clear my head.",
    },
    base_social = {
        "Good to see a living face. How are you holding up?",
        "We made it another day. That counts for something.",
        "Sit with me a minute. Tell me what you have seen out there.",
        "This place is starting to feel like ours, do you not think?",
        "When the work is done we should eat together, all of us.",
    },
    base_snack = {
        "I am having a bite. There is enough if you want some.",
        "A quick drink and back to it.",
        "Nothing fancy, but it keeps me going.",
    },
    camp = {
        "I'm staying close for a while.", "This place will do for now.",
    },
    player_talk = {
        "Keep your voice down. Sound carries.",
        "I have been moving carefully since this started.",
        "If we stay alive, we will need a plan beyond tonight.",
        "I remember when a locked door meant something.",
        "I am watching the roads. People are becoming the bigger danger.",
    },
    player_warm_up = {
        "I am not ready to trust a stranger. Give me a little time.",
        "You seem all right. I still need to see how you handle trouble.",
        "Talk to me again after we have both made it through another day.",
    },
    player_independent = {
        "I travel alone. It is how I have stayed alive.",
        "I appreciate the offer, but I have my own route to follow.",
        "No hard feelings. I do better when I answer only for myself.",
    },
    player_lure = {
        "I know a place nearby. Come on, I can show you.",
        "There is shelter just past those buildings. You should see it.",
        "Keep walking with me. We can talk somewhere quieter.",
    },
    player_attack_warning = {
        "Back away. I do not want to fight, but I will.",
        "You should have kept walking.",
        "One more step and we settle this the hard way.",
    },
}

local PERSONALITY_BANKS = {
    frightened = {
        player_talk = { "I keep thinking I hear someone behind us.",
            "I had people with me once. I do not know where they are now.",
            "Please do not leave me in an empty building." },
        combat = { "I cannot do this alone!", "Stay close, please!", "There are too many!" },
        need_medical = { "It hurts more when I move.", "I need help with this wound." },
        camp = { "I just want one quiet night.", "Maybe tomorrow will be safer." },
    },
    guarded = {
        player_talk = { "I remember enough to know not to trust promises.",
            "Show me what you do when things go wrong.",
            "I am listening. That does not mean I agree." },
        combat = { "Watch the angles.", "Do not chase them into a bad position.", "Hold your ground." },
        need_medical = { "The wound is manageable. It still needs cleaning." },
        camp = { "We need a better fallback before we settle here.", "A base is only as good as its exits." },
    },
    brave = {
        player_talk = { "We can build something if we keep making smart choices.",
            "I have lost people before. I will not waste what they taught me.",
            "Give me a job and I will see it through." },
        combat = { "Stay behind me.", "We finish this and move on.", "Keep the pressure on." },
        need_medical = { "It is a bad cut, but I can still work after it is dressed." },
        camp = { "We should make this place worth defending.", "There is still a future if we plan for it." },
    },
    loner = {
        player_talk = { "I have survived by keeping my footprint small.",
            "I had a route before we met. I may return to it.",
            "Company is useful. Dependence gets people killed." },
        combat = { "Pick one and finish it.", "Do not draw the whole street.", "I will cover this side." },
        camp = { "I will keep to the edge of camp.", "A quiet corner is all I need." },
    },
    sociable = {
        player_talk = { "It helps hearing another living voice.",
            "We should learn what everyone is good at.",
            "I still think people can make a life here." },
        combat = { "Together, now!", "I have your side.", "Call out what you see." },
        camp = { "We should eat together when the work is done.", "A real routine might keep us sane." },
    },
    unstable = {
        player_talk = { "Some days I remember everything. Some days I remember too much.",
            "I had a plan. Then the dead started walking.",
            "Do not mistake a smile for calm." },
        combat = { "They keep coming. Good. Let them.", "I can hear them in the walls.", "Move! Move!" },
        camp = { "The quiet is worse than the noise.", "I need something to do before I start thinking." },
    },
    opportunist = {
        player_talk = { "Everybody needs something. The trick is finding out what.",
            "I know places people overlook.",
            "We could both come out ahead here." },
        combat = { "Take what you can and go.", "Do not get stuck fighting for pride.", "Find the weak side." },
        camp = { "A good base needs supplies and an exit nobody watches.", "I know where the useful things are kept." },
    },
    predatory = {
        player_talk = { "You are carrying more than you can protect.",
            "You should have kept your distance.",
            "This road belongs to whoever can hold it." },
        combat = { "No witnesses.", "Finish it.", "Do not let them run." },
    },
    gunner = {
        player_talk = { "Nice weapon. Do not reach for it.",
            "I have got a bead on this whole street.",
            "Plenty of ammo. Hoping I do not need it." },
        combat = { "Told you.", "Should have walked.", "Cover! Reloading!" },
        camp = { "I sleep light. Do not test it.", "Perimeter stays watched." },
    },
}

local function stableIndex(id, event, ticks, count)
    local text = tostring(id or "survivor") .. ":" .. tostring(event)
        .. ":" .. tostring(math.floor((tonumber(ticks) or 0) / 300))
    local hash = 23
    for index = 1, #text do
        hash = (hash * 37 + string.byte(text, index)) % 2147483647
    end
    return (hash % count) + 1
end

local function enabled()
    return KnoxSettings == nil or KnoxSettings.showSurvivorSpeech == nil
        or KnoxSettings.showSurvivorSpeech()
end

local PLACE_WORDS = {
    "the ridge road", "empty houses", "the treeline", "a burned-out stop",
    "the river bend", "quiet streets", "a stripped farmhouse", "the rail line",
}

local function hashText(text)
    local hash = 23
    text = tostring(text or "")
    for index = 1, #text do
        hash = (hash * 37 + string.byte(text, index)) % 2147483647
    end
    return hash
end

local function placeWord(id, timestamp)
    return PLACE_WORDS[(hashText(tostring(id) .. ":" .. tostring(timestamp)) % #PLACE_WORDS) + 1]
end

--- How `viewerId` refers to `subjectId` inCampfire-style speech. Disposition
--- and shared affiliation decide the noun; no kinship is invented because the
--- ledger tracks none. Deterministic and side-effect free.
function Dialogue.relationNoun(viewerId, subjectId)
    if viewerId == nil or subjectId == nil then return "a traveler" end
    if tostring(viewerId) == tostring(subjectId) then return "myself" end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then return "a traveler" end
    local disposition = nil
    if persistence.getRelationship ~= nil then
        local ok, record = pcall(persistence.getRelationship, viewerId, subjectId)
        if ok and type(record) == "table" then disposition = record.disposition end
    end
    if disposition == "hostile" then return "that hostile soul" end
    if disposition == "declined" then return "that one" end
    local viewerGroup, subjectGroup = nil, nil
    if persistence.getTravelGroupFor ~= nil then
        local ok, group = pcall(persistence.getTravelGroupFor, viewerId)
        if ok and type(group) == "table" then viewerGroup = group end
        ok, group = pcall(persistence.getTravelGroupFor, subjectId)
        if ok and type(group) == "table" then subjectGroup = group end
    end
    if viewerGroup ~= nil and subjectGroup ~= nil
        and tostring(viewerGroup.id) == tostring(subjectGroup.id) then
        return "my groupmate"
    end
    local viewerFaction, subjectFaction = nil, nil
    if persistence.getFactionForSurvivor ~= nil then
        local ok, faction = pcall(persistence.getFactionForSurvivor, viewerId)
        if ok then viewerFaction = faction end
        ok, faction = pcall(persistence.getFactionForSurvivor, subjectId)
        if ok then subjectFaction = faction end
    end
    local viewerFactionId = type(viewerFaction) == "table" and viewerFaction.id or viewerFaction
    local subjectFactionId = type(subjectFaction) == "table" and subjectFaction.id or subjectFaction
    if viewerFactionId ~= nil and subjectFactionId ~= nil
        and tostring(viewerFactionId) == tostring(subjectFactionId) then
        return "one of ours"
    end
    if disposition == "allied" then return "my friend" end
    local meetings = 0
    if persistence.getRelationship ~= nil then
        local ok, record = pcall(persistence.getRelationship, viewerId, subjectId)
        if ok and type(record) == "table" then meetings = tonumber(record.meetings) or 0 end
    end
    if meetings >= 2 then return "someone I have crossed before" end
    return "a traveler"
end

local function forenameOf(id)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getSurvivorIdentity ~= nil then
        local ok, identity = pcall(persistence.getSurvivorIdentity, id)
        if ok and type(identity) == "table" then
            local forename = identity.forename or identity.firstName
            if type(forename) == "string" and forename ~= "" then return forename end
        end
    end
    return nil
end

--- Build campfire recount lines from ledger history (newest first, max 3).
-- Names render relation-aware: repeat meetings speak of relations, first
-- meetings speak the recorded forename when one exists. Returns {} when the
-- survivor has no history worth retelling.
function Dialogue.recountLines(survivorId)
    local stories = rawget(_G, "KnoxOffscreenStories")
    if stories == nil or stories.historyFor == nil then return {} end
    local ok, history = pcall(stories.historyFor, survivorId)
    if not ok or type(history) ~= "table" or #history == 0 then return {} end
    local lines = {}
    for index = #history, math.max(1, #history - 2), -1 do
        local entry = history[index]
        if type(entry) == "table" then
            local line = Dialogue.recountEntry(survivorId, entry)
            if line ~= nil then lines[#lines + 1] = line end
            if #lines >= 3 then break end
        end
    end
    return lines
end

function Dialogue.recountEntry(survivorId, entry)
    local kind = tostring(entry.kind or "")
    if kind == "heard" then
        -- Second-hand memory keeps its source. The line says who told them and
        -- where that person's event happened; it never borrows the listener's
        -- first-person voice for something they did not see.
        local source = forenameOf(entry.from)
        local attribution = source ~= nil and (source .. " told me") or "Someone told me"
        local sourcePlace = placeWord(entry.from, entry.heardAtHours)
        local fact = tostring(entry.heardKind or "")
        if fact == "meet" then
            local met = forenameOf(entry.heardWith) or "someone"
            local line = attribution .. " about crossing " .. met
                .. " out past " .. sourcePlace .. "."
            if entry.heardOutcome == "hostile" then
                line = line .. " It turned hostile between them."
            elseif entry.heardOutcome == "joined" then
                line = line .. " They decided to travel together."
            elseif entry.heardOutcome == "declined" or entry.heardOutcome == "parted" then
                line = line .. " They went their separate ways."
            end
            return line
        end
        if fact == "scar" then
            return attribution .. " about coming back to a place out past "
                .. sourcePlace .. " where weapons had been drawn."
        end
        if fact == "close_call" then
            if entry.heardOutcome == "severe" then
                return attribution .. " about taking a bad wound out past "
                    .. sourcePlace .. "."
            end
            if entry.heardOutcome == "hurt" then
                return attribution .. " about getting hurt out past "
                    .. sourcePlace .. "."
            end
            return attribution .. " something stalked them near " .. sourcePlace .. "."
        end
        if fact == "cache" then
            return attribution .. " they marked a cache out past " .. sourcePlace .. "."
        end
        if fact == "ride" then
            return attribution .. " they caught a ride out past " .. sourcePlace .. "."
        end
        return nil
    end
    local place = placeWord(survivorId, entry.t)
    local subject = nil
    if entry.with ~= nil then
        subject = Dialogue.relationNoun(survivorId, entry.with)
        if subject == "a traveler" or subject == "someone I have crossed before" then
            local name = forenameOf(entry.with)
            if name ~= nil then subject = name end
        end
    end
    if kind == "meet" and subject ~= nil then
        if entry.outcome == "hostile" then
            return "Crossed " .. subject .. " out past " .. place .. ". Things turned hostile between us."
        end
        if entry.outcome == "joined" then
            return "Met " .. subject .. " out past " .. place .. ". We decided to travel together."
        end
        if entry.outcome == "declined" or entry.outcome == "parted" then
            return "Met " .. subject .. " out past " .. place .. ". We decided to go our separate ways."
        end
        return "Ran into " .. subject .. " out past " .. place .. ". We talked and walked on."
    end
    if kind == "close_call" then
        if entry.outcome == "severe" then
            return "Took a bad wound out near " .. place .. ". Patched it as best I could."
        end
        if entry.outcome == "hurt" then
            return "Got hurt out near " .. place .. ". It still bled when I found cover."
        end
        return "Something stalked me near " .. place .. ". Went still until it passed."
    end
    if kind == "rest" then
        return "Found a quiet moment out past " .. place .. ". Caught my breath."
    end
    if kind == "haunt" then
        return "Walked ground that felt known, out past " .. place .. ". Steadied me."
    end
    if kind == "weather" then
        return "Pushed through bad weather past " .. place .. ". Still moving."
    end
    if kind == "cache" then
        return "Marked a spot out past " .. place .. " in my head. Might matter later."
    end
    if kind == "ride" then
        if entry.outcome == "arrived" then
            return "Caught wheels out past " .. place .. ". Rode all the way."
        end
        return "Caught a ride out past " .. place .. ". Saved my legs."
    end
    if kind == "scar" then
        if subject ~= nil then
            return "Came back to where " .. subject .. " and I drew weapons. Still standing."
        end
        return "Came back to where I bled out past " .. place .. ". It looks different in daylight."
    end
    return nil
end

-- The same reason, in the mouth of the person giving it. A proud survivor does
-- not apologise for a bad shoulder and an anxious one does; both refuse the same
-- work for the same measured cause. Only the manner is selected here - the reason
-- still comes from the eligibility gate.
-- A witness says it out loud, and the name is what makes it a person rather
-- than a rule: {name} is where the person it happened to belongs. Five voices,
-- because the same rebuke from a frightened neighbour and a brave one are not
-- the same sentence.
BANKS.witnessed_mean = {
    "I saw that.",
    "That was uncalled for.",
    "They did not deserve that.",
    "You should go and apologise.",
    "Not in front of me. Ever.",
}

-- Said once, when someone who watched it all finally decides about you. Short
-- and plain: a person leaving does not give a speech.
-- A person who will not obey you still talks to you. This is the refusal, not
-- a goodbye: it explains nothing and offers no negotiation.
BANKS.order_refused_wary = {
    "I will not take that from you. Not now.",
    "I will choose what I do for a while.",
    "Ask me again when you have earned it.",
}

BANKS.witness_enough = {
    "That is it. I am done with you.",
    "I have watched you do that once too often.",
    "Do not follow me. We are finished.",
}

local WITNESS_BY_PERSONALITY = {
    brave = { "I saw that. {name} did nothing to deserve it.",
        "Say it to {name} again. See what happens." },
    guarded = { "I saw what you said. Noted.",
        "I will not have that. Not to {name}." },
    sociable = { "I saw that. {name} is one of us.",
        "I heard you. So did {name}." },
    frightened = { "I do not like it. Please do not talk to {name} like that.",
        "I saw it. It scared me." },
    loner = { "I heard you. Keep your voice down around {name}.",
        "Not in front of me. Not to {name}." },
}
for key, lines in pairs(WITNESS_BY_PERSONALITY) do
    local bank = PERSONALITY_BANKS[key]
    if bank ~= nil then bank.witnessed_mean = lines end
end

local CANT_LIFT_BY_PERSONALITY = {
    brave = {
        "Not today. I'd be more trouble than help.",
        "Save it for someone who can lift it.",
    },
    guarded = {
        "No. My back's gone.",
        "Find someone else. I can't lift.",
    },
    sociable = {
        "Sorry - my shoulder's finished. Ask me in a few days.",
        "I hate to say it, but I can't lift that today.",
    },
    frightened = {
        "I can't. My hands won't hold. Please don't make me.",
        "Not the heavy work. Not today. I'm sorry.",
    },
    loner = {
        "I work alone or not at all. Not that.",
        "No. I'll find something else to do.",
    },
}
for key, lines in pairs(CANT_LIFT_BY_PERSONALITY) do
    local bank = PERSONALITY_BANKS[key]
    if bank ~= nil then bank.cant_lift = lines end
end

-- A bitten person's refusal is not a bad back. The reason is the body's own and
-- the words are still theirs: five voices, none of them explaining the system.
BANKS.cant_lift_bitten = {
    "I can't take the heavy work. I got bit.",
    "Not the lifting. My arm's gone hot and it's spreading.",
    "Find someone else for that. I'm not going to last.",
}

local CANT_LIFT_BITTEN_BY_PERSONALITY = {
    brave = {
        "I got bit. I can still work. Not the lifting.",
        "Keep me on light work. That arm's finished.",
    },
    guarded = {
        "No. I got bit on the last run.",
        "Find someone else. I'm done lifting.",
    },
    sociable = {
        "I did not want to say it. I got bit.",
        "I can't lift that. I'm sorry. I got bit.",
    },
    frightened = {
        "I got bit. Please do not make me lift that.",
        "My arm's hot. I think it's bad. Please.",
    },
    loner = {
        "I got bit. Keep it quiet and let me work.",
        "Not the heavy work. I'm bit.",
    },
}
for key, lines in pairs(CANT_LIFT_BITTEN_BY_PERSONALITY) do
    local bank = PERSONALITY_BANKS[key]
    if bank ~= nil then bank.cant_lift_bitten = lines end
end

-- The weapon breaks in the speaker's own mouth, once per item. These are
-- reactions, not a durability lesson: no numbers, no repair promise.
local WEAPON_BROKEN_BY_PERSONALITY = {
    brave = {
        "Broke. I'll make do. Find me another when you can.",
        "It's done. I'll find myself another.",
    },
    guarded = {
        "Weapon's broken. I'll use my hands.",
        "That's finished. Don't expect much from me now.",
    },
    sociable = {
        "It broke. If you see another, I could use it.",
        "My weapon's done. I'm sorry - I'll do what I can.",
    },
    frightened = {
        "It broke. Please tell me you have another.",
        "My weapon's gone. I can't - I can't fight like this.",
    },
    loner = {
        "Broke. I'll manage with my hands.",
        "Weapon's done. My hands will do.",
    },
}
for key, lines in pairs(WEAPON_BROKEN_BY_PERSONALITY) do
    local bank = PERSONALITY_BANKS[key]
    if bank ~= nil then bank.weapon_broken = lines end
end

-- A dry gun in each mouth: the same empty click, five different people.
local AMMO_DRY_BY_PERSONALITY = {
    brave = {
        "Dry. I'll make the next one count.",
        "Empty. Cover me while I reload.",
    },
    guarded = {
        "Out of rounds. I'm reloading.",
        "My gun's dry. Give me a moment.",
    },
    sociable = {
        "I'm out. Reloading - stay close.",
        "Empty here. Cover me a second.",
    },
    frightened = {
        "I'm out of rounds. Please, cover me.",
        "Empty. I need a second to reload.",
    },
    loner = {
        "Dry. I'm reloading.",
        "Out. My problem - reloading.",
    },
}
for key, lines in pairs(AMMO_DRY_BY_PERSONALITY) do
    local bank = PERSONALITY_BANKS[key]
    if bank ~= nil then bank.ammo_dry = lines end
end

-- The same refused shot in each mouth: a warning to a friend, not a jam.
local NO_CLEAR_SHOT_BY_PERSONALITY = {
    brave = {
        "I can't shoot with you there. Shift.",
        "I can't shoot through you. Move up.",
    },
    guarded = {
        "No clear shot. I need you to step aside.",
        "You're blocking me. Move.",
    },
    sociable = {
        "I can't fire with you there. Shift left.",
        "You're in my line, friend. Move.",
    },
    frightened = {
        "I can't shoot. You're in the way.",
        "Please move - I can't fire through you.",
    },
    loner = {
        "Move. You're in my line.",
        "I can't shoot. You're blocking.",
    },
}
for key, lines in pairs(NO_CLEAR_SHOT_BY_PERSONALITY) do
    local bank = PERSONALITY_BANKS[key]
    if bank ~= nil then bank.no_clear_shot = lines end
end

-- Weather remarks in each mouth: the same rain, noticed by five different people.
local WEATHER_BY_PERSONALITY = {
    brave = {
        weather_rain = { "Rain won't kill us. Standing in it might.",
            "Inside. I'm not catching a cold over this." },
        weather_cold = { "Cold's in my hands. I'm going in.",
            "I can't hold a tool like this. Inside." },
        weather_wet = { "Wet through. I'll dry off and get back to it.",
            "Soaked. Give me a minute inside." },
    },
    guarded = {
        weather_rain = { "Getting wet. Going in.", "No point working soaked." },
        weather_cold = { "Too cold. I'll be inside.", "Hands are useless in this. Going in." },
        weather_wet = { "I'm wet through. Going in.",
            "Nothing dries out here. I'll be inside." },
    },
    sociable = {
        weather_rain = { "Come in out of this, would you?",
            "I'm going in before I'm soaked through." },
        weather_cold = { "It's freezing. I'll be by the fire.", "Let's get warm, both of us." },
        weather_wet = { "I'm soaked. Come in before you catch something.",
            "Rain's got through everything. I need to dry off." },
    },
    frightened = {
        weather_rain = { "I don't like being out in this. I'm going in.",
            "It's so loud in the rain. Inside." },
        weather_cold = { "I can't stop shaking. I'm going in.",
            "Please, I need to be warm." },
        weather_wet = { "I'm wet and I can't stop shaking. I'm going in.",
            "Please, I need to get dry." },
    },
    loner = {
        weather_rain = { "Rain. I'll be inside.", "Not standing in this." },
        weather_cold = { "Cold enough. I'm going in.", "I'll wait it out indoors." },
        weather_wet = { "Soaked. I'll be inside.",
            "Wet to the skin. I'm going in." },
    },
}
for key, events in pairs(WEATHER_BY_PERSONALITY) do
    local bank = PERSONALITY_BANKS[key]
    if bank ~= nil then
        for event, lines in pairs(events) do bank[event] = lines end
    end
end

-- Which voice a person has, from the scores their identity already carries.
-- Fear speaks first because it is the loudest thing in a refusal, then warmth,
-- then hardness; a survivor whose scores sit in the middle keeps their
-- archetype's bank. This reads existing fields - sociability, courage, aggression -
-- and adds no new axis or stored value.
Dialogue.VOICE_BANDS = { afraid = 35, open = 65, closed = 25, bold = 75, hard = 65 }

function Dialogue.voiceFor(personality)
    if type(personality) ~= "table" then return nil end
    local courage = tonumber(personality.courage)
    local sociability = tonumber(personality.sociability)
    local aggression = tonumber(personality.aggression)
    if courage ~= nil and courage <= Dialogue.VOICE_BANDS.afraid then return "frightened" end
    if sociability ~= nil and sociability >= Dialogue.VOICE_BANDS.open then return "sociable" end
    if sociability ~= nil and sociability <= Dialogue.VOICE_BANDS.closed then
        if aggression ~= nil and aggression >= Dialogue.VOICE_BANDS.hard then return "guarded" end
        return "loner"
    end
    if courage ~= nil and courage >= Dialogue.VOICE_BANDS.bold then return "brave" end
    if aggression ~= nil and aggression >= Dialogue.VOICE_BANDS.hard then return "guarded" end
    return nil
end

-- One selection rule for every surface: the speaker's own bank when their voice
-- has lines for this event, the shared bank otherwise. Returning the voice as
-- well lets a caller explain which mouth spoke without re-reading identity.
function Dialogue.linesFor(survivorId, event)
    local lines = BANKS[event]
    if event == nil then return nil, nil end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getSurvivorPersonality == nil then
        return lines, nil
    end
    local personality = persistence.getSurvivorPersonality(survivorId)
    local key = personality ~= nil and personality.personality or nil
    local voice = Dialogue.voiceFor(personality) or key
    -- Voice first, then the archetype it was read from, then the shared bank. A
    -- bank that has words for this moment but not for this voice still speaks in
    -- the right manner for the person, instead of dropping to a generic line.
    local candidates = {}
    if voice ~= nil then candidates[#candidates + 1] = voice end
    if key ~= nil and key ~= voice then candidates[#candidates + 1] = key end
    for _, candidate in ipairs(candidates) do
        local bank = PERSONALITY_BANKS[candidate]
        if bank ~= nil and type(bank[event]) == "table" then
            return bank[event], candidate
        end
    end
    return lines, key
end

function Dialogue.sayLines(character, survivorId, event, lines, ticks, cooldown)
    if character == nil or type(lines) ~= "table" or #lines == 0 or not enabled() then
        return false, "unavailable"
    end
    local id = tostring(survivorId or "survivor")
    local now = math.max(0, tonumber(ticks) or 0)
    local state = states[id] or { nextGlobal = 0, events = {} }
    states[id] = state
    if now < (state.nextGlobal or 0) or now < (state.events[event] or 0) then
        return false, "cooldown"
    end
    local line = lines[stableIndex(id, event, now, #lines)]
    KnoxActivityFeed.speak(character, line)
    state.nextGlobal = now + GLOBAL_COOLDOWN
    state.events[event] = now + math.max(GLOBAL_COOLDOWN,
        tonumber(cooldown) or DEFAULT_COOLDOWN)
    return true, line
end

function Dialogue.say(character, survivorId, event, ticks, cooldown)
    -- One selection rule, shared with every caller that asks for the lines
    -- directly: the speaker's own bank when their personality has one.
    local lines = Dialogue.linesFor(survivorId, event)
    if event == "base_social" then
        -- Campfire moments retell ledger history (TIS recount rule) about a
        -- third of the time; otherwise the normal lifestyle bank speaks.
        local window = math.floor((tonumber(ticks) or 0) / 1800)
        if hashText(tostring(survivorId) .. ":recount:" .. tostring(window)) % 100 < 35 then
            local recount = Dialogue.recountLines(survivorId)
            if #recount > 0 then
                return Dialogue.sayLines(character, survivorId, "recount", recount, ticks, cooldown)
            end
        end
    end
    return Dialogue.sayLines(character, survivorId, event, lines, ticks, cooldown)
end

-- One witness, one sentence, said to the player. The name is filled from the
-- identity of the person it happened to; a bank with no placeholder still
-- speaks, so a voice is never silenced for lacking one.
function Dialogue.sayWitness(character, witnessId, targetId, ticks, cooldown, event)
    if character == nil then return false, "unavailable" end
    event = event or "witnessed_mean"
    local lines = Dialogue.linesFor(witnessId, event)
    if type(lines) ~= "table" or #lines == 0 then return false, "no_lines" end
    local now = math.max(0, tonumber(ticks) or 0)
    local line = lines[stableIndex(tostring(witnessId), event, now, #lines)]
    local name = nil
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getSurvivorIdentity ~= nil and targetId ~= nil then
        local identity = persistence.getSurvivorIdentity(targetId)
        name = type(identity) == "table" and identity.firstName or nil
    end
    line = tostring(line):gsub("{name}", name ~= nil and tostring(name) or "them")
    return Dialogue.sayLines(character, witnessId, event, { line }, ticks, cooldown)
end

function Dialogue.lines(event)
    return BANKS[event]
end

function Dialogue.resetRuntime()
    states = {}
end

return Dialogue
