-- The owner's option: ordering a survivor and following the player must not
-- require standing close. It is off by default, so today's behaviour stays, and
-- turning it on restores the old close-contact admission. This drives the real
-- admission (CompanionService.orderAdmitted) with the settings owner stubbed at
-- its boundary.
local S = assert(rawget(_G, "codecOrderContact"), "the order admission owner is loaded")

local previousSettings = rawget(_G, "KnoxSettings")
local previousRuntime = rawget(_G, "KnoxSurvivorRuntime")

local required = false
KnoxSettings = { requireCloseContact = function() return required end }

local function body(x, y, z)
    return {
        getCurrentSquare = function() return { getZ = function() return z or 0 end } end,
        getX = function() return x end,
        getY = function() return y end,
    }
end

local farBody = body(0, 10)
local nearBody = body(2, 2)
KnoxSurvivorRuntime = {
    getCharacter = function(id)
        if id == "near" then return nearBody end
        if id == "far" then return farBody end
        return nil
    end,
}
local player = body(0, 0)

-- Off by default: an order reaches a survivor across the room.
local offOk, offReason = S.orderAdmitted(player, "far")
assert(offOk == true, "with the option off an order needs no proximity")
assert(offReason == nil, "a permitted order carries no refusal")

-- On: the old admission returns, by the same square distance.
required = true
assert(S.orderAdmitted(player, "far") == false, "with the option on a far survivor refuses")
local _, reason = S.orderAdmitted(player, "far")
assert(reason == "too_far_to_order", "the refusal names the distance")
assert(S.orderAdmitted(player, "near") == true, "a survivor beside the player accepts")

-- An unknown or unloaded body is not near.
assert(S.orderAdmitted(player, "missing") == false, "no body is not contact")
assert(S.orderAdmitted(nil, "near") == false, "no player is not contact")

-- Turning the option back off restores the no-proximity admission at once,
-- because the option is read live rather than copied into the order.
required = false
assert(S.orderAdmitted(player, "far") == true, "the option is read live, not cached")

KnoxSettings = previousSettings
KnoxSurvivorRuntime = previousRuntime

print("Follow contact PASS off=true far=true on=false near=true live=true")
