local P,C,D,H=KnoxPersistence,KnoxAutonomyController,KnoxSurvivorDialogue,KnoxBaseCorpseHandling
local old={data=data,runtime=KnoxSurvivorRuntime,feed=KnoxActivityFeed,settings=KnoxSettings,relationships=KnoxSurvivorRelationships,cell=getCell,instance=instanceof,time=getGameTime}
data={};getGameTime=function() return {getWorldAgeHours=function() return 1 end} end
assert(P.ensurePlayerId({getModData=function() return {KnoxSurvivors={playerId='r3b2-owner'}} end})=='r3b2-owner')
assert(P.setRecord('r3b2-victim',expectedRecord));assert(P.setRecord('r3b2-observer',expectedRecord))
assert(P.ensureSurvivorIdentity('r3b2-victim','Nora%','Vale',0))
assert(P.rememberObserverKnowledge('r3b2-owner','r3b2-victim','seen',{alive=true},1))
assert(P.markSurvivorDead('r3b2-victim',2,'fixture'))
local function square(x,z) return {getX=function() return x end,getY=function() return 0 end,getZ=function() return z or 0 end} end
local body={square=square(2),tag=corpseIdentityTable}
function body:getModData() return self.tag end
function body:getCurrentSquare() return self.square end
function body:getItem() return {getID=function() return 99 end} end
function body:getStaticMovingObjectIndex() return 0 end
local actor={square=square(0),visible=true}
function actor:getCurrentSquare() return self.square end
function actor:isDead() return false end
function actor:CanSee() return self.visible end
local list={size=function() return 1 end,get=function() return body end}
local source=body.square;function source:getStaticMovingObjects() return list end
local dest=square(10);local reads=0
getCell=function() return {getGridSquare=function(_,x,y,z) reads=reads+1;if x==2 and y==0 and z==0 then return source elseif x==10 and y==0 and z==0 then return dest end end} end
instanceof=function(object,kind) return object==body and kind=='IsoDeadBody' end
KnoxSurvivorRelationships=relationshipObservationProbe.relationships
local c=setmetatable({id='r3b2-observer',character=actor,companionOwnerId='r3b2-owner',currentTicks=0},C)
KnoxSurvivorRuntime={getController=function(id) if id==c.id then return c end end}
local spoken={};KnoxSettings={showSurvivorSpeech=function() return true end};KnoxActivityFeed={speak=function(_,line) spoken[#spoken+1]=line;return true end}
local base={zones={grave={id='grave',type='corpse',x1=10,y1=0,x2=10,y2=0,z=0}}}
local target=assert(H.resolveTarget(base,{corpseX=2,corpseY=0,corpseZ=0,corpseItemId=99,zoneId='grave'},actor))
assert(target.body==body and target.survivorId=='r3b2-victim','Java tagged body resolves exact identity')
local before=reads;D.resetRuntime();assert(c:reportKnownCorpse(target) and #spoken==1 and spoken[1]:find('Nora% Vale',1,true),'known corpse speaks actual identity');assert(reads==before,'recognition makes no world scan')
body.tag={KnoxSurvivorsCorpseSurvivorId='changed'};D.resetRuntime();assert(not c:reportKnownCorpse(target),'changed tag refuses snapshot')
body.tag=corpseIdentityTable;actor.visible=false;D.resetRuntime();assert(not c:reportKnownCorpse(target),'hidden corpse silent');actor.visible=true
c.companionOwnerId='other';assert(not c:reportKnownCorpse(target),'other owner knowledge excluded');c.companionOwnerId='r3b2-owner'
c.currentTicks=0/0;assert(not c:reportKnownCorpse(target),'invalid clock excluded')
body.tag={KnoxSurvivorsCorpseSurvivorId='  '};assert(H.readTaggedSurvivorId(body)==nil,'blank tag excluded')
body.tag={};assert(H.readTaggedSurvivorId(body)==nil,'old body has no survivor identity')
body.tag={KnoxSurvivorsCorpseSurvivorId=42};assert(H.readTaggedSurvivorId(body)==nil,'malformed identity excluded')
body.tag=corpseIdentityTable;c.currentTicks=0;body.square=square(2,1);D.resetRuntime();assert(not c:reportKnownCorpse(target),'other floor excluded')
body.square=nil;assert(not c:reportKnownCorpse(target),'unloaded body excluded');body.square=square(2)
local originalAlive=P.isSurvivorAlive;P.isSurvivorAlive=function(id) if id=='r3b2-victim' then return true end return originalAlive(id) end
assert(not c:reportKnownCorpse(target),'living record excluded');P.isSurvivorAlive=originalAlive
local originalIdentity=P.getSurvivorIdentity;P.getSurvivorIdentity=function() return {} end
assert(not c:reportKnownCorpse(target),'missing name excluded');P.getSurvivorIdentity=originalIdentity
D.resetRuntime();KnoxActivityFeed.speak=function() return false end;assert(not c:reportKnownCorpse(target),'failed speech not remembered')
KnoxActivityFeed.speak=function() return true end;assert(c:reportKnownCorpse(target),'failed speech can retry')
D.resetRuntime();data=old.data;KnoxSurvivorRuntime=old.runtime;KnoxActivityFeed=old.feed;KnoxSettings=old.settings;KnoxSurvivorRelationships=old.relationships;getCell=old.cell;instanceof=old.instance;getGameTime=old.time
print('Known corpse identity PASS nativeGameplay=false')
