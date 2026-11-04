-- Exact melee fallback must never AddItem an instance already at inventory root.
local function list(items)
    return {size=function() return #items end,get=function(_,index) return items[index+1] end}
end
local weapon={}
function weapon:IsWeapon() return true end
function weapon:isRanged() return false end
function weapon:isBroken() return false end
function weapon:getID() return 421 end
function weapon:getFullType() return "Base.Nightstick" end
local root={contents={weapon},addCalls=0}
function root:getItems() return list(self.contents) end
function root:AddItem(item)
    self.addCalls=self.addCalls+1
    for _,carried in ipairs(self.contents) do
        if carried==item then error("duplicate item ID") end
    end
    self.contents[#self.contents+1]=item
    return item
end
local character={inventory=root,primary=nil}
function character:getInventory() return self.inventory end
function character:getPrimaryHandItem() return self.primary end
local bridge={}
function bridge:equipNpcOwnedWeaponById(_,_,id)
    assert(id==421)
    character.primary=weapon
    return "EQUIPPED_WEAPON Base.Nightstick"
end
assert(KnoxFirearmSupport.fallbackToMelee("test",bridge,character)=="EQUIPPED_WEAPON Base.Nightstick")
assert(root.addCalls==0,"root weapon was added to the same inventory twice")

-- Bagged instances still transfer once into the root before exact equip.
local bagItems={weapon}
local bag={IsInventoryContainer=function() return true end,
    getInventory=function() return {getItems=function() return list(bagItems) end} end}
root.contents={bag}; root.addCalls=0; character.primary=nil
assert(KnoxFirearmSupport.pullMeleeToHands("test",character,bridge))
assert(root.addCalls==1 and root.contents[2]==weapon,"bagged weapon was not transferred once")
print("Firearm inventory ownership PASS root_duplicate=false bag_transfer=once")
