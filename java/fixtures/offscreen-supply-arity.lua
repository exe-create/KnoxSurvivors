-- A hungry hibernated survivor asks the ordinary Java bridge for real food.
-- Its three-argument method must not receive the communal-only fields.
local previousBridge = KnoxJavaBridge
local prior = KnoxPersistence.getUnloadedSurvivalState("codec-person")
local calls = 0
KnoxJavaBridge = {
    getNpcCharacter = function() return nil end,
    consumeNpcRecordSupply = function(self, encoded, kind, amount, ...)
        assert(select("#", ...) == 0, "ordinary supply mutator received communal-only arguments")
        assert(encoded == KnoxPersistence.getRecord("codec-person"))
        assert(kind == "food" or kind == "water")
        assert(type(amount) == "number" and amount > 0)
        calls = calls + 1
        return nil -- No actual item receipt: needs must not improve.
    end,
}
local ok, status = KnoxUnloadedSurvival.advanceHibernated("codec-person", 13)
assert(ok == true and calls > 0, "hungry survivor must request real stored food")
local after = KnoxPersistence.getUnloadedSurvivalState("codec-person")
assert(after.hunger >= prior.hunger, "missing food must not relieve hunger")
assert(KnoxPersistence.setUnloadedSurvivalState("codec-person", prior))
KnoxJavaBridge = previousBridge
print("Offscreen supply arity PASS ordinary_method=true no_fabricated_meal=true")
