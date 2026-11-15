local call = assert(groupSafeProbe.call)
local fallback = {}
local broken = setmetatable({}, { __index = function() error("lookup failure") end })
assert(call(broken, "read", fallback) == fallback, "group lookup returns fallback")
assert(call(nil, "read", fallback) == fallback, "nil target returns fallback")
assert(call({}, "read", fallback) == fallback, "missing method returns fallback")
assert(call({read=12}, "read", fallback) == fallback, "non-callable returns fallback")
assert(call({read=function() error("invoke failure") end}, "read", fallback) == fallback,
    "invocation failure returns fallback")
assert(call({read=function() end}, "read", fallback) == fallback, "nil result returns fallback")
assert(call({read=function() return false end}, "read", fallback) == false, "false is a result")
local owner = {}
owner.read = function(self, ...)
    assert(self == owner and select("#", ...) == 3, "receiver and argument count preserved")
    local first, middle, last = ...
    assert(first == 2 and middle == nil and last == 9, "nil argument preserved")
    return 11, 12
end
local first, second = call(owner, "read", fallback, 2, nil, 9)
assert(first == 11 and second == nil, "single result preserved")
local visits = 0
groupSafeProbe.walk(broken, function() visits=visits+1 end)
assert(visits == 0, "unreadable inventory is skipped")
local item = {getModData=function() return {} end}
local items = {size=function() return 1 end, get=function() return item end}
groupSafeProbe.walk({getItems=function() return items end}, function(found)
    assert(found == item, "real inventory item reaches visitor")
    visits=visits+1
end)
assert(visits == 1, "readable inventory still visited")
print("Group safe dispatch PASS lookup=true fallback=true false=true inventory_walk=true")
