-- GH3 drives the real transaction owner. Only streamed world objects and the
-- native character/queue facades are doubled, exactly as the GH1 fixture does.
gh3Prior={data=data,Runtime=KnoxSurvivorRuntime,Manager=KnoxBaseManager,
    SafeHouse=SafeHouse,Cell=getCell,instanceof=instanceof}
local function runHomeScenario(profile)
data={}
local P=KnoxPersistence
local ids={"g1-a","g1-b","g1-c","g2-a","g2-b","g3-a","g3-b","g4-a","g4-b"}
for _,id in ipairs(ids) do assert(P.setRecord(id,expectedRecord)) end
local g1=assert(P.createTravelGroup({"g1-a","g1-b","g1-c"},20))
local g2=assert(P.createTravelGroup({"g2-a","g2-b"},20))
local g3=assert(P.createTravelGroup({"g3-a","g3-b"},20))
local g4=assert(P.createTravelGroup({"g4-a","g4-b"},20))
for _,leader in ipairs({g1.leaderId,g2.leaderId,g3.leaderId,g4.leaderId}) do
    assert(P.setSurvivorCreatorRecord(leader,{name="Household "..leader,
        profile=leader==g1.leaderId and profile or "household",settlementPolicy="home"}))
end
if profile ~= "household" then
    assert(KnoxCreator.behaviourFor(profile).formsFaction == false, "actual creator profile forbids ordinary founding")
    local function creatorPolicy(policy)
        assert(P.setSurvivorCreatorRecord(g1.leaderId,{name="Home leader",profile=profile,settlementPolicy=policy}))
    end
    for _,policy in ipairs({"default","mobile","independent"}) do
        creatorPolicy(policy)
        local faction,why=P.promoteTravelGroupToFaction(g1.id,20,3)
        assert(faction==nil and why=="mobile_group",profile.." rejects "..policy)
    end
    creatorPolicy(nil)
    local missing,missingWhy=P.promoteTravelGroupToFaction(g1.id,20,3)
    assert(missing==nil and missingWhy=="mobile_group",profile.." rejects missing policy")
    creatorPolicy("home")
    local noHome,noHomeWhy=P.promoteTravelGroupToFaction(g1.id,20,3)
    assert(noHome==nil and noHomeWhy=="mobile_group",profile.." home intent requires real group home")
end

local function itemList(list)
    return {size=function() return #list end,get=function(_,index) return list[index+1] end}
end
local function foodItem(relief)
    return {getHungChange=function() return -relief end,isRotten=function() return false end}
end
local function waterItem(amount)
    return {getFluidContainer=function() return {
        getAmount=function() return amount end,
        isTainted=function() return false end,
        isPoisonous=function() return false end,
        getPrimaryFluid=function() return {kind="water"} end,
        isPureFluid=function() return true end,
    } end}
end
-- One floor square per home carries the whole larder; every other home square is
-- a readable empty floor.
local stock={}
local function floorFor(x,y)
    local list=stock[x..":"..y]
    if list==nil then return nil end
    return {getItems=function() return itemList(list) end}
end
local function inside(x,y)
    return (x>=100 and x<106 and y>=100 and y<106) or (x>=200 and x<206 and y>=200 and y<206)
end
local function buildingIdAt(x,y)
    if x>=100 and x<106 and y>=100 and y<106 then return "gh3-a" end
    if x>=200 and x<206 and y>=200 and y<206 then return "gh3-b" end
    return nil
end
local function defFor(id)
    local minX,minY=id=="gh3-a" and 100 or 200,id=="gh3-a" and 100 or 200
    return {getID=function() return id end,getX=function() return minX end,
        getY=function() return minY end,getX2=function() return minX+6 end,
        getY2=function() return minY+6 end,getW=function() return 6 end,
        getH=function() return 6 end,getRoomsNumber=function() return 3 end,
        getArea=function() return 36 end}
end
local buildings={}
local function buildingAt(x,y)
    local id=buildingIdAt(x,y)
    if id==nil then return nil end
    buildings[id]=buildings[id] or {getDef=function() return defFor(id) end,
        isResidential=function() return true end,hasWater=function() return true end}
    return buildings[id]
end
local function square(x,y,z)
    return {getX=function() return x end,getY=function() return y end,
        getZ=function() return z or 0 end,
        getObjects=function() return {size=function() return 0 end,get=function() return nil end} end,
        getWorldObjects=function()
            local objects={}
            for _,item in ipairs(stock[x..":"..y] or {}) do objects[#objects+1]={getItem=function() return item end} end
            return itemList(objects)
        end,
        getBuilding=function() return buildingAt(x,y) end,
        canStand=function() return true end,
        isOutside=function() return not inside(x,y) end}
end
local positions={}
local characters={}
for _,id in ipairs(ids) do
    local key=id
    characters[id]={getCurrentSquare=function() return positions[key] end,
        isDead=function() return false end,
        getInventory=function(self) return self.inventory end,inventory={}}
end
positions[g1.leaderId]=square(99,102)
positions[g2.leaderId]=square(199,202)
positions[g3.leaderId]=square(130,130)
positions[g4.leaderId]=square(201,201)
getCell=function() return {getGridSquare=function(_,x,y,z) return square(x,y,z) end} end
SafeHouse={getSafehouseOverlapping=function() return nil end}
local runtimeController
KnoxSurvivorRuntime={getCharacter=function(id) return characters[id] end,
    idForCharacter=function(character) for id,body in pairs(characters) do if body==character then return id end end end,
    getController=function(id) return id==g1.leaderId and runtimeController or nil end}
-- The real base manager answers its own defence question for a group home; the
-- bed scan is the same call the capacity owner makes.
gh3Beds,gh3Defend=3,true
KnoxBaseManager={containsSquare=function(base,tile)
        return tile:getX()>=base.home.minX and tile:getX()<base.home.minX+base.home.width
            and tile:getY()>=base.home.minY and tile:getY()<base.home.minY+base.home.height end,
    discoverFactionBeds=function()
        local found={} for i=1,gh3Beds do found[i]={} end return found end,
    defenceAssignment=function(base,survivor)
        if gh3Defend and type(base)=="table" and base.ownerKind=="group"
            and survivor.groupId==base.ownerId then return base,"own_group_home" end
        return nil,"another_group_home" end}
instanceof=function() return false end

local homeA={buildingId="gh3-a",minX=100,minY=100,width=6,height=6,
    x=99,y=102,z=0,probeX=101,probeY=101,probeZ=0,score=50}
local homeB={buildingId="gh3-b",minX=200,minY=200,width=6,height=6,
    x=199,y=202,z=0,probeX=201,probeY=201,probeZ=0,score=50}
stock["101:101"]={foodItem(0.6),foodItem(0.6),foodItem(0.6),
    waterItem(2.0),waterItem(2.0),waterItem(2.0)}
stock["201:201"]={foodItem(0.6),foodItem(0.6),waterItem(2.0),waterItem(2.0)}

assert(P.recordFactionBaseCandidate(g1.id,homeA,20))
local baseA=assert(P.confirmGroupHomeBase(g1.id,"gh3-a",characters[g1.leaderId],20))
assert(P.setGroupBaseResident(g1.leaderId,g1.id,baseA.id,characters[g1.leaderId],20))
positions[g1.memberIds[2]]=square(102,102)
assert(P.setGroupBaseResident(g1.memberIds[2],g1.id,baseA.id,characters[g1.memberIds[2]],20))
assert(P.setFactionResidentBed(g1.leaderId,g1.id,baseA.id,{x=101,y=101,z=0,objectIndex=1},20))

-- 1. Fresh authorization reads today's state, not a stored flag.
local auth,authWhy=P.groupHomeAuthorization(g1.id,20)
assert(auth~=nil,"GH3 authorization refused: "..tostring(authWhy))
assert(authWhy=="authorized" and auth.base==baseA and auth.beds==3
    and auth.defenders==2 and #auth.residents==2,
    "authorization re-derives beds, defenders and residents from current state beds="
    ..tostring(auth.beds).." defenders="..tostring(auth.defenders)
    .." residents="..tostring(#auth.residents))

-- 1b. The Talk owner answers from that same authorization: a held home says
-- so, and a group one short says what it is short of.
local Talk=assert(CompanionService,"the talk owner must be loaded")
local holdLine=Talk.answerHome(g1.leaderId,"player-1")
assert(holdLine:find("We are staying here",1,true)==1,
    "a held group home is spoken as staying: "..tostring(holdLine))

-- Promotion must use the same fresh home authorization for every profile.
if profile ~= "household" then
    local saved=stock["101:101"]
    local function refused(reason)
        local result,why=P.promoteTravelGroupToFaction(g1.id,20,3)
        assert(result==nil and why==reason,profile.." promotion refuses "..reason.." got "..tostring(why))
        assert(P.getBaseForOwner("group",g1.id)==baseA and #g1.memberIds==3,
            "refusal preserves group and home")
    end
    gh3Beds=0;refused("beds_unverified");gh3Beds=3
    gh3Defend=false;refused("defence_unverified");gh3Defend=true
    stock["101:101"]={foodItem(0.1),waterItem(0.1)};refused("provisions_food_short")
    stock["101:101"]={{getHungChange=function() error("unreadable") end}};refused("provisions_unreadable")
    stock["101:101"]=saved
end

-- 2. A qualifying group promotes and keeps the same home and people.
local originalIds={g1.memberIds[1],g1.memberIds[2],g1.memberIds[3]}
local originalInventories={characters[originalIds[1]].inventory,characters[originalIds[2]].inventory,characters[originalIds[3]].inventory}
local faction,factionWhy=P.promoteTravelGroupToFaction(g1.id,20,3)
assert(faction~=nil and factionWhy=="created",profile.." qualifying group is promoted")
for i,id in ipairs(originalIds) do
    assert(characters[id].inventory==originalInventories[i], "promotion preserves personal inventory")
    local found=false
    for _,member in ipairs(faction.memberIds) do if member==id then found=true end end
    assert(found, "promotion preserves every group member identity")
end
local authored=P.getSurvivorCreatorRecord(g1.leaderId)
assert(authored.profile==profile and authored.settlementPolicy=="home", "promotion preserves authored policy and profile")
assert(baseA.id==auth.base.id and P.getBase(baseA.id)==baseA,"the same base record survives promotion")
assert(baseA.ownerKind=="faction" and baseA.ownerId==faction.id,"the home belongs to the new faction")
assert(faction.homeBaseId==baseA.id,"the faction links its own home")
assert(P.getBaseForOwner("group",g1.id)==nil,"the group no longer owns a group home")
assert(P.getSurvivorDuty(g1.leaderId).ownerId==faction.id,"resident duty follows the home owner")
assert(P.getSurvivorPolicies(g1.leaderId).assignedBed.autoFactionId==faction.id,
    "the bed carries the faction owner after promotion")
local again,againWhy=P.promoteTravelGroupToFaction(g1.id,20,3)
assert(again~=nil and againWhy=="already_faction","repeat promotion is idempotent")

-- 3. A non-qualifying group is refused without any home or membership change.
assert(P.setSurvivorCreatorRecord(g3.leaderId,{name="Small group",profile=profile,settlementPolicy="home"}))
local small,smallWhy=P.promoteTravelGroupToFaction(g3.id,20,3)
assert(small==nil and smallWhy=="requires_3_members","a two-person group is not promoted")

-- 4. A second home, then a refusal when its provisions stop supporting it.
assert(P.recordFactionBaseCandidate(g2.id,homeB,20))
local baseB=assert(P.confirmGroupHomeBase(g2.id,"gh3-b",characters[g2.leaderId],20))
assert(P.setGroupBaseResident(g2.leaderId,g2.id,baseB.id,characters[g2.leaderId],20))
positions[g2.memberIds[2]]=square(202,202)
assert(P.setGroupBaseResident(g2.memberIds[2],g2.id,baseB.id,characters[g2.memberIds[2]],20))
local larder=stock["201:201"]
stock["201:201"]={foodItem(0.1),waterItem(0.5)}
local starved,starvedWhy=P.groupHomeAuthorization(g2.id,20)
assert(starved==nil and starvedWhy=="provisions_food_short",
    "a home whose measured provisions cannot feed its people is refused")
stock["201:201"]=larder
assert(select(2,P.groupHomeAuthorization(g2.id,20))=="authorized",
    "restoring the measured stock re-authorizes the same home")

-- 4b. Every failing requirement the transaction would refuse is spoken with the
-- design wording, and the accepted state is never spoken as a refusal.
local function groupReason(id) return select(2,P.groupHomeAuthorization(id,0)) end
gh3Beds=0
assert(groupReason(g2.id)=="beds_unverified","beds refusal reason")
assert(Talk.answerHome(g2.leaderId,"player-1")=="We are not staying here yet.","beds wording")
gh3Beds=3
gh3Defend=false
assert(groupReason(g2.id)=="defence_unverified","defence refusal reason")
assert(Talk.answerHome(g2.leaderId,"player-1")=="We cannot defend this place yet.","defence wording")
gh3Defend=true
stock["201:201"]={foodItem(0.1),waterItem(2.0),waterItem(2.0)}
assert(groupReason(g2.id)=="provisions_food_short","food refusal reason")
assert(Talk.answerHome(g2.leaderId,"player-1")=="We need food.","food wording")
stock["201:201"]={foodItem(0.6),foodItem(0.6),waterItem(0.1)}
assert(groupReason(g2.id)=="provisions_water_short","water refusal reason")
assert(Talk.answerHome(g2.leaderId,"player-1")=="We need water.","water wording")
stock["201:201"]={{getHungChange=function() error("unreadable") end}}
assert(groupReason(g2.id)=="provisions_unreadable","unreadable refusal reason")
assert(Talk.answerHome(g2.leaderId,"player-1")=="Our stores are unverified.","unreadable wording")
stock["201:201"]=larder
assert(groupReason(g2.id)=="authorized"
    and Talk.answerHome(g2.leaderId,"player-1"):find("We are staying here",1,true)==1,
    "an accepted home is spoken as holding, never as a refusal")

-- 5. The home is handed to another qualifying group that is really there.
positions[g4.memberIds[2]]=square(201,201)
local baseBId=baseB.id
local moved,movedWhy=P.transferGroupHome(g2.id,g4.id,20)
assert(moved==true and movedWhy=="transferred","a qualifying group takes over the home")
assert(P.getBase(baseBId)==baseB and baseBId~=nil and baseB.ownerKind=="group",
    "the transferred home is the same group base record")
assert(baseB.ownerId==g4.id and P.getBaseForOwner("group",g4.id)==baseB,
    "the new holder owns the home")
assert(P.getBaseForOwner("group",g2.id)==nil,"the previous holder lost the home")
assert(P.getTravelGroupFor(g2.leaderId)==g2 and #g2.memberIds==2,
    "the previous holder keeps its living people")

-- 6. Outsiders and absent groups cannot take it.
local far,farWhy=P.transferGroupHome(g4.id,g3.id,20)
assert(far==false and farWhy=="recipient_not_arrived","an absent group is refused the home")
assert(P.getBaseForOwner("group",g4.id)==baseB,"a refused transfer changes no owner")
local selfMove,selfWhy=P.transferGroupHome(g4.id,g4.id,20)
assert(selfMove==false and selfWhy=="invalid_owner","a group cannot transfer to itself")
local homeless,homelessWhy=P.transferGroupHome(g3.id,g2.id,20)
assert(homeless==false and homelessWhy=="no_home","a group without a home transfers nothing")

-- 6b. The handed-over home is spoken by its new holder, and the group that lost
-- it no longer claims it: the wording follows the same owner state.
local recipientLine=Talk.answerHome(g4.leaderId,"player-1")
assert(recipientLine:find("We are staying here",1,true)==1,
    "the recipient of a handed-over home says they are staying: "..tostring(recipientLine))
local displacedLine=Talk.answerHome(g2.leaderId,"player-1")
assert(displacedLine:find("We are staying here",1,true)==nil,
    "the previous holder no longer claims the home: "..tostring(displacedLine))

-- 6c. A group below two living people is no longer a group, so the talk path
-- has no home claim to refuse: the authorization says so and the survivor falls
-- back to the ordinary homeless answer instead of borrowing a refusal line.
local doomedId=g3.memberIds[2]
P.markSurvivorDead(doomedId,20,"fixture_short_group")
assert(select(2,P.groupHomeAuthorization(g3.id,0))=="no_group",
    "a dissolved group reports no_group, not a home refusal")
assert(Talk.answerHome(g3.leaderId,"player-1")~="We still need people.",
    "no refusal wording is shown for a group that no longer exists")
assert(P.setRecord(doomedId,expectedRecord),"the fixture record is restored")

-- 7. Codec probe: ownership, duties and measured stock are re-read after reload.
gh3Probe={baseId=baseB.id,ownerId=g4.id,groupId=g2.id,residentId=g4.leaderId}
local before=assert(KnoxSettlementCapacity.baseProvisions(baseB))
gh3Probe.food=before.food
gh3Probe.water=before.water
assert(gh3Probe.food==1.2 and gh3Probe.water==4.0,
    "the transferred home's stock measures from its own floor")
gh3Receipt="promotions=1 refusals=3 transfers=1 outsiders=2 sameHome=true"
    .. " beds="..tostring(auth.beds).." defenders="..tostring(auth.defenders)
    .. " reloadFood="..tostring(gh3Probe.food).." reloadWater="..tostring(gh3Probe.water)
gh3FeedbackReceipt="hold=1 refusals=5 recipient=1 displaced=1 dissolved=1 "
    .. "reasons=beds_unverified,defence_unverified,provisions_food_short,"
    .. "provisions_water_short,provisions_unreadable"
gh3FeedbackPass=true
gh3Pass=true
end
for _,profile in ipairs({"household","looters","solo"}) do runHomeScenario(profile) end
gh3Receipt="profiles=3 runs=3 per_run "..gh3Receipt

function verifyGroupHomeTransferCodec()
    local p=KnoxPersistence
    local base=p.getBase(gh3Probe.baseId)
    assert(base~=nil and base.ownerKind=="group" and base.ownerId==gh3Probe.ownerId,
        "the transferred home and its holder survive a real codec reload")
    assert(p.getBaseForOwner("group",gh3Probe.groupId)==nil,
        "the previous holder stays without a home across the reload")
    local duty=p.getSurvivorDuty(gh3Probe.residentId)
    assert(duty~=nil and duty.ownerId==gh3Probe.ownerId and duty.baseId==gh3Probe.baseId,
        "the new holder's resident duty survives the reload")
    local after=assert(KnoxSettlementCapacity.baseProvisions(base))
    assert(after.food==gh3Probe.food and after.water==gh3Probe.water,
        "the home's measured stock is unchanged after the reload")
    assert(p.normalizeRelationshipDomains()==0,"a transferred group home normalizes idempotently")
end

function finishGroupHomeTransfer()
    data=gh3Prior.data
    KnoxSurvivorRuntime=gh3Prior.Runtime;KnoxBaseManager=gh3Prior.Manager
    SafeHouse=gh3Prior.SafeHouse;getCell=gh3Prior.Cell;instanceof=gh3Prior.instanceof
end
