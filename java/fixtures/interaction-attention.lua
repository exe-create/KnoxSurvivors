-- Production UI/medical/inventory functions; native panels/actions are explicit doubles.
local savedRuntime,savedPlayer,savedTime=KnoxSurvivorRuntime,getSpecificPlayer,getTimestampMs
local savedMedical,savedHealth,savedUtils,savedQueue=ISMedicalCheckAction,ISHealthPanel,luautils,ISTimedActionQueue
local savedLoot,savedInventory,savedPages=getPlayerLoot,getPlayerInventory,ISInventoryPage
local savedTradeActions,savedCollapsable=KnoxTradeActions,ISCollapsableWindowJoypad
local p=KnoxPersistence
local oldAlive,oldAffiliation,oldOwner=p.isSurvivorAlive,p.getSurvivorAffiliation,p.ensurePlayerId
local now,starts,ends,queued=0,0,0,nil
getTimestampMs=function() return now end
local square={canReachTo=function() return true end}
local inventory={}
local function actor()
    return {getCurrentSquare=function() return square end,getZ=function() return 0 end,
        getX=function() return 10 end,getY=function() return 10 end,isDead=function() return false end,
        Say=function() end,getInventory=function() return inventory end}
end
local doctor,patient=actor(),actor()
getSpecificPlayer=function() return doctor end
local owner={state="BASE_TASK_MOVE"}
local finishing=true
KnoxSurvivorRuntime={getCharacter=function() return patient end,getController=function() return owner end,
    canInteract=function() return true end,
    beginPlayerConversation=function(id,player)
        assert(player==doctor)
        if finishing then return false,"work_step_finishing" end
        starts=starts+1;owner.playerConversation=owner.playerConversation or {player=player}
        owner.state="PLAYER_CONVERSATION";return true,"talking"
    end,
    endPlayerConversation=function()
        ends=ends+1;owner.playerConversation=nil;owner.state="IDLE";return true
    end}
local window={survivorId="patient",player=doctor,attentionController=owner,
    attentionPending=true,attentionPendingUntil=1000,refreshActions=function(self) self.refreshed=true end}
assert(codecInteractionUI.updatePendingAttention(window,0) and window.attentionPending)
finishing=false
assert(codecInteractionUI.updatePendingAttention(window,100) and window.attentionStarted and window.refreshed)
assert(codecInteractionUI.ownsAttention(window))
local talkLease=owner.playerConversation
owner.playerConversation={player=doctor}
assert(not codecInteractionUI.ownsAttention(window),"an old Talk panel cannot release a newer medical/inventory lease")
owner.playerConversation=talkLease
assert(not codecInteractionUI.updatePendingAttention(window,1000),"pending request expires without opening another lease")
local originalOwner=owner
owner={state="IDLE"}
assert(not codecInteractionUI.updatePendingAttention(window,200),"pending request cannot follow a replacement body/controller")
owner=originalOwner

ISCollapsableWindowJoypad={update=function() end}
local attempts,refreshes=0,0
KnoxTradeActions={beginBrowse=function()
    attempts=attempts+1
    if attempts==1 then return nil,"work_step_finishing" end
    return {isValid=function() return true end}
end}
local button={setEnable=function() end}
local tradeWindow=setmetatable({playerList={},pendingBrowseUntil=1000,player=doctor,survivorId="patient",
    giveButton=button,takeButton=button,clearButton=button,
    refreshStock=function() refreshes=refreshes+1 end,
    stopBrowsing=function(self,reason) self.reason=reason end},{__index=codecTradeWindow})
tradeWindow:update();now=100;tradeWindow:update()
assert(attempts==1 and tradeWindow.pendingBrowseUntil==1000,"pending trade polls at bounded intervals")
now=300;tradeWindow:update()
assert(attempts==2 and tradeWindow.session~=nil and tradeWindow.pendingBrowseUntil==nil and refreshes==1,
    "trade opens automatically after the native step finishes without submitting an offer")
tradeWindow.pendingBrowseUntil=400;now=500;tradeWindow:update()
assert(tradeWindow.pendingBrowseUntil==nil and tradeWindow.reason=="survivor_busy_or_threatened")
now=0

ISHealthPanel={IsCharactersInSameCar=function() return false end}
luautils={walkAdjTest=function() return true end,walkAdj=function() return true end}
ISMedicalCheckAction={HealthWindows={}}
function ISMedicalCheckAction:new()
    return {isValid=function() return true end,start=function() end,stop=function() end,
        perform=function()
            ISMedicalCheckAction.HealthWindows[patient]={visible=true,
                isVisible=function(self) return self.visible end,bringToTop=function(self) self.raised=true end,
                update=function() end,removeFromUIManager=function(self) self.visible=false end}
        end}
end
ISTimedActionQueue={queues={},add=function(action) queued=action end}
assert(codecMedicalContext.medicalCheck(0,"patient") and queued~=nil)
assert(queued:isValid())
queued:start();queued:perform()
local panel=ISMedicalCheckAction.HealthWindows[patient]
local before=ends
now=600;panel:update()
assert(ends==before and owner.state=="PLAYER_CONVERSATION","patient remains paused while medical panel is open")
local startCount=starts
assert(codecMedicalContext.medicalCheck(0,"patient") and panel.raised and starts==startCount,
    "existing health panel reopens without replacing its attention lease")
panel:removeFromUIManager()
assert(ends==before+1 and owner.state=="IDLE","closing health panel resumes original duty without rewriting orders")
assert(codecMedicalContext.medicalCheck(0,"patient"));queued:perform()
local replacement={player=doctor,newOrder=true}
owner.playerConversation=replacement
before=ends
ISMedicalCheckAction.HealthWindows[patient]:removeFromUIManager()
assert(ends==before and owner.playerConversation==replacement,"old panel cannot release attention belonging to a newer order")

local loot={visible=true,inventoryPane={}}
function loot:setNewContainer(value) self.inventoryPane.inventory=value end
function loot:setVisible(value) self.visible=value end
function loot:isVisible() return self.visible end
local ownPage={setVisible=function() end}
getPlayerLoot=function() return loot end
getPlayerInventory=function() return ownPage end
ISInventoryPage={dirtyUI=function() end,GetFloorContainer=function() return {} end}
p.isSurvivorAlive=function() return true end
p.getSurvivorAffiliation=function() return {kind="player",ownerId="doctor"} end
p.ensurePlayerId=function() return "doctor" end
assert(codecInventory.show(0,"patient"))
assert(loot.inventoryPane.inventory==inventory and owner.state=="PLAYER_CONVERSATION")
startCount=starts
assert(codecInventory.show(0,"patient") and starts==startCount,"reopening inventory retains the same pause and native actions")
now=1200;codecInventory.updateAttention()
assert(owner.state=="PLAYER_CONVERSATION","inventory management retains the shared attention lease")
loot.visible=false;now=1800;before=ends;codecInventory.updateAttention()
assert(ends==before+1 and owner.state=="IDLE","closing inventory releases its own pause")
loot.visible=true
p.getSurvivorAffiliation=function() return {kind="player",ownerId="doctor"} end
assert(codecInventory.show(0,"patient"),"inventory reopens for its legitimate owner")
local savedHostileService=KnoxCompanionService
KnoxCompanionService={getPlayerId=function() return "doctor" end,
    isSociallyHostileToPlayer=function() return true end}
now=2400;before=ends
codecInventory.updateAttention()
assert(ends==before+1 and owner.state=="IDLE","a pack closes when the person turns hostile")
KnoxCompanionService=savedHostileService
p.getSurvivorAffiliation=function() return {kind="player",ownerId="someone-else"} end
assert(not codecInventory.show(0,"patient"),"interaction changes cannot grant inventory access to someone else's survivor")

KnoxSurvivorRuntime,getSpecificPlayer,getTimestampMs=savedRuntime,savedPlayer,savedTime
ISMedicalCheckAction,ISHealthPanel,luautils,ISTimedActionQueue=savedMedical,savedHealth,savedUtils,savedQueue
getPlayerLoot,getPlayerInventory,ISInventoryPage=savedLoot,savedInventory,savedPages
KnoxTradeActions,ISCollapsableWindowJoypad=savedTradeActions,savedCollapsable
p.isSurvivorAlive,p.getSurvivorAffiliation,p.ensurePlayerId=oldAlive,oldAffiliation,oldOwner
print("Interaction attention PASS pending_retry=true identity_guard=true medical_hold_release=true inventory_hold_release=true ownership=true")
