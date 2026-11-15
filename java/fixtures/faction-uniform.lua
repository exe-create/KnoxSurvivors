local E=assert(KnoxEquipmentIntelligence)
local oldActions,oldFaction=KnoxInventoryActions,KnoxPersistence.getFactionForSurvivor
local function list(values)
    return {size=function() return #values end,get=function(_,index) return values[index+1] end,
        getItemByIndex=function(_,index) return values[index+1] end}
end
local source,destination={},{}
local function garment(id)
    local item={container=source}
    item.getFullType=function() return "Base.Jacket_ArmyCamoGreen" end
    item.getID=function() return id end
    item.getBodyLocation=function() return "Jacket" end
    item.isFavorite=function() return false end
    item.getContainer=function(self) return self.container end
    return item
end
local worn,spare=garment(100),garment(101)
source.getItems=function() return list({worn,spare}) end
local recipientWorn=nil
local donor={id="uniform-donor",character={getInventory=function() return source end,
    getWornItems=function() return list({worn}) end,getWornItem=function() return worn end,
    getPrimaryHandItem=function() return nil end,getSecondaryHandItem=function() return nil end,
    isDead=function() return false end}}
local recruit={id="uniform-recruit",character={getInventory=function() return destination end,
    getWornItem=function() return recipientWorn end,isDead=function() return false end}}
local faction={id="uniform-unit",background="military"}
KnoxPersistence.getFactionForSurvivor=function() return faction end
local queued=nil
KnoxInventoryActions={queueTransfer=function(actor,item,from,to,duration,guard)
    assert(actor==donor.character and from==source and to==destination,"donor owns the native transfer")
    assert(item==spare and guard(),"only a real spare is offered")
    queued=item
    return {}
end}
assert(E.offerFactionUniform(donor,recruit,faction,20),"recruit is offered an actual spare uniform")
assert(queued==spare and spare.container==source,"queueing never fabricates a transfer receipt")
local state={uniformReceipts={{item=spare,location="Jacket",expires=620}}}
local bridge={wearNpcOwnedItemById=function(_,id,fullType,itemId)
    assert(id==recruit.id and itemId==101 and spare.container==destination,"only owned received clothing may be worn")
    recipientWorn=spare
    return "WORN_OWNED"
end}
assert(not E.receiveUniform(recruit.id,recruit.character,bridge,state,21),"unreceived clothing is not worn")
spare.container=destination
assert(E.receiveUniform(recruit.id,recruit.character,bridge,state,22),"real receipt allows native wear")
assert(recipientWorn==spare and worn.container==source,"donor keeps their worn uniform")
KnoxInventoryActions,KnoxPersistence.getFactionForSurvivor=oldActions,oldFaction
