local old=KnoxSurvivorNeeds
KnoxSurvivorNeeds={snapshot=function() return {} end,describe=function() return 'needsFixture' end}
local reads=0
local loc={getX=function() reads=reads+1;return 1 end,getY=function() reads=reads+1;return 2 end,getZ=function() reads=reads+1;return 0 end}
local body={}
function body:getCurrentSquare() reads=reads+1;return {} end
function body:getLastHeardSound() reads=reads+1;return loc end
for _,method in ipairs({'getCurrentStateName','getCurrentActionContextStateName','isAttackStarted','isAttacking','isPerformingAttackAnimation','getAttackType','isWeaponReady'}) do body[method]=function() reads=reads+1;return false end end
local c={id='fixture',state='IDLE',character=body,currentTicks=42,counts={roam=0,loot=0,search=0,needs=0,combat=0,groupTravel=0,baseScout=0,robberies=0,failures=0}}
local s=codecEvidenceStatus(c);assert(reads==0 and s:find('id=fixture',1,true) and s:find('needsFixture',1,true) and not s:find('rawLastHeard',1,true),'default status preserves fields without native reads')
s=codecEvidenceStatus(c,true);assert(reads==5 and s:find('rawLastHeard=1,2,0',1,true) and s:find('nativeControllerTick=42',1,true) and s:find('nativeHearing=raw_cache',1,true),'raw cache sample performs five reads')
reads=0;c.state='COMBAT';s=codecEvidenceStatus(c,true);assert(reads==12 and s:find('isAttacking=false',1,true) and s:find('isWeaponReady=false',1,true),'combat sample preserves false with twelve reads')
reads=0;body.getCurrentSquare=function() reads=reads+1;return nil end;s=codecEvidenceStatus(c,true);assert(reads==1 and s:find('rawLastHeard=unloaded',1,true),'unloaded sample stops after square')
body.getCurrentSquare=function() error('missing') end;s=codecEvidenceStatus(c,true);assert(s:find('rawLastHeard=unavailable',1,true),'unreadable square unavailable')
body.getCurrentSquare=function() return {} end;body.getLastHeardSound=function() return nil end;s=codecEvidenceStatus(c,true);assert(s:find('rawLastHeard=none',1,true),'nil cache is none')
body.getLastHeardSound=function() return {} end;body.isAttacking=function() return nil end;body.isWeaponReady=function() error('missing') end;s=codecEvidenceStatus(c,true);assert(s:find('rawLastHeard=malformed',1,true) and s:find('isAttacking=unavailable',1,true) and s:find('isWeaponReady=unavailable',1,true),'malformed coordinates and nil or throwing flags are unavailable')
body.getLastHeardSound=function() error('missing') end;s=codecEvidenceStatus(c,true);assert(s:find('rawLastHeard=unavailable',1,true),'unreadable cache unavailable')
KnoxSurvivorNeeds=old
print('Native evidence formatter PASS nativeGameplay=false')
