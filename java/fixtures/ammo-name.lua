local ammo = assert(codecAmmoName)
local previousInstanceof = instanceof
instanceof = function(item, class) return item.weapon == true and class == "HandWeapon" end
local function hands(primary, secondary)
    return { getPrimaryHandItem=function() return primary end, getSecondaryHandItem=function() return secondary end }
end
local weaponLookupErrors = 0
local nonweapon = setmetatable({weapon=false}, {__index=function()
    weaponLookupErrors = weaponLookupErrors + 1
    error("nonweapon method lookup")
end})
assert(ammo(nil) == nil, "missing character has no ammo")
assert(ammo(hands(nil,nil)) == nil, "empty hands have no ammo")
assert(ammo(hands(nonweapon,nil)) == nil, "ordinary item has no ammo")
assert(weaponLookupErrors == 0, "ordinary item avoids weapon method lookup")
local melee = {weapon=true, isRanged=function() return false end}
assert(ammo(hands(melee,nil)) == nil, "melee has no ammo")
local gun = {weapon=true, isRanged=function() return true end, getCurrentAmmoCount=function() return 0 end, isRoundChambered=function() return false end}
assert(ammo(hands(gun,nil)) == "Empty", "zero rounds reports empty")
gun.isRoundChambered=function() return true end
assert(ammo(hands(nil,gun)) == "1 chambered", "secondary gun reports chamber")
assert(ammo(hands(gun,gun)) == "1 chambered", "two hands do not duplicate ammo")
gun.getCurrentAmmoCount=function() return 3 end
assert(ammo(hands(gun,nil)) == "3 rounds", "loaded gun reports rounds")
gun.getCurrentAmmoCount=nil
assert(ammo(hands(gun,nil)) == nil, "missing count stays unknown")
gun.getCurrentAmmoCount=function() error("native getter failed") end
assert(ammo(hands(gun,nil)) == nil, "failed count stays unknown")
gun.getCurrentAmmoCount=function() return 0 end
gun.isRoundChambered=nil
assert(ammo(hands(gun,nil)) == nil, "missing chamber stays unknown")
gun.isRoundChambered=function() error("chamber getter failed") end
assert(ammo(hands(gun,nil)) == nil, "failed chamber stays unknown")
gun.isRanged=nil
assert(ammo(hands(gun,nil)) == nil, "missing ranged test stays unknown")
gun.isRanged=function() error("ranged getter failed") end
assert(ammo(hands(gun,nil)) == nil, "failed ranged test stays unknown")
local trap=setmetatable({weapon=true}, {__index=function() error("lookup failed") end})
assert(ammo(hands(trap,nil)) == nil, "trapped lookup stays unknown")

instanceof = previousInstanceof
