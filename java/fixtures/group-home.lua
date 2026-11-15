-- GH1 drives real owners; only streamed world objects/native queue are doubled.
groupHomePrior={data=data,Runtime=KnoxSurvivorRuntime,Manager=KnoxBaseManager,
    SafeHouse=SafeHouse,Cell=getCell,instanceof=instanceof,Queue=ISTimedActionQueue}
data={}
local P=KnoxPersistence
local ids={"gh-a","gh-b","gh-outsider","gh-c","gh-d"}
for _,id in ipairs(ids) do assert(P.setRecord(id,expectedRecord)) end
local group=assert(P.createTravelGroup({ids[1],ids[2]},20))
assert(P.setSurvivorCreatorRecord(ids[1],{name="Group Home Scout",profile="household",settlementPolicy="home"}))
local loaded,foreignSafehouse=true,false
local def={getID=function() return "gh-building" end,getX=function() return 100 end,
    getY=function() return 100 end,getX2=function() return 106 end,getY2=function() return 106 end,
    getW=function() return 6 end,getH=function() return 6 end,getRoomsNumber=function() return 3 end,
    getArea=function() return 36 end}
local food={fullType="Base.CannedFood",remainingHunger=.2}
local bottle={fullType="Base.WaterBottle",amount=.35}
local stockItems={food,bottle}
local physicalContainer={getItems=function() return {size=function() return #stockItems end,
    get=function(_,index) return stockItems[index+1] end} end}
local physicalObject={getContainer=function() return physicalContainer end,
    removeFromWorld=function() error("home release must not remove physical world objects") end}
local physicalObjects={size=function() return 1 end,get=function() return physicalObject end}
local function assertWorldStock()
    local actual=physicalObject:getContainer():getItems()
    assert(actual:size()==2 and actual:get(0)==food and actual:get(1)==bottle
        and food.remainingHunger==.2 and bottle.amount==.35,"logical home release preserves actual fixture-world items and remaining amounts")
end
local building={getDef=function() return def end,isResidential=function() return true end,hasWater=function() return true end}
local function square(x,y,z)
    return {getX=function() return x end,getY=function() return y end,getZ=function() return z or 0 end,
        getObjects=function() return physicalObjects end,
        RemoveTileObject=function() error("home release must not remove physical world objects") end,
        canStand=function() return true end,isOutside=function() return x<100 or y<100 or x>=106 or y>=106 end,
        getBuilding=function() return x>=100 and y>=100 and x<106 and y<106 and building or nil end}
end
local positions={ [ids[1]]=square(99,102),[ids[2]]=square(130,130),[ids[3]]=square(101,101) }
local characters={}
for _,id in ipairs(ids) do local key=id;characters[id]={getCurrentSquare=function() return positions[key] end,
    isDead=function() return false end,getInventory=function(self) return self.inventory end,inventory={}} end
getCell=function() return {getGridSquare=function(_,x,y,z) return loaded and square(x,y,z) or nil end} end
SafeHouse={getSafehouseOverlapping=function() return foreignSafehouse and {} or nil end}
local runtimeController
KnoxSurvivorRuntime={getCharacter=function(id) return characters[id] end,
    idForCharacter=function(character) for id,body in pairs(characters) do if body==character then return id end end end,
    getController=function(id) return id==ids[1] and runtimeController or nil end}
KnoxBaseManager={containsSquare=function(base,tile)
    return tile:getX()>=base.home.minX and tile:getX()<base.home.minX+base.home.width
        and tile:getY()>=base.home.minY and tile:getY()<base.home.minY+base.home.height end}
local candidate={buildingId="gh-building",minX=100,minY=100,width=6,height=6,
    x=99,y=102,z=0,probeX=101,probeY=101,probeZ=0,score=50}
group.homeBuildingId=candidate.buildingId
local claimed,claimWhy=P.createBase("group",group.id,candidate,20)
assert(claimed==nil and claimWhy=="arrival_unverified","origin alone is not a home claim; admission is what refuses it")
assert(P.confirmGroupHomeBase(group.id,candidate.buildingId,characters[ids[1]],20)==nil,"origin alone cannot confirm")
assert(P.recordFactionBaseCandidate(group.id,candidate,20)==candidate)
loaded=false
assert(P.confirmGroupHomeBase(group.id,candidate.buildingId,characters[ids[1]],20)==nil,"unknown unloaded building refuses claim")
loaded=true;foreignSafehouse=true
assert(P.confirmGroupHomeBase(group.id,candidate.buildingId,characters[ids[1]],20)==nil,"foreign SafeHouse refuses claim")
foreignSafehouse=false
local other=assert(P.createBase("player","gh-player",candidate,20))
assert(P.confirmGroupHomeBase(group.id,candidate.buildingId,characters[ids[1]],20)==nil,"foreign territory refuses claim")
P.getBases()[other.id]=nil
local beforeCounter=P.getPopulationState().nextBaseId
local base=assert(P.confirmGroupHomeBase(group.id,candidate.buildingId,characters[ids[1]],20))
assert(base.ownerKind=="group" and base.ownerId==group.id and group.factionId==nil,"real loaded group claims without promotion")
assert(P.getBaseForOwner("group",group.id)==base and P.getFaction(group.id)==nil,"one existing base owner, no fake faction")
assert(P.setGroupBaseResident(ids[1],group.id,base.id,characters[ids[1]],20),"scout really arrived at known exterior home anchor")
assert(not P.setGroupBaseResident(ids[2],group.id,base.id,characters[ids[2]],20),"absent member gets no residency")
assert(not P.setGroupBaseResident(ids[3],group.id,base.id,characters[ids[3]],20),"present outsider gets no residency")
positions[ids[2]]=square(102,102)
assert(P.setGroupBaseResident(ids[2],group.id,base.id,characters[ids[2]],20),"actual member arrives inside home")
assert(#P.getBaseResidentIds(base.id)==2 and P.getSurvivorAffiliation(ids[2]).kind=="independent","residency is not affiliation")
assert(codecDefence.defenceAssignment(base,{id=ids[1],groupId=group.id,dutyBaseId=base.id,kind="household"}),"group resident defends own home")
assert(not codecDefence.defenceAssignment(base,{id=ids[3],groupId=group.id,dutyBaseId=base.id,kind="household"}),"forged owner cannot defend another home")
assert(not codecDefence.defenceAssignment(base,{id=ids[1],groupId=group.id,dutyBaseId=base.id,kind="looters"}),"real kind defense policy remains authoritative")
local storeSquare=square(101,101)
assert(KnoxSurvivorLooting.canLootSquare(ids[1],storeSquare),"legitimate resident stock admitted")
assert(not KnoxSurvivorLooting.canLootSquare(ids[3],storeSquare),"outsider stock is refused")
local source={isInCharacterInventory=function() return false end,getParent=function() return {} end,
    getSourceGrid=function() return storeSquare end}
instanceof=function() return false end
assert(codecStockPermission.canTakeWorldStock(characters[ids[1]],source,characters[ids[1]].inventory),"real world-stock transfer admits resident")
assert(not codecStockPermission.canTakeWorldStock(characters[ids[3]],source,characters[ids[3]].inventory),"native transfer boundary refuses outsider")
local task=assert(P.queueBaseTask(base.id,"guard",{x=101,y=101,z=0},{},80))
assert(P.claimBaseTask(base.id,task.id,ids[1],20)==task,"normal task board admits group resident")
local outsiderDuty=P.getSurvivorDuty(ids[3]);outsiderDuty.mode="base";outsiderDuty.baseId=base.id;outsiderDuty.ownerId=group.id
assert(not P.isGroupBaseMember(base,ids[3],true) and not KnoxSurvivorLooting.canLootSquare(ids[3],storeSquare),"forged base duty cannot take stock")
assert(P.claimBaseTask(base.id,task.id,ids[3],20)==nil,"forged outsider duty cannot claim work")
outsiderDuty.mode="autonomous";outsiderDuty.baseId=nil;outsiderDuty.ownerId=nil
local lease={groupOwnerId=group.id,baseId=base.id,leaderId=ids[1],followerId=ids[2]}
assert(codecGroupHomePermissions.leaseAuthorized(lease),"real group supply lease admitted")
assert(codecGroupHomePermissions.belongsToSettlement({base=base,baseId=base.id},ids[1],P),"group settlement admission uses membership")
local permission=codecGroupHomeRecruit.recruitableGroup(ids[1])
assert(permission==nil,"homed household cannot be recruited as homeless")
-- Companion, away and event duty cannot coexist with group membership through
-- any real owner: setPlayerCompanion refuses a group member (already_with_group,
-- proved after the codec passes), and away/event teams require player or faction
-- affiliation an independent member does not hold. Each reachable owner is
-- asserted refusing; isGroupBaseMember keeps the same rows as save-state defence.
local awayOk,awayWhy=P.validateAwayTeam("group",group.id,{ids[2]},"scout",{x=101,y=101,z=0,label="home"})
assert(not awayOk and awayWhy=="invalid_member="..ids[2],"an away duty competing with residency is refused by the real owner")
assert(P.isGroupBaseMember(base,ids[2],true),"the still-resident member keeps real stock permission")
local _,why=codecGroupHomeRecruit.recruitableGroup(ids[1]);assert(why=="homed_group","homed group member is not homeless recruitment")
assert(P.setFactionResidentBed(ids[2],group.id,base.id,{x=102,y=102,z=0,objectIndex=1},20),"existing bed owner assigns group resident")
assert(P.getSurvivorPolicies(ids[2]).assignedBed.autoGroupId==group.id,"bed carries explicit real group owner")
-- The real revocation path retires only its exact pending action, leaving a
-- queued action from a different owner intact, with no item restoration.
local owned={forceCancel=function(self) self.cancelled=true end}
local unrelated={}
local queue={queue={unrelated,owned},current=unrelated,indexOf=function(self,action)
    for i,value in ipairs(self.queue) do if value==action then return i end end return -1 end,
    removeFromQueue=function(self,action) for i,value in ipairs(self.queue) do if value==action then table.remove(self.queue,i);return end end end}
ISTimedActionQueue={queues={[characters[ids[1]]]=queue},clear=function() error("unrelated queue must not be cleared") end}
runtimeController=setmetatable({id=ids[1],character=characters[ids[1]],baseId=base.id,base=base,
    pendingSupply={collectionActions={{action=owned}}},releaseBaseTaskSupplyTransfer=function() end,
    releaseInventoryCleanup=function() end},{__index=codecGroupHomeController})
base.tasks[task.id]=task;assertWorldStock()
assert(P.removeTravelGroupMember(ids[1]),"real membership removal succeeds")
assert(owned.cancelled and #queue.queue==1 and queue.queue[1]==unrelated,"revocation preserves unrelated native queue")
assert(runtimeController.baseId==nil and runtimeController.pendingSupply.collectionRetired,"revocation retires exact collection plan")
assert(not codecGroupHomePermissions.leaseAuthorized(lease),"revoked group lease immediately loses permission")
assert(not KnoxSurvivorLooting.canLootSquare(ids[1],storeSquare),"revoked stock permission is reread")
assert(task.state=="queued" and task.claimedBy==nil,"revoked resident claim is requeued")
assert(P.getTravelGroupFor(ids[2])==group and #group.memberIds==1,"homed singleton retains real group")
assert(P.normalizeRelationshipDomains()==0,"valid singleton normalization is already stable")
assert(P.getBase(base.id)==base,"logical singleton continuity retains the same home");assertWorldStock()
P.rejectFactionBaseCandidate(group.id,"unreachable-next-door",20)
local second=assert(P.createTravelGroup({ids[4],ids[5]},20))
local pending={buildingId="gh-pending",x=300,y=300,z=0,minX=300,minY=300,width=6,height=6,score=8}
assert(P.recordFactionBaseCandidate(second.id,pending,20)==pending)
groupHomeCodecIds={member=ids[2],group=group.id,base=base.id,pendingGroup=second.id}
function verifyGroupHomeCodec()
    local p=KnoxPersistence
    loadedHook()
    local saved=groupHomeCodecIds
    local g=p.getTravelGroupFor(saved.member)
    local b=p.getBase(saved.base)
    assert(g and g.id==saved.group and #g.memberIds==1 and g.leaderId==saved.member,"singleton real table-codec reload preserves group and succession")
    assert(b and b.ownerKind=="group" and b.ownerId==g.id and p.getBaseForOwner("group",g.id)==b,"group base owner survives native codec")
    assert(p.getSurvivorDuty(saved.member).ownerId==g.id and p.isGroupBaseMember(b,saved.member,true),"resident owner survives native codec")
    assert(p.getSurvivorAffiliation(saved.member).kind=="independent","native codec does not silently promote affiliation")
    assert(p.getSurvivorPolicies(saved.member).assignedBed.autoGroupId==g.id,"group bed owner survives codec")
    assert(g.baseSearch.rejected["unreachable-next-door"]==44 and p.getFactionBaseCandidate(saved.pendingGroup).buildingId=="gh-pending","group baseSearch survives actual codec")
    assert(p.normalizeRelationshipDomains()==0,"loading group homes twice is idempotent")
end
function finishGroupHomeCodec()
    local p=KnoxPersistence;local saved=groupHomeCodecIds
    assertWorldStock()
    assert(p.markSurvivorDead(saved.member,21,"fixture"),"last member death follows real lifecycle")
    assert(p.getBase(saved.base)==nil and p.getTravelGroups()[saved.group]==nil,"last death releases only logical owner and home")
    assertWorldStock()
    local second=p.getTravelGroups()[saved.pendingGroup]
    positions[second.leaderId]=square(99,102)
    assert(p.recordFactionBaseCandidate(second.id,candidate,21))
    local nextHome=assert(p.confirmGroupHomeBase(second.id,candidate.buildingId,characters[second.leaderId],21))
    assert(p.setGroupBaseResident(second.leaderId,second.id,nextHome.id,characters[second.leaderId],21))
    assert(p.abandonGroupHome(second.id),"explicit abandonment uses the same logical owner")
    assert(p.getBase(nextHome.id)==nil and p.getTravelGroups()[second.id]==second,"abandonment releases home without deleting living people")
    assertWorldStock()
    -- Real companion owner: a group member is refused companionship outright,
    -- so companion duty cannot coexist with a group home.
    local captured,captureWhy=p.setPlayerCompanion(second.leaderId,"gh-player","follow",21)
    assert(not captured and captureWhy=="already_with_group","companion owner refuses a real group member")
    assert(p.getTravelGroupFor(second.leaderId)==second,"refused companionship leaves real membership intact")
    groupHomePass=true
    data=groupHomePrior.data
    KnoxSurvivorRuntime=groupHomePrior.Runtime;KnoxBaseManager=groupHomePrior.Manager
    SafeHouse=groupHomePrior.SafeHouse;getCell=groupHomePrior.Cell;instanceof=groupHomePrior.instanceof
    ISTimedActionQueue=groupHomePrior.Queue
    print("Group home GH1 PASS actualClaim=true residency=true defense=true stock=true leaseRevocation=true unrelatedQueue=true singletonCodecPasses=2 lastDeathLogicalOnly=true nativeGameplay=false")
end
