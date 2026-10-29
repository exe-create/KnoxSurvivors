local LifecyclePolicy = rawget(_G, "KnoxSurvivorLifecyclePolicy") or {}
_G.KnoxSurvivorLifecyclePolicy = LifecyclePolicy

-- Only successful square and containing-chunk lookups can establish that the
-- actor has left loaded terrain. A missing API or failed lookup is
-- unknown, not permission to remove a live body.
function LifecyclePolicy.detachedTileLoaded(character)
    local ok, loaded = pcall(function()
        if character == nil or getCell == nil then return nil end
        local cell = getCell()
        if cell == nil then return nil end
        local x, y, z = character:getX(), character:getY(), character:getZ()
        for _, value in ipairs({x, y, z}) do
            if type(value) ~= "number" or value ~= value
                or value == math.huge or value == -math.huge then return nil end
        end
        if x == nil or y == nil or z == nil then return nil end
        x, y, z = math.floor(x), math.floor(y), math.floor(z)
        if z < -32 or z > 31 then return nil end
        if cell:getGridSquare(x, y, z) ~= nil then return true end
        -- A loaded chunk can have no square at this floor. That is not an
        -- unload: let native traversal/falling recover without removing it.
        return cell:getChunkForGridSquare(x, y, z) ~= nil
    end)
    if not ok then return nil end
    return loaded
end

function LifecyclePolicy.detachedDecision(
    finiteDistanceSquared,
    activeDistanceSquared,
    grace,
    graceLimit,
    tileLoaded,
    recognizedTransient
)
    if recognizedTransient == true then
        return false, "preserve-native-transient"
    end
    grace = math.max(1, math.floor(tonumber(grace) or 1))
    graceLimit = math.max(1, math.floor(tonumber(graceLimit) or 1))
    if finiteDistanceSquared == nil then
        return true, "hibernate-no-finite"
    end
    if finiteDistanceSquared > activeDistanceSquared then
        return true, "hibernate-far"
    end
    -- Player distance is not the loaded-cell boundary. Independent survivors
    -- can leave streamed terrain while still inside the encounter radius.
    -- Preserve a grace interval, then hand an absent tile to the existing
    -- capture/store/remove owner; loaded or unknown tiles retain native recovery.
    if grace >= graceLimit then
        if tileLoaded == false then return true, "hibernate-unloaded-tile" end
        return false, "preserve-near-detached"
    end
    return false, "preserve-grace"
end

function LifecyclePolicy.distanceEligible(
    isWorldSurvivor,
    dutyMode,
    distanceSquared,
    activeDistanceSquared
)
    return isWorldSurvivor == true
        and dutyMode ~= "companion"
        and distanceSquared ~= nil
        and distanceSquared > activeDistanceSquared
end

function LifecyclePolicy.companionDetachedDecision(
    recognizedTransient,
    finiteDistanceSquared,
    activeDistanceSquared,
    grace,
    graceLimit
)
    if recognizedTransient == true then
        return false, "preserve-native-transient"
    end
    grace = math.max(1, math.floor(tonumber(grace) or 1))
    graceLimit = math.max(1, math.floor(tonumber(graceLimit) or 1))
    if finiteDistanceSquared == nil then
        return true, "hibernate-no-finite"
    end
    if finiteDistanceSquared > activeDistanceSquared then
        return true, "hibernate-far"
    end
    if grace >= graceLimit then
        return true, "hibernate-stale-companion"
    end
    return false, "preserve-companion-grace"
end

-- A just-streamed-out square can briefly resolve again at the cell edge.
-- Wait for a closer player or a bounded retry instead of rebuilding repeatedly.
function LifecyclePolicy.restoreAfterDetach(detachedAt, ticks, distanceSquared)
    return detachedAt == nil or ticks < detachedAt or ticks - detachedAt >= 900
        or (distanceSquared ~= nil and distanceSquared <= 64 * 64)
end

return LifecyclePolicy
