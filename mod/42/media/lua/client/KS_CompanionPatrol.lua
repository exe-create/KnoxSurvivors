local Patrol = rawget(_G, "KnoxCompanionPatrol") or {}
_G.KnoxCompanionPatrol = Patrol

local function stableHash(value)
    local result = 5381
    for index = 1, #tostring(value or "") do
        result = (result * 33 + string.byte(tostring(value), index)) % 2147483647
    end
    return result
end

local function boundsOf(directive)
    if type(directive) ~= "table" then return nil end
    local minX = tonumber(directive.minX or directive.x1 or directive.x)
    local minY = tonumber(directive.minY or directive.y1 or directive.y)
    local maxX = tonumber(directive.maxX or directive.x2 or minX)
    local maxY = tonumber(directive.maxY or directive.y2 or minY)
    if minX == nil or minY == nil or maxX == nil or maxY == nil then return nil end
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(directive.z) or 0
end

Patrol.bounds = boundsOf

function Patrol.squareKey(square)
    return tostring(square:getX())..":"..tostring(square:getY())..":"..tostring(square:getZ())
end

function Patrol.contains(directive, square)
    local minX, minY, maxX, maxY, z = boundsOf(directive)
    return minX ~= nil and square ~= nil and square:getZ() == z
        and square:getX() >= minX and square:getX() <= maxX
        and square:getY() >= minY and square:getY() <= maxY
end

function Patrol.waypoints(directive)
    local minX, minY, maxX, maxY, z = boundsOf(directive)
    if minX == nil then return {} end
    local insetX = maxX - minX >= 4 and 1 or 0
    local insetY = maxY - minY >= 4 and 1 or 0
    minX, maxX = minX + insetX, maxX - insetX
    minY, maxY = minY + insetY, maxY - insetY
    local candidates = {
        { x = minX, y = minY, z = z },
        { x = maxX, y = minY, z = z },
        { x = maxX, y = maxY, z = z },
        { x = minX, y = maxY, z = z },
    }
    local points, seen = {}, {}
    for _, point in ipairs(candidates) do
        local key = tostring(point.x) .. ":" .. tostring(point.y) .. ":" .. tostring(point.z)
        if not seen[key] then
            seen[key] = true
            points[#points + 1] = point
        end
    end
    return points
end

function Patrol.waypointForStep(directive, survivorId, step)
    local points = Patrol.waypoints(directive)
    if #points == 0 then return nil end
    local start = stableHash(survivorId) % #points
    local index = ((start + math.max(0, math.floor(tonumber(step) or 0))) % #points) + 1
    return points[index], #points
end

-- Guard and patrol share the same area geometry but not the same intent. A
-- guard owns one repeatable post; a patrol advances around the route.
function Patrol.guardPost(directive, survivorId)
    return Patrol.waypointForStep(directive, survivorId, 0)
end

local function recordArrival(task, area)
    if type(task) ~= "table" then return false, 0, 0 end
    local count = #Patrol.waypoints(area)
    if count == 0 then return false, 0, 0 end
    local step = math.max(0, math.floor(tonumber(task.patrolStep) or 0)) % count
    -- Existing saves visited the stops sequentially. New obstacle recovery can
    -- skip a stop, so count unique observed arrivals rather than imaginary laps.
    local oldCount = math.min(count, math.max(0, math.floor(tonumber(task.patrolStopsCompleted) or 0)))
    local mask = tonumber(task.patrolVisitedMask) or (2^oldCount-1)
    mask = math.max(0, math.floor(mask)) % (2^count)
    local bit = 2^step
    if math.floor(mask/bit)%2 == 0 then mask = mask+bit end
    local visited = 0
    for index=0,count-1 do if math.floor(mask/2^index)%2 == 1 then visited=visited+1 end end
    task.patrolVisitedMask = mask
    if visited >= count then
        task.patrolStep = 0
        task.patrolStopsCompleted = 0
        task.patrolVisitedMask = 0
        return true, 0, count
    end
    task.patrolStopsCompleted = visited
    task.patrolStep = (step + 1) % count
    return false, task.patrolStep, count
end

function Patrol.recordTaskArrival(task)
    return recordArrival(task, task and task.target)
end

function Patrol.recordDirectiveArrival(directive)
    return recordArrival(directive, directive)
end

-- PATROL SIGHTING (pure)
-- A patrol's report is a reading of what its own arrival can see, not a second
-- threat model. The controller supplies the real nearby count from its existing
-- pressure scan; this module only owns the words and the retelling gap.
function Patrol.sightingWord(pressure, direction, contact)
    local count = tonumber(pressure) or 0
    if contact ~= nil then
        local where = direction ~= nil and (" to the " .. tostring(direction)) or " nearby"
        return "I see " .. tostring(contact) .. where .. "."
    end
    if count <= 0 then return nil end
    local where = direction ~= nil and (" to the " .. tostring(direction))
        or " near the patrol route"
    if count >= 5 then return "A crowd" .. where .. "." end
    if count >= 2 then return "A few" .. where .. "." end
    return "Movement" .. where .. "."
end

-- A patrol names only somebody it does not already own. A player-owned person
-- is not a sighting; a faction member is named by the faction's existing name,
-- and everybody else is a stranger. This is a word choice, not a relationship
-- change or a second faction read.
function Patrol.contactWord(affiliation, factionName, knownName)
    if type(affiliation) ~= "table" then return "a stranger", "stranger" end
    if affiliation.kind == "player" then return nil, "player" end
    if type(knownName) == "string" and knownName ~= "" then return knownName, "known" end
    if affiliation.kind == "faction" and type(factionName) == "string"
        and factionName ~= "" then
        return "a member of " .. factionName, "faction"
    end
    return "a stranger", affiliation.kind == "faction" and "faction" or "stranger"
end

function Patrol.feedLine(line)
    if type(line) ~= "string" or line == "" then return nil end
    return "Patrol: " .. line
end

function Patrol.sightingDue(last, now, cooldown)
    -- An unset stamp is a patrol's first stop, not a stop that must wait for the
    -- cooldown to expire from tick zero.
    if last == nil then return true end
    local stamp = tonumber(last)
    if stamp == nil then return true end
    local wait = tonumber(cooldown) or 1800
    return (tonumber(now) or 0) >= stamp + wait
end
-- END PATROL SIGHTING

-- Resolve a real standing tile around the next stop, never outside the selected
-- area or on another floor. A blocked corner is not the end of a patrol order.
function Patrol.resolveWaypoint(area, survivorId, step, cell, current, excluded, ticks, guard)
    if cell == nil then return nil end
    local count = #Patrol.waypoints(area)
    if count == 0 then return nil end
    step = math.max(0, math.floor(tonumber(step) or 0)) % count
    for offset=0,(guard and 0 or count-1) do
        local selected = (step+offset)%count
        local point = Patrol.waypointForStep(area,survivorId,selected)
        for radius=0,6 do
            for dx=-radius,radius do for dy=-radius,radius do
                if radius==0 or math.max(math.abs(dx),math.abs(dy))==radius then
                    local square=cell:getGridSquare(point.x+dx,point.y+dy,point.z)
                    if square~=nil and Patrol.contains(area,square)
                        and square.canStand~=nil and square:canStand()
                        and (guard or count==1 or current==nil
                            or current:getZ()~=square:getZ()
                            or (current:getX()-square:getX())^2+(current:getY()-square:getY())^2>0)
                        and (excluded==nil or (excluded[Patrol.squareKey(square)] or 0)<=(ticks or 0)) then
                        return square,selected,count
                    end
                end
            end end
        end
    end
    return nil,step,count
end

function Patrol.move(bridge,id,target,area)
    local x1,y1,x2,y2,z=Patrol.bounds(area)
    if bridge.moveNpcWithinArea~=nil then
        return tostring(bridge:moveNpcWithinArea(id,target,x1,y1,x2,y2,z))
    end
    -- Old agents cannot enforce route boundaries. Keep the order for a matched
    -- install rather than silently executing a patrol outside its work area.
    return "MOVE_FAILED AREA_ROUTING_REQUIRES_UPDATED_AGENT"
end

function Patrol.nextWaypoint(directive, current, survivorId)
    local points = Patrol.waypoints(directive)
    if #points == 0 or current == nil then return nil end
    local cx = current.getX ~= nil and current:getX() or tonumber(current.x)
    local cy = current.getY ~= nil and current:getY() or tonumber(current.y)
    if cx == nil or cy == nil then return nil end
    local start = stableHash(survivorId) % #points
    local nearest, nearestDistance = nil, math.huge
    for offset = 0, #points - 1 do
        local index = ((start + offset) % #points) + 1
        local point = points[index]
        local distance = (point.x - cx) ^ 2 + (point.y - cy) ^ 2
        if distance < nearestDistance then
            nearest, nearestDistance = index, distance
        end
    end
    if nearestDistance <= 2.25 then nearest = (nearest % #points) + 1 end
    return points[nearest]
end

return Patrol
