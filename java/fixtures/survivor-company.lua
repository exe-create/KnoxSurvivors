-- A household must be visible as a household. These people already travel
-- together in the persistence ledger; this fixture proves the read-only facts
-- and the one sentence the nameplate and the card share cannot disagree.
local P = KnoxPersistence
local N = KnoxSurvivorNames

assert(type(P.survivorCompany) == "function", "company facts must exist")
assert(type(N) == "table" and type(N.companyName) == "function", "company wording must exist")

local a = assert(P.allocateWorldSurvivor({ x = 51, y = 61, z = 0, key = "co-a", region = "CO" }, 10))
local b = assert(P.allocateWorldSurvivor({ x = 52, y = 61, z = 0, key = "co-b", region = "CO" }, 10))
local c = assert(P.allocateWorldSurvivor({ x = 53, y = 61, z = 0, key = "co-c", region = "CO" }, 10))
local group = assert(P.createTravelGroup({ a, b, c }, 10), "the household group must exist")
assert(group.leaderId == a, "the first member leads")

-- A member belongs to the named household. The leader belongs to it too, and
-- is marked as the leader: a person who leads three others must not look
-- unattached on their own nameplate while everyone around them is labelled.
local company = assert(P.survivorCompany(b), "a household member has a company")
assert(company.leaderId == a, "the company names the real leader")
assert(company.memberCount == 3, "the company counts its members")
assert(company.groupId == tostring(group.id), "the company carries its group")
assert(P.survivorCompany(c) ~= nil, "every member reads the same company")
local lead = assert(P.survivorCompany(a), "the leader belongs to their own household")
assert(lead.isLeader == true, "the leader is marked as leading")
assert(company.isLeader == false, "a member is not marked as leading")
assert(lead.memberCount == 3 and lead.groupId == company.groupId,
    "the leader reads the same household as its members")

-- A lone survivor, an empty id and an unknown id are silent.
local solo = assert(P.allocateWorldSurvivor({ x = 71, y = 41, z = 0, key = "co-solo", region = "CO" }, 10))
assert(P.survivorCompany(solo) == nil, "a lone survivor has no company")
assert(P.survivorCompany(nil) == nil and P.survivorCompany("") == nil,
    "a missing id has no company")
assert(P.survivorCompany("no-such-survivor") == nil, "an unknown id has no company")

-- Wording: the leader's real name, never an id, never a fallback.
local realIdentity = P.getSurvivorIdentity
P.getSurvivorIdentity = function(id)
    return id == a and { forename = "Nora", surname = "Voss" } or nil
end
local name = N.companyName(company)
P.getSurvivorIdentity = realIdentity
assert(name == "Nora Voss", "the company is named by its leader, got " .. tostring(name))
assert(N.companyName(lead) == nil,
    "a leader is never described as being with themselves")
assert(N.companyNameFor == nil, "the unused convenience lookup is gone")
assert(N.companyNameFor == nil, "no id convenience remains to disagree")

P.getSurvivorIdentity = function() return { forename = "ks-world-99" } end
local anonymous = N.companyName(company)
P.getSurvivorIdentity = realIdentity
assert(anonymous == nil, "an unreadable leader gets no sentence instead of an id")

assert(N.companyName(nil) == nil, "no facts, no sentence")
assert(N.companyName({ leaderId = "" }) == nil, "no leader, no sentence")


-- The household's place is a shared fact, never an assumption.
local realOrigin = P.getSurvivorOrigin
P.getSurvivorOrigin = function() return { buildingId = "bld-police", context = "law_enforcement" } end
assert(P.survivorCompany(b).home.context == "law_enforcement", "members from one building share its place")
assert(N.companyPlace(P.survivorCompany(b)) == "police station", "a station is said plainly")
P.getSurvivorOrigin = function(id)
    if id == c then return { buildingId = "bld-other", context = "military" } end
    return { buildingId = "bld-police", context = "law_enforcement" }
end
assert(P.survivorCompany(b).home == nil, "a mixed household has no shared place")
P.getSurvivorOrigin = function() return nil end
assert(P.survivorCompany(b).home == nil, "no origin, no place")
P.getSurvivorOrigin = realOrigin
assert(N.companyPlace({ home = { context = "agriculture" } }) == "farm", "a farm is said plainly")
assert(N.companyPlace({ home = { context = "military" } }) == "military post", "a post is said plainly")
assert(N.companyPlace({ home = { context = "generic" } }) == nil, "an ordinary house invents no name")
assert(N.companyPlace(nil) == nil, "no facts, no place")
print("survivor company PASS member=true leader=true solo=true wording=true anonymous=nil")
