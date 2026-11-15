local P, C = assert(KnoxPersistence), assert(KnoxAutonomyController)
local oldData = data
data = {}
local owner = "supply-intent-owner"
local base = assert(P.createBase("player", owner, { minX = 70, minY = 70, width = 2, height = 2, z = 0 }, 10))
local kinds = { "find_food", "find_water", "find_medical", "find_weapon", "find_tools",
    "find_wood", "find_materials", "find_clothing", "find_ammo", "find_fuel" }
local point = { getX = function() return 100 end, getY = function() return 200 end, getZ = function() return 0 end }
for _, kind in ipairs(kinds) do
    local id = "intent-" .. kind
    assert(P.setRecord(id, expectedRecord))
    assert(P.setPlayerCompanion(id, owner, "hold", 10))
    assert(P.setPlayerBaseResident(id, owner, base.id, 10))
    local item = kind == "find_materials" and "Base.Nails" or nil
    assert(P.setBaseSupplyOrder(id, owner, base.id, kind, 10, 24, item))
    assert(P.beginBaseSupplyRun(id, base.id, kind, 10))
    local c = setmetatable({ id = id }, { __index = C })
    assert(c:setLifeIntent(kind, "traveling", point, "container:100:200:0"))
    local saved = P.getSurvivorLifeIntent(id)
    assert(saved ~= nil and saved.kind == kind and saved.targetX == 100 and saved.targetY == 200,
        "every existing supply order commits its real controller travel intent: " .. kind)
end
local id = "intent-find_materials"
assert(not P.setSurvivorLifeIntent(id, { kind = "travel_area", phase = "traveling" }, 11),
    "base duty still refuses unrelated autonomous itineraries")
assert(not P.setSurvivorLifeIntent(id, { kind = "invented_supply", phase = "traveling" }, 11),
    "unknown intent kinds remain invalid")
assert(P.getSurvivorLifeIntent(id).kind == "find_materials", "a refused write preserves the committed purpose")
supplyIntentGraph = { KnoxSurvivors_IsoPlayer = data.KnoxSurvivors_IsoPlayer }
function verifySupplyIntentReload()
    for _, kind in ipairs(kinds) do
        local saved = assert(P.getSurvivorLifeIntent("intent-" .. kind), "typed intent survives native codec")
        local duty = assert(P.getSurvivorDuty("intent-" .. kind))
        assert(saved.kind == kind and saved.phase == "traveling" and saved.targetX == 100
            and saved.targetY == 200 and saved.targetZ == 0 and saved.targetKey == "container:100:200:0",
            "the native codec retains each existing supply purpose and destination")
        assert(duty.mode == "base" and duty.baseId == base.id and duty.activeSupplyRun.kind == kind,
            "intent reload preserves the existing base duty and active trip")
        if kind == "find_materials" then
            assert(duty.baseSupplyOrder.item == "Base.Nails", "the exact fetch item survives the same codec round trip")
        end
    end
end
data = oldData
print("Supply intent coherence PASS existingKinds=10 realController=true realWriter=true unrelatedRefused=true nativeGameplay=false")
