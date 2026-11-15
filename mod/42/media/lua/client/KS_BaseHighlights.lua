require "KS_Persistence"
require "KS_BaseManager"

local Highlights = rawget(_G, "KnoxBaseHighlights") or {}
_G.KnoxBaseHighlights = Highlights

-- Preview and committed corners must use the same loaded grid square.
function Highlights.pickMouseSquare(player)
    local cell = getCell ~= nil and getCell() or nil
    local current = player ~= nil and player.getCurrentSquare ~= nil and player:getCurrentSquare() or nil
    if cell == nil or current == nil then return nil, nil, nil, nil end
    local z = current:getZ()
    local compat = rawget(_G, "KnoxViewpointCompatibility")
    if compat ~= nil and require("KS_SurvivorUILayout").isPerspective() then
        local square = compat.targetSquare(player)
        if square ~= nil then return square, square:getX(), square:getY(), square:getZ() end
        return nil, nil, nil, z
    end
    local mx, my = getMouseX(), getMouseY()
    local okX, x = pcall(screenToIsoX, player:getPlayerNum(), mx, my, z)
    local okY, y = pcall(screenToIsoY, player:getPlayerNum(), mx, my, z)
    if not okX or not okY or type(x) ~= "number" or type(y) ~= "number" then
        return nil, nil, nil, z
    end
    local square = cell:getGridSquare(math.floor(x), math.floor(y), z)
    if square == nil then return nil, nil, nil, z end
    return square, square:getX(), square:getY(), square:getZ()
end

-- Native area bounds are exclusive at the far edge.
function Highlights.drawArea(playerNum, minX, minY, maxX, maxY, z, color)
    if addAreaHighlightForPlayer ~= nil then
        addAreaHighlightForPlayer(playerNum, minX, minY, maxX + 1, maxY + 1, z,
            color.r, color.g, color.b, color.a)
    elseif addAreaHighlight ~= nil then
        addAreaHighlight(minX, minY, maxX + 1, maxY + 1, z,
            color.r, color.g, color.b, color.a)
    end
end

local enabled = {}
local draftByPlayer = {}
local highlightedFloors = {}
local highlightedSquares = {}

-- B42 marks a tile through its floor square. IsoGridSquare has neither
-- setHighlighted nor setHighlightColor, so the per-square calls were swallowed by
-- pcall on every tile of every area - 2,670 logged exceptions per toggle - and
-- the colour was never written. With no colour anywhere, a guard post and a water
-- shelf painted the same engine default. The mark and the colour now go on the
-- floor, and each call is made only when the object really answers it.
local function hasMethod(object, name)
    return object ~= nil and object[name] ~= nil
end

local function setSquareHighlighted(square, highlight, color)
    if square == nil then return end
    local floor = nil
    if hasMethod(square, "getFloor") then
        pcall(function() floor = square:getFloor() end)
    end
    local target = floor ~= nil and floor or square
    if highlight then
        if floor ~= nil then highlightedFloors[floor] = true end
        if hasMethod(target, "setHighlighted") then
            pcall(function() target:setHighlighted(true, false) end)
        end
        if color ~= nil and hasMethod(target, "setHighlightColor") then
            pcall(function()
                target:setHighlightColor(color.r, color.g, color.b, color.a or 1)
            end)
        end
        -- A square that owns its own highlight is marked too, so a view that
        -- draws the square rather than the floor is not left dark.
        if square ~= target and hasMethod(square, "setHighlighted") then
            highlightedSquares[square] = true
            pcall(function() square:setHighlighted(true, false) end)
            if color ~= nil and hasMethod(square, "setHighlightColor") then
                pcall(function()
                    square:setHighlightColor(color.r, color.g, color.b, color.a or 1)
                end)
            end
        end
    else
        if hasMethod(target, "setHighlighted") then
            pcall(function() target:setHighlighted(false, false) end)
        end
        if square ~= target and hasMethod(square, "setHighlighted") then
            pcall(function() square:setHighlighted(false, false) end)
        end
    end
end

local function forEachSquare(area, callback)
    if area == nil or tonumber(area.minX) == nil or tonumber(area.minY) == nil then return end
    local minX = math.floor(tonumber(area.minX))
    local minY = math.floor(tonumber(area.minY))
    local maxX = math.floor(tonumber(area.maxX) or (minX + (tonumber(area.width) or 1) - 1))
    local maxY = math.floor(tonumber(area.maxY) or (minY + (tonumber(area.height) or 1) - 1))
    local z = math.floor(tonumber(area.z) or 0)
    for x = minX, maxX do
        for y = minY, maxY do
            local sq = getCell() ~= nil and getCell():getGridSquare(x, y, z) or nil
            if sq ~= nil then callback(sq) end
        end
    end
end

function Highlights.isEnabled(playerNum)
    local n = tonumber(playerNum)
    if n == nil then return false end
    return enabled[n] == true
end

function Highlights.setEnabled(playerNum, value)
    local n = tonumber(playerNum)
    if n == nil then return end
    enabled[n] = value == true
    Highlights.refresh(n)
end

function Highlights.toggle(playerNum)
    Highlights.setEnabled(playerNum, not Highlights.isEnabled(playerNum))
    return Highlights.isEnabled(playerNum)
end

function Highlights.setDraft(playerNum, active, zoneType)
    playerNum = tonumber(playerNum)
    if playerNum == nil then return end
    if active then
        draftByPlayer[playerNum] = { active = true, zoneType = zoneType }
    else
        draftByPlayer[playerNum] = nil
    end
    Highlights.refresh(playerNum)
end

function Highlights.isDraft(playerNum)
    local n = tonumber(playerNum)
    if n == nil then return false end
    local entry = draftByPlayer[n]
    return entry ~= nil and entry.active == true
end

-- One palette owns every highlight colour in the game. A zone type or a storage
-- role is a decision about what a colour means, so it is made once, here, and
-- the planner, the storage filters, the two draft selectors and the notebook all
-- read the same tables. Hues are chosen to survive a glance: within each family
-- every pair is at least 0.30 apart in RGB and the two families never come
-- closer than 0.25, which `zone-colours.lua` computes from these tables rather
-- than from a copy. Relevance is deliberate, not incidental: threat is red,
-- movement is amber, water is azure, food is green, medicine is rose, brass is
-- ammunition and fuel is a dark orange.
local WORK_COLOURS = {
    guard           = { r = 0.86, g = 0.10, b = 0.10 }, -- threat: red
    patrol          = { r = 1.00, g = 0.45, b = 0.00 }, -- movement: amber
    farming         = { r = 0.45, g = 0.80, b = 0.05 }, -- crops: lime
    woodcutting     = { r = 0.42, g = 0.38, b = 0.12 }, -- timber: olive
    log_processing  = { r = 0.00, g = 0.60, b = 0.55 }, -- sawmill: teal
    corpse          = { r = 0.52, g = 0.54, b = 0.56 }, -- the dead: neutral grey
    cooking         = { r = 0.85, g = 0.15, b = 0.55 }, -- kitchen: magenta
    repair          = { r = 0.10, g = 0.25, b = 0.90 }, -- workshop: blue
    general         = { r = 0.88, g = 0.84, b = 0.70 }, -- any work: warm beige
}

local STORAGE_COLOURS = {
    food            = { r = 0.35, g = 0.95, b = 0.40 }, -- fresh food: green
    water           = { r = 0.25, g = 0.65, b = 1.00 }, -- water: azure
    medical         = { r = 0.95, g = 0.55, b = 0.62 }, -- medicine: rose
    weapons         = { r = 0.42, g = 0.05, b = 0.05 }, -- weapons: dark maroon
    ammunition      = { r = 0.95, g = 0.78, b = 0.10 }, -- ammunition: brass
    tools           = { r = 0.10, g = 0.80, b = 0.72 }, -- tools: teal
    building        = { r = 0.80, g = 0.58, b = 0.30 }, -- building stock: tan
    farming         = { r = 0.05, g = 0.50, b = 0.10 }, -- seeds and feed: forest green
    fuel            = { r = 0.72, g = 0.30, b = 0.02 }, -- fuel: burnt orange
    clothing        = { r = 0.72, g = 0.40, b = 1.00 }, -- clothing: violet
    junk            = { r = 0.24, g = 0.24, b = 0.26 }, -- junk: dark grey
    supplies        = { r = 0.70, g = 0.80, b = 0.95 }, -- general supplies: pale steel
}

Highlights.WORK_COLOURS = WORK_COLOURS
Highlights.STORAGE_COLOURS = STORAGE_COLOURS

-- The territory keeps the green it has always carried, so home still reads as
-- home and a zone inside it still reads as work.
Highlights.TERRITORY_COLOUR = { r = 0.25, g = 0.55, b = 0.25 }

-- Shared tokens: a draft boundary, the contrast edge drawn where two selections
-- overlap, the tint that marks an overlap as a conflict, and the colour a draft
-- turns when the engine refuses the square.
Highlights.BOUNDARY_COLOUR = { r = 0.30, g = 0.62, b = 0.30, a = 0.32 }
Highlights.OVERLAP_COLOUR = { r = 0.95, g = 0.95, b = 0.92, a = 0.18 }
Highlights.CONFLICT_COLOUR = { r = 0.95, g = 0.55, b = 0.10, a = 0.10 }
Highlights.INVALID_COLOUR = { r = 0.95, g = 0.15, b = 0.15, a = 0.38 }

local function withAlpha(colour, alpha)
    if colour == nil then return nil end
    return { r = colour.r, g = colour.g, b = colour.b, a = alpha or colour.a or 0.85 }
end

-- An unknown type is a real colour, never nil: a zone whose type predates a
-- rename still paints something the player can see.
function Highlights.workColour(zoneType, alpha)
    return withAlpha(WORK_COLOURS[zoneType] or WORK_COLOURS.general, alpha)
end

function Highlights.storageColour(storageRole, alpha)
    return withAlpha(STORAGE_COLOURS[storageRole] or STORAGE_COLOURS.supplies, alpha)
end

local function drawPlayer(playerNum)
    playerNum = tonumber(playerNum) or 0
    local player = getSpecificPlayer(playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    local draft = draftByPlayer[playerNum]
    local isDraft = draft ~= nil and draft.active
    local show = base ~= nil and (Highlights.isEnabled(playerNum) or isDraft)
    -- Clear previous highlights by iterating all known areas once more
    -- Vanilla highlight is per-square; we just re-apply correct state.
    -- During draft, existing are subdued so overlaps stay readable.
    if base ~= nil then
        local territory = base.territory or base.home
        -- Draft strongest, existing subdued: vanilla area-highlight-and-confirm pattern.
        local territoryAlpha = isDraft and 0.14 or 0.85
        local zoneAlpha = isDraft and 0.12 or 0.85
        -- Home is green, the green this highlight always used. An uncoloured
        -- territory was why every area on the map suddenly matched.
        local colorTerritory = withAlpha(Highlights.TERRITORY_COLOUR, territoryAlpha)
        if show then
            forEachSquare(territory, function(sq) setSquareHighlighted(sq, true, colorTerritory) end)
            -- Work areas render over the base border so farming/woodcutting
            -- colors win inside the territory. Sort deterministically by
            -- priority so overlapping fills do not flicker with pairs() order.
            local ordered = {}
            for _, zone in pairs(base.zones or {}) do
                if zone ~= nil and zone.enabled ~= false and zone.x1 ~= nil then
                    ordered[#ordered + 1] = zone
                end
            end
            table.sort(ordered, function(a, b)
                local pa = tonumber(a.priority) or 50
                local pb = tonumber(b.priority) or 50
                if pa ~= pb then return pa < pb end
                return tostring(a.id) < tostring(b.id)
            end)
            for _, zone in ipairs(ordered) do
                local area = { minX = zone.x1, minY = zone.y1, maxX = zone.x2, maxY = zone.y2, z = zone.z or 0 }
                local col = Highlights.workColour(zone.type, zoneAlpha)
                forEachSquare(area, function(sq) setSquareHighlighted(sq, true, col) end)
            end
            for _, policy in ipairs(KnoxBaseStorage.policies(base)) do
                local square = getCell() ~= nil and getCell():getGridSquare(policy.x, policy.y, policy.z) or nil
                local col = Highlights.storageColour(policy.storageRole, zoneAlpha)
                setSquareHighlighted(square, true, col)
            end
        end
    end
end

function Highlights.clear()
    -- Clear the actual objects touched, including removed zones/old boundaries.
    for floor in pairs(highlightedFloors) do
        pcall(function() floor:setHighlighted(false, false) end)
    end
    for square in pairs(highlightedSquares) do
        pcall(function() square:setHighlighted(false, false) end)
    end
    highlightedFloors = {}
    highlightedSquares = {}
end

function Highlights.refresh(playerNum)
    Highlights.clear()
    -- Reapply every viewer so clearing an overlapping area cannot erase another
    -- split-screen player's enabled highlights.
    local viewers = {}
    for number in pairs(enabled) do viewers[number] = true end
    for number in pairs(draftByPlayer) do viewers[number] = true end
    viewers[tonumber(playerNum) or 0] = true
    for number in pairs(viewers) do drawPlayer(number) end
end

Events.OnGameStart.Add(function()
    Highlights.clear()
    enabled, draftByPlayer = {}, {}
end)

return Highlights
