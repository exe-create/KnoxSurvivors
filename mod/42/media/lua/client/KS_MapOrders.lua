require "ISUI/Maps/ISWorldMap"
require "KS_CompanionService"
require "KS_CompanionPatrol"
require "KS_CompanionVehicles"
require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SurvivorViewModel"
require "KS_MissionTargets"

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
    player_in_vehicle="You're already in a car.",
    survivor_unavailable="They can't come right now.",
    vehicle_unavailable="There's no car they can bring.",
    vehicle_low_fuel="That car's tank is nearly dry.",
    vehicle_not_driveable="That car isn't going anywhere.",
    vehicle_doors_locked="That car's locked.",
    no_keys="Nobody has the keys to that car.",
    npc_driving_disabled="Experimental NPC driving is off. Enable it in Sandbox Options, Vehicles page.",
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

-- MAP CONDITION (pure)
-- One condition word on a single-person marker. A group marker keeps its count
-- and names; a word per member would not fit or read. Death already has its own
-- marker and cause, so only a living critical condition is returned.
function Orders.markerCondition(snapshot)
    if type(snapshot) ~= "table" or snapshot.alive == false then return nil end
    local model = rawget(_G, "KnoxSurvivorViewModel")
    if model == nil or model.rosterCondition == nil then return nil end
    return model.rosterCondition(snapshot)
end
-- END MAP CONDITION

-- PATROL OVERLAY (pure)
-- A route on the map is the existing patrol zone geometry, read through the same
-- waypoint owner the walker uses. This adds no route record and no guessed path;
-- a base with no patrol zone has nothing to draw.
function Orders.patrolRoutes(base)
    local patrol = rawget(_G, "KnoxCompanionPatrol")
    if type(base) ~= "table" or patrol == nil or patrol.waypoints == nil then return {} end
    local routes = {}
    for _, zone in pairs(base.zones or {}) do
        local kind = type(zone) == "table" and zone.type or nil
        if kind == "patrol" or kind == "patrol_area" then
            local points = patrol.waypoints(zone)
            if type(points) == "table" and #points > 0 then
                routes[#routes + 1] = { name = zone.name or "Patrol route", points = points }
            end
        end
    end
    table.sort(routes, function(a, b) return a.name < b.name end)
    return routes
end

-- The loop's waypoint order is the walked order, not a screen-space guess. The
-- arrow is returned in UI pixels so the map can draw a direction at each edge
-- midpoint without owning a second route model.
function Orders.routeArrow(x1, y1, x2, y2, size)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0 then return nil end
    local ux, uy = dx / length, dy / length
    local px, py = -uy, ux
    local tipX, tipY = (x1 + x2) / 2, (y1 + y2) / 2
    local back = tonumber(size) or 6
    local wing = back * 0.55
    return tipX, tipY,
        tipX - ux * back + px * wing, tipY - uy * back + py * wing,
        tipX - ux * back - px * wing, tipY - uy * back - py * wing
end

-- A live next stop is the controller's own securityRoute.square, not a persisted
-- plan or a second route store. Only a loaded base resident with an active patrol
-- route contributes; an unloaded or idle resident contributes nothing.
function Orders.livePatrolStops(base, runtime, persistence)
    if type(base) ~= "table" or base.id == nil
        or runtime == nil or runtime.getController == nil
        or persistence == nil or persistence.getBaseResidentIds == nil then return {} end
    local stops = {}
    for _, id in ipairs(persistence.getBaseResidentIds(base.id) or {}) do
        local controller = runtime.getController(id)
        local route = controller ~= nil and controller.securityRoute or nil
        if type(route) == "table" and route.patrol == true and route.square ~= nil then
            local square = route.square
            local x = square.getX ~= nil and square:getX() or tonumber(square.x)
            local y = square.getY ~= nil and square:getY() or tonumber(square.y)
            local z = square.getZ ~= nil and square:getZ() or tonumber(square.z)
            if x ~= nil and y ~= nil then
                local identity = persistence.getSurvivorIdentity ~= nil
                    and persistence.getSurvivorIdentity(id) or nil
                local name = identity ~= nil
                    and (tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")):match("^%s*(.-)%s*$")
                    or ""
                if name == "" then name = "Survivor" end
                stops[#stops + 1] = {id=id,name=name,x=x+0.5,y=y+0.5,z=tonumber(z) or 0,
                    step=tonumber(route.step) or 0,count=tonumber(route.count) or 0}
            end
        end
    end
    table.sort(stops, function(a,b) return a.name < b.name end)
    return stops
end

-- The map legend is a reading of the same two overlays, not a second state
-- source. It appears only when there is something to explain.
function Orders.patrolLegendRows(routes, stops)
    local rows = {}
    if type(routes) == "table" and #routes > 0 then
        rows[#rows + 1] = { kind = "route", label = "Patrol route" }
    end
    if type(stops) == "table" and #stops > 0 then
        rows[#rows + 1] = { kind = "stop", label = "Next stop" }
    end
    return rows
end
-- END PATROL OVERLAY

-- Map and journal share the same observer projection. A loaded native body is
-- not proof that this player can see it; logical travel is never a GPS signal.
-- Keep lightweight in the public signature for callers, without bypassing knowledge.
function Orders.ownedLocations(playerNum, lightweight)
    local player = getSpecificPlayer(playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local summary = {unlocatedCount=0, invalidCount=0}
    local model = rawget(_G, "KnoxSurvivorViewModel")
    if playerId == nil or model == nil or model.getSurvivor == nil then return {}, summary end
    local ids, included = {}, {}
    for _, list in ipairs({
        KnoxPersistence.getSurvivorIds ~= nil and KnoxPersistence.getSurvivorIds() or {},
        KnoxPersistence.getKnownSurvivorIds ~= nil and KnoxPersistence.getKnownSurvivorIds(playerId) or {},
    }) do
        for _, id in ipairs(list) do
            if not included[id] then included[id]=true; ids[#ids+1]=id end
        end
    end
    local locations = {}
    for _, id in ipairs(ids) do
        local affiliation = KnoxPersistence.getSurvivorAffiliation(id)
        local known = KnoxPersistence.getObserverKnowledge ~= nil
            and KnoxPersistence.getObserverKnowledge(playerId,id) or nil
        if (affiliation ~= nil and affiliation.kind == "player" and affiliation.ownerId == playerId)
            or known ~= nil then
            local view = model.getSurvivor(id,playerNum)
            local owner = view ~= nil and view.affiliation or nil
            local duty = view ~= nil and view.duty or nil
            local evidence = view ~= nil and view.alive == false and view.deathEvidence or nil
            -- Death retires live affiliation. Only after the observer already
            -- knows the death may the existing receipt identify prior ownership;
            -- its hidden coordinates/state never supply marker information.
            local priorOwner = evidence ~= nil and KnoxPersistence.getSurvivorDeathEvidence ~= nil
                and KnoxPersistence.getSurvivorDeathEvidence(id) or nil
            local owned = (owner ~= nil and owner.kind == "player" and owner.ownerId == playerId)
                or (duty ~= nil and duty.ownerId == playerId)
                or (evidence ~= nil and evidence.ownerKind == "player" and evidence.ownerId == playerId)
                or (priorOwner ~= nil and priorOwner.ownerKind == "player" and priorOwner.ownerId == playerId)
            if owned then
                local point = view.position or {}
                local current = view.knowledge ~= nil and view.knowledge.current == true
                local simulated = false
                -- The player's own people are tracked by the same offscreen
                -- ledger the world simulation advances. Reading that position
                -- (never a remote native body's) keeps the map and the
                -- simulation from disagreeing while the member is out of the
                -- loaded band. Strangers stay on last-seen evidence only.
                if not current and view.alive ~= false and duty ~= nil
                    and duty.ownerId == playerId
                    and KnoxPersistence.getUnloadedSurvivalState ~= nil then
                    local stored = KnoxPersistence.getUnloadedSurvivalState(id)
                    if stored ~= nil and finiteNumber(stored.virtualX) ~= nil
                        and finiteNumber(stored.virtualY) ~= nil then
                        point = {x=stored.virtualX, y=stored.virtualY, z=stored.virtualZ}
                        simulated = true
                    end
                end
                local x,y,z = finiteNumber(point.x), finiteNumber(point.y), finiteNumber(point.z)
                if x ~= nil and y ~= nil and z ~= nil then
                    local source = view.alive == false and "deceased"
                        or (current and "loaded" or (simulated and "simulated" or "last_known"))
                    locations[#locations+1] = {id=id,name=view.displayName or displayName(id),x=x,y=y,z=z,
                        source=source,confidence=source,activity=view.activity or "Unknown",
                        condition=Orders.markerCondition(view),
                        companion=duty ~= nil and duty.mode == "companion",
                        status=simulated and "Simulated position" or (view.locationLabel or "Location unknown"),
                        deathCauseLabel=view ~= nil and view.deathCauseLabel or nil,
                        corpseState=evidence ~= nil and evidence.corpseState or nil}
                else
                    summary.unlocatedCount=summary.unlocatedCount+1
                    if view.position ~= nil then summary.invalidCount=summary.invalidCount+1 end
                end
            end
        end
    end
    table.sort(locations,function(a,b) return a.id<b.id end)
    return locations,summary
end

local OWNED_MARKER_GROUP_DISTANCE=20
-- Simulated outranks a stale sighting (the ledger is live) but never a
-- currently loaded body the observer can actually see.
local LOCATION_CONFIDENCE_RANK={last_known=1,simulated=2,loaded=3}
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
                loadedCount=0,logicalCount=0,lastKnownCount=0,simulatedCount=0,companionCount=0}
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
        if location.companion then group.companionCount=group.companionCount+1 end
        if location.source=="loaded" then group.loadedCount=group.loadedCount+1
        elseif location.source=="simulated" then group.simulatedCount=group.simulatedCount+1
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
        local player=getSpecificPlayer(pn)
        local base=nil
        if player~=nil and KnoxPersistence~=nil and KnoxPersistence.ensurePlayerId~=nil then
            local ownerId=KnoxPersistence.ensurePlayerId(player)
            local manager=rawget(_G,"KnoxBaseManager")
            if ownerId~=nil and manager~=nil and manager.getForOwner~=nil then
                local ok,found=pcall(function() return manager.getForOwner("player",ownerId) end)
                if ok then base=found end
            end
        end
        cached={playerNum=pn,at=now,groups=groups,summary=summary,
            routes=Orders.patrolRoutes(base),
            stops=Orders.livePatrolStops(base,rawget(_G,"KnoxSurvivorRuntime"),KnoxPersistence)}
        renderedLocations[map]=cached
    end
    -- Draw the walked loop beneath the people: the waypoint order is the route,
    -- and the mid-edge arrowheads give it a direction. A survivor may start at
    -- a different corner, but the loop runs in this order.
    local patrolR,patrolG,patrolB=0.85,0.65,0.25
    local function drawSegment(x1,y1,x2,y2)
        if map.drawLine2~=nil then
            map:drawLine2(x1,y1,x2,y2,0.75,patrolR,patrolG,patrolB)
            return
        end
        local dx,dy=x2-x1,y2-y1
        local steps=math.max(math.abs(dx),math.abs(dy))
        if steps<=0 then return end
        for step=0,steps do
            map:drawRect(math.floor(x1+dx*step/steps),math.floor(y1+dy*step/steps),1,1,
                0.75,patrolR,patrolG,patrolB)
        end
    end
    for _,route in ipairs(cached.routes or {}) do
        local screen={}
        for _,point in ipairs(route.points or {}) do
            local ok,x,y=pcall(function() return map.mapAPI:worldToUIX(point.x,point.y),map.mapAPI:worldToUIY(point.x,point.y) end)
            if ok and tonumber(x)~=nil and tonumber(y)~=nil then
                screen[#screen+1]={x=math.floor(x),y=math.floor(y)}
            end
        end
        if #screen>=2 then
            for index=1,#screen do
                local a=screen[index]
                local b=screen[index%#screen+1]
                drawSegment(a.x,a.y,b.x,b.y)
                local tipX,tipY,leftX,leftY,rightX,rightY=Orders.routeArrow(a.x,a.y,b.x,b.y,6)
                if tipX~=nil then
                    drawSegment(tipX,tipY,leftX,leftY)
                    drawSegment(tipX,tipY,rightX,rightY)
                end
            end
        end
        local minX,minY
        for _,point in ipairs(screen) do
            if minX==nil or point.x<minX then minX=point.x end
            if minY==nil or point.y<minY then minY=point.y end
            map:drawRect(point.x-1,point.y-1,3,3,0.9,patrolR,patrolG,patrolB)
        end
        if minX~=nil and minY~=nil then
            map:drawText(tostring(route.name),minX+4,minY-10,
                patrolR,patrolG,patrolB,0.95,UIFont.Small)
        end
    end
    -- The next stop belongs to a live controller, so it disappears when the
    -- patroller is unloaded, idle or between routes. It never becomes a trail.
    for _,stop in ipairs(cached.stops or {}) do
        local ok,x,y=pcall(function() return map.mapAPI:worldToUIX(stop.x,stop.y),map.mapAPI:worldToUIY(stop.x,stop.y) end)
        if ok and tonumber(x)~=nil and tonumber(y)~=nil then
            x,y=math.floor(x),math.floor(y)
            map:drawRect(x-2,y-2,5,5,0.95,0.95,0.90,0.55)
            map:drawRect(x-1,y-1,3,3,0.95,0.55,0.45,0.25)
            map:drawText("next: "..tostring(stop.name),x+5,y+2,
                0.95,0.90,0.75,0.95,UIFont.Small)
        end
    end
    for _,group in ipairs(cached.groups) do
        local location=group.members[1]
        local ok,x,y=pcall(function() return map.mapAPI:worldToUIX(group.x,group.y),map.mapAPI:worldToUIY(group.x,group.y) end)
        if ok and tonumber(x)~=nil and tonumber(y)~=nil then
            local deceased=group.kind=="deceased"
            local stale=group.lastKnownCount>0
                and group.loadedCount==0 and group.simulatedCount==0
            -- Roadmap marker roles: a companion travelling with the player is
            -- green and takes precedence; a player-faction resident is blue.
            -- An unverified last sighting stays amber, a death stays red.
            local companion=group.companionCount>0
            local r,g,b=deceased and 0.85 or (stale and 0.70
                    or (companion and 0.30 or 0.35)),
                deceased and 0.25 or (stale and 0.75
                    or (companion and 0.90 or 0.60)),
                deceased and 0.25 or (stale and 0.25
                    or (companion and 0.40 or 0.95))
            local label
            if deceased then
                label="X "..location.name
                if type(location.deathCauseLabel) == "string"
                    and location.deathCauseLabel ~= "" then
                    label=label.." - "..location.deathCauseLabel
                end
            elseif group.count==1 then
                local prefix=(location.source=="logical" or location.source=="simulated")
                    and "~ " or (location.source=="last_known" and "? " or "")
                label=prefix..location.name
                if location.condition~=nil then
                    label=label.." - "..tostring(location.condition)
                end
            else
                local names={}
                for _,member in ipairs(group.members) do names[#names+1]=member.name end
                label=tostring(group.count).." survivors ("..tostring(group.loadedCount).." visible, "
                    ..tostring(group.simulatedCount).." tracked, "
                    ..tostring(group.lastKnownCount).." last seen): "
                    ..table.concat(names,", ")
            end
            local size=group.count>1 and 7 or 5
            map:drawRect(math.floor(x)-math.floor(size/2),math.floor(y)-math.floor(size/2),size,size,0.95,r,g,b)
            map:drawText(label,math.floor(x)+4,math.floor(y)-8,r,g,b,0.95,UIFont.Small)
        end
    end
    if cached.summary~=nil and cached.summary.unlocatedCount>0 then
        local count=cached.summary.unlocatedCount
        local noun=count==1 and "survivor" or "survivors"
        map:drawText("Location unknown for "..tostring(count).." known "..noun,
            8,8,0.95,0.75,0.25,0.95,UIFont.Small)
    end
    local legend=Orders.patrolLegendRows(cached.routes,cached.stops)
    if #legend>0 then
        local rowHeight=16
        local height=map.getHeight~=nil and (tonumber(map:getHeight()) or 0) or 0
        local x=8
        local y=height>0 and (height-#legend*rowHeight-12) or 34
        if y<8 then y=8 end
        map:drawRect(x-4,y-4,140,#legend*rowHeight+8,0.55,0.09,0.086,0.078)
        for index,row in ipairs(legend) do
            local rowY=y+(index-1)*rowHeight
            if row.kind=="route" then
                drawSegment(x+4,rowY+6,x+24,rowY+6)
            else
                map:drawRect(x+12,rowY+2,6,6,0.95,0.95,0.90,0.55)
            end
            map:drawText(row.label,x+32,rowY,0.90,0.88,0.82,0.95,UIFont.Small)
        end
    end
end
local function missionDestinationSquare(x,y,z)
    local cell=getCell~=nil and getCell() or nil
    if cell==nil or cell.getGridSquare==nil then return nil end
    local ok,square=pcall(function() return cell:getGridSquare(math.floor(x),math.floor(y),math.floor(z)) end)
    return ok and square or nil
end

-- Where "home" is, in map coordinates. The base record already owns the plot;
-- this only finds one point inside it instead of adding a second notion of home.
function Orders.areaCentre(area)
    if area==nil then return nil end
    local minX,minY=tonumber(area.minX or area.x),tonumber(area.minY or area.y)
    if minX==nil or minY==nil then return nil end
    local z=tonumber(area.z) or 0
    local width,height=tonumber(area.width or area.w),tonumber(area.height or area.h)
    local maxX=tonumber(area.maxX) or (width~=nil and minX+width-1 or nil)
    local maxY=tonumber(area.maxY) or (height~=nil and minY+height-1 or nil)
    if maxX==nil or maxY==nil then return {x=minX,y=minY,z=z} end
    return {x=(minX+maxX)/2,y=(minY+maxY)/2,z=z}
end

function Orders.baseDestination(player)
    local manager=rawget(_G,"KnoxBaseManager")
    if player==nil or manager==nil or manager.getForOwner==nil
        or KnoxPersistence==nil or KnoxPersistence.ensurePlayerId==nil then return nil end
    local ownerId=KnoxPersistence.ensurePlayerId(player)
    if ownerId==nil then return nil end
    local ok,base=pcall(function() return manager.getForOwner("player",ownerId) end)
    if not ok or base==nil then return nil end
    local area=base.home or base.territory
    local centre=Orders.areaCentre(area)
    if centre==nil then return nil end
    -- Stop on ground the car can actually occupy: the plot centre is often the
    -- front room. The approach search still leaves the final word to the
    -- planner, and the centre stays as the fallback when no edge square fits.
    local vehicle=player~=nil and player.getVehicle~=nil and player:getVehicle() or nil
    local nav=rawget(_G,"KnoxVehicleNavigation")
    if vehicle~=nil and nav~=nil and nav.approach~=nil then
        local inspected,geometry=pcall(nav.geometry,vehicle)
        if inspected and geometry~=nil then
            -- No traffic enumeration for a parking search, and it runs on the
            -- frame the map menu opens.
            local context=nav.context(vehicle,geometry,player,true)
            if context~=nil then
                local square=nav.approach(context,area,centre.z,vehicle:getX(),vehicle:getY())
                if square~=nil then return {x=square.x+0.5,y=square.y+0.5,z=centre.z} end
            end
        end
    end
    return centre
end

-- Does a right-click on the world map belong to us at all? Two callers, one
-- rule: the optional legacy command group, and a crew armed in the notebook
-- that is waiting for a destination. The mission draft never depended on the
-- legacy toggle, yet the map handler returned before anything was offered
-- whenever that toggle was off - which is its default - so the map opened
-- from the roster and the click did nothing (owner report, 2026-11-10).
function Orders.missionMapOffered(legacyEnabled, draft, hasBase)
    if draft ~= nil then return true end
    return legacyEnabled == true and hasBase == true
end

function Orders.hasDispatchBase(player)
    local manager=rawget(_G,"KnoxBaseManager")
    if player==nil or manager==nil or manager.getForOwner==nil
        or KnoxPersistence==nil or KnoxPersistence.ensurePlayerId==nil then return false end
    local ownerId=KnoxPersistence.ensurePlayerId(player)
    if ownerId==nil then return false end
    local ok,base=pcall(function() return manager.getForOwner("player",ownerId) end)
    return ok and base~=nil
end

-- The mission owner needs the destination's loaded square: the label, the
-- watchable-mission test and the travel estimate all read it. An explored point
-- outside the loaded band is refused here rather than dispatched from a guess,
-- so the map never sends a crew to coordinates that were never real.
function Orders.fillMission(context,player,x,y,z)
    local targets=rawget(_G,"KnoxMissionTargets")
    if context==nil or player==nil or targets==nil or targets.dispatchFlow==nil then return false end
    local pn=player:getPlayerNum()
    local draft=targets.mapDraft(pn)
    local option=context:addOption(draft and ("Send crew here (" .. tostring(#draft.memberIds) .. ")")
        or "Send a Mission Here",player,Orders.mission,x,y,z)
    if draft then
        context:addOption("Cancel mission placement",pn,targets.cancelMap)
    end
    if missionDestinationSquare(x,y,z)==nil then
        option.tooltip="Remote travel and carried needs continue. Searching waits until real containers load; no supplies are invented."
    else
        option.tooltip="Send residents from your base to clear or search this place."
    end
    return true
end

function Orders.mission(player,x,y,z)
    local targets=rawget(_G,"KnoxMissionTargets")
    local pn=player:getPlayerNum()
    if targets and targets.mapDraft(pn) then
        local ok,result=targets.sendMap(pn,player,x,y,0)
        if KnoxActivityFeed then KnoxActivityFeed.event(ok
            and "Crew dispatched. Their trip is in Missions." or result) end
        return
    end
    local square=missionDestinationSquare(x,y,z)
    if square==nil then
        if KnoxActivityFeed~=nil then
            KnoxActivityFeed.speak(player,"That point is outside the loaded world. Walk closer before sending anyone.")
        end
        return
    end
    local targets=rawget(_G,"KnoxMissionTargets")
    if targets==nil or targets.dispatchFlow==nil then return end
    local pn=player~=nil and player.getPlayerNum~=nil and player:getPlayerNum() or 0
    targets.dispatchFlow(pn,{player=player,anchor=square})
end

-- Can this companion take the wheel of this car, and why not. The same
-- readiness admission the driver run uses decides it, so the menu cannot offer a
-- seat the order will refuse: no key, dead engine, moving, towing, dry tank,
-- locked doors, someone already driving.
-- Why the map offers no vehicle order. Silence is the wrong answer while the
-- player is sitting in a car: one greyed line says which fact is missing
-- instead of leaving them to guess. Nothing is shown when driving is off (no
-- feature to advertise) or when the player is on foot, where a companion with
-- no car still gets an unavailable entry of their own.
function Orders.vehicleMenuHint(player,drivingEnabled,companionCount)
    if player==nil or drivingEnabled~=true then return nil end
    if player.getVehicle==nil or player:getVehicle()==nil then return nil end
    if (tonumber(companionCount) or 0)>0 then return nil end
    return "No companion is with you. Nobody can take the wheel."
end

function Orders.driveHereState(travel,vehicle,character,playerIsDriver)
    if character==nil then return false,"survivor_unavailable" end
    if playerIsDriver then return false,"player_must_vacate_driver_seat" end
    if vehicle==nil then return false,"vehicle_unavailable" end
    if travel==nil or travel.assessReadiness==nil then return false,"vehicle_state_unknown" end
    local ready,reason=travel.assessReadiness(vehicle,character)
    if ready then return true,nil end
    return false,reason or "vehicle_not_driveable"
end

function Orders.drive(player,id,x,y)
    local success,reason=KnoxCompanionService.drivePlayerVehicleTo(player,id,x,y)
    if not success and KnoxActivityFeed~=nil then
        KnoxActivityFeed.speak(player,failureLines[reason] or "That driving order isn't available right now.")
    end
end
-- On foot there is no car to hand over, so the map offers the other direction:
-- a companion fetches a parked car to the point you clicked. Only a genuinely
-- ready car can be sent, and the reason for a refusal is spoken, not swallowed.
-- Whether a companion can bring a car, and the reason when they cannot. Pure:
-- the menu's promise is decided here so it can be checked without a live menu,
-- and so the entry and the order can never disagree about who is able to help.
function Orders.carFetchState(travel,character,parked)
    if character==nil then return false,"survivor_unavailable" end
    if travel==nil or travel.readyVehicleNear==nil then return false,"vehicle_state_unknown" end
    local vehicle,reason=travel.readyVehicleNear(character,parked)
    if vehicle~=nil then return true,nil end
    return false,reason or "vehicle_unavailable"
end

function Orders.sendCar(player,id,x,y,z)
    local success,reason=KnoxCompanionService.sendVehicleTo(player,id,x,y,z)
    if not success and KnoxActivityFeed~=nil then
        KnoxActivityFeed.speak(player,failureLines[reason] or "Nobody can bring a car here right now.")
    end
end

function Orders.fillCar(context,player,x,y,z)
    if context==nil or player==nil or player:getVehicle()~=nil then return false end
    if KnoxSettings==nil or KnoxSettings.enableExperimentalNpcDriving==nil
        or not KnoxSettings.enableExperimentalNpcDriving() then return false end
    local ids=KnoxCompanionService.getCompanionIds(player)
    local candidates={}
    for _,id in ipairs(ids) do
        local character=KnoxSurvivorRuntime.getCharacter(id)
        if character~=nil and not character:isDead() then candidates[#candidates+1]=id end
    end
    if #candidates==0 then return false end
    -- One parked list for the whole menu; each entry is judged against it.
    local travel=rawget(_G,"KnoxNpcVehicleTravel")
    local parked=travel~=nil and travel.parkedVehicles~=nil and travel.parkedVehicles() or nil
    local option=context:addOption("Send a Car Here",nil,nil)
    option.tooltip="A companion brings a parked car to this point so you can drive it."
    local menu=ISContextMenu:getNew(context);context:addSubMenu(option,menu)
    for _,id in ipairs(candidates) do
        local character=KnoxSurvivorRuntime.getCharacter(id)
        local item=menu:addOption(displayName(id),player,Orders.sendCar,id,x,y,z)
        -- Say it before the click: a companion with no usable car is shown as
        -- unavailable, with the real reason, instead of promising a car later.
        local available,reason=Orders.carFetchState(travel,character,parked)
        if not available then
            item.notAvailable=true
            item.tooltip=failureLines[reason] or "No car they can bring right now."
        end
    end
    return true
end

-- Sending the car home should not require hunting for your own base on the map.
-- The order chooses a destination the player already owns and hands it to the
-- same drive run; it is a shortcut, not a second driving path.
function Orders.fillBase(context,player)
    if context==nil or player==nil or player:getVehicle()==nil then return false end
    if KnoxSettings==nil or KnoxSettings.enableExperimentalNpcDriving==nil
        or not KnoxSettings.enableExperimentalNpcDriving() then return false end
    local centre=Orders.baseDestination(player)
    if centre==nil then return false end
    local ids=KnoxCompanionService.getCompanionIds(player)
    local candidates={}
    for _,id in ipairs(ids) do
        local character=KnoxSurvivorRuntime.getCharacter(id)
        if character~=nil and not character:isDead() then candidates[#candidates+1]=id end
    end
    if #candidates==0 then return false end
    local option=context:addOption("Drive to Base",nil,nil)
    option.tooltip="A companion drives you home."
    local menu=ISContextMenu:getNew(context);context:addSubMenu(option,menu)
    for _,id in ipairs(candidates) do
        local item=menu:addOption(displayName(id),player,Orders.drive,id,centre.x,centre.y)
        if player:getVehicle():getDriver()==player then item.notAvailable=true end
    end
    return true
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
    local travel=rawget(_G,"KnoxNpcVehicleTravel")
    local vehicle=player:getVehicle()
    for _,id in ipairs(candidates) do
        local identity=KnoxPersistence.getSurvivorIdentity(id) or {}
        local name=(tostring(identity.forename or "").." "..tostring(identity.surname or "")):match("^%s*(.-)%s*$")
        local item=menu:addOption(name~="" and name or "Survivor",player,Orders.drive,id,x,y)
        local character=KnoxSurvivorRuntime.getCharacter(id)
        local available,reason=Orders.driveHereState(travel,vehicle,character,
            vehicle~=nil and vehicle.getDriver~=nil and vehicle:getDriver()==player)
        if not available then
            item.notAvailable=true
            item.tooltip=failureLines[reason] or "They can't take the wheel right now."
        end
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
    local pn = tonumber(self.playerNum) or 0
        local player=getSpecificPlayer(pn)
    local targets=rawget(_G,"KnoxMissionTargets")
    local draft=targets~=nil and targets.mapDraft~=nil and targets.mapDraft(pn) or nil
    local legacy=contextOrdersEnabled()
    if not Orders.missionMapOffered(legacy,draft,Orders.hasDispatchBase(player)) then return result end
        -- Two independent map orders, one menu. Handing over the wheel needs the
        -- player aboard a car; sending a mission needs an owned base. Neither
        -- entry appears for a player who could not receive it.
        local canDrive=legacy and player:getVehicle()~=nil and KnoxSettings.enableExperimentalNpcDriving()
            and #KnoxCompanionService.getCompanionIds(player)>0
        local canCar=legacy and player:getVehicle()==nil and KnoxSettings.enableExperimentalNpcDriving()
            and #KnoxCompanionService.getCompanionIds(player)>0
        local canDispatch=legacy and Orders.hasDispatchBase(player) or draft~=nil
        local hint=legacy and Orders.vehicleMenuHint(player,KnoxSettings.enableExperimentalNpcDriving(),
            #KnoxCompanionService.getCompanionIds(player)) or nil
        if not canDrive and not canCar and not canDispatch and hint==nil then return result end
        -- canHome adds only a base check on top of canDrive, so a player who can
        -- go home has already passed the gate above.
        local context
        if getDebug() or (isClient() and getAccessLevel()=="admin") then
            context=getPlayerContextMenu(pn) -- Preserve native debug entries.
        else context=ISContextMenu.get(pn,x+self:getAbsoluteX(),y+self:getAbsoluteY()) end
        local worldX=math.floor(self.mapAPI:uiToWorldX(x,y))+0.5
        local worldY=math.floor(self.mapAPI:uiToWorldY(x,y))+0.5
        local canHome=legacy and player:getVehicle()~=nil and KnoxSettings.enableExperimentalNpcDriving()
            and Orders.baseDestination(player)~=nil
            and #KnoxCompanionService.getCompanionIds(player)>0
        if canDrive then Orders.fill(context,player,worldX,worldY) end
        if canHome then Orders.fillBase(context,player) end
        if canCar then
            Orders.fillCar(context,player,worldX,worldY,tonumber(player:getZ()) or 0)
        end
        if hint~=nil then
            local explained=context:addOption("Drive Here",nil,nil)
            explained.notAvailable=true
            explained.tooltip=hint
        end
        if canDispatch then
            Orders.fillMission(context,player,worldX,worldY,tonumber(player:getZ()) or 0)
        end
        return true
    end
end
return Orders
