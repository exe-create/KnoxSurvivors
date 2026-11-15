local C = KnoxCreator
local priorReader,priorWriter=getFileReader,getFileWriter
local old = "knox-creator 3\ngroup|Old group\ngroupfaction|user_old\ndef|user_old|Old group\np|Sam Reed|casual|none|none|unemployed|meal|0|0|||brown||user_old||future-person\nfuture|keep|me\n"
local people, group = C.decode(old)
assert(#people == 1 and group.defs[1].id == "user_old", "old roster loads")
local roundtrip = C.encode(people, group)
assert(string.find(roundtrip, "future%-person") and string.find(roundtrip, "future|keep|me", 1, true), "unknown data survives")
local ok, copy = C.copyFaction(group.defs, "police", "My police")
assert(ok and copy.id ~= "police", "copy gets a personal id")
assert(C.updateFaction(group.defs, copy.id, {attitude="neutral", memberCount=4}), "profile edited")
assert(not C.updateFaction(group.defs, copy.id, {attitude="invented"}), "invalid attitude rejected")
assert(not C.updateFaction(group.defs, "police", {attitude="neutral"}), "builtins protected")
local before = C.profileFor(copy.id, group.defs)
local builtin = C.FACTIONS[2].look
C.FACTIONS[2].look = "work"
assert(C.profileFor(copy.id, group.defs).look == before.look, "personal copy independent of updates")
C.FACTIONS[2].look = builtin
local savedPeople, savedGroup = C.decode(C.encode(people, group))
assert(C.profileFor(copy.id, savedGroup.defs).attitude == "neutral", "profile survives save")
local okHome, home = C.addFaction(savedGroup.defs, "Barley", "household")
local okSecond, second = C.addFaction(savedGroup.defs, "Voss", "household")
assert(okHome and okSecond, "two households are created as separate groups")
assert(C.populateFaction(savedPeople, savedGroup, home.id, 3), "populate a household")
assert(C.populateFaction(savedPeople, savedGroup, second.id, 2), "populate a second household")
assert(#savedPeople == 6 and savedPeople[1].name == "Sam Reed", "existing person retained")
assert(C.capacityForFaction(savedPeople, savedGroup, home.id) == 21, "group capacity")
assert(savedPeople[2].name:find("Barley", 1, true) ~= nil,
    "a household shares the surname its group was named")
assert(savedPeople[5].name:find("Voss", 1, true) ~= nil,
    "the second household uses its own name, not the first")
assert(C.profileFor(home.id, savedGroup.defs).settlementPolicy == "home",
    "a saved household keeps its home policy through the codec")
local unknownPeople, unknownGroup = C.decode("knox-creator 3\ndef|user_x|Example|casual|none|none|meal|household|dynamic|3|default|default|default|future-def\n")
assert(string.find(C.encode(unknownPeople, unknownGroup), "future%-def"), "unknown definition field survives")
local _, future = C.decode("knox-creator 99\nfuture|data\n")
assert(future.readOnly and not C.save({}, future), "future format is read only")
local files = { [C.FILE] = old }
getFileReader = function(path)
    local content = files[path]
    if not content then return nil end
    local lines = {}
    for line in string.gmatch(content, "[^\r\n]+") do lines[#lines + 1] = line end
    local i = 0
    return { readLine = function() i = i + 1; return lines[i] end, close = function() end }
end
local failDestination = false
getFileWriter = function(path)
    if failDestination and path == C.FILE then return { write = function() error("write failed") end, close = function() end } end
    return { write = function(_, value) files[path] = value end, close = function() end }
end
local loaded, loadedGroup = C.load()
failDestination = true
assert(not C.save(loaded, loadedGroup), "failed write reported")
assert(files[C.BACKUPS[1]] == old, "old file backed up before destination write")
files[C.FILE] = "broken"
local recovered, recoveryGroup = C.load()
assert(#recovered == 1 and recoveryGroup.recovered and recoveryGroup.readOnly, "recovery is read only")
assert(not C.save(recovered, recoveryGroup), "recovery needs explicit commit")
local missing = C.decodeSlots("vest:AbsentMod.Vest;mask:AbsentMod.Mask;future_slot:AbsentMod.Item")
assert(missing.vest == "AbsentMod.Vest" and string.find(C.encodeSlots(missing), "future_slot:AbsentMod.Item", 1, true), "missing items and future slots survive")
local cargo = C.decodeCargo("AbsentMod.Tool=3;Base.Hammer=1;Base.Invalid=101")
assert(cargo["AbsentMod.Tool"] == 3 and cargo["Base.Invalid"] == nil, "cargo bounds and missing item")
local cargoPeople, cargoGroup = C.decode(old)
cargoPeople[1].cargo, cargoPeople[1].slots = cargo, missing
local cargoRoundtrip = C.decode(C.encode(cargoPeople, cargoGroup))
assert(cargoRoundtrip[1].cargo["AbsentMod.Tool"] == 3 and cargoRoundtrip[1].slots.vest == "AbsentMod.Vest", "cargo and slots persist")
assert(C.recordFor(cargoRoundtrip[1], cargoGroup).cargo == C.encodeCargo(cargo), "cargo handed over")

local missingWeapon = C.decode("knox-creator 3\np|Absent weapon|casual|none|MissingMod.Rifle|base:unemployed|none|0|0|||brown||household|\n")
assert(missingWeapon[1].weaponId=="MissingMod.Rifle" and string.find(C.encode(missingWeapon,C.newGroup()),"MissingMod.Rifle",1,true),
    "a legacy missing-mod carried weapon is not silently reset")
local priorWeapons,priorReady=C.WEAPONS,C.weaponCatalogueReady
C.WEAPONS={};for i,entry in ipairs(priorWeapons) do C.WEAPONS[i]=entry end
for _,fullType in ipairs({"Base.Pistol2","Base.AssaultRifle2"}) do
    C.WEAPONS[#C.WEAPONS+1]={id=fullType,fullType=fullType,label=fullType}
end
C.weaponCatalogueReady=true
local policeDraft=C.applyPresetLoadout(C.draftForFaction("police",{}),C.profileFor("police",{}),2)
assert(C.WEAPONS[policeDraft.weapon].fullType=="Base.Pistol2" and policeDraft.cargo["Base.45Clip"]==1
    and policeDraft.cargo["Base.Bullets45"]==21 and C.KITS[policeDraft.kit].id=="none",
    "police variation uses a matching finite magazine and rounds without a duplicate default kit")
local militaryDraft=C.applyPresetLoadout(C.draftForFaction("military",{}),C.profileFor("military",{}),2)
assert(C.WEAPONS[militaryDraft.weapon].fullType=="Base.AssaultRifle2" and militaryDraft.cargo["Base.308Bullets"]==40,
    "military variation has matching bounded ammunition")
C.WEAPONS,C.weaponCatalogueReady=priorWeapons,priorReady

-- A successful low-level writer is not enough: the owner verifies the file.
failDestination=false
files[C.FILE]=old
local writerThatWorks=getFileWriter
getFileWriter=function(path)
    if path==C.FILE then return {write=function() end,close=function() end} end
    return writerThatWorks(path)
end
assert(not C.save(loaded,loadedGroup), "a silent short write cannot be reported saved")
assert(files[C.BACKUPS[2]]==old, "verification failure keeps the previous complete file")
getFileWriter=writerThatWorks
assert(C.save(loaded,loadedGroup), "verified format-four write succeeds")
assert(string.find(files[C.FILE],"knox-creator 4",1,true)==1,"new profile fields have an explicit format version")
-- Simulate the installed writer's extension restriction and a failed backup write.
local current = files[C.FILE]
local preserved = files[C.BACKUPS[1]]
getFileWriter=function(path)
    if not string.find(path, "%.txt$") then return nil end
    if path==C.BACKUPS[2] then return {write=function() error("disk full") end,close=function() end} end
    return writerThatWorks(path)
end
local failed,why=C.save(loaded,loadedGroup)
assert(not failed and why=="backup_failed" and files[C.FILE]==current,
    "backup failure leaves the main file intact")
assert(files[C.BACKUPS[1]]==preserved, "failed backup preserves another verified copy")
getFileWriter=writerThatWorks
assert(C.save(loaded,loadedGroup), "allowed txt backup and main write recover")
files[C.FILE]="broken"
local again, recoveredGroup=C.load()
assert(#again==#loaded and recoveredGroup.recovered, "verified backup recovers after main corruption")
getFileReader,getFileWriter=priorReader,priorWriter
