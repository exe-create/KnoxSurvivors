local p=KnoxPersistence
for _,id in ipairs({"codec-owner","codec-other"}) do
    assert(p.ensurePlayerId({getModData=function() return {KnoxSurvivors={playerId=id}} end})==id)
end
assert(p.setRecord("codec-person",expectedRecord))
assert(p.setPlayerCompanion("codec-person","codec-owner","follow",10))
assert(p.rememberSurvivorPlayerContact("codec-person","codec-owner",{x=102,y=203,z=0,atHours=11,source="voice"}))
assert(p.rememberObserverKnowledge("codec-owner","codec-person","seen",{position={x=102,y=203,z=0},alive=true},11))
assert(p.rememberObserverKnowledge("codec-other","codec-person","seen",{position={x=50,y=60,z=0},alive=true},8))
-- Received information and actual social-ledger consequences are fixture inputs;
-- current physical capture must not silently refresh either observer's report.
assert(p.rememberObserverKnowledge("codec-owner","codec-person","report",{
    state={health=65,hunger=.8,thirst=.3,fatigue=.2,endurance=.8,bleedingParts=0},
    line="I am hurt and need food."},11))
assert(p.recordPlayerSocialAct("codec-owner","codec-person","slap",-20,2,10))
assert(p.recordPlayerSocialAct("codec-owner","codec-person","insult",-12,1,10))
local relation,cooldown=p.recordPlayerSocialAct("codec-owner","codec-person","insult",-12,1,10)
assert(relation.trust==0 and cooldown=="cooldown")
assert(p.setUnloadedSurvivalState("codec-person",{hunger=.6,thirst=.3,fatigue=.2,endurance=.8,health=91,
    lastHours=12,status="hibernated",virtualX=105,virtualY=205,virtualZ=0}))
-- Per-pass lookup candidates are runtime references, never durable ownership.
local originA=assert(p.allocateWorldSurvivor({x=105,y=205,z=0,key="codec-origin-a",region="Codec"},12))
local originB=assert(p.allocateWorldSurvivor({x=106,y=205,z=0,key="codec-origin-b",region="Codec"},12))
local savedGroup=assert(p.createTravelGroup({originA,originB},12))
local unused,oldCandidates=p.getTravelGroupsFor({originA,originB})
assert(p.getTravelGroupFor(originA,oldCandidates)==savedGroup)
function verifyReloadedGroupIndex()
    local current=KnoxPersistence
    assert(current.getTravelGroupFor(originA,oldCandidates)==nil,"old-world object cannot own a loaded group")
    local selected,freshCandidates=current.getTravelGroupsFor({originA,originB})
    local group=current.getTravelGroupFor(originA,freshCandidates)
    assert(group~=savedGroup and group.id==savedGroup.id and selected[originB]==group)
    assert(current.getUnloadedSurvivalState(originB).pendingMaterialization==true)
end
function verifyPersistedCompanion()
    local current=KnoxPersistence
    assert(current.getRecord("codec-person")==expectedRecord)
    local duty=current.getSurvivorDuty("codec-person")
    assert(duty.mode=="companion" and duty.order=="follow" and current.getSurvivorAffiliation("codec-person").ownerId=="codec-owner")
    assert(current.getSurvivorPlayerContact("codec-person","codec-owner").x==102)
    assert(current.getSurvivorPlayerContact("codec-person","codec-other")==nil)
    assert(current.getObserverKnowledge("codec-owner","codec-person").seen.value.position.x==102)
    assert(current.getObserverKnowledge("codec-other","codec-person").seen.value.position.x==50)
    assert(current.getPlayerRelationshipSnapshot("codec-owner","codec-person").trust==0)
    assert(current.getPlayerRelationshipSnapshot("codec-other","codec-person")==nil)
    assert(current.getObserverKnowledge("codec-owner","codec-person").report.value.state.health==65)
    assert(current.getObserverKnowledge("codec-owner","codec-person").report.atHours==11)
    assert(current.getObserverKnowledge("codec-other","codec-person").report==nil)
    local state=current.getUnloadedSurvivalState("codec-person")
    assert(state.virtualX==105 and state.health==91 and state.hunger==(expectedHunger or .6) and state.lastHours==12)
    assert(#current.getSurvivorIds()==1 and #current.getActivatableSurvivorIds()==3)
end
verifyPersistedCompanion()
