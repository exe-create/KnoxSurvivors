local call = assert(codecSafeMethod)
local body = { value = 7 }
function body:read(delta, absent, last)
    assert(absent == nil and last == 9, "varargs retain their nil slot")
    return self.value + delta, "second-return"
end
assert(call(body, "read", -1, 2, nil, 9) == 9, "method keeps its receiver and first return")
assert(call(nil, "read", -1) == -1, "nil owner keeps the fallback")
assert(call(body, "missing", -1) == -1, "absent method keeps the fallback")
body.notCallable = 42
assert(call(body, "notCallable", -1) == -1)
body.read = function() error("native boundary failure") end
assert(call(body, "read", -1) == -1, "method errors remain protected")
body.read = function() return nil end
assert(call(body, "read", -1) == -1)
body.read = function() return false end
assert(call(body, "read", true) == false, "false is a real result")
body.read = function() return 0 end
assert(call(body, "read", -1) == 0, "zero is a real result")
local unreadable = setmetatable({}, { __index = function() error("native lookup failure") end })
assert(call(unreadable, "read", -1) == -1, "lookup errors remain protected")
local reads = 0
local changing = setmetatable({}, { __index = function()
    reads = reads + 1
    local version = reads
    return function() return version end
end })
assert(call(changing, "read", -1) == 1 and call(changing, "read", -1) == 2,
    "method lookup stays live; no stale binding cache")

-- Count the protected accessor's identity across a realistic repeated workload.
local oldPcall = pcall
local accessors, lookups = {}, 0
local workload = { read = function(self) return self.value end, value = 7 }
pcall = function(fn, ...)
    if fn ~= workload.read then accessors[fn] = true; lookups = lookups + 1 end
    return oldPcall(fn, ...)
end
local sum = 0
for i = 1, 1024 do sum = sum + call(workload, "read", -1) end
pcall = oldPcall
local distinct = 0
for _ in pairs(accessors) do distinct = distinct + 1 end
assert(sum == 7168 and lookups == 1024, "all live lookups and results are preserved")
assert(distinct == 1, "repeated protected lookups reuse one accessor closure")
print("Protected method lookup PASS live_reads=1024 distinct_accessors=1 errors=true fallback=true varargs=true")
