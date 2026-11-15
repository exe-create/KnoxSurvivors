-- Night sheltering for unbased survivors. At night, independents head for the
-- nearest indoor shelter and sleep till dawn instead of roaming in the dark.
-- No state is invented: movement uses the normal bridge move, and sleep uses
-- the standard fatigue/native sleep path. Curtains are untouched (no verified
-- Build 42 Lua API for them); a roof and sleep carry the fantasy.
local NightShelter = rawget(_G, "KnoxNightShelter") or {}
_G.KnoxNightShelter = NightShelter

NightShelter.NIGHT_START_HOUR = 20
NightShelter.NIGHT_END_HOUR = 7
NightShelter.SHELTER_SCAN_RADIUS = 24

function NightShelter.currentHour()
    if getTimeOfDay == nil then
        return 12
    end
    local ok, hour = pcall(getTimeOfDay)
    if not ok then
        return 12
    end
    return tonumber(hour) or 12
end

function NightShelter.isNight(hour)
    local value = tonumber(hour) or NightShelter.currentHour()
    return value < NightShelter.NIGHT_END_HOUR or value >= NightShelter.NIGHT_START_HOUR
end

-- Indoors counts as sheltered: a room square under a roof.
function NightShelter.isSheltered(character)
    if character == nil or character.getCurrentSquare == nil then
        return false
    end
    local ok, square = pcall(function() return character:getCurrentSquare() end)
    if not ok or square == nil or square.getRoom == nil then
        return false
    end
    local roomOk, room = pcall(function() return square:getRoom() end)
    return roomOk and room ~= nil
end

local function shelterScore(square, originX, originY)
    local dx = square:getX() - originX
    local dy = square:getY() - originY
    local score = -(dx * dx + dy * dy)
    local building = square.getBuilding ~= nil and square:getBuilding() or nil
    if building ~= nil then
        local okResidential, residential = pcall(function() return building:isResidential() end)
        if okResidential and residential == true then
            score = score + 500
        else
            score = score + 100
        end
    end
    return score
end

-- Nearest indoor room square: houses first, any roof second, closeness always.
function NightShelter.findShelter(character, radius, eligible)
    if character == nil or getCell == nil then
        return nil
    end
    local ok, origin = pcall(function() return character:getCurrentSquare() end)
    if not ok or origin == nil then
        return nil
    end
    local scan = math.max(2, tonumber(radius) or NightShelter.SHELTER_SCAN_RADIUS)
    local best, bestScore = nil, nil
    for dx = -scan, scan, 2 do
        for dy = -scan, scan, 2 do
            local square = getCell():getGridSquare(
                origin:getX() + dx, origin:getY() + dy, origin:getZ()
            )
            if square ~= nil and square.canStand ~= nil and square.getRoom ~= nil then
                local usable, room = pcall(function()
                    if not square:canStand() then return nil end
                    return square:getRoom()
                end)
                local allowed = usable and room ~= nil
                if allowed and eligible ~= nil then
                    local filterOk, accepted = pcall(eligible, square)
                    allowed = filterOk and accepted == true
                end
                if allowed then
                    local score = shelterScore(square, origin:getX(), origin:getY())
                    if bestScore == nil or score > bestScore then
                        best, bestScore = square, score
                    end
                end
            end
        end
    end
    return best
end

-- A temporary travel group can sleep in an ordinary building, but it cannot
-- silently occupy an established player/faction territory. This is only a
-- destination filter: it does not claim a base, camp, storage or safehouse.
function NightShelter.isUnclaimedTemporaryShelter(square)
    if square == nil then return false end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getBaseAtSquare ~= nil then
        local ok, base = pcall(
            persistence.getBaseAtSquare,
            square:getX(), square:getY(), square:getZ()
        )
        if ok and base ~= nil then return false end
    end
    return true
end

local function nowHours()
    return getGameTime():getWorldAgeHours()
end

function NightShelter.canShelter(survivorId, square)
    if square==nil then return false end
    local base=KnoxPersistence.getBaseAtSquare(square:getX(),square:getY(),square:getZ())
    if base==nil then return true end
    local duty=KnoxPersistence.getSurvivorDuty(survivorId)
    if duty~=nil and duty.mode=="base" and duty.baseId==base.id then return true end
    local guest=base.overnightGuests~=nil and base.overnightGuests[survivorId] or nil
    return guest~=nil and guest.status=="accepted" and (tonumber(guest.untilHours) or 0)>nowHours()
end

function NightShelter.pendingVisit(player, survivorId)
    local playerId=KnoxCompanionService.getPlayerId(player)
    for _,base in pairs(KnoxPersistence.getBases()) do
        local guest=base.overnightGuests~=nil and base.overnightGuests[survivorId] or nil
        if base.ownerKind=="player" and base.ownerId==playerId and guest~=nil
            and guest.status=="pending" and (tonumber(guest.untilHours) or 0)>nowHours() then return base end
    end
    return nil
end

function NightShelter.respond(player, survivorId, accepted)
    local base=NightShelter.pendingVisit(player,survivorId)
    local character=KnoxSurvivorRuntime.getCharacter(survivorId)
    if base==nil or character==nil or player:isDead() or character:isDead()
        or player:getZ()~=character:getZ()
        or (player:getX()-character:getX())^2+(player:getY()-character:getY())^2>16
        or not player:CanSee(character) then return false,"visitor_unavailable" end
    local hour=NightShelter.currentHour()
    local remaining=(NightShelter.NIGHT_END_HOUR-hour)%24
    local ok,message=KnoxPersistence.answerOvernightStay(base.id,
        KnoxCompanionService.getPlayerId(player),survivorId,accepted,nowHours(),nowHours()+remaining)
    if not ok then return false,"overnight_request_expired" end
    if ok then
        local hostile=KnoxPersistence.isSurvivorHostileToPlayer(survivorId,KnoxCompanionService.getPlayerId(player))
        local line=accepted and KnoxOrderCatalog.text("IGUI_Knox_GuestThanks","Thank you. I'll leave in the morning.")
            or hostile and KnoxOrderCatalog.text("IGUI_Knox_GuestAngry","Get out of my way.")
            or KnoxOrderCatalog.text("IGUI_Knox_GuestLeaves","All right. I'll find somewhere else.")
        KnoxActivityFeed.speak(character,line)
        message=accepted and KnoxOrderCatalog.text("IGUI_Knox_GuestAccepted","The visitor can stay until morning.")
            or KnoxOrderCatalog.text("IGUI_Knox_GuestRefused","The overnight request was refused.")
    end
    return ok,message
end

function NightShelter.requestVisit(controller, ticks)
    if ticks<(controller.nextOvernightAskCheck or 0) then return end
    controller.nextOvernightAskCheck=ticks+600
    if controller.groupLeaderId~=nil or #(controller.groupMembers or {})>1 then return end
    local character=controller.character
    for playerNum=0,(getNumActivePlayers()-1) do
        local player=getSpecificPlayer(playerNum)
        if player~=nil and not player:isDead() and player:getZ()==character:getZ()
            and (player:getX()-character:getX())^2+(player:getY()-character:getY())^2<=64
            and player:CanSee(character) then
            local playerId=KnoxCompanionService.getPlayerId(player)
            local hostSquare=player:getCurrentSquare()
            local base=hostSquare~=nil and KnoxPersistence.getBaseAtSquare(
                hostSquare:getX(),hostSquare:getY(),hostSquare:getZ(),"player") or nil
            if base~=nil and base.ownerId==playerId
                and not KnoxPersistence.isSurvivorHostileToPlayer(controller.id,playerId) then
                local request=KnoxPersistence.requestOvernightStay(base.id,controller.id,nowHours())
                if request~=nil then
                    KnoxActivityFeed.speak(character,KnoxOrderCatalog.text("IGUI_Knox_GuestRequest","Could I spend the night here?"))
                end
                return
            end
        end
    end
end

return NightShelter
