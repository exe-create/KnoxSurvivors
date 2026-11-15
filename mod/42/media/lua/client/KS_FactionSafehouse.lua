require "KS_Persistence"

local FactionSafehouse = rawget(_G, "KnoxFactionSafehouse") or {}
_G.KnoxFactionSafehouse = FactionSafehouse

local TAG = "[KnoxSurvivors][FactionSafehouse]"

local function ownerFor(faction)
    return "KnoxSurvivors:" .. tostring(faction.id)
end

function FactionSafehouse.ensure(faction, base)
    if base and (not faction or base.ownerKind ~= "faction" or base.ownerId ~= faction.id) then return nil, "wrong_owner" end
    local home = base and base.home or faction ~= nil and faction.homeBase or nil
    local binding = base or faction
    if home == nil then
        return nil, "no_home_base"
    end
    local owner = ownerFor(faction)
    local success, safehouse = pcall(function()
        local existing = SafeHouse.getSafehouseOverlapping(
            home.minX,
            home.minY,
            home.minX + home.width,
            home.minY + home.height
        )
        if existing ~= nil then
            if tostring(existing:getOwner()) == owner then
                -- Older saves used the faction id as the title. Upgrade only
                -- that generated title (or an empty one); player-customized
                -- safehouse names remain untouched.
                if existing.setTitle ~= nil and type(faction.name) == "string"
                    and faction.name ~= "" then
                    local currentTitle = ""
                    if existing.getTitle ~= nil then
                        local titleSuccess, title = pcall(function()
                            return existing:getTitle()
                        end)
                        if titleSuccess then currentTitle = tostring(title or "") end
                    end
                    if currentTitle == "" or currentTitle == "Knox faction " .. tostring(faction.id) then
                        existing:setTitle(faction.name .. " Safehouse")
                    end
                end
                return existing
            end
            error("overlaps_existing_safehouse owner=" .. tostring(existing:getOwner()))
        end
        local created = SafeHouse.addSafeHouse(
            home.minX,
            home.minY,
            home.width,
            home.height,
            owner
        )
        if created ~= nil then
            created:setTitle(
                type(faction.name) == "string" and faction.name ~= ""
                    and faction.name .. " Safehouse"
                    or "Knox faction " .. tostring(faction.id)
            )
        end
        return created
    end)
    if not success or safehouse == nil then
        return nil, tostring(safehouse)
    end
    local safehouseId = tostring(safehouse:getId())
    local newlyBound = binding.engineSafehouseId ~= safehouseId
    binding.engineSafehouseOwner = owner
    binding.engineSafehouseId = safehouseId
    if newlyBound then
        print(
            TAG .. " protected=" .. tostring(faction.id)
                .. " safehouse=" .. tostring(binding.engineSafehouseId)
                .. " owner=" .. owner
                .. " bounds=" .. tostring(home.minX) .. "," .. tostring(home.minY)
                    .. "," .. tostring(home.width) .. "," .. tostring(home.height)
        )
    end
    return safehouse, "protected"
end

function FactionSafehouse.ensureAll()
    for _, faction in pairs(KnoxPersistence.getFactions()) do
        if faction ~= nil and faction.militaryCommand then
            for _, base in ipairs(KnoxPersistence.getBasesForOwner("faction", faction.id)) do FactionSafehouse.ensure(faction, base) end
        elseif faction ~= nil and faction.homeBase ~= nil then
            local _, result = FactionSafehouse.ensure(faction)
            if result ~= "protected" then
                print(TAG .. " restore-failed=" .. tostring(faction.id)
                    .. " reason=" .. tostring(result))
            end
        end
    end
end

Events.OnGameStart.Add(FactionSafehouse.ensureAll)

return FactionSafehouse
