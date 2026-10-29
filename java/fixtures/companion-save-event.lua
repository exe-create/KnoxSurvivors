-- Production OnSave -> runtime receipt reconciliation -> capture -> loaded
-- ledger -> real B42 codec (Java runner). Actor/bridge/needs remain explicit doubles.
local p=KnoxPersistence
local c,body=journeyController,journeyBody
body.x,body.y=105,205
assert(KnoxSurvivorRuntime.register("codec-person",c))
local reconciled,captured=0,0
local reconcile=c.recordSettlementLootReceipt
c.recordSettlementLootReceipt=function(self)
    reconciled=reconciled+1
    return reconcile(self)
end
KnoxJavaBridge={
    getActiveNpcIds=function() return "codec-person" end,
    getNpcCharacter=function(_,id) if id=="codec-person" then return body end end,
    captureNpcRecord=function(_,id)
        assert(id=="codec-person" and reconciled==captured+1,
            "real runtime reconciliation must precede native record capture")
        captured=captured+1
        return expectedRecord
    end,
    getTestNpcRecordX=function(_,record) assert(record==expectedRecord);return 105 end,
    getTestNpcRecordY=function(_,record) assert(record==expectedRecord);return 205 end,
    getTestNpcRecordZ=function(_,record) assert(record==expectedRecord);return 0 end,
}
KnoxSurvivorNeeds.snapshot=function(character)
    assert(character==body)
    return {hunger=expectedHunger,thirst=.3,fatigue=.2,endurance=.8,health=91}
end
assert(p.getRecord("codec-person")~=expectedRecord,"journey meal must not be durable before capture")
for pass=1,2 do
    savedHook()
    assert(captured==pass and reconciled==pass)
    verifyPersistedCompanion()
    local state=p.getUnloadedSurvivalState("codec-person")
    assert(state.status=="loaded" and state.virtualY==205,
        "active capture supersedes the dormant ledger with actual captured location")
end
print("Production save event PASS receipt_before_capture=true repeated_save=true loaded_ledger=true native_bridge_double=true")
