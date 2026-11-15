local C,D,H=KnoxAutonomyController,KnoxSurvivorDialogue,KnoxHumanCombatRelations
local old={p=KnoxPersistence,r=KnoxSurvivorRuntime,f=KnoxActivityFeed,s=KnoxSettings,rel=KnoxSurvivorRelationships}
local spoken={}; local enabled=true; local delivered=true; local alive=true
local function square(x,z) return {getX=function() return x end,getY=function() return 0 end,getZ=function() return z or 0 end} end
local actor={square=square(0),dead=false,visible=true}
function actor:getCurrentSquare() return self.square end
function actor:isDead() return self.dead end
function actor:CanSee() if self.throw then error('sight') end return self.visible end
local zombie={square=square(2),dead=true,kind=true,attacker=actor}
function zombie:getCurrentSquare() return self.square end
function zombie:isDead() return self.dead end
function zombie:isZombie() return self.kind end
function zombie:getAttackedBy() return self.attacker end
function zombie:getTarget() return nil end
local c=setmetatable({id='outcome-fixture',character=actor,state='COMBAT',combatTarget=zombie,currentTicks=0,reservations={threats={}}},C)
KnoxSurvivorRuntime={idForCharacter=function(a) if a==actor then return c.id end end,getController=function(id) if id=='outcome-fixture' then return c end end}
KnoxPersistence={isSurvivorAlive=function() return alive end,getSurvivorPersonality=function() return {personality='brave'} end}
KnoxSurvivorRelationships=assert(relationshipObservationProbe.relationships)
KnoxSettings={enabled=function() return true end,showSurvivorSpeech=function() return enabled end}
KnoxActivityFeed={speak=function(_,line) if delivered then spoken[#spoken+1]=line end return delivered end}
D.resetRuntime();H.onZombieDead(zombie)
assert(#spoken==1 and c.combatOutcomeSpoken==true,'native death of exact current zombie voices once')
c.currentTicks=1800;H.onZombieDead(zombie)
assert(#spoken==1,'duplicate outcome stays silent after cooldown')
c:releaseCombat();assert(c.combatOutcomeSpoken==nil,'release clears outcome flag')
c.combatOutcomeSpoken=true;combatOutcomeEntryFactory(c);assert(c.combatOutcomeSpoken==false and c.state=='COMBAT','successful entry resets outcome flag')
for _,mode in ipairs({'wrong-target','state','human','actor-dead','logical-dead','hidden','unknown-sight','unloaded','floor','far','missing-clock','nan-clock','infinite-clock','unregistered','unknown-attacker'}) do
 D.resetRuntime();c.combatOutcomeSpoken=false;c.state='COMBAT';c.combatTarget=zombie;c.currentTicks=0;actor.dead=false;actor.visible=true;actor.throw=false;actor.square=square(0);zombie.square=square(2);zombie.kind=true;zombie.attacker=actor;alive=true
 if mode=='wrong-target' then c.combatTarget={} elseif mode=='state' then c.state='IDLE' elseif mode=='human' then zombie.kind=false elseif mode=='actor-dead' then actor.dead=true elseif mode=='logical-dead' then alive=false elseif mode=='hidden' then actor.visible=false elseif mode=='unknown-sight' then actor.throw=true elseif mode=='unloaded' then actor.square=nil elseif mode=='floor' then zombie.square=square(2,1) elseif mode=='far' then zombie.square=square(40) elseif mode=='missing-clock' then c.currentTicks=nil elseif mode=='nan-clock' then c.currentTicks=0/0 elseif mode=='infinite-clock' then c.currentTicks=math.huge elseif mode=='unregistered' then c.id='unregistered' elseif mode=='unknown-attacker' then zombie.attacker={} end
 local before=#spoken;H.onZombieDead(zombie);assert(#spoken==before and not c.combatOutcomeSpoken,'ineligible outcome silent '..mode);c.id='outcome-fixture'
end
zombie.attacker=actor;zombie.kind=true;zombie.square=square(2);actor.square=square(0);actor.dead=false;actor.visible=true;actor.throw=false;alive=true;c.state='COMBAT';c.combatTarget=zombie;c.currentTicks=0
D.resetRuntime();c.combatOutcomeSpoken=false;enabled=false;H.onZombieDead(zombie);assert(not c.combatOutcomeSpoken,'disabled voice does not consume outcome');enabled=true
delivered=false;H.onZombieDead(zombie);assert(not c.combatOutcomeSpoken,'failed voice does not consume outcome');delivered=true;H.onZombieDead(zombie);assert(c.combatOutcomeSpoken,'failed delivery permits retry')
D.resetRuntime();c.combatOutcomeSpoken=false;assert(D.say(actor,c.id,'combat_zombie',0,900));H.onZombieDead(zombie);assert(not c.combatOutcomeSpoken,'shared cooldown does not consume outcome');c.currentTicks=240;H.onZombieDead(zombie);assert(c.combatOutcomeSpoken,'outcome retries after shared cooldown')
for _,voice in ipairs({'frightened','guarded','loner','sociable','brave'}) do KnoxPersistence.getSurvivorPersonality=function() return {personality=voice} end;local lines,chosen=D.linesFor(c.id,'combat_zombie_done');assert(chosen==voice and #lines==2,'outcome bank '..voice);local entry=D.linesFor(c.id,'combat_zombie');assert(lines[1]~=entry[1] and lines[2]~=entry[2],'outcome differs from entry '..voice) end
-- Exercise the original player-defense path, including an optional callback error.
local priorPlayer,priorCount,priorTime=getSpecificPlayer,getNumActivePlayers,getGameTime
local player={};local target={}
for _,body in ipairs({player,target,zombie}) do
 body.getX=function() return 0 end;body.getY=function() return 0 end;body.getZ=function() return 0 end
end
function player:getCurrentSquare() return square(0) end
function target:getCurrentSquare() return square(0) end
function target:isDead() return false end
local credit=0;getSpecificPlayer=function() return player end;getNumActivePlayers=function() return 1 end
getGameTime=function() return {getWorldAgeHours=function() return 5 end} end
KnoxPersistence.ensurePlayerId=function() return 'player' end
KnoxPersistence.recordPlayerContribution=function() credit=credit+1;return {trustGain=1} end
KnoxSurvivorRuntime.idForCharacter=function(body) if body==player then return 'fault' elseif body==target then return 'defended' end end
KnoxSurvivorRuntime.getController=function(id) if id=='fault' then return {character=player,reportZombieOutcome=function() error('fixture callback') end} end end
zombie.attacker=player;zombie.getTarget=function() return target end
H.onZombieDead(zombie);H.onZombieDead(zombie)
assert(credit==1,'callback failure preserves exactly one player defense credit')
getSpecificPlayer=priorPlayer;getNumActivePlayers=priorCount;getGameTime=priorTime
D.resetRuntime();KnoxPersistence=old.p;KnoxSurvivorRuntime=old.r;KnoxActivityFeed=old.f;KnoxSettings=old.s;KnoxSurvivorRelationships=old.rel
print('Combat outcome PASS nativeGameplay=false')
