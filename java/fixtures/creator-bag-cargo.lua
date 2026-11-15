-- Creator cargo survives the existing roster codec and is placed only in the
-- selected worn container. Engine objects are boundary stubs.
local C = assert(KnoxCreator)
local G = assert(KnoxSurvivorStartingGear)
local oldFactory, oldInstanceof = instanceItem, instanceof
local created=0
instanceItem = function(id)
    created=created+1
    if id == "Mod.Missing" then return nil end
    return { id=id, isTwoHandWeapon=function(self) return self.id == "Mod.Rifle" end,
        isRequiresEquippedBothHands=function() return false end }
end
instanceof = function(item, kind) return kind == "InventoryContainer" and item.bag == true end
assert(C.isTwoHanded("Mod.Rifle"), "two-hand requirement comes from the item")
assert(C.isTwoHanded("Mod.Rifle") and created==1,"card redraws reuse native hand requirements")
assert(not C.isTwoHanded("Mod.Knife"), "ordinary item is not two-handed")
local secondary=codecCreatorView.effectiveSlot({slots={primary="Mod.Rifle",secondary="Mod.Knife"}},C.slotById("secondary"))
assert(secondary.fullType=="Mod.Rifle","two-handed primary occupies the secondary display")
local equipped,held={},{}
local hands={getInventory=function() return {AddItem=function(_,id) local item=instanceItem(id);equipped[#equipped+1]=item;return item end} end,
 setPrimaryHandItem=function(_,item) held.primary=item end,setSecondaryHandItem=function(_,item) held.secondary=item end}
assert(G.applyChosenWeapon("hands-fixture",hands,"Mod.Rifle"))
assert(#equipped==1 and held.primary==held.secondary,"native hands share one two-handed item")
assert(G.applyChosenWeapon("hands-fixture",hands,"Mod.Knife"))
assert(held.primary.id=="Mod.Knife" and held.secondary==nil and #equipped==2,
    "one-handed creator choice clears stale off-hand without removing real carried items")
local roster = {{name="Cargo Test", look="casual", kit="none", weaponId="none", profession="base:unemployed", pack="none", slots={}, cargo={ ["Mod.Knife"]=1 }, bagCargo={ ["Mod.Rifle"]=2 }}}
local decoded = C.decode(C.encode(roster, C.newGroup()))
assert(decoded[1].cargo["Mod.Knife"] == 1 and decoded[1].bagCargo["Mod.Rifle"] == 2, "both destinations survive roster codec")
local P=assert(KnoxPersistence)
local record=C.recordFor(decoded[1],C.newGroup())
assert(P.setSurvivorCreatorRecord("bag-fixture",record))
assert(P.getSurvivorCreatorRecord("bag-fixture").bagCargo==record.bagCargo,"world record retains backpack destination")
local content = {}
local container = {
    hasRoomFor=function(self, character, item) return #content < 1 end,
    AddItem=function(self, item) content[#content+1]=item; return item end,
    Remove=function(self, item) for i=#content,1,-1 do if content[i] == item then table.remove(content,i) end end end,
}
local bag = {bag=true, getFullType=function() return "Mod.Pack" end, getInventory=function() return container end}
local inventory = {getItems=function() return {size=function() return 1 end, get=function() return bag end} end}
local character = {getInventory=function() return inventory end, isEquipped=function(self, item) return item == bag end}
local ok = G.applyBagItems(character, "Mod.Pack", {"Mod.Knife"})
assert(ok and #content == 1 and content[1].id == "Mod.Knife", "item delivered to worn bag")
content = {}
ok = G.applyBagItems(character, "Mod.Pack", {"Mod.Knife", "Mod.Rifle"})
assert(not ok and #content == 0, "full bag refuses and rolls back")
ok = G.applyBagItems(character, "Mod.Other", {"Mod.Knife"})
assert(not ok and #content == 0, "missing authored bag has no fallback")
instanceItem, instanceof = oldFactory, oldInstanceof
