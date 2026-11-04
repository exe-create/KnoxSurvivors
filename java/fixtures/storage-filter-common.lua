local UI=KnoxBaseStorageFilterUI
local scans=0
local priorManager,priorText=getScriptManager,getTextOrNull
getTextOrNull=function() return nil end
local categories={"Food","AnimalFood","Medical","Food"}
getScriptManager=function() return {getAllItems=function()
    scans=scans+1
    return {size=function() return #categories end,get=function(_,i)
        return {getDisplayCategory=function() return categories[i+1] end}
    end}
end} end
local policy={storageFilterVersion=1,storageFilters={food=true,tools=true,["display:AnimalFood"]=true}}
local selected=UI.editableFilters(policy)
assert(selected.food and selected.tools and selected["display:AnimalFood"],"editing must not discard saved convenience filters")
assert(UI.editableFilters({storageRole="food"}).food,"legacy food storage stays selected")
local rows={}
local list={clear=function() rows={} end,addItem=function(_,label,data) rows[#rows+1]={text=label,item=data} end}
local titles={}
local window=setmetatable({selectedFilters=selected,categoryList=list,advancedButton={setTitle=function() end},
    setTitle=function(_,text) titles[#titles+1]=text end},
    {__index=UI.FilterWindow})
window:populateCategories()
assert(#titles>0 and string.find(titles[1],"3 rules",1,true)~=nil,
    "the title must state how many rules the sheet keeps, got "..tostring(titles[1]))
assert(UI.modeButtonTitle("groups")=="Pick exact items" and UI.modeButtonTitle("items")=="All categories",
    "the view button must name the view it opens")
local roomTitle = UI.selectionTitle({food = true}, "Bedroom 1")
assert(string.find(roomTitle, "Bedroom 1", 1, true) ~= nil,
    "the filter title must name the room, got " .. tostring(roomTitle))
assert(string.find(roomTitle, "1 rule", 1, true) ~= nil,
    "the room must not replace the rule count, got " .. tostring(roomTitle))
local bareTitle = UI.selectionTitle({food = true})
assert(string.find(bareTitle, "Bedroom", 1, true) == nil,
    "a policy without a room must not invent one")
-- Ten groups, one curated extra ("Books & Maps") and the one saved advanced
-- filter that is not itself a group: a short first view, not the catalogue.
assert(scans==0 and #rows==12 and rows[1].item.key=="food","basic view uses common groups and selected filters without scanning installed scripts")
local function contains(key)
    for _,row in ipairs(rows) do if row.item.key==key then return true end end
    return false
end
assert(contains("display:AnimalFood") and not contains("display:Medical"),"selected advanced filters stay visible without the whole category list")
window:onAdvanced()
assert(scans==1 and contains("display:Food") and contains("display:Medical"))
window:onAdvanced();window:onAdvanced()
assert(scans==1 and selected.food and selected.tools and selected["display:AnimalFood"],"view switches preserve filters and reuse the same script snapshot")
UI.FilterWindow.onToggleCategory(window,{item={key="tools"}})
assert(not selected.tools and selected.food and selected["display:AnimalFood"],"common toggles change only their own filter")
assert(KnoxBaseStorage.filterAllowsItem({storageFilterVersion=1,storageFilters={["display:AnimalFood"]=true}},
    {getDisplayCategory=function() return "AnimalFood" end}),"saved advanced filter still has its real storage meaning")
getScriptManager,getTextOrNull=priorManager,priorText
KnoxBaseStorage,KnoxBaseStorageFilterUI=codecPreviousStorage,codecPreviousFilterUI
ISCollapsableWindowJoypad=codecPreviousCollapsable



print("Storage filters PASS common_first=true advanced_preserved=true no_silent_filter_loss=true lazy_catalogue=true")
