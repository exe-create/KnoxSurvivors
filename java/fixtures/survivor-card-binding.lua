local body, rosterReads, individualReads, allow = {},0,0,false
local snapshot={id="resident",loaded=false}
local read,bind=cardBindingFactory({
    getSurvivor=function(id,num) assert(id=="resident" and num==0);individualReads=individualReads+1;return snapshot end,
    getForPlayer=function() rosterReads=rosterReads+1;error("card must not project whole party") end,
    resolveLiveCharacter=function(id) assert(id=="resident");return body end,
},{canManage=function(num,id,expected) assert(num==0 and id=="resident" and expected==body);return allow end})
local window={snapshot=read(0,"resident"),playerNum=0}
assert(individualReads==1 and rosterReads==0,"one card reads one survivor, not the whole roster")
assert(bind(window)==nil,"unobserved foreign/unreachable survivor exposes no native sheet")
allow=true
assert(bind(window)==body,"nearby owned survivor binds native sheet despite visibility-only snapshot flag")
body=nil
assert(bind(window)==nil,"unloaded survivor cannot bind stale character panels")
body={};allow=false;snapshot.loaded=true
assert(bind(window)==body,"directly observed native character remains inspectable")
print("Survivor card binding PASS one_projection=true owned_body=true unavailable=false")
