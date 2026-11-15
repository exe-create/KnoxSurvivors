-- Read-only information from the installed game definitions. This module never
-- touches the player descriptor or creates a character for the creator.
KnoxCreatorLoadoutInfo = KnoxCreatorLoadoutInfo or {}
local Info = KnoxCreatorLoadoutInfo
local items = {}

local function methodAt(obj, method) return obj[method] end
local function call(obj, method, ...)
    if obj == nil then return nil end
    local found, fn = pcall(methodAt, obj, method)
    if not found or type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, obj, ...)
    if ok then return value end
end
local function values(list)
    local out = {}
    local size = call(list, "size") or 0
    for i = 0, size - 1 do out[#out + 1] = list:get(i) end
    return out
end
local function definition(kind, id)
    local api = kind == "occupation" and CharacterProfessionDefinition or CharacterTraitDefinition
    local getter = kind == "occupation" and "getProfessions" or "getTraits"
    if api == nil or api[getter] == nil or id == nil then return nil end
    local ok, list = pcall(api[getter])
    if not ok then return nil end
    for _, entry in ipairs(values(list)) do
        if tostring(call(entry, "getType")) == tostring(id) then return entry end
    end
end
local function boosts(def)
    local result, map = {}, call(def, "getXpBoosts")
    if map == nil or transformIntoKahluaTable == nil then return result end
    local ok, entries = pcall(transformIntoKahluaTable, map)
    if not ok or type(entries) ~= "table" then return result end
    for perk, level in pairs(entries) do
        local number = type(level) == "number" and level or call(level, "intValue")
        local label = tostring(perk)
        if PerkFactory and PerkFactory.getPerkName then
            local named, name = pcall(PerkFactory.getPerkName, perk)
            if named and name then label = tostring(name) end
        end
        if number ~= nil then result[#result + 1] = {name=label, level=number} end
    end
    table.sort(result, function(a,b) return a.name < b.name end)
    return result
end
local function info(kind, id)
    local def = definition(kind, id)
    if not def then return nil end
    local granted = {}
    for _, trait in ipairs(values(call(def, "getGrantedTraits"))) do
        granted[#granted + 1] = tostring(trait)
    end
    return {id=tostring(id), name=call(def, "getLabel") or call(def, "getUIName"),
        description=call(def, "getDescription"), texture=call(def, "getTexture"),
        granted=granted, boosts=boosts(def)}
end
function Info.occupation(id) return info("occupation", id) end
function Info.trait(id) return info("trait", id) end
function Info.item(id)
    if not id or id == "" then return nil end
    if items[id] then return items[id] end
    if not instanceItem then return nil end
    local ok, item = pcall(instanceItem, id)
    if not ok or not item then return nil end
    local coverage = {}
    for _, part in ipairs(values(call(item, "getBloodClothingType"))) do coverage[#coverage + 1] = tostring(part) end
    local result = {id=id, name=call(item,"getDisplayName"), texture=call(item,"getTex"),
        weight=call(item,"getActualWeight"), capacity=call(item,"getCapacity"),
        weightReduction=call(item,"getWeightReduction"), bite=call(item,"getBiteDefense"),
        scratch=call(item,"getScratchDefense"), bullet=call(item,"getBulletDefense"), coverage=coverage,
        effectiveCapacity="Requires spawned body"}
    items[id] = result
    return result
end
function Info.itemTooltip(id, person)
    local item = Info.item(id)
    if not item then return tostring(id or "No item selected") end
    local lines = {item.name or id, id}
    if item.weight then lines[#lines+1] = "Weight: " .. tostring(item.weight) end
    if item.capacity and item.capacity > 0 then
        local capacity = Info.backpackCapacity(item, person)
        lines[#lines+1] = "Capacity: " .. tostring(capacity or item.capacity)
            .. (capacity and " (trait adjusted)" or " (base; traits unresolved)")
        if item.weightReduction then lines[#lines+1] = "Weight reduction: " .. item.weightReduction .. "%" end
    end
    local defense = {}
    for _, field in ipairs({{"bite","Bite"},{"scratch","Scratch"},{"bullet","Bullet"}}) do
        if item[field[1]] ~= nil then defense[#defense+1] = field[2] .. " " .. item[field[1]] .. "%" end
    end
    if #defense > 0 then
        lines[#lines+1] = table.concat(defense, " / ")
        lines[#lines+1] = "Per item; worn coverage and condition affect body-part protection."
    end
    if #item.coverage > 0 then lines[#lines+1] = "Coverage: " .. table.concat(item.coverage, ", ") end
    return table.concat(lines, " <LINE> ")
end
function Info.person(person)
    if type(person) ~= "table" then return nil end
    local occupation = Info.occupation(person.profession)
    local traits, seen, unknown = {}, {}, false
    local function add(id)
        if seen[id] then return end
        seen[id] = true
        local trait = Info.trait(id)
        if trait then
            traits[#traits + 1] = trait
            for _, granted in ipairs(trait.granted) do add(granted) end
        else
            unknown = true
        end
    end
    if occupation then for _, id in ipairs(occupation.granted) do add(id) end end
    for _, id in ipairs(person.traits or {}) do add(id) end
    return {occupation=occupation, traits=traits, unknownTraits=unknown, mainCapacity="Requires spawned body"}
end
-- The installed ItemContainer.getEffectiveCapacity applies these modifiers to
-- backpack containers. Automatic traits cannot be predicted before spawning.
local function nativeCapacityProduct(capacity, factor)
    -- Java multiplies floats, then truncates. Lua doubles alone would show 117
    -- for an Organized capacity-90 bag, where the installed float path gives 116.
    local value, exponent = capacity * factor, 0
    if value == 0 then return 0 end
    local normalized = value
    while normalized >= 2 do normalized=normalized/2; exponent=exponent+1 end
    while normalized < 1 do normalized=normalized*2; exponent=exponent-1 end
    local step=2^(exponent-23)
    local scaled=value/step
    local whole=math.floor(scaled)
    local fraction=scaled-whole
    if fraction>0.5 or (fraction==0.5 and whole%2==1) then whole=whole+1 end
    return whole*step
end
function Info.backpackCapacity(item, person)
    if not item or type(item.capacity) ~= "number" or type(person) ~= "table"
        or type(person.traits) ~= "table" then return nil end
    local model = Info.person(person)
    if not model.occupation or model.unknownTraits then return nil end
    local seen = {}
    for _, trait in ipairs(model.traits) do seen[trait.id] = true end
    for _, id in ipairs(person.traits) do if not seen[id] then return nil end end
    for _, id in ipairs(model.occupation.granted) do if not seen[id] then return nil end end
    local n = item.capacity
    if n<0 or n~=math.floor(n) or n>16777215 then return nil end
    if seen["base:organized"] then return math.floor(math.max(nativeCapacityProduct(n,1.2999999523162842), n + 1)) end
    if seen["base:disorganized"] then return math.floor(math.max(nativeCapacityProduct(n,0.699999988079071), 1)) end
    return n
end


return Info
