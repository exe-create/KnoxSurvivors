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
    offer_cigarette = { "Want a smoke?", "I've got a spare cigarette, if you want it." },
    accept_cigarette = { "Thanks. I could use one.", "Yeah, thanks." },
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
        "Too many - move!", "We need to get clear!", "Fall back!",
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
    weather_heat = {
        "Too hot. I need some shade.",
        "I'm overheating. Getting out of the sun.",
        "Need somewhere cooler for a minute.",
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
    -- A trained survivor's diagnosis: what is worst, and who is first. The
    -- name is filled from the person being spoken about; a bank line without
    -- the placeholder still speaks, so a voice is never silenced for it.
    diagnosis_bleeding = {
        "{name} is bleeding out. They are first.",
        "Bleeding first. {name}, you are with me.",
    },
    diagnosis_fracture = {
        "{name}'s bone is broken. They go first.",
        "That needs splinting before anything else. {name} first.",
    },
    diagnosis_infection = {
        "{name}'s wound is turning. They are next.",
        "That wound is infected. {name} first.",
    },
    diagnosis_wound = {
        "{name} is hurt. They are first.",
        "Wounds next. {name} first.",
    },
    diagnosis_dressing = {
        "{name}'s dressing is spent. That comes first.",
        "That bandage is done. {name} first.",
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
    base_greet = {
        "Morning. Good to see you up.",
        "You are back. We held the place down.",
        "Hey. Anything need doing?",
        "Good, you are here. It has been quiet.",
    },
    -- Musing is an idle voice, not a report: a resident thinking out loud while
    -- it walks the base. One category per feeling its own moodles describe.
    base_musing = {
        "Should move the fuel cans before it rains.",
        "I used to know every street in this town.",
        "Count the days by what we fixed, not by what we lost.",
        "Someone should check that back fence again.",
        "One day I am finding a cabin by the water. Just quiet for a while.",
        "I still catch myself planning what I would do on a proper day off.",
    },
    base_musing_hurt = {
        "This arm is not healing as fast as I would like.",
        "I will keep going. Slower, but I will keep going.",
        "Should have let the others handle the heavy side.",
    },
    base_musing_hungry = {
        "I keep thinking about a hot meal.",
        "We are going to have to do better than cold cans.",
        "Note to self: find the can opener next time.",
    },
    base_musing_tired = {
        "Just need to sit for a minute. Just one.",
        "I have been on my feet since dawn.",
        "Sleep would be a luxury right now.",
    },
    base_musing_frightened = {
        "I heard something out there. Probably nothing.",
        "I do not like how quiet it gets after dark.",
        "Keep the rifle close tonight.",
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

local function hashText(text)
    local hash = 23
    text = tostring(text or "")
    for index = 1, #text do
        hash = (hash * 37 + string.byte(text, index)) % 2147483647
    end
    return hash
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
    local lines, seen = {}, {}
    -- The canonical ledger retains twelve entries. Unsupported or duplicate
    -- recent rows must not hide the older facts that are still in that ledger.
    for index = #history, math.max(1, #history - 11), -1 do
        local entry = history[index]
        if type(entry) == "table" then
            local line = Dialogue.recountEntry(survivorId, entry)
            if line ~= nil and not seen[line] then
                lines[#lines + 1] = line
                seen[line] = true
            end
            if #lines >= 3 then break end
        end
    end
    return lines
end

function Dialogue.recountEntry(survivorId, entry)
    if type(entry) ~= "table" then return nil end
    local kind = tostring(entry.kind or "")
    if kind == "heard" then
        -- Second-hand memory keeps its source. The line says who told them and
        -- what that person's event was; it never borrows the listener's
        -- first-person voice for something they did not see.
        local source = forenameOf(entry.from)
        local attribution = source ~= nil and (source .. " told me") or "Someone told me"
        local fact = tostring(entry.heardKind or "")
        if fact == "meet" then
            local met = forenameOf(entry.heardWith) or "someone"
            local line = attribution .. " about crossing " .. met .. "."
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
            if entry.heardDetail == "came back to where weapons were drawn" then
                return attribution .. " about returning to a place where weapons had been drawn."
            end
            if entry.heardDetail == "came back to where blood was left" then
                return attribution .. " about returning to a place where blood was left."
            end
            return attribution .. " about returning to a place they remembered."
        end
        if fact == "close_call" then
            if entry.heardOutcome == "severe" then
                return attribution .. " about taking a bad wound."
            end
            if entry.heardOutcome == "hurt" then
                return attribution .. " about getting hurt."
            end
            return nil
        end
        if fact == "cache" then
            return attribution .. " they marked a cache."
        end
        if fact == "ride" then
            return attribution .. " they caught a ride."
        end
        return nil
    end
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
            return "Crossed " .. subject .. ". Things turned hostile between us."
        end
        if entry.outcome == "joined" then
            return "Met " .. subject .. ". We decided to travel together."
        end
        if entry.outcome == "declined" or entry.outcome == "parted" then
            return "Met " .. subject .. ". We decided to go our separate ways."
        end
        return "Ran into " .. subject .. "."
    end
    if kind == "close_call" then
        if entry.outcome == "severe" then
            return "Took a bad wound."
        end
        if entry.outcome == "hurt" then
            return "Got hurt."
        end
        return nil
    end
    if kind == "rest" then
        return "Stopped to rest."
    end
    if kind == "haunt" then
        return "Walked through a place I remembered."
    end
    if kind == "weather" then
        return "Was out in bad weather."
    end
    if kind == "cache" then
        return "Marked a cache."
    end
    if kind == "ride" then
        if entry.outcome == "arrived" then
            return "Reached the end of a ride."
        end
        return "Caught a ride."
    end
    if kind == "scar" then
        if entry.detail == "came back to where weapons were drawn" then
            if subject ~= nil then return "Came back to where " .. subject .. " and I drew weapons." end
            return "Came back to where weapons were drawn."
        end
        if entry.detail == "came back to where blood was left" then return "Came back to where blood was left." end
        return "Came back to a place I remembered."
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

-- First sight of a living stranger: one factual line in the existing voices.
BANKS.recognition_living = { "Someone's there.", "There's someone alive." }
local RECOGNITION_VOICES = {
    frightened = { "Someone's there. Careful.", "Who is that?" },
    guarded = { "Someone's over there.", "I see someone." },
    loner = { "There's someone.", "Someone's out there." },
    sociable = { "Look, someone's alive.", "Hey, someone made it." },
    brave = { "Someone's there. Stay ready.", "I see someone alive." },
}
for voice, lines in pairs(RECOGNITION_VOICES) do
    if PERSONALITY_BANKS[voice] ~= nil then PERSONALITY_BANKS[voice].recognition_living = lines end
end

-- A visual player greeting is grounded in the existing prior meeting count.
BANKS.player_first = { "Who are you?", "Good to see someone alive." }
BANKS.player_known = { "I remember you.", "Good to see you again." }
local PLAYER_RECOGNITION_VOICES = {
    frightened = { player_first={"You startled me.","You're alive. Good."}, player_known={"Oh. It's you.","Good to see you."} },
    guarded = { player_first={"Who are you?","Keep your hands where I can see."}, player_known={"It's you. All right.","I remember you."} },
    loner = { player_first={"You need something?","What do you want?"}, player_known={"You again.","We've met."} },
    sociable = { player_first={"Hey. Glad you're alive.","Another person. Good to see you."}, player_known={"There you are.","Good to see you again."} },
    brave = { player_first={"Easy. Who are you?","You all right?"}, player_known={"You're still standing. Good.","Good to see you."} },
}
for voice, events in pairs(PLAYER_RECOGNITION_VOICES) do
    if PERSONALITY_BANKS[voice] ~= nil then
        for event, lines in pairs(events) do PERSONALITY_BANKS[voice][event] = lines end
    end
end

-- One admitted combat-start cue, grounded only in a live zombie target.
BANKS.combat_zombie = { "Come on, then.", "Back off, you b*stard." }
local ZOMBIE_COMBAT_VOICES = {
    frightened = { "Stay back!", "Please, just stay back!" },
    guarded = { "Keep coming. See what happens.", "Back off, you b*stard." },
    loner = { "Get the f*ck back.", "Come on, then." },
    sociable = { "Not getting me today.", "Back the h*ll off." },
    brave = { "Come get some!", "Come on, you f*cker." },
}
for voice, lines in pairs(ZOMBIE_COMBAT_VOICES) do
    if PERSONALITY_BANKS[voice] ~= nil then PERSONALITY_BANKS[voice].combat_zombie = lines end
end

-- Names come from the owner's existing observation record, not a new NPC memory.
BANKS.npc_known = { "There's {name}.", "I can see {name}." }
local KNOWN_RECOGNITION_VOICES = {
    frightened = { "There's {name}.", "{name}. Over there." },
    guarded = { "I see {name}.", "{name} is there." },
    loner = { "There's {name}.", "{name}. That way." },
    sociable = { "Look, there's {name}.", "I can see {name}." },
    brave = { "I've got eyes on {name}.", "There's {name}." },
}
for voice, lines in pairs(KNOWN_RECOGNITION_VOICES) do
    if PERSONALITY_BANKS[voice] ~= nil then PERSONALITY_BANKS[voice].npc_known = lines end
end

-- Anonymous undead sighting: no name, identity or aftermath is implied.
BANKS.recognition_undead = { "One of them.", "Zombie. Right there." }
local UNDEAD_RECOGNITION_VOICES = {
    frightened = { "One of them. Careful.", "There's a zombie." },
    guarded = { "Zombie. Right there.", "I see one of them." },
    loner = { "One of them.", "Zombie. Over there." },
    sociable = { "Look out. A zombie.", "One of them, over there." },
    brave = { "There's a zombie.", "One of them. Stay ready." },
}
for voice, lines in pairs(UNDEAD_RECOGNITION_VOICES) do
    if PERSONALITY_BANKS[voice] ~= nil then PERSONALITY_BANKS[voice].recognition_undead = lines end
end

-- Only an actually witnessed death of an owner-known person can use these.
BANKS.known_corpse = { "That's {name}.", "There's {name}'s body." }
do
    local corpseVoices = {
        frightened = { "Oh no. That's {name}.", "{name}. They're dead." },
        guarded = { "That's {name}.", "{name}'s body." },
        loner = { "That's {name}.", "{name}. Dead." },
        sociable = { "Oh no. That's {name}.", "That's {name}'s body." },
        brave = { "That's {name}.", "{name}'s body is here." },
    }
    for voice, lines in pairs(corpseVoices) do
        if PERSONALITY_BANKS[voice] ~= nil then PERSONALITY_BANKS[voice].known_corpse = lines end
    end
end

BANKS.known_death = { "{name} is dead.", "That's {name}. Dead." }
local KNOWN_DEATH_VOICES = {
    frightened = { "{name} is dead.", "Oh no. {name}." },
    guarded = { "{name} is dead.", "{name} is down." },
    loner = { "{name} is dead.", "That's {name}. Dead." },
    sociable = { "Oh no. {name} is dead.", "That's {name}. They're dead." },
    brave = { "{name} is down.", "{name} is dead." },
}
for voice, lines in pairs(KNOWN_DEATH_VOICES) do
    if PERSONALITY_BANKS[voice] ~= nil then PERSONALITY_BANKS[voice].known_death = lines end
end

-- A confirmed, witnessed zombie death can end an encounter with one cue.
BANKS.combat_zombie_done = { "Stay dead.", "That one's down." }
local ZOMBIE_OUTCOME_VOICES = {
    frightened = { "Stay down. Please.", "It's down." },
    guarded = { "Stay dead.", "That one's down." },
    loner = { "Stay down.", "It's down." },
    sociable = { "It's down.", "Stay dead, you b*stard." },
    brave = { "Stay dead!", "Back to the dirt." },
}
for voice, lines in pairs(ZOMBIE_OUTCOME_VOICES) do
    if PERSONALITY_BANKS[voice] ~= nil then PERSONALITY_BANKS[voice].combat_zombie_done = lines end
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

-- Select without consuming a line. Call rememberLine only once the response has
-- actually been accepted, so a refused attempt cannot change the next words.
function Dialogue.chooseLine(survivorId, event, lines, ticks)
    if type(lines) ~= "table" or #lines == 0 then return nil, false end
    local state = states[tostring(survivorId or "survivor")]
    local recent = state ~= nil and state.recent or nil
    local used, last = {}, nil
    for _, item in ipairs(recent or {}) do
        if item.event == event then used[item.line] = true; last = item.line end
    end
    local start = stableIndex(survivorId, event, ticks, #lines)
    for offset = 0, #lines - 1 do
        local line = lines[((start + offset - 1) % #lines) + 1]
        if not used[line] then return line, false end
    end
    for offset = 0, #lines - 1 do
        local line = lines[((start + offset - 1) % #lines) + 1]
        if line ~= last then return line, true end
    end
    return lines[start], true
end

function Dialogue.rememberLine(survivorId, event, line, reset)
    if line == nil then return end
    local id = tostring(survivorId or "survivor")
    local state = states[id] or { nextGlobal = 0, events = {} }
    states[id] = state
    local recent = state.recent or {}
    state.recent = recent
    if reset then
        for index = #recent, 1, -1 do
            if recent[index].event == event then table.remove(recent, index) end
        end
    end
    recent[#recent + 1] = { event = event, line = line }
    if #recent > 32 then table.remove(recent, 1) end
end

function Dialogue.sayLines(character, survivorId, event, lines, ticks, cooldown, delivery)
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
    local line, reset = Dialogue.chooseLine(id, event, lines, now)
    if delivery ~= nil then
        if delivery(character, line) ~= true then return false, "unavailable" end
    elseif KnoxActivityFeed.speak(character, line) == false then
        return false, "unavailable"
    end
    Dialogue.rememberLine(id, event, line, reset)
    state.nextGlobal = now + GLOBAL_COOLDOWN
    state.events[event] = now + math.max(GLOBAL_COOLDOWN,
        tonumber(cooldown) or DEFAULT_COOLDOWN)
    local signals = rawget(_G, "KnoxOrderSignals")
    if signals ~= nil and signals.dialogue ~= nil then pcall(signals.dialogue, character, event) end
    return true, line
end

-- Recent spoken subjects are bounded voice state, not persisted knowledge.
function Dialogue.sayRecognition(character, survivorId, subjectId, ticks, delivery, event, name)
    event = event or "recognition_living"
    if event == "recognition_undead" then
        if type(subjectId) ~= "table" and type(subjectId) ~= "userdata" then return false, "unavailable" end
    elseif subjectId == nil or tostring(subjectId) == "" then return false, "unavailable" end
    if event ~= "recognition_living" and event ~= "player_first" and event ~= "player_known"
        and event ~= "npc_known" and event ~= "recognition_undead" and event ~= "known_death" and event ~= "known_corpse" then
        return false, "unavailable"
    end
    local id = tostring(survivorId or "survivor")
    local subject = event == "recognition_undead" and subjectId or event .. ":" .. tostring(subjectId)
    local state = states[id]
    for _, recent in ipairs(state ~= nil and state.recognitionSubjects or {}) do
        if event == "recognition_undead" then
            if type(recent) == "table" and recent.kind == "undead" and recent.object == subject then
                return false, "recent"
            end
        elseif recent == subject then return false, "recent" end
    end
    local lines = Dialogue.linesFor(survivorId, event)
    if event == "npc_known" or event == "known_death" or event == "known_corpse" then
        if type(name) ~= "string" or name:match("^%s*$") then return false, "unavailable" end
        local grounded = {}
        for _, template in ipairs(lines or {}) do
            grounded[#grounded + 1] = template:gsub("{name}", function() return name end)
        end
        lines = grounded
    end
    local spoke, line = Dialogue.sayLines(character, survivorId, event,
        lines, ticks, GLOBAL_COOLDOWN, delivery)
    if spoke then
        state = states[id]
        local recent = state.recognitionSubjects or {}
        state.recognitionSubjects = recent
        recent[#recent + 1] = event == "recognition_undead" and {kind="undead", object=subject} or subject
        if #recent > 32 then table.remove(recent, 1) end
    end
    return spoke, line
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
    local name = nil
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getSurvivorIdentity ~= nil and targetId ~= nil then
        local identity = persistence.getSurvivorIdentity(targetId)
        name = type(identity) == "table" and identity.forename or nil
    end
    local grounded = {}
    for _, line in ipairs(lines) do
        grounded[#grounded + 1] = tostring(line):gsub("{name}", function()
            return name ~= nil and tostring(name) or "them"
        end)
    end
    return Dialogue.sayLines(character, witnessId, event, grounded, ticks, cooldown)
end

-- The diagnosis speaks under the same voice rules as everything else: the
-- bank for what the body said, the speaker's own manner where it has words,
-- and the patient's name filled in. A missing name is "them", never invented.
function Dialogue.sayDiagnosis(character, doctorId, kind, name, ticks, cooldown)
    if character == nil or type(kind) ~= "string" then return false, "unavailable" end
    local event = "diagnosis_" .. kind
    local lines = Dialogue.linesFor(doctorId, event)
    if type(lines) ~= "table" or #lines == 0 then return false, "no_lines" end
    local grounded = {}
    for _, line in ipairs(lines) do
        local text = tostring(line):gsub("{name}", function()
            return name ~= nil and tostring(name) or "them"
        end)
        grounded[#grounded + 1] = text
    end
    return Dialogue.sayLines(character, doctorId, event, grounded, ticks, cooldown)
end

function Dialogue.lines(event)

    return BANKS[event]
end

function Dialogue.resetRuntime()
    states = {}
end

return Dialogue
