local C,V,W=assert(KnoxCreator),assert(codecCreatorView),assert(codecCreatorCommitWindow)
local old={instance=instanceItem,kind=WeaponType,is=instanceof,bridge=KnoxJavaBridge,api=KnoxRuntimeApi,manager=getScriptManager}
local creates=0
instanceItem=function(id)
    creates=creates+1
    if id=="Mod.Missing" then return nil end
    return {id=id,getStaticModel=function() return id=="Mod.Flat" and "" or id.."Model" end,
        isTwoHandWeapon=function() return id=="Mod.Rifle" end}
end
instanceof=function() return true end
WeaponType={getWeaponType=function() return {getType=function() return "firearm" end} end}
local p={name="Test Person",weapon="Mod.Rifle",slots={secondary="Base.Pistol"}}
local cache={}
local primary,secondary,pose,missing=V.previewHandModels(p,cache)
assert(primary=="Mod.RifleModel" and secondary==nil and pose=="firearm" and not missing,
    "two-handed preview renders one native model with native weapon pose")
V.previewHandModels(p,cache)
assert(creates==1,"preview reuses selected person's real item cache")
assert(C.effectiveSlotChoice(p,"secondary").fullType=="Mod.Rifle",
    "preset and explicit primaries share both-hand projection")
local signature=V.previewSignature(p);p.weapon="Base.Pistol"
assert(signature~=V.previewSignature(p),"preset weapon changes invalidate the visible preview")
p.slots.primary="__none"
primary,secondary,pose,missing=V.previewHandModels(p,cache)
assert(primary==nil and secondary==nil and not missing,"empty primary does not resurrect a preset or show the spare")
p.slots.primary="Mod.Missing"
primary,secondary,pose,missing=V.previewHandModels(p,cache)
assert(primary==nil and missing,"unavailable item reports a partial preview")
p.slots.primary="Mod.Rifle"
local applied,calls={},0
KnoxJavaBridge={setCreatorPreviewHands=function(self,ui,a,b) calls=calls+1;applied={ui,a,b};return true end}
local preview={javaObject={},setVariable=function(self,k,v) self.pose=v end,
    clearVariable=function(self) self.pose=nil end}
local win=setmetatable({preview=preview,previewCaches={[p]=cache}},{__index=W})
win:refreshPreviewHands(p)
assert(applied[1]==preview.javaObject and applied[2]=="Mod.RifleModel" and applied[3]==nil
    and preview.pose=="firearm" and not win.previewHandsUnavailable,"window binds its isolated native renderer")
KnoxJavaBridge=nil;KnoxRuntimeApi=nil
win:refreshPreviewHands(p)
assert(win.previewHandsUnavailable,"older or missing runtime leaves clothing preview available with an honest hand warning")
KnoxJavaBridge={setCreatorPreviewHands=function() error("unavailable") end}
assert(pcall(W.refreshPreviewHands,win,p),"runtime refusal cannot throw away the body preview")

local records={}
for _,entry in ipairs({{"Mod.Belt","base:belt"},{"Mod.Holster","base:beltextra"},
    {"Mod.Shoulder","base:shoulderholster"},{"Mod.Glasses","base:eyes"},
    {"Mod.Socks","base:socks"},{"Mod.Scarf","base:neck"}}) do
    local id,location=entry[1],entry[2]
    records[#records+1]={getFullName=function() return id end,getBodyLocation=function() return location end,
        getDisplayName=function() return id end}
end
getScriptManager=function() return {getAllItems=function() return {
    size=function() return #records end,get=function(self,i) return records[i+1] end} end} end
for slot,id in pairs({belt="Mod.Belt",holster="Mod.Holster",eyes="Mod.Glasses",socks="Mod.Socks",neck="Mod.Scarf"}) do
    local found=false
    for _,item in ipairs(codecAccessoryCatalogue(slot)) do if item.fullType==id then found=true end end
    assert(found,"new clothing slot discovers actual modded body location: "..slot)
end
local worn=C.lookItemsWithSlots("casual",{belt="Base.Belt2",holster="Base.HolsterSimple"})
local seen={};for _,id in ipairs(worn) do seen[id]=true end
assert(seen["Base.Belt2"] and seen["Base.HolsterSimple"],"selected belt and holster reach the real clothing handover")
local roster={{name="Belt Person",look="casual",slots={belt="Base.Belt2",holster="Base.HolsterSimple",eyes="Mod.Glasses"}}}
local read=C.decode(C.encode(roster,C.newGroup()))
assert(read[1].slots.eyes=="Mod.Glasses" and read[1].slots.belt=="Base.Belt2","new slots survive the existing creator codec")
instanceItem,WeaponType,instanceof,KnoxJavaBridge,KnoxRuntimeApi,getScriptManager=old.instance,old.kind,old.is,old.bridge,old.api,old.manager
return "PASS nativeModelBinding=true twoHandsOneModel=true spareNotHeld=true accessorySlots=5 codec=true rendered=false"
