-- Bagged splint retrieval through the real maintenance owner.
-- The maintenance planner used to see only a hand-held Base.Splint. A survivor
-- with one in a bag therefore never splinted an unsplinted fracture. The real
-- plan must now select it, and the real Needs.execute must bring it to hand
-- through the same prepare_supply transfer a bagged bandage uses. Companion aid
-- remains direct-only because its native action cannot reach into the doctor's bag.
local N = assert(rawget(_G, "KnoxSurvivorNeeds"), "needs owner missing")
local M = assert(rawget(_G, "KnoxMedicalActions"), "medical action owner missing")
local A = assert(rawget(_G, "KnoxInventoryActions"), "inventory action owner missing")
local oldSnapshot, oldQueueSelfSplint, oldQueueTransfer = N.snapshot, M.queueSelfSplint, A.queueTransfer
local oldQueue, oldBodyPartType = ISTimedActionQueue, BodyPartType
BodyPartType = BodyPartType or { Head = "head", Torso_Upper = "upper",
    Torso_Lower = "lower", ForeArm_L = "arm" }

local function itemList(...)
    local items = { ... }
    return { size = function() return #items end,
        get = function(_, index) return items[index + 1] end }, items
end
local function container(items, parent)
    local c = { items = items, parent = parent }
    function c:getItems()
        return { size = function() return #self.items end,
            get = function(_, index) return self.items[index + 1] end }
    end
    function c:contains(item)
        for _, candidate in ipairs(self.items) do
            if candidate == item then return true end
        end
        return false
    end
    function c:getContainingItem() return self.parent end
    return c
end

local mainItems, bagItems = {}, {}
local main = container(mainItems)
local bagStore = container(bagItems, main)
local bag = {}
function bag:IsInventoryContainer() return true end
function bag:getInventory() return bagStore end
function bag:getContainer() return main end
mainItems[1] = bag

local splint = { container = bagStore }
function splint:getFullType() return "Base.Splint" end
function splint:isBroken() return false end
function splint:isFavorite() return false end
function splint:IsInventoryContainer() return false end
function splint:getContainer() return self.container end
bagItems[1] = splint

local part = {}
function part:HasInjury() return true end
function part:isInfectedWound() return false end
function part:bandaged() return false end
function part:getAlcoholLevel() return 0 end
function part:getBandageLife() return 0 end
function part:stitched() return false end
function part:getFractureTime() return 100 end
function part:getSplintFactor() return 0 end
function part:getType() return BodyPartType.ForeArm_L end
local parts = { size = function() return 1 end,
    get = function(_, index) if index == 0 then return part end end }

local square = { getX = function() return 1 end, getY = function() return 1 end,
    getZ = function() return 0 end }
local pawn = { getCurrentSquare = function() return square end,
    getInventory = function() return main end,
    getBodyDamage = function() return { getBodyParts = function() return parts end } end,
    isEquipped = function() return false end,
    getReduceInfectionPower = function() return 0 end,
    hasFullInventory = function() return false end,
    isDead = function() return false end,
    getCharacterActions = function() return nil end }
local state = { bleedingParts = 0, thirst = 0, hunger = 0, endurance = 1, fatigue = 0 }
N.snapshot = function() return state end

local queue = { queue = {} }
ISTimedActionQueue = { queues = { [pawn] = queue },
    add = function(action) queue.queue = { action }; return queue end }
local transferCalls, splintCalls, rejectToMain = 0, 0, false
A.queueTransfer = function(character, item, source, destination, _, guard)
    transferCalls = transferCalls + 1
    if rejectToMain then return nil, "native_full" end
    local action = { character = character, item = item,
        srcContainer = source, destContainer = destination,
        isValid = function() return true end }
    action.knoxTransferGuard = guard
    queue.queue = { action }
    return action, "queued"
end
M.queueSelfSplint = function(character, item, bodyPart, guard)
    splintCalls = splintCalls + 1
    local action = { character = character, otherPlayer = character, item = nil,
        plank = item, bodyPart = bodyPart, doIt = true,
        isValid = function() return true end }
    if guard ~= nil then action.knoxSelfGuard = guard end
    queue.queue = { action }
    return action, "queued"
end

-- 1. The real maintenance owner now selects a splint from the bag, and the
-- real Needs.execute starts the shared bag-to-main transfer first.
assert(M.splintUsable(pawn, splint) == false,
    "medical_splint_bag: a bagged splint is not yet hand-held")
local plan = M.maintenancePlan(pawn, pawn)
assert(plan ~= nil and plan.kind == "splint" and plan.item == splint,
    "medical_splint_bag: maintenance selects a bagged splint")
local decision = N.decide(pawn, nil)
assert(decision ~= nil and decision.kind == "splint" and decision.item == splint,
    "medical_splint_bag: decide selects the bagged splint")
assert(decision.bodyPart == part,
    "medical_splint_bag: the plan keeps the fractured body part")
local action, result, intent = N.execute(pawn, decision, nil)
assert(action ~= nil and intent ~= nil and intent.kind == "prepare_supply",
    "medical_splint_bag: bagged splint starts a real transfer")
assert(intent.needKind == "splint" and intent.bodyPart == part,
    "medical_splint_bag: the transfer keeps the splint need and body part")
assert(intent.source == bagStore and intent.destination == main,
    "medical_splint_bag: the transfer moves the bagged splint to hand")
assert(transferCalls == 1 and splintCalls == 0,
    "medical_splint_bag: native splinting waits for the item to come to hand")

-- 2. A genuinely full pack still reports the rejected transfer; the existing
-- controller cleanup owns the capacity path and is not reimplemented here.
queue.queue = {}
rejectToMain, splintCalls = true, 0
local rejected, why = N.execute(pawn, decision, nil)
assert(rejected == nil and why == "supply_transfer_rejected",
    "medical_splint_bag: full pack reports the failed retrieval")
assert(splintCalls == 0,
    "medical_splint_bag: a full pack never queues splinting on a bagged item")

-- 3. Unchanged path: a splint already in the main inventory still goes straight
-- to the native owner without a transfer.
bagItems[1] = nil
mainItems[2] = splint
splint.container = main
queue.queue = {}
rejectToMain, transferCalls, splintCalls = false, 0, 0
local direct = N.decide(pawn, nil)
assert(direct ~= nil and direct.kind == "splint" and direct.item == splint,
    "medical_splint_bag: hand-held splint is still selected")
local directAction, directResult, directIntent = N.execute(pawn, direct, nil)
assert(directAction ~= nil and directIntent ~= nil and directIntent.kind == "splint",
    "medical_splint_bag: hand-held splint queues the native action")
assert(transferCalls == 0 and splintCalls == 1,
    "medical_splint_bag: hand-held splint takes no retrieval transfer")

-- 4. Companion aid is deliberately unchanged: a bagged supply is not a valid
-- aid item because the native action requires it in the doctor's own inventory.
bagItems[1] = splint
mainItems[2] = nil
splint.container = bagStore
local patient = { getBodyDamage = function()
    return { getBodyParts = function() return parts end }
end }
assert(M.maintenancePlan(pawn, patient) == nil,
    "medical_splint_bag: companion aid still requires a hand-held splint")

N.snapshot = oldSnapshot
M.queueSelfSplint = oldQueueSelfSplint
A.queueTransfer = oldQueueTransfer
ISTimedActionQueue, BodyPartType = oldQueue, oldBodyPartType
print("Medical splint bag PASS real_maintenance=true real_execute=true direct=true aid_direct_only=true native_transfer_stub=true")
