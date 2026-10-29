local TAG = "[KnoxSurvivors][Bridge]"
local MAX_ATTEMPTS = 600

local state = {
    attempts = 0,
    complete = false,
}

local retryTick

local function stopRetrying()
    if retryTick ~= nil and Events.OnTick ~= nil then
        Events.OnTick.Remove(retryTick)
    end
end

local function tryBridge()
    if state.complete then
        return true
    end

    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil and KnoxRuntimeApi ~= nil then
        local ok, exposed = pcall(function() return KnoxRuntimeApi.getBridge() end)
        if ok and exposed ~= nil then
            bridge = exposed
            rawset(_G, "KnoxJavaBridge", bridge)
        end
    end
    if bridge == nil then
        return false
    end

    local success, result = pcall(function()
        local ping = bridge:ping()
        local version = bridge:getRuntimeVersion()
        local loaded = bridge:isRuntimeLoaded()
        local count = bridge:getPingCount()

        print(TAG .. " ping=" .. tostring(ping))
        print(TAG .. " version=" .. tostring(version))
        print(TAG .. " loaded=" .. tostring(loaded) .. " count=" .. tostring(count))
        return type(ping) == "string" and loaded == true
    end)

    if not success then
        print(TAG .. " call failed: " .. tostring(result))
        return false
    end

    if result then
        state.complete = true
        print(TAG .. " PASS")
        stopRetrying()
        return true
    end

    return false
end

retryTick = function()
    if tryBridge() then
        return
    end

    state.attempts = state.attempts + 1
    if state.attempts >= MAX_ATTEMPTS then
        print(TAG .. " FAILED bridge was not available before retry limit")
        pcall(function()
            local feed = rawget(_G, "KnoxActivityFeed")
            if feed ~= nil and feed.event ~= nil then
                feed.event("Knox Survivors Java systems are not loaded. "
                    .. "Choose KnoxBridge or a compatible ZombieBuddy build, enable the chosen runtime and Knox Survivors, "
                    .. "and approve the Knox Java package through that runtime. "
                    .. "Restart Project Zomboid after installing or approving the package.")
            end
        end)
        stopRetrying()
    end
end

local function onGameStart()
    if not tryBridge() and Events.OnTick ~= nil then
        Events.OnTick.Add(retryTick)
    end
end

Events.OnGameStart.Add(onGameStart)
