local viewType=codecCrewView
local previousPersistence=KnoxPersistence
KnoxPersistence={getSurvivorDuty=function(id)
    return id=="resident-b" and {mode="base",baseId="home"} or nil
end}
local selected="resident-b"
local repaintCount=0
local function button()
    return {setEnable=function(self,value) self.enabled=value end,
        setEnabled=function(self,value) self.enabled=value end}
end
local view={detailResidentId="resident-a",viewBtn=button(),joinPartyBtn=button(),
    jobPicker=button(),setJobBtn=button(),saveScheduleBtn=button(),colonyPresetBtn=button(),
    nightPresetBtn=button(),clearPresetBtn=button(),resetPrioritiesBtn=button(),
    inventoryBtn=button(),
    refreshGuardOverrideControl=viewType.refreshGuardOverrideControl,
    selectedCrewId=function() return selected end,
    paintCrewDetail=function(self)
        repaintCount=repaintCount+1
        self.detailResidentId=selected
    end,
    crewBase=function() return {id="home"} end}
viewType.prerender(view)
assert(repaintCount==1 and view.detailResidentId=="resident-b",
    "selected resident details repaint on the same frame")
assert(view.viewBtn.enabled and view.joinPartyBtn.enabled and view.saveScheduleBtn.enabled,
    "base schedule controls follow the selected resident")
viewType.prerender(view)
assert(repaintCount==1,"stable selection does not repaint details every frame")
selected=nil
viewType.prerender(view)
assert(repaintCount==2 and not view.viewBtn.enabled and not view.joinPartyBtn.enabled,
    "clearing selection refreshes details and disables resident controls")
assert(not view.inventoryBtn.enabled,
    "the pack action follows the same selection as the other resident controls")
KnoxPersistence=previousPersistence
print("Notebook crew selection PASS immediate_repaint=true no_frame_loop=true controls_match=true")
