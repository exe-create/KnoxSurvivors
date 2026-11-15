local A=assert(codecStockPermission)
local oldRuntime,oldLooting,oldInstance=KnoxSurvivorRuntime,KnoxSurvivorLooting,instanceof
local own={}
local character={getInventory=function() return own end}
local world={}
local parentIsPerson=false
local source={isInCharacterInventory=function() return false end,
    getParent=function() return {} end,getSourceGrid=function() return world end}
instanceof=function() return parentIsPerson end
KnoxSurvivorRuntime={idForCharacter=function() return "stranger" end}
local allowed=false
KnoxSurvivorLooting={canLootSquare=function(id,square) return id=="stranger" and square==world and allowed end}
assert(not A.canTakeWorldStock(character,source,own),"foreign claimed stock is refused at native transfer boundary")
allowed=true
assert(A.canTakeWorldStock(character,source,own),"resident or valid raid take is admitted")
allowed=false
assert(not A.canTakeWorldStock(character,source,own),"permission changes are reread before transfer")
assert(A.canTakeWorldStock(character,source,{isInCharacterInventory=function() return false end}),"deposit is not a world take")
local bag={isInCharacterInventory=function() return true end}
assert(not A.canTakeWorldStock(character,source,bag),"a carried bag cannot bypass claimed stock permissions")
parentIsPerson=true
assert(A.canTakeWorldStock(character,source,own),"personal handoffs retain their separate permission owner")
KnoxSurvivorRuntime,KnoxSurvivorLooting,instanceof=oldRuntime,oldLooting,oldInstance
