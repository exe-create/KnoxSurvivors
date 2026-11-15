local oldSupport, oldSpeech = KnoxGroupSupport, codecSupportSpeech
local spoken, failed, receiptError = 0, 0, false
codecSupportSpeech = function(_, _, event)
    assert(event == "share_supply")
    spoken = spoken + 1
end
local sourceHas, destinationHas = true, false
local plan = { kind = "food", recipient = {}, item = {},
    source = { contains = function() return sourceHas end },
    destination = { contains = function() return destinationHas end } }
KnoxGroupSupport = { plan = function() return plan end,
    queue = function() return {} end,
    verify = function(current)
        if receiptError then error("unreadable transfer") end
        return codecGroupSupportVerify(current)
    end }
local character = { getCharacterActions = function() return { isEmpty = function() return true end } end }
local controller = setmetatable({ id = "support-donor", character = character,
    groupMembers = {{}, {}}, reservations = {}, state = "IDLE" }, { __index = codecSupportController })
function controller:recordFailure() failed = failed + 1 end
function controller:releaseTransferActions() end
function controller:finishDecision() self.state = "IDLE" end
function controller:diag() end
assert(controller:beginGroupSupport(0))
assert(spoken == 0, "queued help must not announce a completed handoff before its receipt")
assert(controller:completeGroupSupport(1) == false and spoken == 0 and failed == 1,
    "a failed transfer has no successful-handoff speech")
assert(controller.pendingGroupSupport == nil and controller.reservations.items[plan.item] == nil,
    "failed help releases its claim and pending plan")
assert(controller:beginGroupSupport(100))
sourceHas, destinationHas = false, true
assert(controller:completeGroupSupport(101) == true and spoken == 1,
    "source removal and destination ownership produce one real handoff line")
sourceHas, destinationHas, receiptError = true, false, true
assert(controller:beginGroupSupport(200))
assert(controller:completeGroupSupport(201) == false and spoken == 1 and failed == 2,
    "unreadable receipt fails without inventing help or a completion line")
KnoxGroupSupport, codecSupportSpeech = oldSupport, oldSpeech
print("Group support receipt PASS noEarlySuccess=true physicalReceipt=true unreadableFails=true")
