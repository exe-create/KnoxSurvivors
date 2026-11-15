-- Placement is installed on the creator owner; receipts live in world population state.
local World = {}
_G.KnoxCreatorWorld = World

local contexts = { police = "law_enforcement", military = "military", doctors = "medical", fire_service = "fire_service" }
local profiles = { custom=true, household=true, police=true, military=true, doctors=true, fire_service=true,
    solo=true, looters=true, robbers=true, cannibals=true }

local function matches(origin, profile)
    if type(origin) ~= "table" or origin.source ~= "world_building" or not origin.buildingId or not origin.key then return false end
    if type(profile.region) == "string" and profile.region ~= "" then
        local region = tostring(origin.region or ""):match("^%s*([^,]+)") or ""
        region = region:gsub("%s+$", "")
        if string.lower(region) ~= string.lower(profile.region) then return false end
    end
    local context = profile.spawnContext
    if not context or context == "default" then context = contexts[profile.profile] or (profile.profile == "household" and "household" or "any") end
    if context == "household" or context == "residential" then return origin.household == true or origin.residential == true end
    if context == "any" then return true end
    return origin.context == context
end

local function listCall(owner, method)
    if not owner or type(owner[method]) ~= "function" then return {} end
    local ok, result = pcall(owner[method])
    return ok and type(result) == "table" and result or {}
end

function World.install(Creator)
    function Creator.pendingWorldPlan(roster, group, catalog, state)
        local P = KnoxPersistence
        state.creatorRoster = type(state.creatorRoster) == "table" and state.creatorRoster or {}
        local receipts = state.creatorRoster
        -- Reconcile legacy creator records including dead survivors; their receipts
        -- prevent a template from resurrecting somebody on an upgrade.
        if P.getSurvivorCreatorRecord then
            for _, id in ipairs(listCall(P, "getAllWorldSurvivorIds")) do
                local record = P.getSurvivorCreatorRecord(id)
                if record and record.faction and record.name then
                    local key = record.faction .. ":" .. record.name
                    if receipts[key] == nil then receipts[key] = id end
                end
            end
        end
        local used = type(P.getUsedWorldOriginKeys) == "function" and P.getUsedWorldOriginKeys() or {}
        local occupied = {}
        for _, origin in ipairs(type(catalog) == "table" and catalog.origins or {}) do
            if origin.buildingId and used[origin.key] then occupied[origin.buildingId] = true end
        end
        local groups, order = {}, {}
        for _, person in ipairs(roster or {}) do
            -- Ticked out of the spawn pool: no cohort, no site, no receipt, no
            -- companion or spouse wiring - unless marked. A marked Spouse or
            -- Companion walks in with the player without joining the random
            -- pool, so the marks bypass the switch. The person stays in the
            -- file either way, so dev tools can still place them by hand.
            if Creator.spawnIncluded(person) or person.startSpouse == true
                or person.startCompanion == true then
                local id = Creator.personFactionId(person, group)
                if not groups[id] then groups[id] = { id=id, people={}, profile=Creator.profileFor(id, group.defs) }; order[#order + 1] = groups[id] end
                groups[id].people[#groups[id].people + 1] = person
            end
        end
        local complete = true
        for _, cohort in ipairs(order) do
            cohort.pending, cohort.sites = {}, {}
            for _, person in ipairs(cohort.people) do
                local receipt = receipts[cohort.id .. ":" .. person.name]
                if receipt then
                    if cohort.profile and cohort.profile.profile ~= "solo" and P.getSurvivorOrigin then
                        local origin = P.getSurvivorOrigin(receipt)
                        if origin and origin.source == "world_building" and origin.buildingId then
                            if cohort.buildingId and cohort.buildingId ~= origin.buildingId then cohort.incompatibleReceipt = true end
                            cohort.buildingId = cohort.buildingId or origin.buildingId
                        else cohort.incompatibleReceipt = true end
                    end
                else cohort.pending[#cohort.pending + 1] = person end
            end
            if not cohort.profile or not profiles[cohort.profile.profile] then
                cohort.reason = "unknown_profile"; complete = false
            elseif #cohort.pending > 0 and cohort.incompatibleReceipt then
                cohort.reason = "existing_origin_unavailable"; complete = false
            elseif #cohort.pending > 0 and cohort.profile.profile == "solo" then
                -- An independent survivor is not a group. Sharing one building was
                -- wrong here: it demanded N free origins in one house and then
                -- formed a travel group of people who belong to nothing. Each one
                -- takes its own site, and the group block below skips them.
                for index = 1, #cohort.pending do
                    local site = nil
                    local person = cohort.pending[index]
                    local soloProfile = {}
                    for key, value in pairs(cohort.profile) do soloProfile[key] = value end
                    soloProfile.spawnContext = person.spawnContext or soloProfile.spawnContext
                    soloProfile.region = person.region or soloProfile.region
                    for _, origin in ipairs(type(catalog) == "table" and catalog.origins or {}) do
                        if matches(origin, soloProfile) and not used[origin.key]
                            and not occupied[origin.buildingId] then
                            site = origin
                            break
                        end
                    end
                    if site ~= nil then
                        cohort.sites[index] = site
                        used[site.key], occupied[site.buildingId] = true, true
                    else
                        cohort.reason = "no_suitable_site"
                        complete = false
                        break
                    end
                end
            elseif #cohort.pending > 0 then
                local buildings, buildingOrder = {}, {}
                for _, origin in ipairs(type(catalog) == "table" and catalog.origins or {}) do
                    if matches(origin, cohort.profile) and not used[origin.key]
                        and (not occupied[origin.buildingId] or cohort.buildingId == origin.buildingId)
                        and (not cohort.buildingId or cohort.buildingId == origin.buildingId) then
                        if not buildings[origin.buildingId] then buildings[origin.buildingId] = {}; buildingOrder[#buildingOrder + 1] = origin.buildingId end
                        buildings[origin.buildingId][#buildings[origin.buildingId] + 1] = origin
                    end
                end
                for _, building in ipairs(buildingOrder) do
                    if #buildings[building] >= #cohort.pending then
                        cohort.buildingId = building
                        for i = 1, #cohort.pending do cohort.sites[i] = buildings[building][i]; used[cohort.sites[i].key] = true end
                        occupied[building] = true
                        break
                    end
                end
                if #cohort.sites < #cohort.pending then cohort.reason = "no_suitable_site"; complete = false end
            end
        end
        return order, complete
    end

    function Creator.spawnPending()
        local P = KnoxPersistence
        if not P or type(P.getPopulationState) ~= "function" then return 0, 0, "no_population_state" end
        local state = P.getPopulationState()
        if type(state) ~= "table" then return 0, 0, "no_population_state" end
        if Creator.preparedPopulation == state then return 0, 0, "ready" end
        local roster, group = Creator.load()
        if group.readOnly then return 0, 0, "creator_file_needs_review" end
        local catalog = KnoxWorldPopulation and KnoxWorldPopulation.spawnCatalog and KnoxWorldPopulation.spawnCatalog() or nil
        if type(catalog) ~= "table" then return 0, 0, "no_catalog" end
        local cohorts, complete = Creator.pendingWorldPlan(roster, group, catalog, state)
        local hours = 0
        pcall(function() hours = getGameTime():getWorldAgeHours() end)
        local added, degraded, reason = 0, 0, nil
        -- Fresh ids are this run's new allocations. Only they are walked in
        -- beside the player; receipts from earlier runs are already in the
        -- world, so a reload never yanks anyone anywhere.
        local freshIds, freshCompanions = {}, {}
        local living = {}
        for _, id in ipairs(listCall(P, "getLivingWorldSurvivorIds")) do living[id] = true end
        for _, cohort in ipairs(cohorts) do
            if cohort.reason then reason = reason or cohort.reason end
            if not cohort.reason then
                for i, person in ipairs(cohort.pending) do
                    local origin = {}
                    for key, value in pairs(cohort.sites[i]) do origin[key] = value end
                    if type(person.profession) == "string" and person.profession ~= "" then
                        origin.professionCandidates = {person.profession}
                    end
                    local ok, id = pcall(P.allocateWorldSurvivor, origin, hours)
                    if ok and id then
                        state.creatorRoster[cohort.id .. ":" .. person.name] = id
                        added = added + 1; living[id] = true; freshIds[id] = true
                    else complete = false; reason = reason or "allocation_failed" end
                end
                local members, ready = {}, true
                for _, person in ipairs(cohort.people) do
                    local id = state.creatorRoster[cohort.id .. ":" .. person.name]
                    if id then
                        local record = P.getSurvivorCreatorRecord and P.getSurvivorCreatorRecord(id)
                        if not record and living[id] then
                            local ok, result = pcall(P.setSurvivorCreatorRecord, id, Creator.recordFor(person, group))
                            if not ok or result ~= true then degraded = degraded + 1; ready = false; complete = false; reason = reason or "record_failed" end
                        end
                        if living[id] then members[#members + 1] = id end
                    else ready = false; complete = false end
                end
                -- Who walks in with the player: the creator's marks, companions
                -- capped by the sandbox limit and at most one spouse, applied
                -- through the same writers the recruit and spouse paths use.
                local startPlayer = getSpecificPlayer ~= nil and getSpecificPlayer(0) or nil
                local ownerId = startPlayer ~= nil and P.ensurePlayerId ~= nil
                    and P.ensurePlayerId(startPlayer) or nil
                -- Sandbox default 3; a missing settings table must not ban the cast.
                local limit = 3
                local settings = rawget(_G, "KnoxSettings")
                if settings ~= nil and settings.companionLimit ~= nil then
                    local limitOk, value = pcall(settings.companionLimit)
                    if limitOk then limit = tonumber(value) or 3 end
                end
                if startPlayer ~= nil then
                    local companions, spouse = Creator.startingSplit(cohort.people, limit)
                    if ownerId ~= nil and P.setPlayerCompanion ~= nil then
                        for _, person in ipairs(companions) do
                            local id = state.creatorRoster[cohort.id .. ":" .. person.name]
                            if id ~= nil and living[id] then
                                local saved = P.setPlayerCompanion(id, ownerId, "follow", hours)
                                if saved == false then degraded = degraded + 1 end
                                if freshIds[id] then freshCompanions[#freshCompanions + 1] = id end
                            end
                        end
                    end
                    -- Hand the reconcile pass the companions it must walk in.
                    if #freshCompanions > 0 then
                        local md = startPlayer:getModData()
                        md.KnoxSurvivors = md.KnoxSurvivors or {}
                        md.KnoxSurvivors.creatorStart = { companionIds = freshCompanions }
                    end
                    if spouse ~= nil then
                        local id = state.creatorRoster[cohort.id .. ":" .. spouse.name]
                        local spouseStart = rawget(_G, "KnoxSpouseStart")
                        if id ~= nil and living[id] and spouseStart ~= nil
                            and spouseStart.adopt ~= nil then
                            -- The marked spouse replaces the random reservation so
                            -- the spouse pass cannot introduce a second person.
                            local md = startPlayer:getModData()
                            md.KnoxSurvivors = md.KnoxSurvivors or {}
                            -- The reservation is written complete only once the marked
                            -- survivor is actually adopted, so a failed adoption
                            -- cannot block a later attempt with a phantom record.
                            if spouseStart.adopt(startPlayer, id) then
                                -- Fresh this run: the spouse pass places the
                                -- marked spouse beside the player, so the
                                -- reservation stays pending until then. Older
                                -- receipts keep the current complete marker.
                                if freshIds[id] then
                                    md.KnoxSurvivors.spouseStart = { status = "pending", id = id, marked = true }
                                else
                                    md.KnoxSurvivors.spouseStart = { status = "complete", id = id }
                                end
                            else
                                degraded = degraded + 1
                            end
                        end
                    end
                end
                if ready and #members >= 2 and cohort.profile.profile ~= "solo" and type(P.createTravelGroup) == "function" then
                    local existing, conflict = nil, false
                    if P.getTravelGroupFor then
                        for _, id in ipairs(members) do
                            local memberGroup = P.getTravelGroupFor(id)
                            if memberGroup then
                                if existing and existing.id ~= memberGroup.id then conflict = true end
                                existing = memberGroup
                            end
                        end
                        if existing then
                            local intended = {}
                            for _, id in ipairs(members) do intended[id] = true end
                            for _, id in ipairs(existing.memberIds or {}) do if not intended[id] then conflict = true end end
                            for _, id in ipairs(members) do if P.getTravelGroupFor(id) ~= existing then conflict = true end end
                        end
                    end
                    local travel = not conflict and (existing or P.createTravelGroup(members, hours)) or nil
                    if travel then
                        travel.originCohort = true
                        travel.background = contexts[cohort.profile.profile] or cohort.profile.profile
                        travel.populationAnchor = P.getSurvivorOrigin and P.getSurvivorOrigin(members[1]) or nil
                        if cohort.profile.profile == "household" then
                            travel.household, travel.homeBuildingId = true, cohort.buildingId
                            travel.householdName = cohort.profile.label
                        end
                        if string.sub(cohort.id, 1, 5) == "user_" then travel.name = cohort.profile.label end
                        if not existing and #members >= 3
                            and cohort.profile.settlementPolicy ~= "mobile" and cohort.profile.settlementPolicy ~= "independent"
                            and P.promoteTravelGroupToFaction then
                            local faction = P.promoteTravelGroupToFaction(travel.id, hours, 3)
                            if faction then faction.foundingPopulation = true; faction.background = faction.background or travel.background end
                        end
                    else complete = false; reason = reason or (conflict and "group_conflict" or "group_failed") end
                end
            end
        end
        if complete then Creator.preparedPopulation = state end
        return added, degraded, reason or "ready"
    end
end

return World
