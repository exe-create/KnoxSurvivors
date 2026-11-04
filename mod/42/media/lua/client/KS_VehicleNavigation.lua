-- Original Knox routing on loaded, physically clear ground. Routes are plain
-- coordinates; native vehicle physics owns all movement. No teleporting or
-- character-sized path is used to certify clearance for a vehicle.
local Navigation={MAX_DISTANCE=160,MAX_NODES=384}
KnoxVehicleNavigation=Navigation
local scratch=nil

function Navigation.forward(vehicle)
    if Vector3f==nil or vehicle.getForwardVector==nil
        or (vehicle.getUpVectorDot~=nil and vehicle:getUpVectorDot()<0.95) then return nil end
    scratch=scratch or Vector3f.new()
    local v=vehicle:getForwardVector(scratch)
    local x,y=v:x(),v:z() -- Bullet's horizontal X/Z becomes world X/Y.
    local length=math.sqrt(x*x+y*y)
    if length<0.1 or (v.y~=nil and math.abs(v:y())>0.25) then return nil end
    return x/length,y/length
end

function Navigation.geometry(vehicle)
    local script=vehicle.getScript~=nil and vehicle:getScript() or nil
    local extents=script~=nil and script:getExtents() or nil
    if extents==nil then return nil end
    local width,length=tonumber(extents:x()),tonumber(extents:z())
    if width==nil or length==nil or width<=0 or length<=0 or width>8 or length>18 then return nil end
    local com=script:getCenterOfMassOffset()
    local model=script:getModelOffset()
    local minX,maxX=com:x()-width/2,com:x()+width/2
    local minZ,maxZ=com:z()-length/2,com:z()+length/2
    local function include(cx,cz,halfX,halfZ)
        if halfX~=halfX or halfZ~=halfZ or halfX<=0 or halfZ<=0 then return false end
        minX,maxX=math.min(minX,cx-halfX),math.max(maxX,cx+halfX)
        minZ,maxZ=math.min(minZ,cz-halfZ),math.max(maxZ,cz+halfZ)
        return true
    end
    if script.hasPhysicsChassisShape~=nil and script:hasPhysicsChassisShape()
        and script:useChassisPhysicsCollision() then
        local shape=script:getPhysicsChassisShape()
        if not include(com:x(),com:z(),shape:x()/2,shape:z()/2) then return nil end
    end
    for i=0,(script.getPhysicsShapeCount~=nil and script:getPhysicsShapeCount() or 0)-1 do
        local shape=script:getPhysicsShape(i)
        local kind,offset=shape:getTypeString(),shape:getOffset()
        local halfX,halfZ
        if kind=="sphere" then halfX,halfZ=shape:getRadius(),shape:getRadius()
        elseif kind=="box" then
            local dimensions,rotation=shape:getExtents(),shape:getRotate()
            halfX,halfZ=dimensions:x()/2,dimensions:z()/2
            if math.abs(rotation:x())+math.abs(rotation:y())+math.abs(rotation:z())>0.001 then
                -- Enclose a rotated custom part regardless of Euler convention.
                local radius=math.sqrt(dimensions:x()^2+dimensions:y()^2+dimensions:z()^2)/2
                halfX,halfZ=radius,radius
            end
        else return nil end -- mesh bounds cannot be inferred from render extents
        if not include(offset:x(),offset:z(),halfX,halfZ) then return nil end
    end
    if maxX-minX>12 or maxZ-minZ>24 then return nil end
    local front,rear,rearX=nil,nil,0
    for i=0,script:getWheelCount()-1 do
        local offset=script:getWheel(i):getOffset()
        front=math.max(front or offset:z(),offset:z())
        if rear==nil or offset:z()<rear then rear,rearX=offset:z(),offset:x() end
    end
    if front==nil or rear==nil or front-rear<0.5 then return nil end
    -- Average the rear axle pair, including a scaled model offset. Loaded()
    -- already scales extents, COM and wheel offsets; never apply scale twice.
    local sum,count=0,0
    for i=0,script:getWheelCount()-1 do
        local offset=script:getWheel(i):getOffset()
        if math.abs(offset:z()-rear)<0.2 then sum,count=sum+offset:x(),count+1 end
    end
    rearX=sum/math.max(1,count)+(model~=nil and model:x() or 0)
    local wheelbase=front-rear
    local steeringLimit=math.min(0.7,script:getSteeringClamp(8))
    if steeringLimit<=0 or steeringLimit~=steeringLimit then return nil end
    return {halfWidth=(maxX-minX)/2+0.4,halfLength=(maxZ-minZ)/2+0.5,
        centerX=(minX+maxX)/2,centerZ=(minZ+maxZ)/2,rearX=rearX,rearZ=rear+(model~=nil and model:z() or 0),
        wheelbase=wheelbase,steeringLimit=steeringLimit,
        maxCurvature=math.tan(steeringLimit)*0.75/wheelbase}
end

-- lightweight skips the other-vehicle enumeration. An approach search only
-- asks whether a square and a pose are free; it does not reason about traffic,
-- so paying for every vehicle in the cell there is wasted work.
function Navigation.context(vehicle,geometry,driver,lightweight)
    local cell=getCell()
    if cell==nil then return nil end
    local others={}
    local vehicles=nil
    if not lightweight and cell.getVehicles~=nil then vehicles=cell:getVehicles() end
    local function add(other)
        if other~=vehicle and other~=nil then others[#others+1]=other end
    end
    if vehicles~=nil then
        if vehicles.iterator~=nil then
            local iterator=vehicles:iterator()
            while iterator:hasNext() do add(iterator:next()) end
        else
            for i=0,vehicles:size()-1 do add(vehicles:get(i)) end
        end
    end
    return {vehicle=vehicle,driver=driver,geometry=geometry,cell=cell,others=others,squares={}}
end

local function tile(context,x,y,z)
    x,y=math.floor(x),math.floor(y)
    local key=x..":"..y..":"..z
    local cached=context.squares[key]
    if cached~=nil then return cached~=false and cached or nil end
    local square=context.cell:getGridSquare(x,y,z)
    local free=square~=nil and square:canStand() and square:isOutside()
        and not square:isSolid() and not square:isSolidTrans() and not square:HasTree()
    if free then
        local moving=square:getMovingObjects()
        for i=0,moving:size()-1 do
            local object=moving:get(i)
            if object~=context.driver and instanceof(object,"IsoGameCharacter") and not object:isDead()
                and object:getVehicle()~=context.vehicle then free=false;break end
        end
    end
    if free then
        for _,other in ipairs(context.others) do
            if math.abs(other:getX()-x)<=20 and math.abs(other:getY()-y)<=20
                and other:isIntersectingSquare(x,y,z) then free=false;break end
        end
    end
    context.squares[key]=free and square or false
    return free and square or nil
end

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function distance(ax,ay,bx,by) return math.sqrt((ax-bx)^2+(ay-by)^2) end
local function clamp(value,low,high) return math.max(low,math.min(high,value)) end

-- Surface knowledge. These numbers are planning preferences, not physics:
-- native handling still owns traction, and no speed here is applied to the
-- controller directly. Names come from the floor sprite when the build exposes
-- one; every unreadable case falls back to a mid cost, so uncertain ground is
-- never mistaken for the best road.
local SURFACES = {
    asphalt = { weight = 1.00, speed = 1.00 },
    gravel  = { weight = 1.12, speed = 0.85 },
    dirt    = { weight = 1.28, speed = 0.70 },
    trail   = { weight = 1.45, speed = 0.55 },
    grass   = { weight = 1.65, speed = 0.60 },
    unknown = { weight = 1.35, speed = 0.80 },
}
Navigation.SURFACES = SURFACES

-- Order matters: "dirtroad" is dirt, not a road, and a "gravel" name wins over
-- a generic "road" substring. Longest-meaning first.
local SURFACE_ORDER = {
    { "trail",   { "trail" } },
    { "dirt",    { "dirt", "mud", "soil" } },
    { "gravel",  { "gravel", "shingle" } },
    { "asphalt", { "street", "road", "pavement", "sidewalk", "kerb", "tarmac", "asphalt" } },
    { "grass",   { "grass", "vegetation", "lawn", "meadow", "natural" } },
}

local function floorName(square)
    if square == nil or square.getFloor == nil then return nil end
    local ok, floor = pcall(function() return square:getFloor() end)
    if not ok or floor == nil or floor.getSpriteName == nil then return nil end
    local named, name = pcall(function() return floor:getSpriteName() end)
    if not named or type(name) ~= "string" or name == "" then return nil end
    return string.lower(name)
end

-- Unread window. When a floor name matches nothing, the plan was made from a
-- guess. Each distinct name is recorded once through the existing diagnostics
-- owner, so one real drive reports exactly which tiles the classifier does not
-- know instead of the owner hunting sprite names by hand. Bounded: this is a
-- report, not an accumulating log.
local UNKNOWN_LIMIT = 24
local unknownGround = {}
local unknownGroundCount = 0

local function noteUnknownGround(name)
    if name == nil then return end
    local record = unknownGround[name]
    if record == nil then
        if unknownGroundCount >= UNKNOWN_LIMIT then return end
        unknownGround[name] = { count = 1 }
        unknownGroundCount = unknownGroundCount + 1
        local log = rawget(_G, "KnoxDebugLog")
        if log ~= nil and log.once ~= nil then
            pcall(log.once, "vehicles", name, "surface_unknown", { sprite = name })
        end
        return
    end
    record.count = record.count + 1
end

-- "name x count" from most to least seen, plus how many distinct names there
-- are. Returns an empty string when every surface read so far was understood.
function Navigation.unknownGround()
    local rows = {}
    for name, record in pairs(unknownGround) do
        rows[#rows + 1] = { name = name, count = record.count }
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    local parts = {}
    for _, row in ipairs(rows) do
        parts[#parts + 1] = row.name .. "x" .. tostring(row.count)
    end
    return table.concat(parts, ", "), #rows
end

function Navigation.resetUnknownGround()
    unknownGround = {}
    unknownGroundCount = 0
end

-- Returns the surface name and its entry. Read-only and never raising: a
-- missing square, a missing floor or a failing reader is "unknown" ground.
function Navigation.surface(square)
    local name = floorName(square)
    if name == nil then return "unknown", SURFACES.unknown end
    for _, entry in ipairs(SURFACE_ORDER) do
        for _, word in ipairs(entry[2]) do
            if string.find(name, word, 1, true) ~= nil then
                return entry[1], SURFACES[entry[1]]
            end
        end
    end
    noteUnknownGround(name)
    return "unknown", SURFACES.unknown
end

function Navigation.speedFactor(name)
    local surface = SURFACES[name] or SURFACES.unknown
    return surface.speed
end

-- The planning cost of one step. Pure, so the preference can be exercised
-- without a vehicle: distance on that ground, the price of changing surface
-- (a route that hops between pavement and grass is worse than one that stays),
-- and the price of asking for a turn.
function Navigation.linkCost(length, surfaceWeight, previousWeight, turn)
    local weight = finite(surfaceWeight) and math.max(0.5, surfaceWeight) or SURFACES.unknown.weight
    local cost = length * weight
    if finite(previousWeight) and math.abs(previousWeight - weight) > 0.001 then
        cost = cost + 0.6
    end
    return cost + math.abs(finite(turn) and turn or 0) * 0.4
end

-- Certify the whole oriented body, including nose and rear overhang. Checking
-- only a centre corridor misses the outside corner of a turning car.
function Navigation.poseClear(context,x,y,heading,z)
    if context==nil or not finite(x) or not finite(y) or not finite(heading) then return false end
    local geometry=context.geometry
    local fx,fy=math.cos(heading),math.sin(heading)
    local rx,ry=fy,-fx
    local cx=x+fx*(geometry.centerZ or 0)+rx*(geometry.centerX or 0)
    local cy=y+fy*(geometry.centerZ or 0)+ry*(geometry.centerX or 0)
    local halfX=math.abs(fx)*geometry.halfLength+math.abs(rx)*geometry.halfWidth
    local halfY=math.abs(fy)*geometry.halfLength+math.abs(ry)*geometry.halfWidth
    local projection=0.5*(math.abs(fx)+math.abs(fy))
    local previous={}
    -- Rectangle/tile separating axes cover corner grazes that point samples
    -- can miss, while visiting each overlapped tile just once per pose.
    for ty=math.floor(cy-halfY),math.floor(cy+halfY) do
        local row={}
        for tx=math.floor(cx-halfX),math.floor(cx+halfX) do
            context.samples=(context.samples or 0)+1
            if context.samples>(context.sampleLimit or 300000) then context.exhausted=true;return false end
            local dx,dy=tx+0.5-cx,ty+0.5-cy
            if math.abs(dx*fx+dy*fy)<=geometry.halfLength+projection
                and math.abs(dx*rx+dy*ry)<=geometry.halfWidth+projection then
                local square=tile(context,tx,ty,z)
                if square==nil then return false end
                local before,beside=previous[tx],row[tx-1]
                if before~=nil and before:isBlockedTo(square) then return false end
                if beside~=nil and beside:isBlockedTo(square) then return false end
                row[tx]=square
            end
        end
        previous=row
    end
    return true
end

function Navigation.rearPosition(x,y,heading,geometry)
    local rearX,rearZ=geometry.rearX or 0,geometry.rearZ or 0
    return x+math.cos(heading)*rearZ+math.sin(heading)*rearX,
        y+math.sin(heading)*rearZ-math.cos(heading)*rearX
end

function Navigation.advance(x,y,heading,curvature,length,geometry)
    local angle=curvature*length
    if math.abs(curvature)<0.000001 then
        return x+math.cos(heading)*length,y+math.sin(heading)*length,heading
    end
    local rearX,rearZ=geometry~=nil and geometry.rearX or 0,geometry~=nil and geometry.rearZ or 0
    local startX,startY=x+math.cos(heading)*rearZ+math.sin(heading)*rearX,
        y+math.sin(heading)*rearZ-math.cos(heading)*rearX
    return startX+(math.sin(heading+angle)-math.sin(heading))/curvature
            -math.cos(heading+angle)*rearZ-math.sin(heading+angle)*rearX,
        startY+(math.cos(heading)-math.cos(heading+angle))/curvature
            -math.sin(heading+angle)*rearZ+math.cos(heading+angle)*rearX,heading+angle
end

function Navigation.arcClear(context,x,y,heading,curvature,length,z)
    if context==nil or not finite(length) or length<0 or not finite(curvature) then return false end
    -- Bound the distance swept by the outermost corner between samples, not
    -- just the distance travelled by the centre of the vehicle.
    local g=context.geometry
    local radius=math.sqrt((g.halfLength+math.abs((g.centerZ or 0)-(g.rearZ or 0)))^2
        +(g.halfWidth+math.abs((g.centerX or 0)-(g.rearX or 0)))^2)
    local steps=math.max(1,math.ceil(length*(1+math.abs(curvature)*radius)/0.4))
    for i=0,steps do
        local px,py,angle=Navigation.advance(x,y,heading,curvature,length*i/steps,context.geometry)
        if not Navigation.poseClear(context,px,py,angle,z) then return false end
    end
    return true
end

-- Straight translation is also a whole-body sweep, including its end caps.
function Navigation.clear(context,ax,ay,bx,by,z)
    if context==nil then return false end
    local length=distance(ax,ay,bx,by)
    local heading=math.atan2(by-ay,bx-ax)
    if length<0.01 then
        local fx,fy=Navigation.forward(context.vehicle)
        if fx==nil then return false end
        heading=math.atan2(fy,fx)
    end
    return Navigation.arcClear(context,ax,ay,heading,0,length,z)
end

-- Where to actually stop at a destination plot. A centre is often inside the
-- house or behind a fence, so the edges are tried first, and a square only wins
-- when the whole car body fits on it at some heading. Falls back to nothing: the
-- caller decides what to do when there is no drivable approach.
function Navigation.approach(context,area,z,fromX,fromY)
    if context==nil or area==nil then return nil end
    local minX,minY=tonumber(area.minX or area.x),tonumber(area.minY or area.y)
    if minX==nil or minY==nil then return nil end
    local width,height=tonumber(area.width or area.w),tonumber(area.height or area.h)
    local maxX=tonumber(area.maxX) or (width~=nil and minX+width-1 or minX)
    local maxY=tonumber(area.maxY) or (height~=nil and minY+height-1 or minY)
    z=tonumber(z) or tonumber(area.z) or 0
    fromX,fromY=tonumber(fromX) or minX,tonumber(fromY) or minY
    local midX,midY=math.floor((minX+maxX)/2),math.floor((minY+maxY)/2)
    local candidates={
        {x=midX,y=minY},{x=midX,y=maxY},{x=minX,y=midY},{x=maxX,y=midY},
        {x=minX,y=minY},{x=maxX,y=minY},{x=minX,y=maxY},{x=maxX,y=maxY},
        {x=midX,y=midY},
    }
    local best,bestDistance=nil,nil
    for _,candidate in ipairs(candidates) do
        local square=tile(context,candidate.x,candidate.y,z)
        if square~=nil then
            local fitted=false
            for _,angle in ipairs({0,math.pi/2,math.pi,-math.pi/2}) do
                if Navigation.poseClear(context,candidate.x+0.5,candidate.y+0.5,angle,z) then
                    fitted=true;break
                end
            end
            if fitted then
                local dx,dy=candidate.x-fromX,candidate.y-fromY
                local distance=dx*dx+dy*dy
                -- A road-side stop beats a nearer field edge: pavement is where a
                -- car can be left and driven away from. Unread ground is not
                -- punished twice, it just has to be clearly closer to win.
                if Navigation.surface(square)~="asphalt" then distance=distance*2 end
                if bestDistance==nil or distance<bestDistance then
                    best,bestDistance=candidate,distance
                end
            end
        end
    end
    return best
end

local function connection(node,x,y,geometry)
    local dx,dy=x-node.x,y-node.y
    local fx,fy=math.cos(node.heading),math.sin(node.heading)
    local along,side=dx*fx+dy*fy,fx*dy-fy*dx
    local squared=dx*dx+dy*dy
    if squared<0.01 then return 0,0 end
    if math.abs(side)<0.001 then
        if along<=0 then return nil end
        return 0,along
    end
    local rearAlong,rearSide=geometry.rearZ or 0,-(geometry.rearX or 0)
    local denominator=squared-2*rearAlong*along-2*rearSide*side
    if math.abs(denominator)<0.001 then return nil end
    local curvature=2*side/denominator
    if math.abs(curvature)>geometry.maxCurvature then return nil end
    local centerAlong,centerSide=rearAlong,rearSide+1/curvature
    local startAlong,startSide=-centerAlong,-centerSide
    local endAlong,endSide=along-centerAlong,side-centerSide
    local angle=math.atan2(startAlong*endSide-startSide*endAlong,startAlong*endAlong+startSide*endSide)
    if angle*curvature<=0 or math.abs(angle)>math.pi*0.75 then return nil end
    return curvature,angle/curvature
end

local function keyFor(x,y,heading)
    return math.floor(x+0.5)..":"..math.floor(y+0.5)..":"..(math.floor(heading*12/math.pi+0.5)%24)
end

function Navigation.plan(vehicle,x,y,z,geometry,driver)
    local origin=vehicle:getSquare()
    x,y,z=tonumber(x),tonumber(y),tonumber(z)
    if origin==nil or not finite(x) or not finite(y) or not finite(z) or z~=origin:getZ() then
        return nil,"destination_unavailable"
    end
    local ax,ay=vehicle:getX(),vehicle:getY()
    local total=distance(ax,ay,x,y)
    if total>Navigation.MAX_DISTANCE then return nil,"destination_too_far" end
    if total<4 then return nil,"destination_too_close" end
    local fx,fy=Navigation.forward(vehicle)
    if fx==nil then return nil,"vehicle_heading_unavailable" end
    if geometry==nil or not finite(geometry.maxCurvature) or geometry.maxCurvature<=0 then
        return nil,"vehicle_geometry_unavailable"
    end
    local context=Navigation.context(vehicle,geometry,driver)
    local heading=math.atan2(fy,fx)
    if context==nil or tile(context,x,y,z)==nil or not Navigation.poseClear(context,ax,ay,heading,z) then
        return nil,"destination_unavailable"
    end
    local originSurfaceName,originSurface=Navigation.surface(origin)
    local start={x=ax,y=ay,heading=heading,g=0,key=keyFor(ax,ay,heading),
        surfaceWeight=originSurface.weight,surface=originSurfaceName}
    local open,best,closed={start},{[start.key]=start},{}
    local final,expanded=nil,0
    -- Original Knox forward arc search. Heading is part of every state, and a
    -- successor must be physically reachable with the vehicle's turning radius.
    -- Nodes are immutable: replacing a cheaper candidate cannot bend descendants.
    while #open>0 and expanded<Navigation.MAX_NODES and not context.exhausted do
        local index,score=1,math.huge
        for i,node in ipairs(open) do
            local f=node.g+distance(node.x,node.y,x,y)*1.1
            if f<score then index,score=i,f end
        end
        local node=table.remove(open,index)
        if best[node.key]==node and not closed[node.key] then
            closed[node.key]=true;expanded=expanded+1
            local curvature,length=connection(node,x,y,geometry)
            if curvature~=nil and Navigation.arcClear(context,node.x,node.y,node.heading,curvature,length,z) then
                final={parent=node,curvature=curvature,length=length};break
            end
            for _,turn in ipairs({0,-1,1}) do
                curvature,length=turn*geometry.maxCurvature,4
                local nx,ny,angle=Navigation.advance(node.x,node.y,node.heading,curvature,length,geometry)
                local key=keyFor(nx,ny,angle)
                local stepSquare=context.cell:getGridSquare(math.floor(nx),math.floor(ny),z)
                local stepSurfaceName,stepSurface=Navigation.surface(stepSquare)
                local cost=node.g+Navigation.linkCost(length,stepSurface.weight,
                    node.surfaceWeight,turn)
                    + math.abs(curvature-(node.curvature or 0))*3
                if not closed[key] and distance(ax,ay,nx,ny)<=Navigation.MAX_DISTANCE
                    and (best[key]==nil or cost<best[key].g)
                    and Navigation.arcClear(context,node.x,node.y,node.heading,curvature,length,z) then
                    local nextNode={key=key,x=nx,y=ny,heading=angle,g=cost,
                        curvature=curvature,length=length,parent=node,
                        surfaceWeight=stepSurface.weight,surface=stepSurfaceName}
                    best[key]=nextNode;open[#open+1]=nextNode
                end
            end
        end
    end
    if final==nil then return nil,context.exhausted and "drive_planning_budget" or "drive_route_unavailable" end
    local reversed={}
    while final~=start do reversed[#reversed+1]=final;final=final.parent end
    local route={origin={x=ax,y=ay,z=z,s=0,heading=heading},length=0,expanded=expanded,samples=context.samples}
    for i=#reversed,1,-1 do
        local segment=reversed[i]
        local count=math.max(1,math.ceil(segment.length/1.5))
        for j=1,count do
            local px,py,angle=Navigation.advance(segment.parent.x,segment.parent.y,segment.parent.heading,
                segment.curvature,segment.length*j/count,geometry)
            route[#route+1]={x=px,y=py,z=z,heading=angle,curvature=segment.curvature,
                s=route.length+segment.length*j/count}
        end
        route.length=route.length+segment.length
    end
    route[#route].x,route[#route].y=x,y
    return route
end

function Navigation.stoppingDistance(speed)
    local velocity=math.abs(speed)/3.6
    return 2+velocity*0.35+velocity*velocity/4
end

-- Project onto nearby route segments, then aim ahead along the route. Intermediate
-- samples are steering guides, not destinations at which the driver should stop.
function Navigation.follow(route,index,x,y,speed)
    local selected,progress,errorSquared=index,0,math.huge
    for i=index,math.min(#route,index+8) do
        local a,b=i==1 and route.origin or route[i-1],route[i]
        local dx,dy=b.x-a.x,b.y-a.y
        local squared=dx*dx+dy*dy
        local t=squared>0 and clamp(((x-a.x)*dx+(y-a.y)*dy)/squared,0,1) or 1
        local error=(x-a.x-dx*t)^2+(y-a.y-dy*t)^2
        if error<errorSquared then
            selected,progress,errorSquared=i,a.s+(b.s-a.s)*t,error
        end
    end
    local aimAt=math.min(route.length,progress+clamp(3+math.abs(speed)/3.6*0.6,3,7))
    local aim,curvature=route[#route],0
    local found=false
    for i=selected,#route do
        local a,b=i==1 and route.origin or route[i-1],route[i]
        if not found and b.s>=aimAt then
            local t=b.s>a.s and clamp((aimAt-a.s)/(b.s-a.s),0,1) or 1
            aim={x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t,heading=a.heading+(b.heading-a.heading)*t};found=true
        end
        if b.s<=progress+Navigation.stoppingDistance(speed)+8 then
            curvature=math.max(curvature,math.abs(b.curvature or 0))
        elseif found then break end
    end
    return {index=selected,remaining=math.max(0,route.length-progress),aim=aim,
        error=math.sqrt(errorSquared),curvature=curvature,progress=progress}
end

function Navigation.controls(speed,remaining,dot,cross,limit,geometry,aimDistance,curvature)
    local desired=math.min(limit,math.sqrt(math.max(0,remaining-2)*4)*3.6)
    if curvature~=nil and curvature>0.001 then desired=math.min(desired,math.sqrt(1.5/curvature)*3.6,10) end
    if dot<0.9 then desired=math.min(desired,8) end
    if dot<=0 then desired=0 end
    local steering=clamp(cross*3,-1,1)
    if geometry~=nil and aimDistance~=nil then
        local pursuit=2*cross/math.max(0.5,aimDistance)
        -- Native ClientControls steers toward an angle; it is not a normalized
        -- percentage of the script's clamp. Native smoothing remains in charge.
        steering=clamp(math.atan(geometry.wheelbase*pursuit),-geometry.steeringLimit,geometry.steeringLimit)
        -- <=0.1 is native recentering, not a gentle held steering command.
        -- Small route errors coast straight; larger corrections cross that
        -- deadband while retaining the game's own steering smoothing.
        if math.abs(steering)<0.015 then steering=0
        elseif math.abs(steering)<=0.1 then steering=steering<0 and -0.11 or 0.11 end
    end
    return {steering=steering,forward=desired>0 and speed<desired-1,backward=false,
        brake=desired<=0 or speed>desired+1,shift=false},desired
end
return Navigation
