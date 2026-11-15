-- Optional EFZ family detection uses a real carried gun and compatible ammo.
-- The Gunworks registry and inventory are small doubles; no game action runs.
local previousSettings, previousPerks = KnoxSettings, Perks
local previousReload, previousFamily, previousRequire = ISReloadWeaponAction, TWAmmoFamily, require
local function list(entries)
    return {size=function() return #entries end,
        get=function(_,i) return entries[i+1] end}
end
local gun={}
function gun:IsWeapon() return true end
function gun:isRanged() return true end
function gun:isBroken() return false end
function gun:isSelectFire() return false end
function gun:getFullType() return "EscapeFromZomboidFirearms.M870" end
function gun:getMaxRange() return 8 end
function gun:getMaxDamage() return 2 end
function gun:getCondition() return 10 end
function gun:getBestMagazine() return nil end
function gun:getAmmoType() return {getItemKey=function() return "Base.ShotgunShells" end} end
local melee={IsWeapon=function() return true end,isRanged=function() return false end,
    isBroken=function() return false end}
local carried={getItems=function() return list({gun,melee}) end,
    getItemCountRecurse=function() return 0 end}
local actor={getInventory=function() return carried end,
    getPrimaryHandItem=function() return melee end,
    getPerkLevel=function() return 0 end,
    getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
local target={getX=function() return 5 end,getY=function() return 0 end,getZ=function() return 0 end}
Perks={Aiming="aiming"}
ISReloadWeaponAction={canShoot=function() return false end,canRack=function() return false end}
TWAmmoFamily=function() return "TW:ammo:12ga" end
require=function(name)
    if name=="WeaponSystems/Utils/Ammo" then
        return {GetAutomaticReloadAmmoType=function(_,item)
            return item==gun and "EscapeFromZomboidFirearms.A_compatible" or nil end}
    end
    if name=="WeaponSystems/Utils/Magazine" then
        return {getBestMagazineForGun=function() return nil end}
    end
    return previousRequire(name)
end
KnoxSettings={efzFirearmCompatibility=function() return false end,
    survivorAimingAssist=function() return 1 end}
local wanted=KnoxFirearmSupport.wantsRanged("codec-person",actor,target,false)
assert(wanted==false,"disabled EFZ option must retain the ordinary choice")
local groupWanted, groupReason = KnoxFirearmSupport.wantsRanged("codec-person",actor,target,false,true)
assert(groupWanted==false and groupReason=="group_melee_preference",
    "a party with usable steel prefers melee so gunfire does not pull the horde in")
KnoxSettings.efzFirearmCompatibility=function() return true end
wanted=KnoxFirearmSupport.wantsRanged("codec-person",actor,target,false)
assert(wanted==true,"EFZ option should recognize a carried gun with compatible ammo")
TWAmmoFamily=nil
wanted=KnoxFirearmSupport.wantsRanged("codec-person",actor,target,false)
assert(wanted==false,"missing EFZ must leave the ordinary choice intact")
KnoxSettings, Perks = previousSettings, previousPerks
ISReloadWeaponAction, TWAmmoFamily, require = previousReload, previousFamily, previousRequire
print("EFZ firearm compatibility PASS opt_in=true compatible_ammo=true missing_mod_safe=true")
