local Stories = rawget(_G, "KnoxOffscreenStories") or {}
_G.KnoxOffscreenStories = Stories

-- Suspends all storylet resolution while true. The packaged regression
-- suite pins exact legacy simulation numbers, so those tests set this flag
-- (it survives module reloads, unlike fields on this table). Live play
-- leaves it unset. See tools/test-offscreen-stories.lua for covered behavior
-- with the engine enabled.
--   _G.KnoxOffscreenStoriesDisabled = true

-- Bounded nearby stored-survivor encounters use canonical people/positions.
-- Condition and ordinary travel belong to UnloadedSurvival, never random
-- narrative rewards or penalties. Historical story records remain readable.
--
-- Hard rules (never relaxed):
--   * No hunger/thirst relief: only real items relieve needs.
--   * No condition changes and no items, loot, or supplies of any kind.
--   * No world mutation: effects land on the survivor ledger, relationship
--     records, queued scar traces, and the activity feed only.
--   * Away-team, event-owned, and non-hibernated survivors are never touched.

local HISTORY_CAP = 12
local MEET_RADIUS_TILES = 60
local CANDIDATE_SCAN_CAP = 48

local function stableHash(text)
    local result = 5381
    text = tostring(text or "")
    for index = 1, #text do
        result = (result * 33 + string.byte(text, index)) % 2147483647
    end
    return result
end

local function nowHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and tonumber(getGameTime():getWorldAgeHours()) or 0
end

local function persistence()
    return rawget(_G, "KnoxPersistence")
end

local function pushHistory(state, entry)
    if type(state.history) ~= "table" then state.history = {} end
    entry.t = tonumber(entry.t) or nowHours()
    state.history[#state.history + 1] = entry
    while #state.history > HISTORY_CAP do
        table.remove(state.history, 1)
    end
end

local function feed(text)
    print("[KnoxSurvivors][Story] " .. tostring(text))
end

local function virtualPosition(state)
    local x = tonumber(state.virtualX)
    local y = tonumber(state.virtualY)
    local z = tonumber(state.virtualZ) or 0
    if x == nil or y == nil then return nil end
    return x, y, z
end

-- Deterministic roll in [0, 100) for this survivor, phase, and purpose.
-- Same ledger state always yields the same outcome: no save/load desync.
local function rollFor(id, phase, purpose)
    return stableHash(tostring(id) .. ":" .. tostring(phase) .. ":" .. tostring(purpose)) % 100
end

local function dutyAllows(id)
    local persist = persistence()
    if persist == nil or persist.getSurvivorDuty == nil then return true end
    local ok, duty = pcall(persist.getSurvivorDuty, id)
    if not ok or type(duty) ~= "table" then return true end
    if duty.eventId ~= nil then return false end
    if duty.mode == "away" then return false end
    return true
end

local function socialAllows(id, state)
    local persist = persistence()
    if persist == nil then return false end
    local affiliation = persist.getSurvivorAffiliation ~= nil
        and persist.getSurvivorAffiliation(id) or nil
    local duty = persist.getSurvivorDuty ~= nil and persist.getSurvivorDuty(id) or nil
    if type(affiliation) == "table" and affiliation.kind == "player" then return false end
    if type(duty) ~= "table" or duty.mode == nil then return true end
    if duty.mode == "companion" or duty.mode == "away" or duty.eventId ~= nil then return false end
    if duty.mode == "base" then
        local activity = type(state) == "table" and tostring(state.activity or "") or ""
        return type(affiliation) == "table" and affiliation.kind == "faction"
            and (activity == "base_life" or activity == "sheltering")
    end
    return true
end

local function encounterDisposition(firstId, secondId)
    local persist = persistence()
    if persist == nil or persist.getSurvivorDisposition == nil then return nil end
    local ok, disposition = pcall(persist.getSurvivorDisposition, firstId, secondId)
    if not ok then return nil end
    disposition = tostring(disposition or "")
    if disposition == "neutral" or disposition == "hostile" then return disposition end
    return nil
end

function Stories.canEncounterPair(firstId, secondId)
    if type(firstId) ~= "string" or type(secondId) ~= "string" or firstId == secondId then
        return false
    end
    return encounterDisposition(firstId, secondId) ~= nil
end

local function nearbyStored(id, x, y, z)
    local persist = persistence()
    if persist == nil or persist.getActivatableSurvivorIds == nil then return {} end
    local ok, ids = pcall(persist.getActivatableSurvivorIds)
    if not ok or type(ids) ~= "table" then return {} end
    local found = {}
    local scanned = 0
    for _, otherId in ipairs(ids) do
        if scanned >= CANDIDATE_SCAN_CAP then break end
        scanned = scanned + 1
        if otherId ~= id and type(otherId) == "string" then
            local alive = persist.isSurvivorAlive == nil
                or (pcall(persist.isSurvivorAlive, otherId) and persist.isSurvivorAlive(otherId) ~= false)
            local available = false
            local other = nil
            if alive and persist.getUnloadedSurvivalState ~= nil then
                local okState, fetched = pcall(persist.getUnloadedSurvivalState, otherId)
                if okState then other = fetched end
                if okState and type(other) == "table" and other.status == "hibernated"
                    and other.pendingMaterialization ~= true and other.restMode ~= "sleep" then
                    available = true
                    if persist.getSurvivorDuty ~= nil then
                        local okDuty, duty = pcall(persist.getSurvivorDuty, otherId)
                        if okDuty and type(duty) == "table"
                            and (duty.mode == "away" or duty.eventId ~= nil) then
                            available = false
                        end
                    end
                end
            end
            if available and socialAllows(otherId, other)
                and Stories.canEncounterPair(id, otherId) then
                local ox, oy, oz = virtualPosition(other)
                if ox ~= nil and oz == z then
                    local dx, dy = ox - x, oy - y
                    if dx * dx + dy * dy <= MEET_RADIUS_TILES * MEET_RADIUS_TILES then
                        found[#found + 1] = otherId
                    end
                end
            end
        end
    end
    table.sort(found)
    return found
end

--- Record a pending meet intent on both ledgers. Either side materializing
-- near the other lets the loaded encounter engine prioritize the pair.
-- Kinds: rob (hostile intent), befriend (first friendly contact), greet
-- (repeat friendly contact), tail (follow without contact; resolved later).
local function pairPhaseToken(id, otherId, phase)
    local first, second = tostring(id), tostring(otherId)
    if second < first then first, second = second, first end
    return first .. "::" .. second .. "@" .. tostring(math.floor(tonumber(phase) or 0))
end

local function partnerStateFor(otherId)
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return nil end
    local ok, state = pcall(persist.getUnloadedSurvivalState, otherId)
    if not ok or type(state) ~= "table" or state.status ~= "hibernated"
        or state.pendingMaterialization == true or state.restMode == "sleep" then
        return nil
    end
    return state
end

local function pairAlreadyProcessed(id, state, otherId, otherState, phase)
    local token = pairPhaseToken(id, otherId, phase)
    return state.lastOffscreenMeetToken == token
        or (type(otherState) == "table" and otherState.lastOffscreenMeetToken == token)
end

local function writePendingMeet(id, state, otherId, otherState, kind, hours, phase)
    if kind ~= "rob" and kind ~= "befriend" and kind ~= "greet" and kind ~= "tail" then
        return false
    end
    local persist = persistence()
    if persist == nil or persist.setUnloadedSurvivalState == nil
        or type(state) ~= "table" or type(otherState) ~= "table" then
        return false
    end
    local atHours = tonumber(hours) or nowHours()
    local token = pairPhaseToken(id, otherId, phase)
    -- Save the freshly-read partner ledger first. The caller owns `state` and
    -- persists it after the simulation step; fetching and saving another copy
    -- of it here would let that stale working copy erase this intent.
    otherState.pendingMeet = { with = id, kind = kind, atHours = atHours, pairPhase = token }
    otherState.lastOffscreenMeetToken = token
    local okSave, saved = pcall(persist.setUnloadedSurvivalState, otherId, otherState)
    if not okSave or saved == false then return false end
    state.pendingMeet = { with = otherId, kind = kind, atHours = atHours, pairPhase = token }
    state.lastOffscreenMeetToken = token
    return true
end

-- Physical condition, rest, weather exposure, transport and discovered supplies
-- require evidence from their real owners. A seeded story cannot supply it
-- (BUG-KS-079). Keep only the existing nearby stored-survivor encounter path.
local STORYLETS = {}

-- Stored proximity proposes contact with a real canonical person. Only the
-- loaded encounter owner can commit a conversation, hostility or shared memory.
STORYLETS.fellow_traveler = {
    activities = { exploring = true, seeking_supplies = true, group_travel = true, group_objective = true },
    chance = function() return 30 end,
    resolve = function(id, state, hours, phase)
        if not socialAllows(id, state) then return nil end
        local x, y, z = virtualPosition(state)
        if x == nil then return nil end
        local candidates = nearbyStored(id, x, y, z)
        if #candidates == 0 then return nil end
        local otherId = candidates[(stableHash(tostring(id) .. ":" .. tostring(phase) .. ":meet") % #candidates) + 1]
        local otherState = partnerStateFor(otherId)
        if otherState == nil or pairAlreadyProcessed(id, state, otherId, otherState, phase) then
            return nil
        end
        local disposition = encounterDisposition(id, otherId)
        if disposition == nil then return nil end
        -- Preserve established hostility; never create it from a seeded roll.
        local kind = disposition == "hostile" and "rob" or "greet"
        if not writePendingMeet(id, state, otherId, otherState, kind, hours, phase) then
            return nil
        end
        return "contact_pending"
    end,
}

local STORYLET_ORDER = { "fellow_traveler" }

local function activityChance(activity)
    if activity == "exploring" or activity == "group_travel" or activity == "group_objective" then
        return 38
    end
    if activity == "seeking_supplies" then return 36 end
    if activity == "sheltering" then return 14 end
    if activity == "base_life" then return 12 end
    return 10
end

local SCAR_RETURN_RADIUS_TILES = 30
--- Resolve at most one storylet for a hibernated survivor's simulation step.
-- @param id string survivor id
-- @param state table mutable survival ledger (history/scars appended in place)
-- @param hours number current world age hours
-- @param elapsed number hours covered by this step
-- @return string|nil outcome code, or nil when nothing happened
function Stories.resolveFor(id, state, hours, elapsed)
    if rawget(_G, "KnoxOffscreenStoriesDisabled") == true then return nil end
    if type(id) ~= "string" or type(state) ~= "table" then return nil end
    if state.status ~= "hibernated" or state.pendingMaterialization == true then return nil end
    if (tonumber(state.health) or 0) <= 0 then return nil end
    if state.restMode == "sleep" then return nil end
    if not dutyAllows(id) then return nil end
    hours = tonumber(hours) or nowHours()
    elapsed = math.max(0, tonumber(elapsed) or 0)
    if elapsed <= 0 then return nil end
    local activity = tostring(state.activity or "sheltering")
    local phase = math.floor(hours / 6)
    -- Persist the attempt, not only a successful outcome. Repeated scheduler
    -- calls and save/reload in the same window must never reroll a storylet.
    if tonumber(state.lastStoryAttemptPhase) == phase then return nil end
    state.lastStoryAttemptPhase = phase
    if rollFor(id, phase, "any:" .. activity) >= activityChance(activity) then
        return nil
    end
    local cursor = rollFor(id, phase, "pick")
    for _, key in ipairs(STORYLET_ORDER) do
        local storylet = STORYLETS[key]
        local allowed = storylet.activities[activity] == true
        if allowed then
            local chance = storylet.chance(activity)
            if cursor < chance then
                local ok, outcome = pcall(storylet.resolve, id, state, hours, phase)
                if ok and outcome ~= nil then
                    return tostring(outcome)
                end
                return nil
            end
            cursor = cursor - chance
        end
    end
    return nil
end

function Stories.historyFor(id)
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return {} end
    local ok, state = pcall(persist.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.history) ~= "table" then return {} end
    local copy = {}
    for index, entry in ipairs(state.history) do
        copy[index] = entry
    end
    return copy
end

--- Append a finalized loaded encounter to the existing survivor history.
-- The loaded relationship coordinator owns when an encounter is real; this
-- owner only stores the bounded fact. Missing ledgers are not synthesized.
function Stories.recordLoadedEncounter(id, otherId, outcome, hours)
    if type(id) ~= "string" or id == "" or type(otherId) ~= "string"
        or otherId == "" or id == otherId then
        return false, "invalid_identity"
    end
    local allowed = {
        friendly = true,
        joined = true,
        declined = true,
        parted = true,
        hostile = true,
    }
    if allowed[outcome] ~= true then return false, "invalid_outcome" end
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil
        or persist.setUnloadedSurvivalState == nil then
        return false, "history_unavailable"
    end
    local okRead, state = pcall(persist.getUnloadedSurvivalState, id)
    if not okRead or type(state) ~= "table" then
        return false, "canonical_history_missing"
    end
    local atHours = tonumber(hours) or nowHours()
    if type(state.history) == "table" then
        for _, entry in ipairs(state.history) do
            if type(entry) == "table" and entry.kind == "meet"
                and entry.with == otherId and entry.outcome == outcome
                and tonumber(entry.t) == atHours then
                return true, "already_recorded"
            end
        end
    end
    pushHistory(state, {
        kind = "meet",
        with = otherId,
        outcome = outcome,
        detail = "a loaded survivor encounter",
        t = atHours,
    })
    local okWrite, saved = pcall(persist.setUnloadedSurvivalState, id, state)
    if not okWrite or saved ~= true then return false, "history_write_failed" end
    return true, "recorded"
end

local function boundedText(value, maximum)
    if value == nil then return nil end
    local valueText = tostring(value):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if valueText == "" then return nil end
    maximum = math.max(1, tonumber(maximum) or 120)
    return #valueText > maximum and valueText:sub(1, maximum) or valueText
end

local function normalizeHistoryEntry(entry)
    if type(entry) ~= "table" then return nil end
    local kind = boundedText(entry.kind, 32)
    if kind == nil then return nil end
    return {
        kind = kind,
        outcome = boundedText(entry.outcome, 48),
        detail = boundedText(entry.detail, 160),
        with = boundedText(entry.with, 96),
        atHours = tonumber(entry.t),
    }
end

--- Read-only, newest-first survivor memory for UI and integrations. The
-- count and strings are bounded so malformed legacy data cannot grow a card
-- or expose arbitrary nested persistence state.
function Stories.recentHistoryFor(id, limit)
    local history = Stories.historyFor(id)
    local maximum = math.max(0, math.min(5, math.floor(tonumber(limit) or 3)))
    if maximum == 0 then return {} end
    local recent = {}
    for index = #history, 1, -1 do
        local entry = normalizeHistoryEntry(history[index])
        if entry ~= nil then recent[#recent + 1] = entry end
        if #recent >= maximum then break end
    end
    return recent
end

function Stories.scarsFor(id)
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return {} end
    local ok, state = pcall(persist.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.scars) ~= "table" then return {} end
    local copy = {}
    for index, entry in ipairs(state.scars) do
        copy[index] = entry
    end
    return copy
end

--- Remove consumed scar traces after world resolution. Never fabricates.
function Stories.clearScars(id, keepNewerThanHours)
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return false end
    local ok, state = pcall(persist.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.scars) ~= "table" then return false end
    local cutoff = tonumber(keepNewerThanHours) or 0
    local kept = {}
    for _, scar in ipairs(state.scars) do
        if tonumber(scar.t) ~= nil and tonumber(scar.t) > cutoff then
            kept[#kept + 1] = scar
        end
    end
    state.scars = kept
    if persist.setUnloadedSurvivalState ~= nil then
        pcall(persist.setUnloadedSurvivalState, id, state)
    end
    return true
end

--- Resolve queued scar traces against a materialized body. Places remember:
-- returning near a scar site appends history, announces fight sites on the
-- feed, and consumes the trace. Geometry (corpses, barricades, blood) is
-- deliberately NOT fabricated: only the engine or loaded survivors carrying
-- real items may change the world. Returns the count resolved.
function Stories.resolveScars(id, character, hours)
    if type(id) ~= "string" or character == nil then return 0 end
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return 0 end
    local ok, state = pcall(persist.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.scars) ~= "table"
        or #state.scars == 0 then
        return 0
    end
    local okSquare, square = pcall(function() return character:getCurrentSquare() end)
    if not okSquare or square == nil or square.getX == nil then return 0 end
    local cx, cy, cz = tonumber(square:getX()), tonumber(square:getY()), tonumber(square:getZ()) or 0
    if cx == nil or cy == nil then return 0 end
    hours = tonumber(hours) or nowHours()
    local resolved, kept = 0, {}
    for _, scar in ipairs(state.scars) do
        local consumed = false
        if type(scar) == "table" and tonumber(scar.x) ~= nil
            and tonumber(scar.z or cz) == cz then
            local dx, dy = tonumber(scar.x) - cx, tonumber(scar.y) - cy
            if dx * dx + dy * dy <= SCAR_RETURN_RADIUS_TILES * SCAR_RETURN_RADIUS_TILES then
                consumed = true
                resolved = resolved + 1
                if scar.kind == "fight" then
                    pushHistory(state, {
                        kind = "scar", detail = "came back to where weapons were drawn",
                        with = scar.with, outcome = "returned",
                    })
                    feed("id=" .. tostring(id) .. " returned to a fight site")
                else
                    pushHistory(state, {
                        kind = "scar", detail = "came back to where blood was left",
                        outcome = "returned",
                    })
                end
            end
        end
        if not consumed then kept[#kept + 1] = scar end
    end
    state.scars = kept
    if persist.setUnloadedSurvivalState ~= nil then
        pcall(persist.setUnloadedSurvivalState, id, state)
    end
    return resolved
end

return Stories
