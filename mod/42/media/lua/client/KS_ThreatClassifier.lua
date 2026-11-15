local Threats = rawget(_G, "KnoxThreatClassifier") or {}
_G.KnoxThreatClassifier = Threats

-- Build 42 uses an IsoZombie as the physical grapple representation of a
-- carried corpse. It is not alive for AI purposes even when isDead() is false.
-- The engine flag distinguishes that body from actual zombie reanimation.
-- The flag accessor must only run on zombies: on a human shell the lookup
-- throws a Java exception that pcall cannot catch, which used to kill the
-- whole threat scan the moment a hostile faction appeared.
function Threats.isCorpseProxy(character)
    if character == nil then return false end
    local isZombie = false
    if rawget(_G, "instanceof") ~= nil then
        local okType, result = pcall(function()
            return instanceof(character, "IsoZombie")
        end)
        isZombie = okType and result == true
    else
        local okType, result = pcall(function() return character:isZombie() end)
        isZombie = okType and result == true
    end
    if not isZombie then return false end
    local ok, proxy = pcall(function() return character:isReanimatedForGrappleOnly() end)
    return ok and proxy == true
end
-- Read-only Bandits boundary. The owning mod supplies disposition; an identified
-- body with unreadable ownership is not silently treated as an ordinary zombie.
function Threats.banditDisposition(character)
    if character == nil or character.getVariableBoolean == nil then return nil end
    local marked, bandit = pcall(function() return character:getVariableBoolean("Bandit") end)
    if not marked or bandit ~= true then return nil end
    local api = rawget(_G, "Bandit")
    if type(api) ~= "table" or type(api.IsHostile) ~= "function" then return "unknown" end
    local ok, hostile = pcall(api.IsHostile,character)
    if ok and hostile == true then return "hostile" end
    if ok and hostile == false then return "neutral" end
    return "unknown"
end

function Threats.ignoreForeignNpc(character)
    local disposition=Threats.banditDisposition(character)
    return disposition == "neutral" or disposition == "unknown"
end
return Threats
