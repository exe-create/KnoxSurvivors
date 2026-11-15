-- The installed attackHook returns no outcome; even a successful call may do nothing.
local firearms = assert(KnoxFirearmSupport)
local gun = {
    IsWeapon=function() return true end,
    isRanged=function() return true end,
    isBroken=function() return false end,
    isSelectFire=function() return false end,
    getFullType=function() return "Base.TestGun" end,
}
local character = {
    getPrimaryHandItem=function() return gun end,
    isAttackStarted=function() return false end,
    isAuthorizeMeleeAction=function() return true end,
}
local calls = 0
ISReloadWeaponAction = {
    canShoot=function() return true end,
    attackHook=function() calls = calls + 1; return end,
}
ISTimedActionQueue = { queues = {} }
assert(firearms.nativeHookAttemptCount(character) == 0)
local dispatched = firearms.fireNative(character)
assert(dispatched and calls == 1, "the real wrapper must call the no-attack hook")
assert(firearms.nativeHookAttemptCount(character) == 1, "a hook call is an attempt, not a confirmed shot")
assert(firearms.nativeShotCount(character) == 1, "legacy diagnostic callers retain the attempt count")
ISReloadWeaponAction.attackHook=function() error("fixture hook failure") end
assert(not firearms.fireNative(character), "hook errors remain failures")
assert(firearms.nativeHookAttemptCount(character) == 2, "failed hook calls are still attempts")
print("Firearm hook attempts PASS no_attack=attempt error=attempt")
