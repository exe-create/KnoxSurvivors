-- Production forced-entry admission; the live body and base are replaced by
-- the four facts the boundary gathers. Every refusal must name its real cause:
-- the break boundary used to print one sentence for four different causes.
local admission=codecForcedEntry
assert(type(admission)=="table","forced entry admission is loaded")
assert(type(admission.forcedEntryRefusalFrom)=="function","the reason boundary is loaded")
assert(type(admission.forcedEntryIntentAllows)=="function","the intent gate is loaded")
local refusal=admission.forcedEntryRefusalFrom
local intent=admission.forcedEntryIntentAllows

local function show(value)
    if value==nil then return "nil" end
    return tostring(value)
end

-- The two-argument form asserts that no refusal was produced.
local function expect(actual,wanted,label)
    if label==nil then label,wanted=wanted,nil end
    assert(actual==wanted,label..": got "..show(actual)..", wanted "..show(wanted))
end

-- Each cause has its own sentence.
expect(refusal(true,nil,"melee",1),"structure_check_unavailable",
    "an unavailable protection check is not a protected base")
expect(refusal(true,false,"melee",1),"protected_player_base","a protected base refuses")
expect(refusal(false,true,"melee",1),"intent_not_allowed",
    "the decision gates before the weapon")
expect(refusal(true,true,nil,1),"no_melee_weapon","an empty hand is refused")
expect(refusal(true,true,"none",1),"no_melee_weapon","a held non-weapon is not a melee weapon")
expect(refusal(true,true,"broken",1),"melee_weapon_broken",
    "a broken handle is its own reason, not a missing weapon")
expect(refusal(true,true,"ranged",1),"ranged_weapon_not_a_melee_tool",
    "a gun is not a door tool")
expect(refusal(true,true,"melee",0.39),"too_tired_for_forced_entry",
    "endurance below the threshold refuses")
expect(refusal(true,true,"melee",0.40),"the threshold itself is enough")
expect(refusal(true,true,"melee",nil),"too_tired_for_forced_entry",
    "unreadable endurance fails closed")
expect(refusal(true,true,"melee",1),"an armed, rested survivor may break a door")

-- Precedence stays protection, then decision, then weapon, then stamina.
expect(refusal(false,false,nil,0),"protected_player_base",
    "protection is reported before the decision")
expect(refusal(false,true,nil,0),"intent_not_allowed",
    "the decision is reported before the weapon")
expect(refusal(true,true,"broken",0),"melee_weapon_broken",
    "the weapon is reported before stamina")

-- The intent gate keeps the published decisions and its prefix forms.
for _,allowed in ipairs{"scavenge","inspect_container","return_to_base","patrol_base",
    "loot_building","find_food","base_task_haul"} do
    assert(intent(allowed)==true,"intent "..allowed.." is allowed")
end
for _,refused in ipairs{"hold","follow","rest","eat","","nil"} do
    assert(intent(refused)==false,"intent '"..refused.."' is refused")
end
assert(intent(nil)==false,"a missing decision is refused")
