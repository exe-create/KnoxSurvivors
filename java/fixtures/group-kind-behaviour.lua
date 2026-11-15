-- Kind -> behaviour, driven through the payload's own owners.
--
-- What is out of reach offline: a loaded body walking to a window and swinging a
-- hammer. Everything below is production code - the creator's kind table, the
-- real allocation, the real creator record store, the real disposition classifier,
-- the real travel-group promotion and the real base/barricade permission.
local C = assert(KnoxCreator, "the creator model is loaded")
local P = assert(KnoxPersistence, "the persistence owner is loaded")
local Jobs = assert(KnoxBaseJobs, "the base job owner is loaded")

local function kind(id)
    local behaviour = C.behaviourFor(id)
    assert(behaviour ~= nil, "the kind exists: " .. tostring(id))
    return behaviour
end

-- 1. One table states what each kind does.
assert(kind("household").settles and kind("household").defendsHome
    and kind("household").canFoundFaction, "a household settles a home, holds it and can found a faction")
assert(kind("household").attitude == "dynamic", "a household is not hostile by default")
assert(kind("robbers").hostileToOutsiders and kind("robbers").canFoundFaction,
    "robbers are hostile and are still their own faction")
assert(kind("cannibals").hostileToOutsiders, "cannibals are hostile")
assert(kind("looters").roams and kind("looters").loots
    and not kind("looters").canFoundFaction, "looters roam, loot, and never settle as a faction")
assert(kind("looters").settlementPolicy == "mobile", "the looter kind is mobile by decision, not by name")
assert(kind("solo").independent and not kind("solo").canFoundFaction,
    "a solo survivor is independent and never a faction")
assert(kind("solo").settlementPolicy == "independent", "a solo has no settlement")
assert(C.behaviourFor("invented_kind") == nil, "an unknown kind has no behaviour to obey")

-- 2. Two households are two groups, each carrying the household kind.
local defs = {}
local okHomeA, homeA = C.addFaction(defs, "Barley", "household")
local okHomeB, homeB = C.addFaction(defs, "Voss", "household")
assert(okHomeA and okHomeB and homeA.id ~= homeB.id, "two households are two separate groups")
for _, group in ipairs({ homeA, homeB }) do
    local policy = C.profileFor(group.id, defs)
    assert(policy.profile == "household", "the group keeps the household kind")
    assert(policy.behaviour ~= nil and policy.behaviour.defendsHome == true,
        "the kind reaches the group's behaviour")
    assert(policy.settlementPolicy == "home" and policy.spawnContext == "household",
        "the kind decides where the group settles")
end

-- 3. A creator-authored person reaches the survivor the world allocates.
-- One world survivor per coordinate: allocation refuses a second person at an
-- origin key already in use, and the key is the x,y,z of the site.
local slotCounter = 0
local function person(name, building, group, extra)
    slotCounter = slotCounter + 1
    local slot = slotCounter
    local home = group ~= nil and group.profile == "household"
    -- A far-away coordinate band keeps these people from colliding with a
    -- survivor an earlier fixture already placed.
    local x, y = 1000 + slot, 2000 + slot * 2
    local origin = { source = "world_building", buildingId = building,
        key = building .. "#" .. tostring(slot), x = x, y = y, z = 0,
        context = "generic", household = home or nil, residential = home or nil }
    local id, why = P.allocateWorldSurvivor(origin, 20)
    assert(id, "allocated at the chosen site: " .. tostring(building) .. " (" .. tostring(why) .. ")")
    local roster = { name = name, look = "casual", kit = "none", pack = "meal",
        slots = {}, faction = group ~= nil and group.id or nil }
    for key, value in pairs(extra or {}) do roster[key] = value end
    local record = C.recordFor(roster, { defs = defs, name = group ~= nil and group.label or "" })
    if extra ~= nil and extra.stripAttitude == true then record.attitude = nil end
    assert(P.setSurvivorCreatorRecord(id, record) == true,
        "the creator record is stored: " .. tostring(name))
    return id
end

local mara = person("Mara Barley", "home-a", homeA,
    { look = "police", kit = "police", hair = "Bob", hairColour = "red", female = true,
      slots = { torso = "Base.Shirt_PoliceBlue" } })
local homeOrigin = P.getSurvivorOrigin(mara)
assert(homeOrigin.buildingId == "home-a", "the chosen cell is the cell the survivor spawned at")
local maraRecord = P.getSurvivorCreatorRecord(mara)
assert(maraRecord.look == "police" and maraRecord.kit == "police",
    "the authored outfit and kit are on the spawned survivor")
assert(type(maraRecord.slots) == "string" and maraRecord.slots:find("torso", 1, true) ~= nil,
    "the authored clothing slot reaches the spawned survivor")
assert(maraRecord.hair == "Bob" and maraRecord.hairColour == "red"
    and maraRecord.female == true, "the authored face reaches the spawned survivor")
assert(maraRecord.profile == "household", "the spawned survivor carries its group's kind")

-- 4. Robbers are hostile to non-robbers, and the kind is what says so.
local _, gangOne = C.addFaction(defs, "Road Robbers", "robbers")
local _, gangTwo = C.addFaction(defs, "Bridge Robbers", "robbers")
assert(gangOne.id ~= gangTwo.id, "two robber groups are two groups")
local robber = person("Silas Road", "road-b", gangOne, { stripAttitude = true })
assert(P.getSurvivorDisposition(robber, mara) == "hostile",
    "a robber is hostile to a householder even with no stored stance: the kind decides")
local otherRobber = person("Ivo Bridge", "road-c", gangTwo, { stripAttitude = true })
assert(P.getSurvivorDisposition(robber, otherRobber) ~= "allied",
    "two robber groups are not allied to each other")
local robberFaction = P.getFactionForSurvivor(robber)
local otherFaction = P.getFactionForSurvivor(otherRobber)
assert(robberFaction == nil or otherFaction == nil or robberFaction.id ~= otherFaction.id,
    "two robber groups do not merge into one faction")

-- 5. Looters follow the looter rule: a crew is never promoted to a faction.
local _, crewA = C.addFaction(defs, "Westside Scavengers", "looters")
local _, crewB = C.addFaction(defs, "Dixie Scavengers", "looters")
assert(crewA.id ~= crewB.id, "two looter crews are two groups")
local function crew(group, building, names)
    local ids = {}
    for _, name in ipairs(names) do
        ids[#ids + 1] = person(name, building, group, {})
    end
    local travel = P.createTravelGroup(ids, 30)
    assert(travel ~= nil, "the crew forms a travel group: " .. tostring(group.label))
    return travel, ids
end
local travelA, idsA = crew(crewA, "depot-a", { "Ada West", "Bex West", "Cal West" })
local travelB = crew(crewB, "depot-b", { "Dee Dixie", "Eli Dixie", "Fay Dixie" })
assert(travelA.id ~= travelB.id, "two looter crews are two travel groups")
local promoted, why = P.promoteTravelGroupToFaction(travelA.id, 30, 3)
assert(promoted == nil and why == "mobile_group",
    "a looter crew is never promoted to a faction: " .. tostring(why))
assert(P.getTravelGroupFor(idsA[1]) ~= nil, "looters keep travelling together instead")

-- 6. A household does settle, and the name it was given is kept verbatim.
local travelHome, homeIds = crew(homeA, "home-b", { "Nora Voss", "Owen Voss", "Ruth Voss" })
local faction, factionWhy = P.promoteTravelGroupToFaction(travelHome.id, 30, 3)
assert(faction ~= nil, "the household forms a faction: " .. tostring(factionWhy))
-- The creator's own group name is the faction's name: "Barley" is not rewritten
-- into a generated "The <Surname> Household" sentence.
assert(faction.name == "Barley",
    "the creator's group name is kept verbatim: " .. tostring(faction.name))

-- A household the simulation named after a short surname keeps that surname too.
-- The five-character floor used to rewrite "Voss" into a generated sentence, so
-- a family was renamed behind the player's back.
local bare = {}
for _, name in ipairs({ "Ada Voss", "Bo Voss", "Cy Voss" }) do
    slotCounter = slotCounter + 1
    local slot = slotCounter
    local id = assert(P.allocateWorldSurvivor({ source = "world_building",
        buildingId = "home-short", key = "home-short#" .. tostring(slot),
        x = 1000 + slot, y = 2000 + slot * 2, z = 0, context = "generic",
        household = true, residential = true }, 20),
        "the short-named household member is allocated: " .. tostring(name))
    bare[#bare + 1] = id
end
local shortTravel = assert(P.createTravelGroup(bare, 30),
    "the short-named household travels together")
shortTravel.name = "Voss"
local shortFaction, shortWhy = P.promoteTravelGroupToFaction(shortTravel.id, 30, 3)
assert(shortFaction ~= nil, "the short-named household forms a faction: " .. tostring(shortWhy))
assert(shortFaction.name == "Voss",
    "a short household name is kept verbatim, not rewritten: " .. tostring(shortFaction.name))

-- 7. Two households claim and protect their own home, and a faction home boards up.
local function claimHome(target, building, x, y)
    local candidate = { buildingId = building, x = x, y = y, z = 0,
        minX = x, minY = y, width = 12, height = 12, score = 40 }
    assert(P.recordFactionBaseCandidate(target.id, candidate, 40) ~= nil,
        "the home candidate is recorded: " .. building)
    local homeBase, result = P.confirmFactionHomeBase(target.id, building, 40)
    if homeBase == nil then
        local summary = {}
        for id, base in pairs(P.getBases() or {}) do
            local area = base.territory or base.home or {}
            summary[#summary + 1] = tostring(id) .. ":" .. tostring(area.minX) .. ","
                .. tostring(area.minY) .. "x" .. tostring(area.width) .. "x"
                .. tostring(area.height) .. "z" .. tostring(area.z)
        end
        assert(false, "the home is claimed: " .. tostring(result)
            .. " bases=" .. table.concat(summary, " | "))
    end
    local base = P.createBase("faction", target.id, homeBase, 40)
    assert(base ~= nil, "the faction owns a base record for that home")
    return base
end

-- A second household faction of its own, so both are real factions with homes.
local _, homeC = C.addFaction(defs, "Mercer", "household")
local travelC, mercerIds = crew(homeC, "home-c", { "Ada Mercer", "Bo Mercer", "Cy Mercer" })
local factionC, whyC = P.promoteTravelGroupToFaction(travelC.id, 30, 3)
assert(factionC ~= nil, "the third household forms a faction: " .. tostring(whyC))

-- Far from any base an earlier fixture created, so the claim itself is what is
-- under test rather than territory overlap.
local baseVoss = claimHome(faction, "home-voss", 2500, 2500)
local baseMercer = claimHome(factionC, "home-mercer", 2650, 2650)
assert(baseVoss.home.buildingId == "home-voss" and baseMercer.home.buildingId == "home-mercer",
    "each household owns its own home")
assert(baseVoss.home.buildingId ~= baseMercer.home.buildingId,
    "two households never share one home")
assert(Jobs.automaticBarricadeAllowed(baseVoss) == true
    and Jobs.automaticBarricadeAllowed(baseMercer) == true,
    "a faction home boards up its own windows")
assert(Jobs.automaticBarricadeAllowed({ id = "player-base", ownerKind = "player" }) == false,
    "a player base still needs explicit consent, so the rule is not simply always-on")

-- 8. A solo survivor is one individual with no group, approachable, and mortal.
local soloId = person("Wren Solo", "cabin-s", nil, { stripAttitude = true })
local soloRecord = P.getSurvivorCreatorRecord(soloId)
-- A solo is not a group, so the creator writes the kind on the person, not on a
-- roster entry; this is the record shape the solo spawn path stores.
soloRecord.profile = "solo"
soloRecord.faction = nil
soloRecord.settlementPolicy = "independent"
assert(P.setSurvivorCreatorRecord(soloId, soloRecord) == true, "the solo record is stored")
assert(P.getSurvivorCreatorRecord(soloId).profile == "solo", "the solo keeps its kind")
assert(P.getTravelGroupFor(soloId) == nil, "a solo is in no travel group")
assert(P.getFactionForSurvivor(soloId) == nil, "a solo belongs to no faction")
assert(P.isIndependentSurvivor(soloId) == true, "a solo is an independent survivor")
assert(P.getSurvivorOrigin(soloId).buildingId == "cabin-s", "a solo spawns at its own site")
assert(P.isSurvivorHostileToPlayer(soloId, "player") == false,
    "a solo can be approached and recruited")
assert(P.isSurvivorAlive(soloId) == true, "a solo is alive like any individual")
P.markSurvivorDead(soloId, 50, "fixture_kill")
assert(P.isSurvivorAlive(soloId) == false, "a solo dies like any individual")

-- 9. The threatened home is answered by its own household, through the single
-- assignment decision the alarm path reads.
local Base = assert(codecDefence, "the base owner exposes its defence assignment")
local function assigned(base, survivorId, factionId, extra)
    local row = { id = survivorId, factionId = factionId, dutyBaseId = base.id }
    for key, value in pairs(extra or {}) do row[key] = value end
    local allowed, reason = Base.defenceAssignment(base, row)
    return allowed, reason
end

local ownOk, ownWhy = assigned(baseVoss, homeIds[1], faction.id, { kind = "household" })
assert(ownOk == true and ownWhy == "own_group_home",
    "a household member is a defender of its own home: " .. tostring(ownWhy))
assert(assigned(baseVoss, homeIds[1], faction.id, { kind = "household", defendsHome = false }) == false,
    "an explicit group choice still wins over the kind")

-- Household B is never promoted to defend household A's home.
assert(assigned(baseVoss, mercerIds[1], factionC.id, { kind = "household" }) == false,
    "no group defends another group's home")
assert(Base.defenceAssignment(baseVoss, { id = mercerIds[1], factionId = factionC.id }) == false,
    "a foreign member without a duty record is refused too")
-- Household B is the defender of its own site.
assert(assigned(baseMercer, mercerIds[1], factionC.id, { kind = "household" }) == true,
    "each household is the defender of its own home")
assert(baseVoss.id ~= baseMercer.id, "the two defended sites are two sites")

-- The kind, not the name: a looting kind holds no home, a robber kind does.
assert(Base.defenceAssignment(baseVoss, { id = homeIds[2], factionId = faction.id,
    kind = "looters" }) == false, "a looting kind is not a home defender")
assert(Base.defenceAssignment(baseVoss, { id = homeIds[2], factionId = faction.id,
    kind = "robbers" }) == true, "a robber kind defends its own site")
assert(Base.defenceAssignment(baseVoss, { id = homeIds[2], factionId = faction.id,
    kind = "invented_kind" }) == false, "an unknown kind is refused rather than defaulted")
-- No creator kind keeps the answer this path already gave.
assert(assigned(baseMercer, "legacy-person", factionC.id, {}) == true,
    "a person with no creator kind keeps the old answer")

-- A player base still answers only through residency.
assert(assigned({ id = "pb", ownerKind = "player", ownerId = "player" }, "someone", nil,
    { dutyBaseId = "pb" }) == true, "a player base resident still answers")
assert(assigned({ id = "pb", ownerKind = "player", ownerId = "player" }, "someone", nil,
    { dutyBaseId = "other" }) == false, "a non-resident does not")

-- A robber's engagement follows its kind, but the kind is not blind hostility.
assert(C.behaviourFor("robbers").hostileToOutsiders == true,
    "the robber kind is what makes a robber hostile")
assert(P.getSurvivorDisposition(robber, mara) == "hostile",
    "a robber stays hostile to a householder with the stance stripped")
assert(P.getSurvivorDisposition(homeIds[1], homeIds[2]) ~= "hostile",
    "a household's own members are not hostile to each other")

-- 10. The engagement decision itself, read the way the threat scan reads it:
-- hostileHuman -> areSurvivorsHostile -> disposition -> the stance of the kind.
local function restate(id, attitude)
    local record = assert(P.getSurvivorCreatorRecord(id), "a record to restate")
    record.attitude = attitude
    assert(P.setSurvivorCreatorRecord(id, record) == true, "the stance is stored")
end

-- Two groups differing only in kind, both with no stored stance: an older record
-- that predates the field is exactly where the kind has to answer.
local robberDyn = person("Rook Road", "road-e", gangOne, {})
restate(robberDyn, nil)
local houseDyn = person("Ivy Barley", "home-d", homeA, {})
restate(houseDyn, nil)
assert(P.areSurvivorsHostile(robberDyn, mara) == true,
    "a robber kind engages the same outsider")
assert(P.areSurvivorsHostile(houseDyn, mara) == false,
    "a household kind, same stored emptiness, does not engage")

-- Flipping the kind flips the decision on the same survivor.
local flip = assert(P.getSurvivorCreatorRecord(robberDyn))
flip.profile = "household"
assert(P.setSurvivorCreatorRecord(robberDyn, flip) == true)
assert(P.areSurvivorsHostile(robberDyn, mara) == false,
    "flipping the kind to household stops the engagement")
flip.profile = "robbers"
assert(P.setSurvivorCreatorRecord(robberDyn, flip) == true)
assert(P.areSurvivorsHostile(robberDyn, mara) == true,
    "and flipping it back resumes the engagement")

-- An explicit stance beats the kind, and the kind is only the default.
local robberStance = assert(P.getSurvivorCreatorRecord(robberDyn))
assert(P.creatorEngagementStance(robberStance) == "hostile",
    "with no stored stance the robber kind decides")
restate(robberDyn, "friendly")
assert(P.areSurvivorsHostile(robberDyn, mara) == false,
    "an explicit friendly stance beats a hostile kind")
assert(P.creatorEngagementStance(assert(P.getSurvivorCreatorRecord(robberDyn))) == "friendly",
    "and the explicit stance is what the decision reports")
restate(robberDyn, nil)
assert(P.areSurvivorsHostile(robberDyn, mara) == true,
    "removing the explicit stance returns the kind's answer")

-- A kind without a fixed stance does not become automatically hostile.
assert(P.creatorEngagementStance(assert(P.getSurvivorCreatorRecord(idsA[1]))) == "random",
    "a looting kind stays a roll rather than automatic hostility")
assert(P.areSurvivorsHostile(houseDyn, mara) == false,
    "a household remains peaceful after the looter check")

-- A group never engages its own members.
assert(P.areSurvivorsHostile(homeIds[1], homeIds[2]) == false,
    "a group does not engage its own members")
assert(P.getSurvivorDisposition(homeIds[1], homeIds[2]) == "allied",
    "its own members read allied, not merely non-hostile")

-- 11. The real creator-to-spawn path: a group authored as robbers, recorded by
-- the creator, allocated by the world allocator, then read by the engagement
-- decision. No hand-authored stance anywhere in this block.
local function spawnFromCreator(name, building, group)
    slotCounter = slotCounter + 1
    local slot = slotCounter
    local id = assert(P.allocateWorldSurvivor({ source = "world_building",
        buildingId = building, key = building .. "#" .. tostring(slot),
        x = 1000 + slot, y = 2000 + slot * 2, z = 0, context = "generic" }, 60),
        "the authored person is allocated: " .. tostring(name))
    local record = assert(C.recordFor({ name = name, look = "casual", kit = "none",
        pack = "meal", slots = {}, faction = group.id }, { defs = defs }),
        "the creator builds the record: " .. tostring(name))
    assert(P.setSurvivorCreatorRecord(id, record) == true, "the authored record is stored")
    return id, record
end

local realRobber, realRobberRecord = spawnFromCreator("Rook Road", "road-f", gangOne)
assert(realRobberRecord.profile == "robbers", "the spawned robber carries the robber kind from its group")
assert(realRobberRecord.attitude == nil,
    "the spawn path no longer copies the kind's default stance onto the person")
assert(P.areSurvivorsHostile(realRobber, mara) == true,
    "a robber spawned by the real path engages the same outsider")

local realHouse, realHouseRecord = spawnFromCreator("Ivy Barley", "home-e", homeA)
assert(realHouseRecord.profile == "household", "the spawned householder carries the household kind")
assert(realHouseRecord.attitude == nil, "the household record carries no copied stance either")
assert(P.areSurvivorsHostile(realHouse, mara) == false,
    "a household spawned by the same path does not engage")

-- The kind is the selector: change the group's kind, the spawned person changes answer.
assert(C.updateFaction(defs, gangOne.id, { profile = "household" }) == true,
    "the creator can change a group's kind")
local asHouse, asHouseRecord = spawnFromCreator("Rook Household", "home-f", gangOne)
assert(asHouseRecord.profile == "household" and asHouseRecord.attitude == nil)
assert(P.areSurvivorsHostile(asHouse, mara) == false,
    "the same group authored as a household does not engage")
assert(C.updateFaction(defs, gangOne.id, { profile = "robbers" }) == true)
local again, againRecord = spawnFromCreator("Rook Again", "road-g", gangOne)
assert(againRecord.profile == "robbers" and againRecord.attitude == nil,
    "the kind change re-derives the stance instead of keeping the old copy")
assert(P.areSurvivorsHostile(again, mara) == true,
    "flipping the kind back resumes the engagement")

-- An explicit group stance, set through the creator's own edit path, still wins.
assert(C.updateFaction(defs, gangOne.id, { attitude = "friendly" }) == true)
local peaceful, peacefulRecord = spawnFromCreator("Peaceful Rook", "road-h", gangOne)
assert(peacefulRecord.attitude == "friendly", "an explicit stance is stored on the person")
assert(P.areSurvivorsHostile(peaceful, mara) == false,
    "an explicit friendly stance beats the robber kind")
assert(C.updateFaction(defs, gangOne.id, { attitude = "hostile" }) == true)
local restored, restoredRecord = spawnFromCreator("Rook Restored", "road-i", gangOne)
assert(restoredRecord.attitude == nil, "returning to the kind's own stance stores no copy")
assert(P.areSurvivorsHostile(restored, mara) == true, "and the kind answers again")

-- 12. Same-group non-engagement and stance stability, still through the real
-- authoring path: each person below comes from Creator.recordFor on a real group.
local mateA = spawnFromCreator("Rook Mate", "road-j", gangOne)
local mateB = spawnFromCreator("Rook Sister", "road-k", gangOne)
local rival = spawnFromCreator("Bridge Rook", "road-l", gangTwo)
assert(P.areSurvivorsHostile(mateA, mateB) == false,
    "two spawned robbers of the same creator group do not engage each other")
assert(P.getSurvivorDisposition(mateA, mateB) == "allied",
    "they read as one group, not merely as non-hostile")
assert(P.areSurvivorsHostile(mateA, rival) == true,
    "a spawned robber still engages a member of a different robber group")
assert(P.areSurvivorsHostile(mateB, rival) == true,
    "and so does the other member of that group")

-- Repeated calls must agree for the same stored person, including the looter
-- kind whose stance is a stable roll rather than a fixed answer.
local looterA = idsA[1]
local firstLooterAnswer = P.areSurvivorsHostile(looterA, mara)
for i = 1, 25 do
    assert(P.areSurvivorsHostile(realRobber, mara) == true,
        "the robber answer is stable on repeat " .. tostring(i))
    assert(P.areSurvivorsHostile(realHouse, mara) == false,
        "the household answer is stable on repeat " .. tostring(i))
    assert(P.areSurvivorsHostile(looterA, mara) == firstLooterAnswer,
        "the looter roll is stable on repeat " .. tostring(i))
    assert(P.areSurvivorsHostile(mateA, mateB) == false,
        "the same-group answer is stable on repeat " .. tostring(i))
end

-- A reload of the persisted record answers the same way.
local reloaded = assert(P.getSurvivorCreatorRecord(realRobber), "the record reloads")
assert(reloaded.attitude == nil, "the reloaded record still carries no copied stance")
assert(P.setSurvivorCreatorRecord(realRobber, reloaded) == true, "the record is written back")
assert(P.areSurvivorsHostile(realRobber, mara) == true,
    "a reload of the persisted record keeps the same answer")
local reloadedLooter = assert(P.getSurvivorCreatorRecord(looterA), "the looter record reloads")
assert(P.setSurvivorCreatorRecord(looterA, reloadedLooter) == true, "the looter record is written back")
assert(P.areSurvivorsHostile(looterA, mara) == firstLooterAnswer,
    "a reload keeps the looter answer too")

-- A kind that does not engage outsiders never engages on any call.
for i = 1, 10 do
    assert(P.areSurvivorsHostile(realHouse, mara) == false,
        "a household never engages on call " .. tostring(i))
end

-- 13. A saved roster file must not turn the kind's default into a stored choice.
local fileRoster = { { name = "Rook File", look = "casual", kit = "none",
    pack = "meal", slots = {}, faction = gangOne.id } }
local fileText = C.encode(fileRoster, { name = "Road Robbers File", defs = defs,
    factionId = gangOne.id })
assert(type(fileText) == "string" and fileText:find("knox-creator", 1, true) ~= nil,
    "the roster encodes")
local loadedRoster, loadedGroup = C.decode(fileText)
assert(#loadedRoster == 1 and type(loadedGroup) == "table", "the roster decodes")
local loadedEntry
for _, entry in ipairs(loadedGroup.defs) do
    if entry.id == gangOne.id then loadedEntry = entry end
end
assert(loadedEntry ~= nil, "the group definition survives the file")
assert(loadedEntry.attitude == nil,
    "the file does not store the kind's default as a chosen stance")
assert(C.profileFor(gangOne.id, loadedGroup.defs).attitude == "hostile",
    "the decoded group still answers as a robber")

local fromFile = C.recordFor(loadedRoster[1], { defs = loadedGroup.defs,
    factionId = gangOne.id })
assert(fromFile ~= nil and fromFile.attitude == nil,
    "a person authored from the reloaded file stores no copied stance")
slotCounter = slotCounter + 1
local fileSlot = slotCounter
local fileRobber = assert(P.allocateWorldSurvivor({ source = "world_building",
    buildingId = "road-m", key = "road-m#" .. tostring(fileSlot),
    x = 1000 + fileSlot, y = 2000 + fileSlot * 2, z = 0, context = "generic" }, 60),
    "the reloaded person is allocated")
assert(P.setSurvivorCreatorRecord(fileRobber, fromFile) == true)
assert(P.areSurvivorsHostile(fileRobber, mara) == true,
    "a robber authored from the reloaded file still engages")

-- An explicit stance is a choice and survives the file.
assert(C.updateFaction(defs, gangOne.id, { attitude = "friendly" }) == true)
local peaceText = C.encode({ { name = "Peace File", look = "casual", kit = "none",
    pack = "meal", slots = {}, faction = gangOne.id } },
    { name = "Peace File Group", defs = defs, factionId = gangOne.id })
local _, peaceGroup = C.decode(peaceText)
local peaceEntry
for _, entry in ipairs(peaceGroup.defs) do
    if entry.id == gangOne.id then peaceEntry = entry end
end
assert(peaceEntry ~= nil and peaceEntry.attitude == "friendly",
    "an explicit stance survives the file")
assert(C.updateFaction(defs, gangOne.id, { attitude = "hostile" }) == true)

print("group_kind_behaviour ok households=3 robbers=2 looters=2 solo=1")
