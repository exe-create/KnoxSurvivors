local P=assert(KnoxPersistence)
local base=assert(P.createBase("player","guest-host",{minX=8700,minY=8700,width=4,height=4,z=0},10))
for _,id in ipairs({"guest-one","guest-two","guest-three","guest-four"}) do
    P.ensureSurvivorIdentity(id,"Guest","Fixture",10,30)
end
local request=assert(P.requestOvernightStay(base.id,"guest-one",20))
assert(request.status=="pending","a request does not grant entry")
local square={getX=function() return 8701 end,getY=function() return 8701 end,getZ=function() return 0 end}
assert(not KnoxNightShelter.canShelter("guest-one",square),"a solo stranger cannot silently choose a claimed house")
assert(P.requestOvernightStay(base.id,"guest-one",20)==nil,"repeat requests do not spam or renew")
assert(not P.answerOvernightStay(base.id,"other-host","guest-one",true,20,31),"another player cannot admit a guest")
assert(P.answerOvernightStay(base.id,"guest-host","guest-one",true,20,31),"host can admit the actual requester")
assert(request.status=="accepted" and request.untilHours==31,"permission has a dawn expiry")
assert(KnoxNightShelter.canShelter("guest-one",square),"accepted guest may choose the host house")
local oldClock=getGameTime
getGameTime=function() return {getWorldAgeHours=function() return 31 end} end
assert(not KnoxNightShelter.canShelter("guest-one",square),"dawn removes guest access without recruiting or teleporting")
getGameTime=oldClock
assert(not P.answerOvernightStay(base.id,"guest-host","guest-one",false,21,31),"a response cannot be replayed")
assert(P.requestOvernightStay(base.id,"guest-two",20))
assert(not P.answerOvernightStay(base.id,"guest-host","guest-two",true,22,31),"an expired request is refused")
assert(P.requestOvernightStay(base.id,"guest-three",20))
assert(P.answerOvernightStay(base.id,"guest-host","guest-three",false,20,31),"refusal is a real response")
assert(base.overnightGuests["guest-three"].status=="refused","refusal grants no stay")
assert(P.getSurvivorDuty("guest-one").mode~="base","guest was not silently recruited")
assert(P.requestOvernightStay(base.id,"guest-one",44),"a later night can produce a new request")
assert(P.requestOvernightStay(base.id,"guest-four",20))
local relation=P.getPlayerRelationship("guest-host","guest-four")
relation.trust=11
assert(P.answerOvernightStay(base.id,"guest-host","guest-four",false,20,31))
assert(relation.trust==7 and P.isSurvivorHostileToPlayer("guest-four","guest-host"),
    "refusing a visitor with already-poor standing can become hostile through the existing writer")
