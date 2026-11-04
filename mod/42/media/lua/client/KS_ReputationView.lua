-- One read-out for standing. This module formats what the save really holds,
-- never writes a relationship and never merges a person's trust with their
-- faction's diplomacy. The survivor card, the Talk panel and any later roster
-- read from here so the same relationship cannot be described two ways.
local ReputationView = rawget(_G, "KnoxReputationView") or {}
_G.KnoxReputationView = ReputationView

local PERSONAL_MIN, PERSONAL_MAX = 0, 100
local FACTION_MIN, FACTION_MAX = -100, 100

-- Ordered high to low. These are the bands the card already used, so an old
-- save and a new one never change what "Cautious" means.
local PERSONAL_BANDS = {
    { at = 70, label = "Trusting", tone = "friendly" },
    { at = 40, label = "Cautious", tone = "cautious" },
    { at = 0, label = "Wary", tone = "wary" },
}

local DISPOSITION_LABELS = {
    allied = "Allied",
    neutral = "Neutral",
    hostile = "Hostile",
}

-- Cause keys are the ones the save really writes: contribution kinds, social
-- acts, passive proximity and aggression. An unknown key stays silent rather
-- than showing an internal code to the player.
local TRUST_CAUSES = {
    nearby = "stood nearby",
    talk = "talked with you",
    defense = "defended them",
    gift = "took your gift",
    trade = "traded with you",
    treatment = "was treated by you",
    construction = "saw you work on their base",
    aggression = "was attacked by you",
    joke = "shared a joke",
    compliment = "was complimented",
    funny_face = "shared a laugh",
    insult = "was insulted",
    slap = "was hit by you",
}

local REPUTATION_CAUSES = {
    defense = "you helped defend them",
    gift = "you gave them supplies",
    trade = "you traded with them",
    treatment = "you treated their wounds",
    construction = "you helped at their base",
    aggression = "you attacked one of them",
}

local function number(value)
    local parsed = tonumber(value)
    if parsed == nil or parsed ~= parsed then return nil end
    return parsed
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function rounded(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function signed(value)
    local amount = rounded(value)
    return amount > 0 and ("+" .. tostring(amount)) or tostring(amount)
end

local function deltaText(delta, causes, cause, fallback)
    local applied = number(delta)
    if applied == nil or applied == 0 then return nil end
    local words = causes ~= nil and causes[tostring(cause or "")] or nil
    return signed(applied) .. " · " .. (words or fallback)
end

-- The band describes the personal relationship record. Faction hostility is
-- deliberately not folded in here: the card shows that as its own state and
-- its own faction bar, so a trusting person in a hostile faction keeps both
-- truths visible.
function ReputationView.personalLabel(trust)
    local value = number(trust)
    if value == nil then return "Unknown" end
    for _, band in ipairs(PERSONAL_BANDS) do
        if value >= band.at then return band.label end
    end
    return "Wary"
end

-- relationship is the flat player-relationship snapshot. A nil snapshot is an
-- honest "unknown"; it must never be rendered as a neutral score.
function ReputationView.personal(relationship, hostile)
    local trust = number(relationship ~= nil and relationship.trust or nil)
    if trust == nil then
        return {
            kind = "personal",
            known = false,
            label = "Unknown",
            tone = "unknown",
        }
    end
    trust = clamp(trust, PERSONAL_MIN, PERSONAL_MAX)
    local band, nextBand = PERSONAL_BANDS[#PERSONAL_BANDS], nil
    for index, candidate in ipairs(PERSONAL_BANDS) do
        if trust >= candidate.at then
            band = candidate
            nextBand = index > 1 and PERSONAL_BANDS[index - 1] or nil
            break
        end
    end
    local isHostile = hostile == true
    local nextText = nil
    if nextBand ~= nil then
        nextText = tostring(math.max(1, math.ceil(nextBand.at - trust)))
            .. " to " .. nextBand.label
    else
        nextText = "Fully trusted"
    end
    local cause = relationship ~= nil and relationship.lastTrustCause or nil
    local delta = number(relationship ~= nil and relationship.lastTrustDelta or nil)
    return {
        kind = "personal",
        known = true,
        hostile = isHostile,
        hostileText = isHostile and "Hostile right now" or nil,
        label = band.label,
        tone = band.tone,
        score = trust,
        min = PERSONAL_MIN,
        max = PERSONAL_MAX,
        fill = (trust - PERSONAL_MIN) / (PERSONAL_MAX - PERSONAL_MIN),
        percent = rounded(trust),
        nextLabel = nextBand ~= nil and nextBand.label or nil,
        nextAt = nextBand ~= nil and nextBand.at or nil,
        nextText = nextText,
        delta = delta,
        cause = cause,
        deltaText = deltaText(delta, TRUST_CAUSES, cause, "their trust changed"),
    }
end

-- relationship is the faction-diplomacy row. Its disposition is the authority
-- on whether the faction is allied or hostile; the reputation score is the
-- signed bar underneath it. Neither is the person's own trust.
function ReputationView.faction(relationship, factionName)
    local name = type(factionName) == "string" and factionName or nil
    if type(relationship) ~= "table" then
        return {
            kind = "faction",
            known = false,
            name = name,
            label = "No contact recorded",
            shortLabel = "No contact",
            tone = "unknown",
            fill = 0.5,
            zero = 0.5,
        }
    end
    local disposition = tostring(relationship.disposition or "neutral")
    local score = clamp(number(relationship.reputation) or 0, FACTION_MIN, FACTION_MAX)
    local cause = relationship.lastReputationCause or relationship.reason
    if cause == "player_aggression" then cause = "aggression" end
    local delta = number(relationship.lastReputationDelta)
    return {
        kind = "faction",
        known = true,
        name = name,
        label = DISPOSITION_LABELS[disposition] or "Neutral",
        shortLabel = DISPOSITION_LABELS[disposition] or "Neutral",
        tone = disposition == "allied" and "friendly" or disposition,
        score = score,
        min = FACTION_MIN,
        max = FACTION_MAX,
        fill = (score - FACTION_MIN) / (FACTION_MAX - FACTION_MIN),
        zero = (0 - FACTION_MIN) / (FACTION_MAX - FACTION_MIN),
        delta = delta,
        cause = cause,
        deltaText = deltaText(delta, REPUTATION_CAUSES, cause, "their standing changed"),
    }
end

-- Read-only lookup. No relationship is created for a faction the player has
-- never dealt with; that absence is shown as "No contact recorded".
function ReputationView.factionFor(playerId, survivorId)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or type(playerId) ~= "string" or playerId == ""
        or type(survivorId) ~= "string" or survivorId == "" then
        return nil
    end
    if persistence.getSurvivorAffiliation == nil or persistence.getFaction == nil
        or persistence.getPlayerFaction == nil then
        return nil
    end
    local okAffiliation, affiliation = pcall(persistence.getSurvivorAffiliation,
        survivorId)
    if not okAffiliation or type(affiliation) ~= "table"
        or affiliation.factionId == nil then
        return nil
    end
    local factionId = affiliation.factionId
    local okFaction, faction = pcall(persistence.getFaction, factionId)
    if not okFaction or type(faction) ~= "table" or faction.kind == "player" then
        return nil
    end
    local okPlayerFaction, playerFaction = pcall(persistence.getPlayerFaction,
        playerId)
    if not okPlayerFaction or type(playerFaction) ~= "table"
        or playerFaction.id == nil or tostring(playerFaction.id) == tostring(factionId) then
        return nil
    end
    local relationship = nil
    if persistence.getFactionRelationship ~= nil then
        local okRelationship, saved = pcall(persistence.getFactionRelationship,
            playerFaction.id, factionId)
        if okRelationship and type(saved) == "table" then relationship = saved end
    end
    return ReputationView.faction(relationship,
        faction.name or faction.id or factionId)
end

-- Both answers together, kept in separate fields so no caller can accidentally
-- read a faction bar as the person's own trust.
function ReputationView.forSurvivor(playerId, survivorId, relationship, hostile)
    return {
        personal = ReputationView.personal(relationship, hostile == true),
        faction = ReputationView.factionFor(playerId, survivorId),
    }
end

return ReputationView
