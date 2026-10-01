require "ISUI/Maps/ISWorldMap"
require "KS_CompanionService"
require "KS_CompanionVehicles"
require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SurvivorViewModel"

local Orders={}
KnoxMapOrders=Orders
local function contextOrdersEnabled()
    if KnoxSettings == nil or KnoxSettings.showLegacyContextCommands == nil then return false end
    local ok, enabled = pcall(KnoxSettings.showLegacyContextCommands)
    return ok and enabled == true
end
local failureLines={
    destination_too_far="Choose a closer destination. I can plan nearby routes for now.",
    destination_too_close="We're already close to that point.",
    destination_unavailable="Choose loaded, open ground for our destination.",
    drive_route_unavailable="I can't find a clear route there.",
    drive_planning_budget="I can't work out a route through those obstacles. Try an intermediate point.",
    vehicle_geometry_unavailable="I can't safely plan turns for this vehicle yet.",
    vehicle_heading_unavailable="The vehicle needs to be upright before I can drive.",
    vehicle_moving="Stop the vehicle before I take the driver's seat.",
    vehicle_engine_off="Start the engine first, then move to a passenger seat.",
    driver_seat_occupied="Someone is already driving.",
    player_must_vacate_driver_seat="Move to a passenger seat so I can drive.",
    towing_not_supported="I can't drive safely with a trailer yet.",
}

local function displayName(id)
    local identity=KnoxPersistence.getSurvivorIdentity(id) or {}
    local name=(tostring(identity.forename or "").." "..tostring(identity.surname or "")):match("^%s*(.-)%s*$")
    return name~="" and name or "Survivor"
end

local function finiteNumber(value)
    local number=tonumber(value)
    if number==nil or number~=number or number==math.huge or number==-math.huge then return nil end
    return number
end

local function recordLocation(id)
    local bridge=rawget(_G,"KnoxJavaBridge")
    local record=KnoxPersistence.getRecord~=nil and KnoxPersistence.getRecord(id) or nil
    if bridge==nil or record==nil then return nil end
    local ok,x,y,z=pcall(function()
        return bridge:getTestNpcRecordX(record),bridge:getTestNpcRecordY(record),bridge:getTestNpcRecordZ(record)
    end)
    x,y,z=finiteNumber(x),finiteNumber(y),finiteNumber(z)
    if not ok or x==nil or y==nil or z==nil then return nil end
    return x,y,z
end

-- Read-only locator data for player-owned survivors.  It deliberately never
-- materializes, moves or persists a survivor/map symbol.
function Orders.ownedLocations(playerNum, lightweight)
    local player=getSpecificPlayer(playerNum)
    local playerId=player~=nil and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId==nil or KnoxPersistence.getSurvivorIds==nil then return {},{unlocatedCount=0,invalidCount=0} end
    local locations,seenIds={},{}
    local summary={unlocatedCount=0,invalidCount=0}
    for _,id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        if id~=nil and not seenIds[id] then
        seenIds[id]=true
        local affiliation=KnoxPersistence.getSurvivorAffiliation(id)
        if affiliation~=nil and affiliation.kind=="player" and affiliation.ownerId==playerId
            and KnoxPersistence.isSurvivorAlive(id) then
            local character=KnoxSurvivorRuntime~=nil and KnoxSurvivorRuntime.getCharacter(id) or nil
            local x,y,z,source=nil,nil,nil,nil
            local invalidCoordinates=false
            if character~=nil then
                local ok,cx,cy,cz=pcall(function() return character:getX(),character:getY(),character:getZ() end)
                cx,cy,cz=finiteNumber(cx),finiteNumber(cy),finiteNumber(cz)
                if ok and cx~=nil and cy~=nil and cz~=nil then
                    x,y,z,source=cx,cy,cz,"loaded"
                elseif ok then
                    invalidCoordinates=true
                end
            end
            local state=KnoxPersistence.getUnloadedSurvivalState~=nil
                and KnoxPersistence.getUnloadedSurvivalState(id) or nil
            if source==nil and state~=nil then
                local sx,sy,sz=finiteNumber(state.virtualX),finiteNumber(state.virtualY),finiteNumber(state.virtualZ)
                if sx~=nil and sy~=nil and sz~=nil then
                    x,y,z,source=sx,sy,sz,"logical"
                elseif state.virtualX~=nil or state.virtualY~=nil or state.virtualZ~=nil then
                    invalidCoordinates=true
                end
            end
            if source==nil then
                x,y,z=recordLocation(id)
                if x~=nil then source="last_known"
                elseif KnoxPersistence.getRecord~=nil and KnoxPersistence.getRecord(id)~=nil then invalidCoordinates=true end
            end
            if source~=nil then
                local snapshot=not lightweight and KnoxSurvivorViewModel~=nil and KnoxSurvivorViewModel.getSurvivor~=nil
                    and KnoxSurvivorViewModel.getSurvivor(id,playerNum) or nil
                locations[#locations+1]={id=id,name=displayName(id),x=x,y=y,z=z,source=source,
                    confidence=source,activity=snapshot~=nil and snapshot.activity or (state~=nil and state.activity or "Unknown"),
                    status=snapshot~=nil and snapshot.locationLabel or source}
            else
                summary.unlocatedCount=summary.unlocatedCount+1
                if invalidCoordinates then summary.invalidCount=summary.invalidCount+1 end
            end
        elseif KnoxPersistence.isSurvivorAlive(id)==false then
            local evidence=KnoxPersistence.getSurvivorDeathEvidence~=nil
                and KnoxPersistence.getSurvivorDeathEvidence(id) or nil
            if type(evidence)=="table" and evidence.ownerKind=="player"
                and evidence.ownerId==playerId and tonumber(evidence.x)~=nil
                and tonumber(evidence.y)~=nil and tonumber(evidence.z)~=nil then
                locations[#locations+1]={id=id,name=displayName(id),x=tonumber(evidence.x),y=tonumber(evidence.y),z=tonumber(evidence.z),
                    source="deceased",confidence="deceased",activity="Deceased",corpseState=evidence.corpseState,
                    status="Deceased - "..tostring(evidence.locationSource or "last-known").." location recorded"}
            end
        end
        end
    end
    table.sort(locations,function(a,b) return a.id<b.id end)
    return locations,summary
end

local OWNED_MARKER_GROUP_DISTANCE=20
local LOCATION_CONFIDENCE_RANK={last_known=1,logical=2,loaded=3}
local function groupOwnedLocations(locations)
    local groups={}
    for _,location in ipairs(locations or {}) do
        local group=nil
        if location.source~="deceased" then
            for _,candidate in ipairs(groups) do
                local anchor=candidate.members[1]
                local dx,dy=location.x-anchor.x,location.y-anchor.y
                if candidate.kind=="owned_group" and location.z==anchor.z
                    and dx*dx+dy*dy<=OWNED_MARKER_GROUP_DISTANCE*OWNED_MARKER_GROUP_DISTANCE then
                    group=candidate
                    break
                end
            end
        end
        if group==nil then
            group={kind=location.source=="deceased" and "deceased" or "owned_group",
                x=location.x,y=location.y,z=location.z,members={},memberIds={},count=0,
                loadedCount=0,logicalCount=0,lastKnownCount=0}
            groups[#groups+1]=group
        end
        group.members[#group.members+1]=location
        group.memberIds[#group.memberIds+1]=location.id
        group.count=group.count+1
        local rank=LOCATION_CONFIDENCE_RANK[location.source] or 0
        if rank>(group.positionConfidence or 0) then
            group.x,group.y,group.z=location.x,location.y,location.z
            group.positionConfidence=rank
        end
        if location.source=="loaded" then group.loadedCount=group.loadedCount+1
        elseif location.source=="logical" then group.logicalCount=group.logicalCount+1
        elseif location.source=="last_known" then group.lastKnownCount=group.lastKnownCount+1 end
    end
    return groups
end

function Orders.ownedLocationGroups(playerNum,lightweight)
    local locations,summary=Orders.ownedLocations(playerNum,lightweight)
    return groupOwnedLocations(locations),summary
end

local renderedLocations=setmetatable({}, {__mode="k"})
local function drawOwnedLocations(map)
    local pn=tonumber(map.playerNum)
    if pn==nil or map.mapAPI==nil then return end
    -- The overlay needs positions/names, not inventory/health UI snapshots.
    -- Refresh at most four times a second; project coordinates every frame so
    -- zooming and panning remain smooth. A separate cache isolates split screen.
    local now=getTimestampMs~=nil and getTimestampMs() or nil
    local cached=renderedLocations[map]
    if now==nil or cached==nil or cached.playerNum~=pn or now<cached.at or now-cached.at>=250 then
        local groups,summary=Orders.ownedLocationGroups(pn,true)
        cached={playerNum=pn,at=now,groups=groups,summary=summary}
        renderedLocations[map]=cached
    end
    for _,group in ipairs(cached.groups) do
        local location=group.members[1]
        local ok,x,y=pcall(function() return map.mapAPI:worldToUIX(group.x,group.y),map.mapAPI:worldToUIY(group.x,group.y) end)
        if ok and tonumber(x)~=nil and tonumber(y)~=nil then
            local deceased=group.kind=="deceased"
            local stale=group.lastKnownCount>0
            local persisted=group.logicalCount>0
            local r,g,b=deceased and 0.85 or (stale and 0.70 or (persisted and 0.95 or 0.25)),
                deceased and 0.25 or (stale and 0.75 or (persisted and 0.75 or 0.95)),
                deceased and 0.25 or (stale and 0.25 or (persisted and 0.25 or 0.35))
            local label
            if deceased then
                label="X "..location.name
            elseif group.count==1 then
                local prefix=location.source=="logical" and "~ " or (location.source=="last_known" and "? " or "")
                label=prefix..location.name
            else
                local names={}
                for _,member in ipairs(group.members) do names[#names+1]=member.name end
                label=tostring(group.count).." survivors ("..tostring(group.loadedCount).." loaded, "
                    ..tostring(group.logicalCount).." persisted, "..tostring(group.lastKnownCount).." last-known): "
                    ..table.concat(names,", ")
            end
            local size=group.count>1 and 7 or 5
            map:drawRect(math.floor(x)-math.floor(size/2),math.floor(y)-math.floor(size/2),size,size,0.95,r,g,b)
            map:drawText(label,math.floor(x)+4,math.floor(y)-8,r,g,b,0.95,UIFont.Small)
        end
    end
    if cached.summary~=nil and cached.summary.unlocatedCount>0 then
        local count=cached.summary.unlocatedCount
        local noun=count==1 and "survivor has" or "survivors have"
        local invalid=cached.summary.invalidCount or 0
        local detail=invalid>0 and (" ("..tostring(invalid).." invalid coordinate"..(invalid==1 and "" or "s")..")") or ""
        map:drawText("? "..tostring(count).." owned "..noun.." no usable map location"..detail,
            8,8,0.95,0.75,0.25,0.95,UIFont.Small)
    end
end
function Orders.drive(player,id,x,y)
    local success,reason=KnoxCompanionService.drivePlayerVehicleTo(player,id,x,y)
    if not success and KnoxActivityFeed~=nil then
        KnoxActivityFeed.speak(player,failureLines[reason] or "That driving order isn't available right now.")
    end
end
function Orders.fill(context,player,x,y)
    if not contextOrdersEnabled() then return false end
    if player==nil or player:getVehicle()==nil or not KnoxSettings.enableExperimentalNpcDriving() then return false end
    local ids=KnoxCompanionService.getCompanionIds(player)
    local candidates={}
    for _,id in ipairs(ids) do
        local character=KnoxSurvivorRuntime.getCharacter(id)
        if character~=nil and not character:isDead() then candidates[#candidates+1]=id end
    end
    if #candidates==0 then return false end
    local option=context:addOption("Drive Here",nil,nil)
    local menu=ISContextMenu:getNew(context);context:addSubMenu(option,menu)
    for _,id in ipairs(candidates) do
        local identity=KnoxPersistence.getSurvivorIdentity(id) or {}
        local name=(tostring(identity.forename or "").." "..tostring(identity.surname or "")):match("^%s*(.-)%s*$")
        local item=menu:addOption(name~="" and name or "Survivor",player,Orders.drive,id,x,y)
        if player:getVehicle():getDriver()==player then item.notAvailable=true end
        local character=KnoxSurvivorRuntime.getCharacter(id)
        if character:getVehicle()==player:getVehicle() and KnoxCompanionVehicles.driverStatus(character)~=nil then
            context:addOption("Stop Driving",player,KnoxCompanionService.stopPlayerVehicle,id)
        end
    end
    return true
end

if ISWorldMap~=nil and not ISWorldMap.knoxDrivingOrdersInstalled then
    ISWorldMap.knoxDrivingOrdersInstalled=true
    local originalPrerender=ISWorldMap.prerender
    function ISWorldMap:prerender()
        originalPrerender(self)
        drawOwnedLocations(self)
    end
    local original=ISWorldMap.onRightMouseUp
    function ISWorldMap:onRightMouseUp(x,y)
        local result=original(self,x,y)
        if result==true then return result end -- A map-symbol tool consumed it.
        local pn = tonumber(self.playerNum)
        if pn == nil then return result end
        local player=getSpecificPlayer(pn)
        if player==nil or player:getVehicle()==nil or not KnoxSettings.enableExperimentalNpcDriving()
            or not contextOrdersEnabled()
            or #KnoxCompanionService.getCompanionIds(player)==0 then return result end
        local context
        if getDebug() or (isClient() and getAccessLevel()=="admin") then
            context=getPlayerContextMenu(pn) -- Preserve native debug entries.
        else context=ISContextMenu.get(pn,x+self:getAbsoluteX(),y+self:getAbsoluteY()) end
        Orders.fill(context,player,math.floor(self.mapAPI:uiToWorldX(x,y))+0.5,
            math.floor(self.mapAPI:uiToWorldY(x,y))+0.5)
        return true
    end
end
return Orders
