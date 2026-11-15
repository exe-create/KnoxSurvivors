-- Presentation only: runtime IDs never become names and saved identity is untouched.
local Names = {}

local function part(value, id)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    local lower = text:lower()
    -- Runtime ids are never names. The world population allocates
    -- "ks-world-N", which used to fall through here and be displayed verbatim
    -- whenever an identity had no readable name, so the player saw an id where
    -- a person should be.
    if text == tostring(id or "") or lower:match("^ks%-survivor")
        or lower:match("^knox%-survivor") or lower:match("^ks%-world%-")
        or lower:match("^ks%-dev%-") then return "" end
    return text
end

function Names.resolve(id, identity, character)
    identity = type(identity) == "table" and identity or {}
    local first, last = part(identity.forename, id), part(identity.surname, id)
    if character ~= nil and (first == "" or last == "") then
        local ok, descriptor = pcall(function() return character:getDescriptor() end)
        if ok and descriptor ~= nil then
            if first == "" then
                local got, value = pcall(function() return descriptor:getForename() end)
                if got then first = part(value, id) end
            end
            if last == "" then
                local got, value = pcall(function() return descriptor:getSurname() end)
                if got then last = part(value, id) end
            end
        end
    end
    local name = (first .. " " .. last):match("^%s*(.-)%s*$")
    return first, last, name ~= "" and name or "Survivor"
end

-- The world's one wording for "this person is with someone". The facts come from
-- the persistence owner (a real travel group, never a faction and never the
-- player's own people); only the name lives here, so the nameplate above a
-- person and the card's row cannot drift apart. A leader whose identity has no
-- readable name gets no sentence at all rather than an id or "Survivor".
function Names.companyName(company)
    if type(company) ~= "table" or type(company.leaderId) ~= "string"
        or company.leaderId == "" then return nil end
    -- "Who are you with" has no answer for the person being named: a leader is
    -- not with themselves. A leader's own surface reads `company.name` directly.
    if company.isLeader == true then return nil end
    -- A household names itself. A mixed group still answers with its leader's
    -- name because it has no household identity to borrow.
    if type(company.name) == "string" then
        local name = company.name:match("^%s*(.-)%s*$")
        if name ~= "" then return name end
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getSurvivorIdentity == nil then return nil end
    local identity = persistence.getSurvivorIdentity(company.leaderId)
    local first, last, name = Names.resolve(company.leaderId, identity or {}, nil)
    if (first == nil or first == "") and (last == nil or last == "") then return nil end
    return tostring(name)
end

-- The workplace the household was allocated in, said the way a local would say
-- it. Only named facilities get a phrase: an ordinary house has no name here, so
-- nothing is invented for it.
local COMPANY_PLACES = {
    law_enforcement = "police station",
    fire_service = "fire station",
    medical = "clinic",
    military = "military post",
    agriculture = "farm",
}

function Names.companyPlace(company)
    local home = type(company) == "table" and company.home or nil
    local context = type(home) == "table" and home.context or nil
    if type(context) ~= "string" then return nil end
    return COMPANY_PLACES[context]
end

_G.KnoxSurvivorNames = Names

return Names
