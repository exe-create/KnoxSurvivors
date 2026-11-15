-- Positioning is part of the existing controller, not another combat scheduler.
local Positioning = {}
_G.KnoxCombatPositioning = Positioning

function Positioning.blockedEdge(first, second)
    if first == nil or second == nil or first:getZ() ~= second:getZ() then return false end
    local dx, dy = math.abs(first:getX()-second:getX()), math.abs(first:getY()-second:getY())
    if dx > 1 or dy > 1 or dx+dy == 0 then return false end
    local ok,blocked=pcall(function() return first:isBlockedTo(second) end)
    if not ok or blocked then return true end
    local hopOk,hoppable=pcall(function() return first:isHoppableTo(second) end)
    return hopOk and hoppable==true
end

-- Only a still-loaded, cardinal edge with explicit native clearance in both
-- directions can release a hold while the actors remain in different rooms.
local function retainedEdgeOpen(held, origin, destination)
    local ok, open = pcall(function()
        local first, second = held.edgeInside, held.edgeOutside
        if first == nil or second == nil or origin == nil or destination == nil then return false end
        local z = first:getZ()
        if second:getZ() ~= z or origin:getZ() ~= z or destination:getZ() ~= z
            or math.abs(first:getX()-second:getX()) + math.abs(first:getY()-second:getY()) ~= 1 then
            return false
        end
        local cell = getCell()
        if cell == nil or cell:getGridSquare(first:getX(),first:getY(),z) ~= first
            or cell:getGridSquare(second:getX(),second:getY(),z) ~= second then return false end
        return first:isBlockedTo(second) == false and second:isBlockedTo(first) == false
            and first:isHoppableTo(second) == false and second:isHoppableTo(first) == false
    end)
    return ok and open == true
end

function Positioning.keepMeleeTarget(distanceSquared, currentPriority, candidatePriority)
    return distanceSquared ~= nil and distanceSquared <= 4
        and (tonumber(currentPriority) or 0) >= (tonumber(candidatePriority) or 0)
end

function Positioning.barrierPolicy(visibleThreats)
    return (tonumber(visibleThreats) or 0) <= 2 and "exit" or "hold"
end

-- A human who is armed changes the geometry of a fight in a way a zombie does
-- not: the open ground between two shooters is where people die. These are the
-- decisions only, kept pure so they can be driven offline; the movement, the
-- rally point and the formation spacing still belong to their existing owners.
function Positioning.humanThreatPolicy(state)
    state = type(state) == "table" and state or {}
    if state.armedHuman ~= true then return "advance" end
    local distanceSquared = tonumber(state.distanceSquared) or 0
    if distanceSquared <= 4 then return "melee" end
    if state.hasCover == true then return "peek" end
    return "cover"
end

-- Two people do not reposition at once. The one without the shot holds the
-- target while the other moves, and only a ready partner may be left covering.
function Positioning.pairRole(state)
    state = type(state) == "table" and state or {}
    if state.selfReady == false then return "hold" end
    if state.partnerReady == true and state.partnerHolding == true then return "move" end
    return "hold"
end

-- Breaking off is not cowardice and not a morale stat: it is what a person does
-- when the fight is already lost. The caller falls back to the rally the alarm
-- already picks, so no second retreat target exists.
function Positioning.breakOff(state)
    state = type(state) == "table" and state or {}
    local health = tonumber(state.health) or 100
    local allies = math.max(1, tonumber(state.allies) or 1)
    local enemies = math.max(1, tonumber(state.enemies) or 1)
    if health <= 35 then return true, "wounded" end
    if state.armed == true and tonumber(state.ammo) ~= nil and tonumber(state.ammo) <= 0 then
        return true, "no_ammo"
    end
    if enemies > allies * 2 then return true, "outnumbered" end
    return false, "fight"
end

-- Cover is map geometry, not room identity. The line between the cover square
-- and the threat is walked one tile at a time, and an anti-diagonal step across a
-- blocked edge counts as obstruction. A square that does not block the threat's
-- own line is not cover, however convenient it looks.
function Positioning.lineBlocked(from, to)
    if from == nil or to == nil or from:getZ() ~= to:getZ() then return false end
    local dx, dy = to:getX() - from:getX(), to:getY() - from:getY()
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps == 0 then return false end
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil then return false end
    local previous = from
    for i = 1, steps do
        local square = cell:getGridSquare(
            from:getX() + math.floor(dx * i / steps + 0.5),
            from:getY() + math.floor(dy * i / steps + 0.5), from:getZ())
        if square == nil then return true end
        if Positioning.blockedEdge(previous, square) then return true end
        previous = square
    end
    return false
end

-- True walls only: a step counts as wall-blocked when the edge reports
-- blocked, is not hoppable, and is not a door, window or window frame in
-- either direction. Doors, windows and fences already have owners (door
-- recovery, window climbs, fence vaults); only a bare wall means there is
-- no approach square worth walking. Anything unreadable fails closed to
-- false so an unknown edge never reroutes a fight.
function Positioning.wallBlockedLine(from, to)
    if from == nil or to == nil or from:getZ() ~= to:getZ() then return false end
    local dx, dy = to:getX() - from:getX(), to:getY() - from:getY()
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps == 0 then return false end
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil then return false end
    local previous = from
    for i = 1, steps do
        local square = cell:getGridSquare(
            from:getX() + math.floor(dx * i / steps + 0.5),
            from:getY() + math.floor(dy * i / steps + 0.5), from:getZ())
        if square == nil then return false end
        if square:getX() ~= previous:getX() or square:getY() ~= previous:getY() then
            local okBlocked, blocked = pcall(function() return previous:isBlockedTo(square) end)
            if okBlocked and blocked == true then
                local okHop, hop = pcall(function() return previous:isHoppableTo(square) end)
                if not (okHop and hop == true) then
                    local okDoor, door = pcall(function()
                        return previous:getDoorTo(square) or square:getDoorTo(previous)
                    end)
                    if not (okDoor and door ~= nil) then
                        local okWin, win = pcall(function()
                            return previous:getWindowTo(square) or square:getWindowTo(previous)
                                or previous:getWindowFrameTo(square) or square:getWindowFrameTo(previous)
                        end)
                        if not (okWin and win ~= nil) then return true end
                    end
                end
            end
            previous = square
        end
    end
    return false
end

function Positioning.coverFaces(cover, threat)
    return cover ~= nil and threat ~= nil and Positioning.lineBlocked(cover, threat)
end

-- The square the fighter steps onto to shoot from cover: one tile out, roughly
-- perpendicular to the threat line, so the peek is out of the wall rather than
-- through it.
function Positioning.peekSquare(cover, threat, free)
    if cover == nil or threat == nil then return nil end
    local dx, dy = threat:getX() - cover:getX(), threat:getY() - cover:getY()
    local length = math.max(1, math.sqrt(dx * dx + dy * dy))
    local px, py = -dy / length, dx / length
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil then return nil end
    for _, sign in ipairs({ 1, -1 }) do
        local square = cell:getGridSquare(cover:getX() + math.floor(px * sign + 0.5),
            cover:getY() + math.floor(py * sign + 0.5), cover:getZ())
        if square ~= nil and square:canStand()
            and (free == nil or free(square, nil) == true)
            and not Positioning.blockedEdge(cover, square) then
            return square
        end
    end
    return nil
end

function Positioning.coverSquare(character, target, free)
    if character == nil or target == nil or getCell == nil then return nil end
    local here = character:getCurrentSquare()
    local there = target:getCurrentSquare()
    if here == nil or there == nil or here:getZ() ~= there:getZ() then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local best, bestDistance = nil, nil
    for dx = -6, 6 do
        for dy = -6, 6 do
            local square = cell:getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
            if square ~= nil and square:canStand() and (free == nil or free(square, character))
                and Positioning.coverFaces(square, there) then
                local distance = dx * dx + dy * dy
                if distance > 0 and distance <= 64
                    and (bestDistance == nil or distance < bestDistance) then
                    best, bestDistance = square, distance
                end
            end
        end
    end
    return best
end

-- Ammo is whatever the fighter is actually carrying: hands, belt, worn
-- containers and nested bags. The engine exposes the same inventory hierarchy
-- the trader and view-model owners already read.
function Positioning.carriedAmmo(character)
    if character == nil then return 0, false end
    local total, armed, seen = 0, false, 0
    local function readItem(item)
        if item == nil or seen >= 200 then return end
        seen = seen + 1
        -- A carried object is not always a Java InventoryItem with these
        -- methods. Calling a missing method threw inside the pcall, and debug
        -- mode logged every caught failure on every combat tick
        -- (console.txt 2026-11-09 03:47: 164 "Tried to call nil" bursts).
        local okCount, count = false, nil
        if item.getCurrentAmmoCount ~= nil then
            okCount, count = pcall(function() return item:getCurrentAmmoCount() end)
        end
        if okCount and tonumber(count) ~= nil then
            armed = true
            total = total + math.max(0, tonumber(count))
        end
        local okInv, inv = false, nil
        if item.getInventory ~= nil then
            okInv, inv = pcall(function() return item:getInventory() end)
        end
        if okInv and inv ~= nil then
            local okItems, items = pcall(function() return inv:getItems() end)
            if okItems and items ~= nil then
                for i = 0, math.min(items:size() - 1, 60) do readItem(items:get(i)) end
            end
        end
    end
    local okInv, inv = pcall(function() return character:getInventory() end)
    if okInv and inv ~= nil then
        local okItems, items = pcall(function() return inv:getItems() end)
        if okItems and items ~= nil then
            for i = 0, items:size() - 1 do readItem(items:get(i)) end
        end
    end
    return total, armed
end

-- One place decides engage, hold, withdraw or rally. Numbers, health and the
-- ammo actually carried feed it; no morale stat is invented.
function Positioning.engageDecision(state)
    state = type(state) == "table" and state or {}
    local enemies = math.max(1, tonumber(state.enemies) or 1)
    local allies = math.max(1, tonumber(state.allies) or 1)
    local health = tonumber(state.health) or 100
    local ammo = tonumber(state.ammo) or 0
    if health <= 35 then return "rally", "wounded" end
    if state.armed == true and ammo <= 0 then return "rally", "no_ammo" end
    if enemies >= allies * 3 then return "rally", "outnumbered" end
    if enemies >= allies * 2 then return "withdraw", "outnumbered" end
    if state.hasCover ~= true and state.armedHuman == true then return "hold", "exposed" end
    return "engage", "fight"
end

function Positioning.squadSpacing(underFire, approach)
    if underFire == true then return 4 end
    if approach == true then return 1 end
    return 2
end

-- Formation slots in plain offsets. The caller keeps the leader body and the
-- existing formation settings; this only answers where member N belongs.
function Positioning.squadSlot(leaderX, leaderY, index, spacing, shape)
    local slot = math.max(1, tonumber(index) or 1) - 1
    local step = math.max(1, tonumber(spacing) or 2)
    local x, y = tonumber(leaderX) or 0, tonumber(leaderY) or 0
    if slot == 0 then return x, y end
    shape = tostring(shape or "column")
    if shape == "line" then return x + slot * step, y end
    if shape == "wedge" then
        local side = slot % 2 == 0 and 1 or -1
        return x + math.ceil(slot / 2) * step, y + side * step
    end
    return x, y + slot * step
end

local function exitSquare(character, target, openingAllowed, free)
    local origin = character:getCurrentSquare()
    local room = origin:getRoom()
    if room == nil then return nil end
    local squares, best, score = room:getSquares(), nil, nil
    for i = 0, math.min(squares:size()-1,255) do
        local inside = squares:get(i)
        if inside:getZ() == origin:getZ() then
            for _, offset in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                local outside = getCell():getGridSquare(inside:getX()+offset[1], inside:getY()+offset[2], inside:getZ())
                if outside ~= nil and outside:getRoom() == nil and outside:canStand() and free(outside,character) then
                    local door = inside:getDoorTo(outside) or outside:getDoorTo(inside)
                    if door ~= nil and not door:isBarricaded()
                        and (door:IsOpen() or (openingAllowed and not door:isLocked())) then
                        local d = (outside:getX()-origin:getX())^2+(outside:getY()-origin:getY())^2
                        if d<=144 and (score == nil or d < score) then best,score=outside,d end
                    end
                end
            end
        end
    end
    return best
end

-- One step of human-on-human positioning, called before the room/barrier path.
-- Returning false leaves every existing rule untouched, which is what keeps a
-- zombie fight on exactly the code it had before.
function Positioning.humanCombatStep(controller, target, ticks, context)
    if controller == nil or controller.character == nil or target == nil then return false end
    local character = controller.character
    local here = character:getCurrentSquare()
    local there = target:getCurrentSquare()
    if here == nil or there == nil then return false end
    local health = 100
    local okHealth, raw = pcall(function() return character:getHealth() end)
    if okHealth and tonumber(raw) ~= nil then
        health = tonumber(raw) <= 1 and math.floor(tonumber(raw) * 100) or math.floor(tonumber(raw))
    end
    -- Ammo is read from whatever the fighter carries, not just the hand: a
    -- reserve magazine in a pack is still rounds that can be fired.
    local ammo, armed = Positioning.carriedAmmo(character)
    -- Allies are the party the controller already belongs to: a base roster or
    -- the travel group's size. A hostile group counts exactly like a resident one.
    local allies = 1
    local groupSize = tonumber(controller.groupSize)
    if groupSize ~= nil then allies = math.max(1, groupSize) end
    local persistence = rawget(_G, "KnoxPersistence")
    if controller.baseId ~= nil and persistence ~= nil and persistence.getBaseResidentIds ~= nil then
        local ids = persistence.getBaseResidentIds(controller.baseId)
        if type(ids) == "table" then allies = math.max(allies, #ids) end
    end
    -- Every enemy the resident believes is in the fight counts, not a hardcoded
    -- one, and the hostile group is read from the same perception memory the
    -- threat scan already fills.
    local enemies = 0
    if controller.perceivedThreats ~= nil then
        for _ in pairs(controller.perceivedThreats) do enemies = enemies + 1 end
    end
    if enemies == 0 then enemies = 1 end
    -- The target's own group counts too, so a hostile group is never read as a
    -- single body. The runtime already owns that lookup.
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.idForCharacter ~= nil and runtime.getController ~= nil then
        local okTarget, targetId = pcall(runtime.idForCharacter, target)
        local owner = okTarget and targetId ~= nil and runtime.getController(targetId) or nil
        local strength = owner ~= nil and tonumber(owner.groupSize) or nil
        if strength ~= nil and strength > enemies then enemies = strength end
    end
    local distance = (here:getX() - there:getX()) ^ 2 + (here:getY() - there:getY()) ^ 2
    local cover = Positioning.coverSquare(character, target, context.free)
    local armedHuman = armed or target.isArmed == true
    local policy, reason = Positioning.engageDecision({
        enemies = enemies, allies = allies, health = health,
        armed = armed, ammo = ammo, hasCover = cover ~= nil, armedHuman = armedHuman,
    })
    local alarm = { x = there:getX(), y = there:getY(), z = there:getZ() }
    if policy == "rally" then
        if controller.withdrawToRally ~= nil and controller:withdrawToRally(ticks, alarm) then
            controller.activeDecision = "base_break_off"
            controller.breakOffReason = reason
            return true
        end
        return false
    end
    if policy == "withdraw" then
        local retreat = cover or Positioning.peekSquare(here, there, context.free)
        if retreat ~= nil then
            local result = tostring(controller.bridge:moveNpc(controller.id, retreat))
            if result:find("MOVE_STARTED", 1, true) == 1 then
                controller.activeDecision = "combat_withdraw"
                controller.breakOffReason = reason
                return true
            end
        end
        if controller.withdrawToRally ~= nil and controller:withdrawToRally(ticks, alarm) then
            controller.activeDecision = "base_break_off"
            controller.breakOffReason = reason
            return true
        end
        return false
    end
    if policy == "engage" and cover ~= nil then
        -- Step out of cover to shoot, then the existing combat path resumes on
        -- the next tick. The peek is a square, never a teleport.
        local peek = Positioning.peekSquare(cover, there, context.free)
        local step = peek or cover
        local result = tostring(controller.bridge:moveNpc(controller.id, step))
        if result:find("MOVE_STARTED", 1, true) == 1 then
            controller.activeDecision = "combat_take_cover"
            return true
        end
    end
    if policy == "hold" and cover ~= nil then
        local result = tostring(controller.bridge:moveNpc(controller.id, cover))
        if result:find("MOVE_STARTED", 1, true) == 1 then
            controller.activeDecision = "combat_hold_cover"
            return true
        end
    end
    return false
end

function Positioning.install(Controller, context)
    function Controller:handleCombatBarrier(ticks)
        local target = self.combatTarget
        local origin = self.character:getCurrentSquare()
        local destination = target ~= nil and target:getCurrentSquare() or nil
        local held = self.combatBarrier
        if target ~= nil and target.isZombie ~= nil and target:isZombie() == false
            and Positioning.humanCombatStep(self, target, ticks, context) then
            return true
        end
        if origin == nil or destination == nil or target:isDead()
            or origin:getZ() ~= destination:getZ()
            or (origin:getX()-destination:getX())^2+(origin:getY()-destination:getY())^2 > 144 then
            if held ~= nil then
                self.bridge:cancelNpcMove(self.id)
                self:releaseCombat()
                self:finishDecision(ticks)
                return true
            end
            return false
        end
        if held ~= nil and held.target ~= target then self.combatBarrier=nil; held=nil end
        if held ~= nil and held.mode == "exit" then
            local movement = tostring(self.bridge:tickNpc(self.id))
            if movement:find("Succeeded",1,true) or ticks-held.started > 300
                or movement:find("Failed",1,true) then
                self.bridge:cancelNpcMove(self.id)
                self.combatBarrier=nil
                if movement:find("Succeeded",1,true) then self:beginCombat(target)
                else self.combatBarrier={ target=target, mode="hold", started=ticks,
                    edgeInside=held.edgeInside, edgeOutside=held.edgeOutside } end
            end
            return true
        end
        if held ~= nil then
            if held.backing then
                local movement=tostring(self.bridge:tickNpc(self.id))
                if movement:find("Succeeded",1,true) or movement:find("Failed",1,true)
                    or ticks-held.started>300 then
                    held.backing=nil
                    self.bridge:cancelNpcMove(self.id)
                end
            end
            -- A climb must actually cross the native collision boundary before
            -- normal attacks resume. No hit or knockdown is granted by this wait.
            if (origin:getRoom() == destination:getRoom()
                and not Positioning.blockedEdge(origin,destination))
                or retainedEdgeOpen(held, origin, destination) then
                self.bridge:cancelNpcMove(self.id)
                self.combatBarrier=nil
                self:beginCombat(target)
            end
            return true
        end
        if not Positioning.blockedEdge(origin,destination) then return false end
        local visible = 0
        local cell = getCell()
        local awareness = rawget(_G, "KnoxZombieAwareness")
        local zombies = awareness ~= nil and awareness.zombieList ~= nil
            and awareness.zombieList(cell, ticks) or cell:getZombieList()
        for i=0,zombies:size()-1 do
            local zombie=zombies:get(i)
            if not zombie:isDead() and self.character:CanSee(zombie)
                and zombie:getZ()==origin:getZ()
                and (zombie:getX()-origin:getX())^2+(zombie:getY()-origin:getY())^2 <= 64 then
                visible=visible+1
                if visible>2 then break end
            end
        end
        self.bridge:resetNpcCombat(self.id)
        self.bridge:cancelNpcMove(self.id)
        local exit = Positioning.barrierPolicy(visible)=="exit"
            and exitSquare(self.character,target,context.canOpen(self),context.free) or nil
        local record={target=target,mode="hold",started=ticks,edgeInside=origin,edgeOutside=destination}
        self.combatBarrier=record
        if exit ~= nil then
            local result=tostring(self.bridge:moveNpc(self.id,exit))
            if result:find("MOVE_STARTED",1,true)==1 then record.mode="exit" end
        else
            -- Give the crossing room without backing through a wall or another body.
            local dx=origin:getX()-destination:getX()
            local dy=origin:getY()-destination:getY()
            local back=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
            if back ~= nil and back:getRoom()==origin:getRoom() and back:canStand()
                and context.free(back,self.character)
                and not Positioning.blockedEdge(origin,back) then
                local result=tostring(self.bridge:moveNpc(self.id,back))
                record.backing=result:find("MOVE_STARTED",1,true)==1
            end
        end
        return true
    end
end

return Positioning
