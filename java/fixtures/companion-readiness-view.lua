-- Real production ViewModel after the journey/save event and after each actual
-- B42 table-codec round. Observer/actor contact remain explicit doubles.
local players={}
for index,id in ipairs({"codec-owner","codec-other"}) do
    local observerId=id
    players[index-1]={getModData=function() return {KnoxSurvivors={playerId=observerId}} end,
        CanSee=function() return false end}
end
getSpecificPlayer=function(index) return players[index] end
KnoxSurvivorNeeds.thresholds={hunger=.65,thirst=.65,fatigue=.72,lowEndurance=.25}
function verifyReadinessView()
    local view=KnoxSurvivorViewModel
    local owner=view.getSurvivor("codec-person",0)
    local other=view.getSurvivor("codec-person",1)
    assert(owner.trust==nil and owner.trustLabel=="Wary" and other.trustLabel=="Unknown")
    assert(owner.health==.65 and owner.knowledge.reportAtHours==11
        and owner.needSummary=="Last reported (60 min ago): Hurt, Food")
    assert(other.health==nil and other.knowledge.reportAtHours==nil)
    assert(owner.position.x==102 and other.position.x==50 and owner.order=="follow")
    assert(KnoxPersistence.getUnloadedSurvivalState("codec-person").health==91,
        "real current capture cannot overwrite observer-specific historical condition")
    assert(KnoxPersistence.getPlayerRelationshipSnapshot("codec-owner","codec-person").trust==0,
        "viewing or loading cannot silently forgive recorded harm")
end
verifyReadinessView()
print("Readiness projection PASS qualitative=true reports_dated=true separate_observers=true current_capture_not_report=true actual_codec_rounds_follow=true")
