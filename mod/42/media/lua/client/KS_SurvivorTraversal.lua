-- Vertical traversal for survivors. Ladders and sheet ropes use the same vanilla
-- timed actions the player uses (ISClimbLadderAction, ISClimbSheetRopeAction),
-- and forced entry uses the Build 42 crowbar action (ISForceOpen). API names and
-- the equip order are taken from the installed game:
--   media/lua/client/ISUI/ISWorldObjectContextMenu.lua  onClimbLadder :2182,
--   onForceOpen :2310; media/lua/client/TimedActions/ISClimbLadderAction.lua,
--   ISClimbSheetRopeAction.lua, ISForceOpen.lua.
local Traversal = {}

-- Which way up the survivor is going, from the floor it stands on to the goal.
function Traversal.climbDirection(currentZ, goalZ)
    local from, to = tonumber(currentZ), tonumber(goalZ)
    if from == nil or to == nil then return nil end
    if to == from then return nil end
    return to < from and "down" or "up"
end

-- Ladder first: it is the built object and never runs out. A sheet rope is the
-- improvised fallback, exactly the order the player's own context menu uses.
function Traversal.climbChoice(hasLadder, hasRope)
    if hasLadder == true then return "ladder" end
    if hasRope == true then return "rope" end
    return nil
end

function Traversal.ladderFor(character, square, down)
    if character == nil or square == nil then return nil end
    local ok, ladder
    if down == true then
        if character.getClimbLadderDown == nil then return nil end
        ok, ladder = pcall(function() return character:getClimbLadderDown(square) end)
    else
        if character.getClimbLadder == nil then return nil end
        ok, ladder = pcall(function() return character:getClimbLadder(square) end)
    end
    return ok and ladder or nil
end

function Traversal.ropeAvailable(character, square, down)
    if character == nil or square == nil then return false end
    local ok, can
    if down == true then
        if character.canClimbDownSheetRope == nil then return false end
        ok, can = pcall(function() return character:canClimbDownSheetRope(square) end)
    else
        if character.canClimbSheetRope == nil then return false end
        ok, can = pcall(function() return character:canClimbSheetRope(square) end)
    end
    return ok and can == true
end

-- Queue the real climb. Returns true only when a native action was queued.
function Traversal.beginClimb(character, square, goalZ)
    if character == nil or square == nil then return false, "no_character" end
    local direction = Traversal.climbDirection(square:getZ(), goalZ)
    if direction == nil then return false, "same_floor" end
    local down = direction == "down"
    local ladder = Traversal.ladderFor(character, square, down)
    local kind = Traversal.climbChoice(
        ladder ~= nil, Traversal.ropeAvailable(character, square, down)
    )
    if kind == nil then return false, "no_climbable" end
    if ISTimedActionQueue == nil then return false, "no_action_queue" end
    if kind == "ladder" then
        if ISClimbLadderAction == nil then return false, "no_ladder_action" end
        ISTimedActionQueue.add(ISClimbLadderAction:new(character, down, ladder))
        return true, down and "ladder_down" or "ladder_up"
    end
    if ISClimbSheetRopeAction == nil then return false, "no_rope_action" end
    ISTimedActionQueue.add(ISClimbSheetRopeAction:new(character, down))
    return true, down and "rope_down" or "rope_up"
end

local function usableTool(item)
    if item == nil then return false end
    local ok, broken = pcall(function() return item:isBroken() end)
    return ok and broken ~= true
end

-- The installed context menu reaches for the first unbroken crowbar in the
-- player's inventory by item tag; use the same tag so forged crowbars count.
function Traversal.findCrowbar(character)
    local inventory = character ~= nil and character:getInventory() or nil
    if inventory == nil or inventory.getFirstTagEvalRecurse == nil then return nil end
    if ItemTag == nil or ItemTag.CROWBAR == nil then return nil end
    local ok, item = pcall(function()
        return inventory:getFirstTagEvalRecurse(ItemTag.CROWBAR, usableTool)
    end)
    return ok and item or nil
end

-- Equip the pry bar the way the player's forced-entry action expects, then hand
-- the object to the vanilla action. No hand-rolled pry animation.
function Traversal.beginForceOpen(character, object)
    if character == nil or object == nil then return false, "no_object" end
    if ISForceOpen == nil or ISTimedActionQueue == nil then return false, "no_force_action" end
    local crowbar = Traversal.findCrowbar(character)
    if crowbar == nil then return false, "no_crowbar" end
    if character.setPrimaryHandItem ~= nil then
        pcall(function() character:setPrimaryHandItem(crowbar) end)
    end
    ISTimedActionQueue.add(ISForceOpen:new(character, object))
    return true, "force_open"
end

KnoxSurvivorTraversal = Traversal
return Traversal
