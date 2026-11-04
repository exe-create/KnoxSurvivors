-- PT-12 house clearing: room planning, room-scoped directives, guard,
-- live reassignment, verified find lines, cancellation and ending once.
-- No native body or world is created; every engine object below is a facade.

local House = KnoxHouseClearing
assert(type(House) == "table", "house clearing module loads")
House.reset()

local age = 12
local feedLines = {}
local duties = {}
local issued = {}
local issuedCounter = 0
local companions = {}
local characters = {}
local ownBase = nil
local refuseIssues = {}
local playerSquare = nil
local player = nil
local building = nil

KnoxActivityFeed = {
    event = function(text) feedLines[#feedLines + 1] = tostring(text) end,
    speak = function() end,
}

local function containerObject(kind)
    local container = {
        isExistYet = function() return true end,
        getType = function() return kind or "counter" end,
        getSourceGrid = function() return nil end,
    }
    local object = {
        getContainerCount = function() return 1 end,
        getContainerByIndex = function() return container end,
    }
    return object, container
end

local function squareAt(x, y, z, kind)
    local object, container = containerObject(kind or "counter")
    local objects = {
        size = function() return 1 end,
        get = function(_, index) return object end,
    }
    local square = {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        getObjects = function() return objects end,
        getRoom = function() return nil end,
    }
    local source = {
        getRoom = function()
            return { getName = function() return "kitchen" end }
        end,
    }
    container.getSourceGrid = function() return source end
    square.container = container
    return square
end

local squares = {}
local function gridKey(x, y, z) return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z) end
local function putSquare(x, y, z)
    squares[gridKey(x, y, z)] = squareAt(x, y, z)
end

local function rect(x, y, w, h)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getW = function() return w end,
        getH = function() return h end,
    }
end

local function rectList(rects)
    return {
        size = function() return #rects end,
        get = function(_, index) return rects[index + 1] end,
    }
end

local function room(name, x, y, w, h, z, containerKind)
    local bounds = rect(x, y, w, h)
    if containerKind ~= false then
        squares[gridKey(x, y, z)] = squareAt(x, y, z, containerKind)
    end
    return {
        getName = function() return name end,
        getZ = function() return z end,
        getRects = function() return rectList({ bounds }) end,
    }
end

local function roomList(rooms)
    return {
        size = function() return #rooms end,
        get = function(_, index) return rooms[index + 1] end,
    }
end

local kitchen = room("kitchen", 10, 10, 4, 4, 0, "counter")
local bedroom = room("bedroom", 14, 10, 4, 4, 0, "dresser")
local study = room("study", 14, 14, 3, 3, 0, "desk")
local bathroom = room("bathroom", 10, 14, 3, 3, 0, "water")
local rooms = roomList({ kitchen, bedroom, study, bathroom })

building = {
    getDef = function()
        return {
            getID = function() return "willow-house" end,
            getName = function() return "Willow Street House" end,
        }
    end,
    getRooms = function() return rooms end,
}

playerSquare = {
    getX = function() return 11 end,
    getY = function() return 11 end,
    getZ = function() return 0 end,
    getBuilding = function() return building end,
}

player = {
    getCurrentSquare = function() return playerSquare end,
    getPlayerNum = function() return 0 end,
}

getGameTime = function()
    return { getWorldAgeHours = function() return age end }
end

getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return squares[gridKey(x, y, z)] end,
    }
end

getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return player end

local names = { a = "Iris", b = "Owen", c = "Mara", d = "Rook", e = "Pike" }

KnoxPersistence = {
    getPlayerId = function() return "player-1" end,
    getSurvivorIdentity = function(id)
        return { forename = names[id] or id, surname = "Voss" }
    end,
    getSurvivorDuty = function(id)
        if duties[id] == nil then duties[id] = { mode = "companion" } end
        return duties[id]
    end,
    clearCompanionDirective = function(id)
        if duties[id] ~= nil then duties[id].directive = nil end
        return true
    end,
    isSurvivorAlive = function() return true end,
    getBaseAtSquare = function() return ownBase end,
}

KnoxSurvivorRuntime = {
    getCharacter = function(id) return characters[id] end,
}

local function character(id, health)
    local square = { getX = function() return 11 end, getY = function() return 11 end,
        getZ = function() return 0 end }
    local inventory = {
        getWeight = function() return 5 end,
        getCapacityWeight = function() return 40 end,
    }
    local body = {
        id = id,
        getCurrentSquare = function() return square end,
        isDead = function() return false end,
        getHealth = function() return health or 80 end,
        getInventory = function() return inventory end,
    }
    characters[id] = body
    return body
end

KnoxCompanionService = {
    getPlayerId = function() return "player-1" end,
    resolvePlayer = function(id) if id == "player-1" then return player end return nil end,
    getCompanionIds = function() return companions end,
    issueDirective = function(_, id, directive)
        if refuseIssues[id] then return false, "no_contact" end
        issuedCounter = issuedCounter + 1
        local copy = {}
        for key, value in pairs(directive) do copy[key] = value end
        copy.issuedAtHours = age + issuedCounter / 100000
        duties[id] = duties[id] or { mode = "companion" }
        duties[id].directive = copy
        issued[#issued + 1] = { id = id, directive = copy }
        return true, "accepted"
    end,
    clearDirective = function(_, id)
        if duties[id] ~= nil then duties[id].directive = nil end
        return true, "cleared"
    end,
}

local function resetWorld()
    House.reset()
    age = 12
    feedLines = {}
    duties = {}
    issued = {}
    issuedCounter = 0
    companions = { "a", "b" }
    characters = {}
    ownBase = nil
    refuseIssues = {}
    playerSquare = {
        getX = function() return 11 end,
        getY = function() return 11 end,
        getZ = function() return 0 end,
        getBuilding = function() return building end,
    }
    character("a", 80)
    character("b", 70)
end

local function lastLine()
    return feedLines[#feedLines] or ""
end

-- Planning: three real rooms, one water-only bathroom excluded, sorted by
-- distance from the player. Two companions both search and one room queues.
resetWorld()
assert(type(getCell) == "function", "fixture cell is available")
assert(getCell():getGridSquare(10, 10, 0) ~= nil, "fixture kitchen square exists")
local debugRooms = building:getRooms()
assert(debugRooms:size() == 4, "fixture room list has four entries")
assert(debugRooms:get(0) ~= nil, "fixture first room is readable")
local plan, reason = House.plan(player)
assert(plan ~= nil, "plan exists: " .. tostring(reason))
assert(#plan.rooms == 3, "water-only bathroom is not a search room: " .. tostring(#plan.rooms))
assert(plan.rooms[1].name == "kitchen", "nearest room is first")
assert(#plan.searchers == 2 and #plan.guards == 0, "two companions both search")
assert(#plan.roomQueue == 1, "third room waits for a free searcher")
assert(plan.label == "Willow Street House", "plan names the building")

-- Three companions: one healthy guard, two searchers, one room queued.
resetWorld()
companions = { "a", "b", "c" }
character("c", 100)
local guarded = assert(House.plan(player))
assert(#guarded.guards == 1 and guarded.guards[1].id == "c",
    "healthiest companion guards")
assert(#guarded.searchers == 2 and #guarded.roomQueue == 1,
    "guard does not replace a searcher seat")

-- Four companions and three rooms: one guard, three searchers, no queue.
resetWorld()
companions = { "a", "b", "c", "d" }
character("c", 100)
character("d", 60)
local full = assert(House.plan(player))
assert(#full.guards == 1 and #full.searchers == 3 and #full.roomQueue == 0,
    "one guard plus one searcher per room")

-- Five companions are capped at four; the closest four take the order.
resetWorld()
companions = { "a", "b", "c", "d", "e" }
character("c", 100)
character("d", 60)
character("e", 50)
local capped = assert(House.plan(player))
assert(#capped.searchers + #capped.guards == House.MAX_PARTY,
    "party is capped at four")

-- Own base is never stripped by a house sweep.
resetWorld()
ownBase = { ownerKind = "player" }
local refused, ownReason = House.plan(player)
assert(refused == nil and ownReason == "own_base", "own base refuses")
ownBase = nil

-- No building and no companion are named refusals, not silent no-ops.
resetWorld()
local outside = {
    getX = function() return 100 end, getY = function() return 100 end,
    getZ = function() return 0 end, getBuilding = function() return nil end,
}
playerSquare = outside
local noBuilding, noBuildingReason = House.plan(player, outside)
assert(noBuilding == nil and noBuildingReason == "no_building", "no building refuses")
resetWorld()
companions = {}
local noParty, noPartyReason = House.plan(player)
assert(noParty == nil and noPartyReason == "no_companions", "no companion refuses")

-- Issue: two searchers receive room-bounded loot_building directives, the
-- guard (when present) receives a guard directive at the entry point.
resetWorld()
local started, sweep = House.issue(player)
assert(started == true and House.runtimeSize() == 1, "sweep starts")
assert(#issued == 2, "two search directives were issued")
for _, entry in ipairs(issued) do
    assert(entry.directive.kind == "loot_building", "search uses existing loot directive")
    assert(entry.directive.buildingId == "willow-house", "building is scoped")
    assert(entry.directive.minX ~= nil and entry.directive.maxX ~= nil,
        "room bounds are persisted")
end
assert(#feedLines[1] > 0 and string.find(feedLines[1], "Clearing Willow Street House", 1, true) ~= nil,
    "start line names the building")

-- A verified container receipt produces one aggregated, real find line.
local kit = issued[1] and issued[1].directive
local kitchenContainer = squares[gridKey(10, 10, 0)].container
local controller = {
    id = "a",
    companionOwnerId = "player-1",
    collectionItemReceived = function(_, pending, item) return item.received == true end,
}
local pending = {
    container = kitchenContainer,
    items = {
        { item = { received = true, getName = function() return "Canned Beans" end } },
        { item = { received = true, getName = function() return "Canned Beans" end } },
        { item = { received = true, getName = function() return "Bandage" end } },
    },
}
assert(House.onLootVerified(controller, pending) == true, "verified find is announced")
assert(string.find(lastLine(), "Iris Voss took 2 Canned Beans, Bandage", 1, true) ~= nil,
    "find line aggregates real items: " .. lastLine())
assert(string.find(lastLine(), "kitchen counter", 1, true) ~= nil,
    "find line names room and container")
assert(House.onLootVerified(controller, pending) == false, "same container is not announced twice")

-- A companion who cannot take the first order does not cost the party that
-- room; it joins the queue for the member who did start.
resetWorld()
feedLines = {}
refuseIssues["b"] = true
assert(House.issue(player) == true, "partial party still starts")
assert(#issued == 1, "only the reachable companion was ordered")
assert(duties["b"] == nil or duties["b"].directive == nil,
    "refused companion received no directive")
assert(House.onRoomFinished({ id = "a", companionOwnerId = "player-1" }) == true,
    "reachable searcher can finish its room")
duties["a"].directive = nil
local beforeQueue = #issued
House.coordinate(nil, nil, 15)
assert(#issued == beforeQueue + 1, "a room skipped by the refused companion is queued")
refuseIssues["b"] = false

-- When the controller exhausts a room, the queued room is assigned to that
-- same body; no second looter is created.
resetWorld()
assert(House.issue(player) == true, "reassignment sweep starts")
assert(House.onLootVerified(controller, pending) == true, "reassignment sweep records a find")
local function markExhausted(id)
    return House.onRoomFinished({ id = id, companionOwnerId = "player-1" })
end
local before = #issued
assert(markExhausted("a") == true, "controller reports an exhausted room")
duties["a"].directive = nil
House.coordinate(nil, nil, 15)
assert(#issued == before + 1, "queued room is reassigned")
local reassigned = duties["a"] and duties["a"].directive or nil
assert(reassigned ~= nil and reassigned.kind == "loot_building", "reassignment stays a search")
assert(reassigned.minX == 14 and reassigned.minY == 14, "reassigned to the study bounds")

-- When every searcher is finished, the sweep ends once with a summary.
feedLines = {}
assert(markExhausted("a"), "first searcher finishes")
assert(markExhausted("b"), "second searcher finishes")
duties["a"].directive = nil
duties["b"].directive = nil
House.coordinate(nil, nil, 30)
assert(House.runtimeSize() == 0, "finished sweep is removed")
assert(#feedLines == 1, "one ending line")
assert(string.find(lastLine(), "House swept", 1, true) ~= nil, "ending says swept")
assert(string.find(lastLine(), "3 of 3 rooms searched", 1, true) ~= nil,
    "ending reports room progress: " .. lastLine())
assert(string.find(lastLine(), "3 items taken", 1, true) ~= nil,
    "ending reports real finds")

-- With a guard, finishing clears the guard's directive too.
resetWorld()
companions = { "a", "b", "c", "d" }
character("c", 100)
character("d", 60)
feedLines = {}
assert(House.issue(player) == true, "guarded sweep starts")
assert(duties["c"].directive ~= nil and duties["c"].directive.kind == "guard",
    "guard directive installed")
assert(markExhausted("a"), "guarded searcher a finishes")
assert(markExhausted("b"), "guarded searcher b finishes")
assert(markExhausted("d"), "guarded searcher d finishes")
duties["a"].directive = nil
duties["b"].directive = nil
duties["d"].directive = nil
House.coordinate(nil, nil, 15)
assert(duties["c"].directive == nil, "guard returns to ordinary duty")
assert(House.runtimeSize() == 0, "guarded sweep ends")

-- A full pack releases that member at the room boundary instead of sending
-- them into the next room to fail. The remaining searcher takes the queue.
resetWorld()
feedLines = {}
assert(House.issue(player) == true, "pack-limit sweep starts")
local fullPack = { getWeight = function() return 40 end,
    getCapacityWeight = function() return 40 end }
characters["a"].getInventory = function() return fullPack end
assert(markExhausted("a"), "full-pack searcher finishes its room")
duties["a"].directive = nil
local beforeFull = #issued
House.coordinate(nil, nil, 15)
assert(duties["a"].directive == nil, "full pack is not sent to another room")
assert(#issued == beforeFull, "no new directive is issued to a full pack")
assert(string.find(table.concat(feedLines, "|"), "Iris Voss's pack is full", 1, true) ~= nil,
    "release names the full pack: " .. table.concat(feedLines, " | "))
assert(House.onRoomFinished({ id = "b", companionOwnerId = "player-1" }) == true,
    "remaining searcher can finish")
duties["b"].directive = nil
House.coordinate(nil, nil, 15)
assert(House.runtimeSize() == 1, "remaining searcher takes the queued room")
assert(duties["b"].directive ~= nil and duties["b"].directive.kind == "loot_building",
    "queue is assigned to a searcher with room")
House.cancel(player, "cancelled")

-- When every remaining searcher is full and a room is queued, the ending names
-- the pack limit instead of claiming the rooms were unreachable.
resetWorld()
feedLines = {}
assert(House.issue(player) == true, "all-full sweep starts")
characters["a"].getInventory = function() return fullPack end
characters["b"].getInventory = function() return fullPack end
assert(markExhausted("a"), "first full searcher finishes")
assert(markExhausted("b"), "second full searcher finishes")
duties["a"].directive = nil
duties["b"].directive = nil
House.coordinate(nil, nil, 15)
assert(House.runtimeSize() == 0, "all-full sweep ends")
assert(string.find(lastLine(), "packs are full", 1, true) ~= nil,
    "ending names the pack limit: " .. lastLine())

-- A new player order owns the body: the sweep stops, and that new order is
-- not cleared by the ending cleanup.
resetWorld()
feedLines = {}
assert(House.issue(player) == true, "cancellation sweep starts")
duties["a"].directive = { kind = "hold", issuedAtHours = 999 }
House.coordinate(nil, nil, 15)
assert(House.runtimeSize() == 0, "new order stops the sweep")
assert(duties["a"].directive.kind == "hold", "new order survives cleanup")
assert(duties["b"].directive == nil, "other member returns to ordinary duty")
assert(string.find(lastLine(), "new order took over", 1, true) ~= nil,
    "ending names the interruption: " .. lastLine())

-- A player-cleared directive is also nil, but it must not be mistaken for a
-- finished room and replaced with queued work.
resetWorld()
feedLines = {}
assert(House.issue(player) == true, "nil-clear sweep starts")
duties["a"].directive = nil
House.coordinate(nil, nil, 15)
assert(House.runtimeSize() == 0, "nil clear stops the sweep")
assert(duties["a"].directive == nil, "nil clear is not replaced by a room")
assert(string.find(lastLine(), "new order took over", 1, true) ~= nil,
    "nil clear is treated as a player order: " .. lastLine())

-- Timeout and player leaving are bounded endings, not immortal sweeps.
resetWorld()
assert(House.issue(player) == true, "timeout sweep starts")
age = age + House.MAX_HOURS + 0.1
House.coordinate(nil, nil, 15)
assert(House.runtimeSize() == 0 and string.find(lastLine(), "took too long", 1, true) ~= nil,
    "timeout ends the sweep")

resetWorld()
assert(House.issue(player) == true, "leash sweep starts")
playerSquare = {
    getX = function() return 100 end,
    getY = function() return 100 end,
    getZ = function() return 0 end,
    getBuilding = function() return nil end,
}
House.coordinate(nil, nil, 15)
assert(House.runtimeSize() == 0 and string.find(lastLine(), "moved too far away", 1, true) ~= nil,
    "player leaving the leash ends the sweep with the real reason: " .. lastLine())

-- A missing body names the person and keeps a verb in the sentence.
resetWorld()
feedLines = {}
assert(House.issue(player) == true, "member-loss sweep starts")
characters["a"] = nil
House.coordinate(nil, nil, 15)
assert(House.runtimeSize() == 0, "member loss ends the sweep")
assert(string.find(lastLine(), "Iris Voss was lost", 1, true) ~= nil,
    "member loss names the person: " .. lastLine())

-- Menu-facing availability is a named refusal, not a silent disabled row.
resetWorld()
local can, canReason = House.canIssue(player)
assert(can == true and canReason == nil, "available inside a searchable house")
ownBase = { ownerKind = "player" }
local cannot, cannotReason = House.canIssue(player)
assert(cannot == false and cannotReason == "own_base", "availability names own base")
ownBase = nil

print("House clearing PASS rooms=3 guard=true reassign=true finds=true cancel=true timeout=true")
