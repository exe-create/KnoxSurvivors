require "KS_Settings"
local Signals = rawget(_G, "KnoxOrderSignals") or {}
_G.KnoxOrderSignals = Signals
local cooldowns = setmetatable({}, {__mode="k"})
local EMOTES = {follow="followme",hold="stop",relax="signalok",guard="stop",
    patrol="moveout",patrol_area="moveout",go_to="moveout",return_to_base="comehere",
    scavenge="moveout",investigate_building="moveout",base_supply="comehere",
    loot_area="moveout",loot_building="moveout",loot_corpses="moveout",
    find_food="moveout",find_water="moveout",find_medical="moveout",
    find_weapon="moveout",find_tools="moveout",find_wood="moveout",find_materials="moveout",
    find_clothing="moveout",find_ammo="moveout",clean_inventory="signalok",
    farming="signalok",woodwork="signalok",hauling="signalok",
    repair="signalok",haul_corpse="signalok",sort_depot="signalok",
    auto="signalok",rest="signalok",job="signalok",
    allow_climbing="signalok",disallow_climbing="signalok",
    allow_doors="signalok",disallow_doors="signalok",
    enable_autoloot="moveout",disable_autoloot="signalok",
    formation="moveout",combat_stance="stop",weapon_preference="signalok",
    enter_vehicle="comehere",exit_vehicle="signalok",dismiss="signalok",
    drive_ahead="moveout",drive_nearest_vehicle="moveout",
    enable_auto_equipment="signalok",disable_auto_equipment="signalok",
    signalok="signalok",
    talk="wavehi",joke="clap",compliment="thumbsup",funny_face="shrug",
    insult="insult",slap="thumbsdown",
    mock="insult",blame="thumbsdown",threaten="stop"}
-- A vanilla emote has no duration: playEmote keeps the pose until something
-- else replaces it, so telling a joke left the survivor clapping forever. Every
-- emote started here gets an end time, and the pose is cleared on the tick that
-- reaches it. Another emote, a death or a vehicle simply replaces the record.
local EMOTE_HOLD_MS = 3500
local pendingStops = {}
-- Build 42's Kahlua has no global next(), so "is the table empty" was calling
-- nil once per frame and threw 1934 exceptions in one session. A count costs
-- less than a scan and cannot fail.
local pendingCount = 0
local stopTickerInstalled = false

local function installStopTicker()
    if stopTickerInstalled or Events == nil or Events.OnTick == nil then return end
    stopTickerInstalled = true
    Events.OnTick.Add(function()
        if pendingCount <= 0 then return end
        local now = getTimestampMs ~= nil and tonumber(getTimestampMs()) or nil
        for actor, record in pairs(pendingStops) do
            if record == nil or now == nil or now >= (record.untilMs or 0) then
                pendingStops[actor] = nil
                pendingCount = pendingCount - 1
                if pendingCount < 0 then pendingCount = 0 end
                local cleared = pcall(function()
                    if actor.stopEmote ~= nil then actor:stopEmote() end
                end)
                if not cleared then
                    pcall(function() actor:playEmote(nil) end)
                end
            end
        end
    end)
end

local function call(actor, method)
    local ok,value=pcall(function() return actor[method](actor) end)
    return ok and value or nil
end
function Signals.play(actor, emote)
    if actor==nil or actor.playEmote==nil then return false end
    local settings=rawget(_G,"KnoxSettings")
    if settings~=nil and settings.orderGesturesEnabled~=nil and not settings.orderGesturesEnabled() then return false end
    if call(actor,"isDead")==true or call(actor,"getVehicle")~=nil or call(actor,"isAiming")==true then return false end
    local actions=call(actor,"getCharacterActions")
    if actions==nil or not actions:isEmpty() then return false end
    local state=string.lower(tostring(call(actor,"getCurrentStateName") or "")
        .." "..tostring(call(actor,"getCurrentActionContextStateName") or ""))
    for _,busy in ipairs({"climb","attack","swipe","hitreact","grappl","fall"}) do
        if state:find(busy,1,true) then return false end
    end
    local now=getTimestampMs~=nil and tonumber(getTimestampMs()) or nil
    if now==nil then now=getGameTime~=nil and getGameTime():getWorldAgeHours()*3600000 or 0 end
    local previous=cooldowns[actor]
    if previous~=nil and now>=previous and now-previous<3000 then return false end
    local success=pcall(function() actor:playEmote(emote) end)
    if success then
        cooldowns[actor]=now
        installStopTicker()
        if pendingStops[actor] == nil then pendingCount = pendingCount + 1 end
        pendingStops[actor] = { untilMs = (now or 0) + EMOTE_HOLD_MS }
    end
    return success
end
function Signals.send(player, kind)
    local emote=EMOTES[kind]
    if emote==nil then return false end
    return Signals.play(player,emote)
end
function Signals.order(player, kind, survivor)
    local played=Signals.send(player,kind)
    if played then Signals.acknowledge(player, survivor) end
    return played
end

function Signals.acknowledge(leader, member)
    if member == nil or member == leader then return false end
    local ok, visible = pcall(function()
        local first, second = leader:getCurrentSquare(), member:getCurrentSquare()
        return first ~= nil and second ~= nil and first:getZ() == second:getZ()
            and (first:getX() - second:getX())^2 + (first:getY() - second:getY())^2 <= 49
            and member:CanSee(leader) == true
    end)
    return ok and visible and Signals.play(member, "yes") or false
end

-- Only accepted speech calls this. The voice owns its cooldown; play retains
-- native action/aiming guards and the existing bounded emote lifetime.
function Signals.dialogue(actor, event)
    local emotes = { base_greet = "wavehi", base_social = "yes", accept_cigarette = "yes",
        cant_lift = "thumbsdown", cant_lift_bitten = "thumbsdown", order_refused_wary = "thumbsdown",
        player_attack_warning = "stop", base_musing_frightened = "stop" }
    local emote = emotes[event]
    return emote ~= nil and Signals.play(actor, emote) or false
end

-- Autonomous leaders use the same readable gestures as player-issued orders.
-- Only nearby loaded followers acknowledge; the group objective remains the
-- durable authority and this helper never changes movement or task state.
function Signals.group(leader, members, kind)
    local emote = EMOTES[kind]
    if emote == nil or not Signals.play(leader, emote) then return false end
    for _, member in ipairs(members or {}) do
        Signals.acknowledge(leader, member)
    end
    return true
end
return Signals
