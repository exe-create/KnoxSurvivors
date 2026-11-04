local Origins = rawget(_G, "KnoxSurvivorOrigins") or {}
_G.KnoxSurvivorOrigins = Origins

-- Pure policy for evidence that already exists in vanilla spawn definitions
-- and BuildingDef room names. This module never reads the world, creates an
-- item, or assigns a faction; callers remain the owners of those domains.
local MAX_PROFESSION_CANDIDATES = 12

local CONTEXTS = {
    generic = true,
    law_enforcement = true,
    medical = true,
    military = true,
    fire_service = true,
    automotive = true,
    agriculture = true,
    food_service = true,
    private_security = true,
}

local CONTEXT_PRIORITY = {
    military = 90,
    law_enforcement = 80,
    medical = 70,
    fire_service = 60,
    automotive = 50,
    agriculture = 40,
    food_service = 30,
    private_security = 20,
    generic = 0,
}

local EXACT_ROOM_CONTEXT = {
    policearchive = "law_enforcement",
    policegarage = "law_enforcement",
    policelibrary = "law_enforcement",
    policelocker = "law_enforcement",
    policeoffice = "law_enforcement",
    policegunstorage = "law_enforcement",
    policeoutfitstorage = "law_enforcement",
    policestorage = "law_enforcement",
    policeswat = "law_enforcement",
    hospitalhallway = "medical",
    hospitalroom = "medical",
    hospitalstorage = "medical",
    medical = "medical",
    medicaloffice = "medical",
    medicalstorage = "medical",
    pharmacy = "medical",
    pharmacystorage = "medical",
    armystorage = "military",
    armysurplus = "military",
    armytent = "military",
    firegarage = "fire_service",
    firestorage = "fire_service",
    mechanic = "automotive",
    garagestorage = "automotive",
    garage_ranger = "automotive",
    farmstorage = "agriculture",
    bakery = "food_service",
    bakerykitchen = "food_service",
    barkitchen = "food_service",
    restaurant = "food_service",
    restaurantkitchen = "food_service",
    diner = "food_service",
    security = "private_security",
}

-- Prefixes are deliberately narrow vanilla semantic prefixes. Container
-- names such as militarylocker are not listed and therefore cannot turn an
-- unrelated room into a military facility.
local PREFIX_ROOM_CONTEXT = {
    { "police", "law_enforcement" },
    { "hospital", "medical" },
    { "clinic", "medical" },
    { "greenhouse", "agriculture" },
    { "restaurant_", "food_service" },
    { "diner_", "food_service" },
    { "spiffo_", "food_service" },
}

local SPAWN_PROFESSION_ALIASES = {
    burglar = "base:burglar",
    burgerflipper = "base:burgerflipper",
    carpenter = "base:carpenter",
    chef = "base:chef",
    constructionworker = "base:constructionworker",
    doctor = "base:doctor",
    electrician = "base:electrician",
    engineer = "base:engineer",
    farmer = "base:farmer",
    fireofficer = "base:fireofficer",
    fisherman = "base:fisherman",
    fitnessinstructor = "base:fitnessinstructor",
    lumberjack = "base:lumberjack",
    mechanics = "base:mechanics",
    mechanic = "base:mechanics",
    metalworker = "base:metalworker",
    nurse = "base:nurse",
    parkranger = "base:parkranger",
    policeofficer = "base:policeofficer",
    rancher = "base:rancher",
    repairman = "base:repairman",
    securityguard = "base:securityguard",
    smither = "base:smither",
    tailor = "base:tailor",
    unemployed = "base:unemployed",
    veteran = "base:veteran",
}

local PROFESSION_CONTEXT = {
    ["base:policeofficer"] = "law_enforcement",
    ["base:doctor"] = "medical",
    ["base:nurse"] = "medical",
    ["base:veteran"] = "military",
    ["base:fireofficer"] = "fire_service",
    ["base:mechanics"] = "automotive",
    ["base:farmer"] = "agriculture",
    ["base:rancher"] = "agriculture",
    ["base:chef"] = "food_service",
    ["base:burgerflipper"] = "food_service",
    ["base:securityguard"] = "private_security",
}

local CONTEXT_PROFESSIONS = {
    law_enforcement = { "base:policeofficer" },
    medical = { "base:doctor", "base:nurse" },
    military = { "base:veteran" },
    fire_service = { "base:fireofficer" },
    automotive = { "base:mechanics" },
    agriculture = { "base:farmer", "base:rancher" },
    food_service = { "base:chef", "base:burgerflipper" },
    private_security = { "base:securityguard" },
}

-- A facility profession wears that facility's clothing and carries its kit.
-- It is only legitimate at the place that produced it: every downstream reader
-- (appearance, starting gear, job preference) keys off this one profession id,
-- so an ordinary household survivor rolling base:policeofficer is not variety,
-- it is a defect.
local FACILITY_PROFESSIONS = {
    ["base:policeofficer"] = true,
    ["base:veteran"] = true,
    ["base:fireofficer"] = true,
}

local JOB_PREFERENCES = {
    ["base:mechanics"] = "repair",
    ["base:chef"] = "cooking",
    ["base:burgerflipper"] = "cooking",
    ["base:farmer"] = "farming",
    ["base:rancher"] = "farming",
    ["base:policeofficer"] = "guard",
    ["base:securityguard"] = "guard",
    ["base:veteran"] = "guard",
    ["base:carpenter"] = "woodwork",
    ["base:constructionworker"] = "woodwork",
    ["base:lumberjack"] = "woodwork",
    ["base:repairman"] = "woodwork",
}

local function token(value)
    if type(value) ~= "string" then return nil end
    local normalized = string.lower(value)
    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    normalized = string.gsub(normalized, "[%s%-]+", "_")
    normalized = string.gsub(normalized, "[^%w_:]", "")
    return normalized ~= "" and normalized or nil
end

local function uniqueSorted(values, maximum)
    local seen, result = {}, {}
    for _, value in ipairs(values or {}) do
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    table.sort(result)
    while #result > (maximum or #result) do table.remove(result) end
    return result
end

function Origins.normalizeRoomName(value)
    return token(value)
end

function Origins.normalizeProfessionId(value)
    local normalized = token(value)
    if normalized == nil then return nil end
    if SPAWN_PROFESSION_ALIASES[normalized] ~= nil then
        return SPAWN_PROFESSION_ALIASES[normalized]
    end
    if normalized:match("^[a-z][a-z0-9_]*:[a-z][a-z0-9_]*$") then
        return normalized
    end
    return nil
end

function Origins.isContext(value)
    return CONTEXTS[value] == true
end

function Origins.contextPriority(value)
    return CONTEXT_PRIORITY[value] or 0
end

-- The professions that may not be rolled without facility evidence.
function Origins.facilityProfessions()
    local listed = {}
    for professionId in pairs(FACILITY_PROFESSIONS) do
        listed[#listed + 1] = professionId
    end
    table.sort(listed)
    return listed
end

-- True when the profession may exist at that context. Only facility
-- professions are place-bound: a farmer or a mechanic is ordinary anywhere, and
-- gating every profession that carries a context would have made a farming
-- household unable to hold a farmer.
function Origins.professionAllowedAtContext(professionId, context)
    local normalized = Origins.normalizeProfessionId(professionId)
    if normalized == nil or FACILITY_PROFESSIONS[normalized] ~= true then
        return true
    end
    local expected = PROFESSION_CONTEXT[normalized]
    return expected ~= nil and expected == tostring(context or "generic")
end

function Origins.classifyRooms(roomNames)
    local selected, priority = "generic", 0
    for _, rawName in ipairs(roomNames or {}) do
        local name = Origins.normalizeRoomName(rawName)
        local context = name ~= nil and EXACT_ROOM_CONTEXT[name] or nil
        if context == nil and name ~= nil then
            for _, entry in ipairs(PREFIX_ROOM_CONTEXT) do
                if string.sub(name, 1, #entry[1]) == entry[1] then
                    context = entry[2]
                    break
                end
            end
        end
        local candidatePriority = CONTEXT_PRIORITY[context] or 0
        if candidatePriority > priority then
            selected, priority = context, candidatePriority
        end
    end
    return selected
end

function Origins.mergeProfessionCandidate(values, value)
    local normalized = Origins.normalizeProfessionId(value)
    local merged = {}
    for _, candidate in ipairs(values or {}) do
        local existing = Origins.normalizeProfessionId(candidate)
        if existing ~= nil then merged[#merged + 1] = existing end
    end
    if normalized ~= nil then merged[#merged + 1] = normalized end
    return uniqueSorted(merged, MAX_PROFESSION_CANDIDATES)
end

function Origins.contextForProfessionCandidates(candidates)
    local selected = nil
    for _, candidate in ipairs(candidates or {}) do
        local context = PROFESSION_CONTEXT[Origins.normalizeProfessionId(candidate)]
        if context ~= nil then
            if selected ~= nil and selected ~= context then return "generic" end
            selected = context
        end
    end
    return selected or "generic"
end

function Origins.finalizeCatalogOrigin(origin)
    if type(origin) ~= "table" then return origin end
    origin.professionCandidates = uniqueSorted(origin.professionCandidates,
        MAX_PROFESSION_CANDIDATES)
    if not Origins.isContext(origin.context) or origin.context == "generic" then
        origin.context = Origins.contextForProfessionCandidates(origin.professionCandidates)
    end
    if #origin.professionCandidates == 0 then origin.professionCandidates = nil end
    return origin
end

function Origins.professionCandidates(origin, survivorId)
    local candidates = uniqueSorted(type(origin) == "table"
        and origin.professionCandidates or nil, MAX_PROFESSION_CANDIDATES)
    if #candidates == 0 and type(origin) == "table" then
        for _, professionId in ipairs(CONTEXT_PROFESSIONS[origin.context] or {}) do
            candidates[#candidates + 1] = professionId
        end
    end
    if #candidates > 1 then
        local hash = 5381
        for index = 1, #tostring(survivorId or "") do
            hash = (hash * 33 + string.byte(tostring(survivorId), index)) % 2147483647
        end
        local rotated = {}
        local start = hash % #candidates
        for offset = 0, #candidates - 1 do
            rotated[#rotated + 1] = candidates[((start + offset) % #candidates) + 1]
        end
        return rotated
    end
    return candidates
end

function Origins.facilityAffinity(professionId, context)
    local expected = PROFESSION_CONTEXT[Origins.normalizeProfessionId(professionId)]
    return expected ~= nil and expected == context and context ~= "generic" and 1 or 0
end

function Origins.jobPreference(professionId)
    return JOB_PREFERENCES[Origins.normalizeProfessionId(professionId)]
end

-- Persistence boundary. Missing schema-17 metadata remains missing; metadata
-- that claims a context is either canonical and bounded or collapses to the
-- generic context without retaining suspect candidate/building evidence.
function Origins.sanitizeMetadata(origin, preserveMissing)
    if type(origin) ~= "table" then return { context = "generic" } end
    local hasMetadata = origin.context ~= nil or origin.professionCandidates ~= nil
        or origin.buildingId ~= nil
    if preserveMissing and not hasMetadata then return {} end
    if origin.context ~= nil and not Origins.isContext(origin.context) then
        return { context = "generic" }
    end
    local context = origin.context or "generic"
    local candidates = {}
    if origin.professionCandidates ~= nil then
        if type(origin.professionCandidates) ~= "table" then
            return { context = "generic" }
        end
        for key, value in pairs(origin.professionCandidates) do
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
                return { context = "generic" }
            end
            local normalized = Origins.normalizeProfessionId(value)
            if normalized == nil then return { context = "generic" } end
            candidates[#candidates + 1] = normalized
        end
        candidates = uniqueSorted(candidates, MAX_PROFESSION_CANDIDATES)
    end
    local buildingId = nil
    if origin.buildingId ~= nil then
        if type(origin.buildingId) ~= "string" or origin.buildingId == ""
            or #origin.buildingId > 80 then
            return { context = "generic" }
        end
        buildingId = origin.buildingId
    end
    return {
        context = context,
        professionCandidates = #candidates > 0 and candidates or nil,
        buildingId = buildingId,
    }
end

return Origins
