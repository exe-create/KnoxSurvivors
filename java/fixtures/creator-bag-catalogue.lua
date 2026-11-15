local oldManager=getScriptManager
local count=0
local item={getFullName=function() return "Tarkov.Pack" end,getBodyLocation=function() return nil end,
 getItemType=function() return "Container" end,getDisplayName=function() return "Installed mod backpack" end}
getScriptManager=function() count=count+1;return {getAllItems=function() return {size=function() return 1 end,get=function() return item end} end} end
local entries=codecBagCatalogue("backpack")
local found=false
for _,entry in ipairs(entries) do if entry.fullType=="Tarkov.Pack" then found=true end end
assert(found,"installed containers need no clothing body location to appear")
assert(codecBagCatalogue("backpack")==entries and count==1,"unchanged catalogue is reused")
getScriptManager=oldManager
