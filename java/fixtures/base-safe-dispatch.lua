local wrappers = assert(baseSafeDispatch)
local names = { "Compound", "CorpseHandling", "Farming", "Repairs", "Woodcutting" }
for _, name in ipairs(names) do
    local call = assert(wrappers[name], name .. " wrapper missing")
    local owner = {}
    local lookupFailure = setmetatable({}, { __index = function() error("lookup failure") end })
    assert(call(lookupFailure, "read") == nil, name .. " protects lookup")
    assert(call(nil, "read") == nil, name .. " handles nil target")
    assert(call(owner, "missing") == nil, name .. " handles missing method")
    owner.read = 42
    assert(call(owner, "read") == nil, name .. " handles non-callable method")
    owner.read = function() error("invocation failure") end
    assert(call(owner, "read") == nil, name .. " protects invocation")
    owner.read = function() return nil end
    assert(call(owner, "read") == nil, name .. " preserves nil")
    owner.read = function() return false end
    local falseResult = call(owner, "read")
    if name == "CorpseHandling" or name == "Woodcutting" then
        assert(falseResult == nil, name .. " collapses false")
    else
        assert(falseResult == false, name .. " preserves false")
    end
    owner.read = function() return true end
    assert(call(owner, "read") == true, name .. " preserves true")
    owner.read = function(self, ...)
        assert(self == owner, name .. " retains receiver")
        if name == "Compound" then
            assert(select("#", ...) == 0, name .. " ignores extra arguments")
        else
            assert(select("#", ...) == 3, name .. " retains argument count")
            local first, middle, last = ...
            assert(first == 2 and middle == nil and last == 9, name .. " retains nil argument")
        end
        return 11, 12
    end
    local first, second = call(owner, "read", 2, nil, 9)
    assert(first == 11 and second == nil, name .. " returns only first result")
end
assert(wrappers.Repairs(false, "read") == nil and wrappers.Repairs(true, "read") == nil,
    "Repairs rejects boolean targets")
print("Base safe dispatch PASS wrappers=5 lookup=true invocation=true false_conventions=true varargs=true")
