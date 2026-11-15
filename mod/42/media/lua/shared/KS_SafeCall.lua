-- Protected, single-result method dispatch for engine objects.
-- Nil guards avoid needless engine diagnostics. Lookup and invocation still
-- need pcall: either can fail. Installed KahluaThread.pcall(int) catches
-- java.lang.Throwable; an engine stack trace is not proof pcall was bypassed.
--
-- USAGE:
--   local value, reason, name = KS_SafeCall.invoke(obj, "methodName", arg1, arg2)
--   if value == nil and reason == "nil_target" then
--       -- handle the missing target cleanly
--   end
--
-- RETURN SHAPE:
--   (value,    nil,         methodName)   -- success
--   (nil,      "nil_target", methodName) -- obj was nil
--   (nil,      "nil_method", methodName) -- obj[methodName] was nil
--   (nil,      "lua_error",  methodName, err) -- lookup or invocation failed
--
-- DO NOT use this for cases where nil dispatch is already impossible
-- (literal string methods, module-level functions). Keep `safe(fn, fb)` for
-- those - `KS_SafeCall.invoke` is specifically for engine-returned objects.
local KS_SafeCall = {}

function KS_SafeCall.invoke(obj, methodName, ...)
    if obj == nil then
        return nil, "nil_target", methodName
    end
    local lookedUp, method = pcall(function() return obj[methodName] end)
    if not lookedUp then return nil, "lua_error", methodName, method end
    if method == nil then
        return nil, "nil_method", methodName
    end
    local success, value = pcall(method, obj, ...)
    if not success then return nil, "lua_error", methodName, value end
    return value, nil, methodName
end

function KS_SafeCall.isUsable(obj, predicate, fallback)
    if obj == nil then return fallback end
    local success, value = pcall(predicate, obj)
    if not success or value == nil then return fallback end
    return value
end

return KS_SafeCall
