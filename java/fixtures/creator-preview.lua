local View, C = assert(codecCreatorView), assert(KnoxCreator)
local saved = {factory=SurvivorFactory, instance=instanceItem, color=ImmutableColor,
    location=ItemBodyLocation, resource=ResourceLocation, main=MainScreen, save=C.save}
local descriptors = {}
SurvivorFactory = {CreateSurvivor=function()
    local desc = {worn={}, visual={}}
    function desc:setFemale(value) self.female=value end
    function desc:setForename(value) self.name=value end
    function desc:setSurname(value) self.surname=value end
    function desc:getWornItems() return {clear=function() self.worn={} end} end
    function desc:setWornItem(location,item) self.worn[location]=item end
    for _,method in ipairs({"setSkinTextureIndex","setHairModel","setBeardModel","setHairColor","setBeardColor",
        "setNaturalHairColor","setNaturalBeardColor"}) do
        desc.visual[method]=function(self,value) self[method.."Value"]=value end
    end
    function desc:getHumanVisual() return self.visual end
    descriptors[#descriptors+1]=desc
    return desc
end}
local mainDesc = {untouched=true}
MainScreen = {instance={desc=mainDesc}}
ImmutableColor = {new=function(r,g,b) return {r,g,b} end}
ResourceLocation = {of=function(value) return value end}
ItemBodyLocation = {get=function(value) return value end}
instanceItem = function(fullType)
    return {fullType=fullType, IsClothing=function() return true end,
        getBodyLocation=function() return fullType end}
end
local person = {name="June Barley",look="casual",female=true,hair="Long",beard="Full",
    hairColour="brown",skin=3,slots={head="Base.Hat_Police"}}
local desc = assert(View.createPreviewDescriptor(person))
assert(desc~=mainDesc and MainScreen.instance.desc==mainDesc and mainDesc.untouched,
    "preview has its own descriptor and never changes the player's main-menu character")
assert(desc.female and desc.name=="June" and desc.surname=="Barley" and desc.visual.setHairModelValue=="Long",
    "the selected person's identity and hair reach the preview")
assert(desc.visual.setBeardModelValue==nil and desc.worn["Base.Hat_Police"]~=nil,
    "sex and selected clothing reach the isolated body")
assert(View.previewSignature(person)~=View.previewSignature({look="casual",slots={}}),
    "appearance changes invalidate the preview")
assert(desc.visual.setSkinTextureIndexValue==3,"the selected skin texture reaches the preview")
local nextDesc=assert(View.createPreviewDescriptor(person))
assert(nextDesc~=desc, "building another preview cannot mutate an earlier descriptor")
for _,font in ipairs({14,24}) do
    for _,size in ipairs({{1024,768},{1280,720},{1920,1080}}) do
        local m=View.editorMetrics(size[1],size[2],font)
        assert(m.width<=size[1] and m.height<=size[2] and m.row>=font+12,
            "editor stays on screen and rows fit small and large font")
        assert(m.width-m.rail-m.detail-40>=190 and m.cell>=font*2+20,
            "rail, cards, labeled item cells and detail retain real space")
    end
end
local Window=assert(codecCreatorCommitWindow)
local window=setmetatable({dirty=true,visible=true,removed=false,roster={},group={defs={}},
    setNote=function(self,text) self.note=text end,
    promptFor=function(self,caption,callback) self.discardCallback=callback end,
    setVisible=function(self,value) self.visible=value end,
    removeFromUIManager=function(self) self.removed=true end}, {__index=Window})
C.save=function() return false,"write_failed" end
assert(window:onClose()==false and window.visible and not window.removed and window.dirty,
    "failed save keeps the user's edits open")
C.save=function() return true,"saved" end
window:onClose()
assert(not window.visible and window.removed and not window.dirty,
    "successful close writes through the existing owner once")
-- The real window refresh should only hand a new descriptor to the native
-- model when the person or their visible appearance actually changes.
local current=person
local sets=0
local preview={visible=false,setVisible=function(self,v) self.visible=v end,
    setSurvivorDesc=function(self,desc) sets=sets+1;self.descriptor=desc end}
local viewWindow=setmetatable({selected=function() return current end,preview=preview,previewSet=true},{__index=Window})
viewWindow:refreshPreview()
local originalDescriptor=preview.descriptor
viewWindow:refreshPreview()
assert(sets==1,"an unchanged preview does not reset its native model")
local identical={}
for key,value in pairs(person) do identical[key]=value end
current=identical
viewWindow:refreshPreview()
assert(sets==2 and preview.descriptor~=originalDescriptor,"identical appearance choices still get the selected person's own descriptor")
current.skin=2
viewWindow:refreshPreview()
assert(sets==3 and preview.descriptor.visual.setSkinTextureIndexValue==2,"a real appearance edit reaches the model once")
current.skills={Aiming=8}
viewWindow:refreshPreview()
assert(sets==3,"a skill edit leaves the visual preview intact")
local expected=preview.descriptor
current=nil
viewWindow:refreshPreview()
assert(not preview.visible,"no selected person hides the old model")
current=identical
viewWindow:refreshPreview()
assert(preview.visible and preview.descriptor~=expected,"reselecting after an empty view rebuilds the correct private descriptor")
C.save=saved.save
SurvivorFactory,instanceItem,ImmutableColor,ItemBodyLocation,ResourceLocation,MainScreen=
    saved.factory,saved.instance,saved.color,saved.location,saved.resource,saved.main
print("Creator preview PASS isolated=true dressed=true fontFit=true failedSaveRetained=true")
