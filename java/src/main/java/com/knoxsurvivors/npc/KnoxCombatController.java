package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.agent.KnoxCombatGate;
import com.knoxsurvivors.agent.KnoxHumanCombatGate;
import java.util.Map;
import java.util.List;

/** Drives one controlled melee encounter through IsoPlayer's normal attack entry point. */
final class KnoxCombatController {
    private static final int ATTACK_RETRY_TICKS = 30;
    private static final int DEFAULT_AIM_SETTLE_TICKS = 18;
    private static final int MIN_AIM_SETTLE_TICKS = 8;
    private static final int MAX_AIM_SETTLE_TICKS = 30;
    private static final int DIRECT_STATE_FALLBACK_TICKS = 3;
    private static final int ATTACK_RECOVERY_TICKS = 24;
    private static final int MELEE_RECOVERY_TICKS = 12;
    private static final float ATTACK_ENTRY_BUFFER = 0.05f;
    private static final float REAPPROACH_BUFFER = 0.25f;
    private static final int RANGED_REPOSITION_COOLDOWN_TICKS = 60;
    private static final int APPROACH_REFRESH_TICKS = 30;
    private static final int DAMAGE_LOG_INTERVAL_TICKS = 60;
    // Build 42 resolves a shot through the character's aim-control owner; an
    // off-slot shell has no input component, so a firearm can request attacks
    // and never reduce the target. Bound that silence instead of firing forever.
    private static final int RANGED_NO_DAMAGE_ATTACKS = 3;
    private static final int RANGED_NO_DAMAGE_TICKS = 180;

    private KnoxNpc npc;
    private Object target;
    private String phase = "IDLE";
    private int ticks;
    private int lastAttackTick = -ATTACK_RETRY_TICKS;
    private int attackRequests;
    private int reactingTicks;
    private float initialTargetHealth;
    private float lastTargetHealth;
    private int lastDamageLogTick = -DAMAGE_LOG_INTERVAL_TICKS;
    private int pendingDamageSamples;
    private float pendingDamageStartHealth;
    private int initialWeaponCondition;
    private float weaponMaxRange;
    private float desiredAttackRange;
    private boolean rangedWeapon;
    private boolean unarmedCombat;
    private Object combatWeapon;
    private boolean damageObserved;
    private boolean attackAnimationObserved;
    private int aimTicks;
    private int aimSettleTicks = DEFAULT_AIM_SETTLE_TICKS;
    private boolean directStateFallbackUsed;
    private boolean obstacleTarget;
    private boolean attackCycleActive;
    private boolean liveCombat;
    private int defenseWindowUntil;
    private Object approachSquare;
    private int lastRangedRepositionTick = -RANGED_REPOSITION_COOLDOWN_TICKS;
    private int lastApproachTick;
    private int lastDefensiveStepTick = -60;
    private int defensiveStepEndTick;
    private float defensiveStepAwayX, defensiveStepAwayY, defensiveStepX, defensiveStepY;
    private float approachTargetX;
    private float approachTargetY;
    private int stationaryApproachRetries;
    // Measurements for the two combat complaints that cannot be seen offline:
    // a swing that reads as slow, and a first swing that starts at the edge of
    // reach. These are observations only; no timing or range rule reads them.
    private int firstSwingTick = -1;
    private float distanceAtFirstSwing = -1.0f;
    private float distanceAtLastSwing = -1.0f;
    private int swingCount;
    private int approachSteps;
    private int approachRefreshes;

    String begin(KnoxNpc activeNpc, Object zombie, Object approachSquare)
        throws ReflectiveOperationException {
        return begin(activeNpc, zombie, approachSquare, true, DEFAULT_AIM_SETTLE_TICKS);
    }

    String beginLive(KnoxNpc activeNpc, Object target, Object approachSquare)
        throws ReflectiveOperationException {
        return begin(activeNpc, target, approachSquare, false, DEFAULT_AIM_SETTLE_TICKS);
    }

    String beginLive(
        KnoxNpc activeNpc,
        Object target,
        Object approachSquare,
        int requestedAimSettleTicks
    ) throws ReflectiveOperationException {
        return begin(activeNpc, target, approachSquare, false, requestedAimSettleTicks);
    }

    String beginLockedDoor(KnoxNpc activeNpc, Object door)
        throws ReflectiveOperationException {
        if (activeNpc == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        if (door == null || !inherits(door, "zombie.iso.objects.IsoDoor")) {
            return "COMBAT_FAILED NO_LOCKED_DOOR_TARGET";
        }
        if (hasNativeRecoveryOwner(activeNpc)) return "COMBAT_DEFERRED NATIVE_RECOVERY";

        reset();
        npc = activeNpc;
        target = door;
        obstacleTarget = true;
        liveCombat = false;
        Object body = npc.getBody();
        Class.forName(
            "zombie.ai.states.SwipeStatePlayer",
            true,
            body.getClass().getClassLoader()
        );
        if (!KnoxCombatGate.isPatchReady() && !com.knoxsurvivors.agent.KnoxAgent.usesZombieBuddyPatches()) {
            reset();
            return "COMBAT_FAILED CALLBACK_PATCH_NOT_READY calls="
                + KnoxCombatGate.getPatchedCallCount();
        }
        Object weapon = body.getClass().getMethod("getPrimaryHandItem").invoke(body);
        if (weapon == null || !inherits(weapon, "zombie.inventory.types.HandWeapon")) {
            reset();
            return "COMBAT_FAILED NO_EQUIPPED_WEAPON";
        }
        initialWeaponCondition = ((Number) weapon.getClass().getMethod("getCondition")
            .invoke(weapon)).intValue();
        combatWeapon = weapon;
        rangedWeapon = (Boolean) weapon.getClass().getMethod("isRanged").invoke(weapon);
        initialTargetHealth = health(target);
        lastTargetHealth = initialTargetHealth;

        // An interrupted prior action must not leak attack input into door combat.
        clearAttackIntent();
        npc.setCombatActive(true);
        phase = "AIMING";
        clearMovementIntent();
        String result = "COMBAT_STARTED mode=locked-door targetHealth="
            + initialTargetHealth
            + " weaponCondition="
            + initialWeaponCondition + " npcId=" + npc.getId();
        KnoxAgent.writeLog("NPC combat " + result);
        return result;
    }

    private String begin(
        KnoxNpc activeNpc,
        Object combatTarget,
        Object approachSquare,
        boolean controlledGate,
        int requestedAimSettleTicks
    ) throws ReflectiveOperationException {
        if (activeNpc == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        boolean zombieTarget = combatTarget != null
            && inherits(combatTarget, "zombie.characters.IsoZombie");
        boolean humanTarget = combatTarget != null
            && inherits(combatTarget, "zombie.characters.IsoPlayer");
        if (combatTarget == null || (!zombieTarget && (!liveTargetMode(controlledGate)
            || !humanTarget))) {
            return "COMBAT_FAILED INVALID_TARGET";
        }
        if (hasNativeRecoveryOwner(activeNpc)) return "COMBAT_DEFERRED NATIVE_RECOVERY";

        reset();
        npc = activeNpc;
        target = combatTarget;
        this.approachSquare = approachSquare;
        aimSettleTicks = clampAimSettleTicks(requestedAimSettleTicks);
        liveCombat = !controlledGate;
        Object body = npc.getBody();
        Class.forName(
            "zombie.ai.states.SwipeStatePlayer",
            true,
            body.getClass().getClassLoader()
        );
        if (!KnoxCombatGate.isPatchReady() && !com.knoxsurvivors.agent.KnoxAgent.usesZombieBuddyPatches()) {
            reset();
            return "COMBAT_FAILED CALLBACK_PATCH_NOT_READY calls="
                + KnoxCombatGate.getPatchedCallCount();
        }
        if (!controlledGate && zombieTarget && !KnoxCombatGate.isVisibilityPatchReady()
            && !com.knoxsurvivors.agent.KnoxAgent.usesZombieBuddyPatches()) {
            reset();
            return "COMBAT_FAILED ZOMBIE_VISIBILITY_PATCH_NOT_READY calls="
                + KnoxCombatGate.getVisibilityPatchedCallCount();
        }
        Object weapon = body.getClass().getMethod("getPrimaryHandItem").invoke(body);
        if (weapon == null) {
            // Build 42's native player attack gate supports shove/stomp without a
            // HandWeapon. Keep the survivor in the live combat loop so an unarmed
            // NPC does not stand still until a zombie reaches them.
            initialWeaponCondition = -1;
            combatWeapon = null;
            rangedWeapon = false;
            unarmedCombat = true;
            weaponMaxRange = 1.0f;
            desiredAttackRange = 1.0f;
        } else if (inherits(weapon, "zombie.inventory.types.HandWeapon")) {
            initialWeaponCondition = ((Number) weapon.getClass().getMethod("getCondition")
                .invoke(weapon)).intValue();
            combatWeapon = weapon;
            rangedWeapon = (Boolean) weapon.getClass().getMethod("isRanged").invoke(weapon);
            unarmedCombat = false;
        } else {
            reset();
            return "COMBAT_FAILED INVALID_PRIMARY_ITEM";
        }

        // Combat always interrupts rest. Clear posture flags that can remain set for a
        // frame after a timed sit/rest action and make both zombie eligibility and melee
        // movement treat the visibly standing shell as prone.
        boolean knockedDown = (Boolean) body.getClass().getMethod("isKnockedDown").invoke(body);
        if (knockedDown) {
            reset();
            return "COMBAT_FAILED ACTOR_KNOCKED_DOWN";
        }
        body.getClass().getMethod("setSitOnGround", boolean.class).invoke(body, false);
        body.getClass().getMethod("setSittingOnFurniture", boolean.class).invoke(body, false);
        body.getClass().getMethod("setOnFloor", boolean.class).invoke(body, false);
        // Player parity for knockdowns: vanilla only pulses forceGetUp on a
        // discrete input (sit key, timed-action start). Latching it true here
        // re-armed on every engagement, so every later knockdown stood up
        // instantly. Actively clear any stale latch instead; knocked-down
        // bodies are refused above and recover on the native timer.
        body.getClass().getMethod("setVariable", String.class, boolean.class)
            .invoke(body, "forceGetUp", false);
        if (weapon == null) {
            weaponMaxRange = 1.0f;
            desiredAttackRange = 1.0f;
        } else {
            weaponMaxRange = ((Number) weapon.getClass().getMethod(
                "getMaxRange",
                classFor(body, "zombie.characters.IsoGameCharacter")
            ).invoke(weapon, body)).floatValue();
        }
        if (weapon == null) {
            // Native shove/stomp owns its own short attack range.
        } else if (rangedWeapon) {
            // Firearms should keep a player-like stand-off distance.  The native
            // max range already includes the survivor's aiming modifiers; use a
            // conservative middle distance so a moving zombie does not force a
            // melee collision, while still leaving room for the normal shot path.
            float minimum = 0.0f;
            try {
                minimum = ((Number) weapon.getClass().getMethod("getMinRangeRanged")
                    .invoke(weapon)).floatValue();
            } catch (ReflectiveOperationException ignored) {
                // Older compatible weapon classes may not expose this accessor.
            }
            desiredAttackRange = desiredRange(true, weaponMaxRange, minimum);
        } else {
            // Build 42's IsoGameCharacter.isMeleeAttackRange() multiplies the
            // character-adjusted maximum by the weapon's range modifier. Mirror
            // that native gate when choosing the approach point; raw script range
            // can otherwise disagree with the collision calculation.
            float rangeModifier = ((Number) weapon.getClass().getMethod(
                "getRangeMod",
                classFor(body, "zombie.characters.IsoGameCharacter")
            ).invoke(weapon, body)).floatValue();
            weaponMaxRange *= rangeModifier;
            desiredAttackRange = desiredRange(false, weaponMaxRange, 0.0f);
        }
        initialTargetHealth = health(target);
        lastTargetHealth = initialTargetHealth;

        // Build 42's standing-zombie collision callback rejects a frontal bite while
        // the target still advertises an AttackType. A previous interrupted swing can
        // leave that animation variable behind even after the boolean attack flags are
        // clear, so every new combat owner begins from one clean native input state.
        clearAttackIntent();

        if (controlledGate) {
            // The development gate isolates outgoing combat. Live autonomy leaves both
            // characters vulnerable and allows the zombie to keep moving and attacking.
            body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, true);
            target.getClass().getMethod("setCanWalk", boolean.class).invoke(target, false);
            target.getClass().getMethod("setUseless", boolean.class).invoke(target, true);
            target.getClass().getMethod("setTarget", classFor(target, "zombie.iso.IsoMovingObject"))
                .invoke(target, (Object) null);
        } else if (zombieTarget) {
            body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
            target.getClass().getMethod("setCanWalk", boolean.class).invoke(target, true);
            target.getClass().getMethod("setUseless", boolean.class).invoke(target, false);
        }
        // Human targeting must not change either participant's player safety settings.
        // Native checkPVP uses coopPVP in single-player; factionPvp is not an NPC bypass.

        npc.setCombatActive(true);
        body.getClass().getMethod("setSneaking", boolean.class).invoke(body, false);
        beginLiveApproach();
        if (humanTarget) KnoxHumanCombatGate.refresh(this, body, target);
        phase = "APPROACHING";
        String result = "COMBAT_STARTED mode=" + (controlledGate ? "gate" : "live")
            + " targetHealth=" + initialTargetHealth
            + " weaponCondition=" + initialWeaponCondition
            + " maxRange=" + weaponMaxRange
            + " desiredRange=" + desiredAttackRange + " npcId=" + npc.getId();
        KnoxAgent.writeLog("NPC combat " + result);
        return result;
    }

    String tick() throws ReflectiveOperationException {
        if (npc == null || target == null) {
            return "COMBAT_IDLE";
        }

        ticks++;
        Object body = npc.getBody();
        boolean actorUnavailable = combatantUnavailable(body);
        // A live native crossing/opening owns input, facing and its route even
        // when the combat target is already close enough to attack. Observe
        // required native receipts without turning this into a movement tick.
        if (!actorUnavailable && KnoxNpcFactory.hasNativeTraversalOwner(npc)) {
            // Traversal pauses the encounter: it must not inherit a stale stall.
            reactingTicks = 0;
            if ("DEFENSIVE_STEP".equals(phase)) {
                KnoxNpcFactory.stopCombatStep(npc);
                phase = "ATTACKING";
            }
            KnoxNpcFactory.observeNativeAction(npc);
            return "COMBAT_NATIVE_ACTION phase=" + phase;
        }
        if (liveCombat && inherits(target, "zombie.characters.IsoPlayer"))
            KnoxHumanCombatGate.refresh(this, npc.getBody(), target);
        float currentHealth = health(target);
        observeTargetHealth(currentHealth);

        boolean finishedTarget = targetFinished(target);
        boolean unavailableTarget = !finishedTarget && targetUnavailable(target);
        if (!actorUnavailable && (finishedTarget || unavailableTarget) && nativeAttackOwnsBody(body)) {
            // The last native hit can finish a target before the animation's
            // remaining frames release the actor. Retire the target afterward,
            // without pressing another attack or cancelling this native action.
            return "COMBAT_NATIVE_ATTACK phase=" + phase;
        }
        if (finishedTarget) {
            if (attackRequests == 0 || !damageObserved) {
                phase = "FAILED";
                return finish("COMBAT_FAILED TARGET_DIED_WITHOUT_NPC_DAMAGE attacks="
                    + attackRequests + " damageObserved=" + damageObserved);
            }
            phase = "SUCCEEDED";
            Object weapon = npc.getBody().getClass().getMethod("getPrimaryHandItem")
                .invoke(npc.getBody());
            int condition = weapon == null
                ? -1
                : ((Number) weapon.getClass().getMethod("getCondition").invoke(weapon)).intValue();
            return finish("COMBAT_SUCCEEDED target="
                + (obstacleTarget ? "locked-door"
                    : inherits(target, "zombie.characters.IsoPlayer") ? "human" : "zombie")
                + " attacks=" + attackRequests
                + " damageObserved=" + damageObserved
                + " targetHealth=" + currentHealth
                + " weaponCondition=" + initialWeaponCondition + "->" + condition);
        }

        if (actorUnavailable || unavailableTarget) {
            phase = "FAILED";
            return finish("COMBAT_FAILED INVALID_OR_UNLOADED_COMBATANT");
        }

        Object equippedWeapon = body.getClass().getMethod("getPrimaryHandItem").invoke(body);
        if (equippedWeapon != combatWeapon) {
            phase = "FAILED";
            return finish("COMBAT_FAILED WEAPON_CHANGED");
        }
        float targetX = ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue();
        float targetY = ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue();
        float bodyX = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
        float bodyY = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
        float dx = targetX - bodyX;
        float dy = targetY - bodyY;
        float targetDistance = (float) Math.sqrt(dx * dx + dy * dy);
        float attackEntryThreshold = attackEntryThreshold(desiredAttackRange);
        float reapproachThreshold = combatReapproachRange(rangedWeapon, desiredAttackRange, weaponMaxRange);

        String bodyAction = String.valueOf(
            body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
        );
        String bodyState = String.valueOf(body.getClass().getMethod("getCurrentStateName").invoke(body));
        if ((liveCombat || obstacleTarget) && nativeInjuryOwnsBody(body, bodyState, bodyAction)) {
            // A vanilla zombie hit reaction owns the shell until its action graph exits.
            // Reapplying aim/attack input here suppresses the visible reaction and can
            // leave AttackType set, which also makes a frontal zombie collision return
            // before AddRandomDamageFromZombie is called.
            if ("DEFENSIVE_STEP".equals(phase)) {
                KnoxNpcFactory.stopCombatStep(npc);
                phase = "ATTACKING";
            }
            clearNativeRecoveryInput(body);
            reactingTicks++;
            // The three other waits in this encounter are all bounded (idle-latch
            // recovery, ATTACK_STALLED, ranged silence). An injury-owned body is
            // the only unbounded one: the idle latch needs idle, the stall gate
            // needs attackStarted, and the request block sits below this return.
            // Chain-stunned bodies waited here until death (7 bitten seconds with
            // zero swings, encounter never ended). Fail so Lua re-decides.
            if (injuryStallExpired(reactingTicks)) {
                phase = "FAILED";
                return finish("COMBAT_FAILED INJURY_STALL action=" + bodyAction
                    + " attacks=" + attackRequests + " targetHealth=" + currentHealth);
            }
            return "COMBAT_REACTING action=" + bodyAction
                + " targetHealth=" + currentHealth;
        }
        // Any tick past the injury check proves the body is answering again:
        // only consecutive injury-owned ticks count toward the stall.
        reactingTicks = 0;

        // One native ownership snapshot governs movement and attack admission.
        // A requested attack can precede both the attacking flag and animation.
        boolean attackStarted = (Boolean) body.getClass().getMethod("isAttackStarted").invoke(body);
        boolean attacking = (Boolean) body.getClass().getMethod("isAttacking").invoke(body);
        boolean attackAnimation = (Boolean) body.getClass()
            .getMethod("isPerformingAttackAnimation").invoke(body);
        boolean attackActive = attackStarted || attacking || attackAnimation;
        if (recoverIdleAttackLatch(body)) {
            return "COMBAT_RECOVERING_STALE_ATTACK targetHealth=" + currentHealth;
        }
        if ("DEFENSIVE_STEP".equals(phase)) {
            boolean safe = !attackActive && ticks < defensiveStepEndTick && ticks < defenseWindowUntil
                && defensiveStepStillFacesThreat(defensiveStepAwayX, defensiveStepAwayY,
                    dx, dy, targetDistance)
                && defensiveStepDestination(body, target, targetDistance, defensiveStepX, defensiveStepY) != null;
            if (safe) {
                faceTarget(body, targetX, targetY);
                applyReadyPosture(body);
                String movement = KnoxNpcFactory.tickMovement(npc, 0.0f, "walk");
                if ("ManualRoute".equals(movement)) return "COMBAT_DEFENSIVE_STEP";
            }
            KnoxNpcFactory.stopCombatStep(npc);
            phase = "ATTACKING";
        }
        if (liveCombat && !rangedWeapon && !obstacleTarget && !attackActive
            && ticks < defenseWindowUntil && ticks - lastDefensiveStepTick >= 60) {
            float[] destination = defensiveStepDestination(body, target, targetDistance);
            if (destination != null && KnoxNpcFactory.beginCombatStep(npc,
                destination[0], destination[1], destination[2])) {
                lastDefensiveStepTick = ticks;
                defensiveStepEndTick = ticks + 36;
                defensiveStepX = destination[0]; defensiveStepY = destination[1];
                defensiveStepAwayX = -dx / targetDistance;
                defensiveStepAwayY = -dy / targetDistance;
                phase = "DEFENSIVE_STEP";
                faceTarget(body, targetX, targetY);
                applyReadyPosture(body);
                String movement = KnoxNpcFactory.tickMovement(npc, 0.0f, "walk");
                if ("ManualRoute".equals(movement)) return "COMBAT_DEFENSIVE_STEP";
                KnoxNpcFactory.stopCombatStep(npc);
                phase = "ATTACKING";
            }
        }
        float minimumRangedDistance = minimumRangedDistance(desiredAttackRange);
        if (!"RANGED_REPOSITIONING".equals(phase) && shouldRepositionRanged(
            rangedWeapon,
            targetDistance,
            minimumRangedDistance,
            ticks,
            lastRangedRepositionTick,
            attackActive
        )) {
            clearAttackIntent();
            KnoxNpcFactory.moveToRangeFromCurrentSide(
                npc,
                target,
                approachSquare,
                rangedSpacingRange(minimumRangedDistance)
            );
            body.getClass().getMethod("setRunning", boolean.class).invoke(body, true);
            phase = "RANGED_REPOSITIONING";
            aimTicks = 0;
            attackCycleActive = false;
            lastRangedRepositionTick = ticks;
            KnoxAgent.writeLog(
                "NPC combat RANGED_REPOSITION distance=" + targetDistance
                    + " minimum=" + minimumRangedDistance
                    + " desiredRange=" + desiredAttackRange
            );
            return "COMBAT_RANGED_REPOSITIONING distance=" + targetDistance
                + " targetHealth=" + currentHealth;
        }

        // One-tick bridge: an arrival inside native reach skips both the
        // re-route above and the immediate reapproach below that would undo it.
        boolean justArrivedInReach = false;
        if ("RANGED_REPOSITIONING".equals(phase)) {
            // The Build 42 Lua firearm hook observes the shell's aiming/attack
            // variables independently of this controller phase. Clear them on
            // every reposition tick, not just when entering the phase, so a
            // queued attack cannot emit a shot while the survivor is running.
            clearAttackIntent();
            String movement = KnoxNpcFactory.tickMovement(npc, targetDistance, "run");
            if (movement.startsWith("Failed")) {
                phase = "FAILED";
                return finish("COMBAT_FIREARM_FALLBACK CLOSE_REPOSITION " + movement);
            }
            float resumeDistance = rangedSpacingRange(minimumRangedDistance) - 0.15f;
            if (!"Succeeded".equals(movement) && targetDistance < resumeDistance) {
                return "COMBAT_RANGED_REPOSITIONING movement=" + movement
                    + " distance=" + targetDistance
                    + " resumeDistance=" + resumeDistance
                    + " targetHealth=" + currentHealth;
            }
            clearMovementIntent();
            body.getClass().getMethod("setRunning", boolean.class).invoke(body, false);
            phase = "AIMING";
            aimTicks = 0;
        } else if ("APPROACHING".equals(phase) && !obstacleTarget) {
            // Tick movement before judging the band: a route that just arrived
            // inside native reach admits the swing below instead of re-routing
            // around a target that barely drifted (log: give-ups at 1.03/1.14
            // vs entries 0.75/0.90 with 0.9/1.25 reach, after ~100 approach
            // steps and two swings). Ranged keeps its own spacing.
            String movement = null;
            if (targetDistance > attackEntryThreshold) {
                // Nearby combat keeps the weapon facing the opponent while the
                // existing native control-space conversion supplies strafing.
                // Route heading must not overwrite aim heading every frame.
                if (targetDistance <= 4.0f) {
                    faceTarget(body, targetX, targetY);
                    applyReadyPosture(body);
                }
                // Keep one range-based destination under the captured-route adapter.
                // Replacing it with pathToCharacter() every few ticks sends the shell
                // into the target's occupied space, then repeatedly invalidates its
                // own route as the target and animation graph move.
                approachSteps++;
                movement = KnoxNpcFactory.tickMovement(npc, targetDistance,
                    approachPace(rangedWeapon, targetDistance, attackEntryThreshold));
                if (movement.startsWith("Failed")) {
                    phase = "FAILED";
                    return finish("COMBAT_FAILED APPROACH " + movement);
                }
            }
            justArrivedInReach = movement != null && arrivedInMeleeReach(
                rangedWeapon, movement, targetDistance, weaponMaxRange);
            if (movement == null || justArrivedInReach) {
                phase = "AIMING";
                aimTicks = 0;
                if (!attackActive) clearMovementIntent();
                stationaryApproachRetries = 0;
            } else {
                boolean targetMoved = targetMovedSinceApproach(
                    targetX, targetY, approachTargetX, approachTargetY
                );
                if (shouldRefreshApproach(movement, targetMoved, ticks - lastApproachTick)) {
                    approachRefreshes++;
                    stationaryApproachRetries = targetMoved ? 0 : stationaryApproachRetries + 1;
                    if (stationaryApproachRetries > 2) {
                        return finish("COMBAT_FAILED APPROACH_OUT_OF_RANGE distance="
                            + targetDistance + " entryRange=" + attackEntryThreshold);
                    }
                    clearMovementIntent();
                    KnoxNpcFactory.moveToRangeFromCurrentSide(
                        npc, target, approachSquare, desiredAttackRange
                    );
                    rememberApproachTarget(targetX, targetY);
                    return "COMBAT_APPROACH_REFRESH targetMoved=" + targetMoved
                        + " distance=" + targetDistance;
                }
                return "COMBAT_APPROACHING movement=" + movement
                    + " liveDistance=" + targetDistance
                    + " desiredRange=" + desiredAttackRange
                    + " targetHealth=" + currentHealth;
            }
        } else if ("APPROACHING".equals(phase)) {
            approachSteps++;
            String movement = KnoxNpcFactory.tickMovement(npc);
            if (movement.startsWith("Failed")) {
                phase = "FAILED";
                return finish("COMBAT_FAILED APPROACH " + movement);
            }
            if (!"Succeeded".equals(movement)) {
                return "COMBAT_APPROACHING movement=" + movement + " targetHealth=" + currentHealth;
            }
            phase = "AIMING";
            clearMovementIntent();
        }

        if ("FAILED".equals(phase) || "SUCCEEDED".equals(phase)) {
            return "COMBAT_" + phase;
        }

        if (!obstacleTarget && targetDistance > reapproachThreshold && !justArrivedInReach) {
            if (!attackActive) {
                clearAttackIntent();
                beginLiveApproach();
                phase = "APPROACHING";
                aimTicks = 0;
                KnoxAgent.writeLog(
                    "NPC combat REAPPROACH distance=" + targetDistance
                        + " desiredRange=" + desiredAttackRange + " npcId=" + npc.getId()
                );
                return "COMBAT_REAPPROACHING distance=" + targetDistance
                    + " targetHealth=" + currentHealth;
            }
        }
        Object targetSquare = obstacleTarget
            ? target.getClass().getMethod("getSquare").invoke(target)
            : target.getClass().getMethod("getCurrentSquare").invoke(target);
        body.getClass().getMethod(
            "setAttackTargetSquare",
            classFor(body, "zombie.iso.IsoGridSquare")
        ).invoke(body, targetSquare);

        if (attackCycleActive && !attackActive) {
            // Yield the complete interval between swings to vanilla defense/hit
            // reactions. AttackState rejects a frontal collision while the target's
            // AttackType is non-empty, so clear the completed swing explicitly.
            lastAttackTick = ticks;
            attackCycleActive = false;
            if (liveCombat) {
                clearAttackIntent();
                body.getClass().getMethod("clearVariable", String.class)
                    .invoke(body, "AttackType");
                defenseWindowUntil = ticks + recoveryTicks(rangedWeapon);
                return "COMBAT_RECOVERING ticks=" + recoveryTicks(rangedWeapon)
                    + " targetHealth=" + currentHealth;
            }
        } else {
            attackCycleActive = attackActive;
        }

        if (liveCombat && ticks < defenseWindowUntil) {
            // Aiming is not attacking: keep the native ready posture, but leave
            // AttackType and attack triggers cleared for normal bite/reaction gates.
            applyReadyPosture(body);
            return "COMBAT_RECOVERING ticks=" + (defenseWindowUntil - ticks)
                + " targetHealth=" + currentHealth;
        }

        boolean targetOnFloor = !obstacleTarget
            && (Boolean) target.getClass().getMethod("isOnFloor").invoke(target);
        // SwipeStatePlayer owns orientation during an active swing. Forcing a new
        // heading during that graph produces visible 360-degree turns and can move
        // the collision arc away from the attack target.
        if (!attackActive) {
            faceTarget(body, targetX, targetY);
        }

        boolean aimAtFloor = targetOnFloor;
        // The Lua hook has admitted this ranged attack through pressedAttack.
        // Preserve that pending input in the AI component until its graph starts;
        // clearing it on the next tick can leave audio without an actual shot.
        applyCombatStance(body, rangedWeapon && attackStarted && !attackAnimation,
            aimAtFloor, rangedWeapon);

        if ("AIMING".equals(phase)) {
            aimTicks++;
            boolean armedMeleeContact = liveCombat && !rangedWeapon && !obstacleTarget
                && combatWeapon != null && !attackActive && Float.isFinite(targetDistance)
                && Float.isFinite(desiredAttackRange) && desiredAttackRange > 0.0f
                && targetDistance > .001f && targetDistance <= desiredAttackRange;
            if (aimTicks < aimSettleTicks && !armedMeleeContact) {
                return "COMBAT_AIMING ticks=" + aimTicks + "/" + aimSettleTicks
                    + " targetHealth=" + currentHealth;
            }
            phase = "ATTACKING";
        }

        boolean weaponReady = combatWeapon == null
            || (Boolean) body.getClass().getMethod("isWeaponReady").invoke(body);
        boolean initiateAttack = (Boolean) body.getClass().getMethod("isInitiateAttack").invoke(body);
        attackAnimationObserved = attackAnimationObserved || attackAnimation;
        if (attackAnimation && !rangedWeapon) {
            body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, false);
            setAiAttackIntent(body, true, false);
        }
        if (!rangedWeapon && attackRequests > 0 && !attackAnimationObserved && !damageObserved) {
            setAiAttackIntent(body, true, true);
            body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
        }
        if (allowsDirectSwipeFallback(rangedWeapon)
            && attackRequests > 0
            && !directStateFallbackUsed
            && !attackAnimationObserved
            && ticks - lastAttackTick >= DIRECT_STATE_FALLBACK_TICKS
            && "idle".equalsIgnoreCase(String.valueOf(
                body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
            ))) {
            enterSwipeState(body);
            directStateFallbackUsed = true;
            KnoxAgent.writeLog("NPC combat DIRECT_SWIPE_STATE_FALLBACK");
        }
        // A firearm that fires without ever reducing the target still pays the
        // noise, ammunition and condition cost while the survivor stands in the
        // open. Its ballistics owner needs an aim-control source this shell does
        // not have, so the engagement can request shots indefinitely and observe
        // no damage. After a few silent requests, fail it: the Lua owner already
        // answers COMBAT_FAILED with its bounded melee fallback.
        if (rangedSilentExhausted(
            rangedWeapon, damageObserved, attackRequests, firstSwingTick, ticks)) {
            phase = "FAILED";
            return finish("COMBAT_FAILED RANGED_NO_DAMAGE attacks=" + attackRequests
                + " distance=" + targetDistance + " targetHealth=" + currentHealth);
        }
        if (attackStarted
            && attackRequests > 0
            && ticks - lastAttackTick > 180
            && !attackAnimationObserved
            && !damageObserved) {
            phase = "FAILED";
            return finish("COMBAT_FAILED ATTACK_STALLED state="
                + body.getClass().getMethod("getCurrentStateName").invoke(body)
                + " action="
                + body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
                + " initiateAttack="
                + initiateAttack
                + " attackType="
                + body.getClass().getMethod("getAttackType").invoke(body));
        }
        String attackType = String.valueOf(
            body.getClass().getMethod("getAttackType").invoke(body)
        );
        boolean attackTypeClear = attackType.isEmpty() || "NONE".equalsIgnoreCase(attackType);
        if (!attackActive && weaponReady && attackTypeClear
            && ticks - lastAttackTick >= attackRetryTicks(rangedWeapon)) {
            requestAttack(body, aimAtFloor, rangedWeapon);
            attackRequests++;
            swingCount++;
            if (firstSwingTick < 0) {
                firstSwingTick = ticks;
                distanceAtFirstSwing = targetDistance;
                KnoxAgent.writeLog("NPC combat FIRST_SWING tick=" + ticks
                    + " distance=" + targetDistance
                    + " desiredRange=" + desiredAttackRange
                    + " weaponMaxRange=" + weaponMaxRange + " npcId=" + npc.getId());
            }
            distanceAtLastSwing = targetDistance;
            lastAttackTick = ticks;
            attackAnimationObserved = false;
            directStateFallbackUsed = false;
            KnoxAgent.writeLog(
                "NPC combat ATTACK_REQUEST count=" + attackRequests + " targetHealth=" + currentHealth
                    + " npcId=" + npc.getId()
            );
            if (rangedWeapon) {
                return "COMBAT_FIREARM_REQUEST attacks=" + attackRequests
                    + " targetHealth=" + currentHealth;
            }
        }

        return "COMBAT_ATTACKING attacks=" + attackRequests
            + " attackStarted=" + attackStarted
            + " attacking=" + attacking
            + " initiateAttack=" + initiateAttack
            + " attackAnimation=" + attackAnimation
            + " animationObserved=" + attackAnimationObserved
            + " fallback=" + directStateFallbackUsed
            + " weaponReady=" + weaponReady
            + " damageObserved=" + damageObserved
            + " targetHealth=" + currentHealth
            + " state=" + body.getClass().getMethod("getCurrentStateName").invoke(body)
            + " action=" + body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
            + " attackType=" + attackType;
    }

    // Every native health decrease still reaches the combat state immediately.
    // Only the synchronous filesystem diagnostic is coalesced.
    void observeTargetHealth(float currentHealth) {
        if (currentHealth < lastTargetHealth) {
            damageObserved = true;
            if (pendingDamageSamples == 0) pendingDamageStartHealth = lastTargetHealth;
            pendingDamageSamples++;
            if (lastDamageLogTick < 0 || ticks - lastDamageLogTick >= DAMAGE_LOG_INTERVAL_TICKS
                || currentHealth <= 0.0f) {
                KnoxAgent.writeLog("NPC combat DAMAGE targetHealth=" + currentHealth
                    + " previous=" + pendingDamageStartHealth + " samples=" + pendingDamageSamples
                    + " npcId=" + (npc != null ? npc.getId() : "unavailable"));
                lastDamageLogTick = ticks;
                pendingDamageSamples = 0;
            }
        }
        lastTargetHealth = currentHealth;
    }

    String diagnostics() {
        if (npc == null || target == null) {
            return "COMBAT_DIAGNOSTICS phase=" + phase + " active=false";
        }
        try {
            Object body = npc.getBody();
            float dx = ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue()
                - ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
            float dy = ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue()
                - ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
            return "COMBAT_DIAGNOSTICS phase=" + phase
                + " active=true ticks=" + ticks
                + " ranged=" + rangedWeapon
                + " aim=" + aimTicks + "/" + aimSettleTicks
                + " distance=" + (float) Math.sqrt(dx * dx + dy * dy)
                + " attacks=" + attackRequests
                + " damageObserved=" + damageObserved
                + " targetHealth=" + health(target)
                + " bodyHealth=" + KnoxHealthController.health(body)
                + " bodyState=" + body.getClass().getMethod("getCurrentStateName").invoke(body)
                + " bodyAction="
                + body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)
                + " attackType=" + body.getClass().getMethod("getAttackType").invoke(body)
                + metricsSuffix();
        } catch (ReflectiveOperationException exception) {
            return "COMBAT_DIAGNOSTICS_FAILED " + exception.getClass().getSimpleName()
                + ": " + exception.getMessage();
        }
    }

    void reset() {
        if (npc != null && "DEFENSIVE_STEP".equals(phase)) {
            try { KnoxNpcFactory.stopCombatStep(npc); }
            catch (ReflectiveOperationException ignored) { }
        }
        KnoxHumanCombatGate.clear(this);
        if (npc != null) {
            npc.setCombatActive(false);
            try {
                // Never leave a latched get-up behind: the next knockdown
                // must run the native timer exactly like a player's does.
                npc.getBody().getClass().getMethod("setVariable", String.class, boolean.class)
                    .invoke(npc.getBody(), "forceGetUp", false);
            } catch (ReflectiveOperationException ignored) {
                // World teardown may invalidate the body before the bridge is notified.
            }
            try {
                clearAttackIntent();
            } catch (ReflectiveOperationException ignored) {
                // World teardown may invalidate the body before the bridge is notified.
            }
            try {
                clearMovementIntent();
            } catch (ReflectiveOperationException ignored) {
                // Attempt both cleanup halves independently during world teardown.
            }
        }
        npc = null;
        target = null;
        phase = "IDLE";
        ticks = 0;
        lastAttackTick = -ATTACK_RETRY_TICKS;
        attackRequests = 0;
        reactingTicks = 0;
        initialTargetHealth = 0.0f;
        lastTargetHealth = 0.0f;
        lastDamageLogTick = -DAMAGE_LOG_INTERVAL_TICKS;
        pendingDamageSamples = 0;
        pendingDamageStartHealth = 0.0f;
        initialWeaponCondition = -1;
        weaponMaxRange = 0.0f;
        desiredAttackRange = 0.0f;
        rangedWeapon = false;
        unarmedCombat = false;
        combatWeapon = null;
        damageObserved = false;
        attackAnimationObserved = false;
        aimTicks = 0;
        aimSettleTicks = DEFAULT_AIM_SETTLE_TICKS;
        directStateFallbackUsed = false;
        obstacleTarget = false;
        attackCycleActive = false;
        liveCombat = false;
        defenseWindowUntil = 0;
        approachSquare = null;
        lastApproachTick = 0;
        approachTargetX = 0.0f;
        approachTargetY = 0.0f;
        stationaryApproachRetries = 0;
        firstSwingTick = -1;
        distanceAtFirstSwing = -1.0f;
        distanceAtLastSwing = -1.0f;
        swingCount = 0;
        approachSteps = 0;
        approachRefreshes = 0;
        lastRangedRepositionTick = -RANGED_REPOSITION_COOLDOWN_TICKS;
        lastDefensiveStepTick = -60;
        defensiveStepEndTick = 0;
    }

    private void beginLiveApproach() throws ReflectiveOperationException {
        if (approachSquare == null) {
            throw new IllegalStateException("Live combat has no approach square");
        }
        // All encounter routes use the same current-side policy. A fallback tile
        // resolves exact overlap; it must not pull an ordinary approach around
        // the target or disagree with range refresh/ranged spacing.
        KnoxNpcFactory.moveToRangeFromCurrentSide(npc, target, approachSquare, desiredAttackRange);
        rememberApproachTarget(
            ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue(),
            ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue()
        );
        npc.getBody().getClass().getMethod("setRunning", boolean.class).invoke(npc.getBody(), true);
    }

    private void rememberApproachTarget(float x, float y) {
        approachTargetX = x;
        approachTargetY = y;
        lastApproachTick = ticks;
    }

    static boolean targetMovedSinceApproach(float x, float y, float oldX, float oldY) {
        float dx = x - oldX;
        float dy = y - oldY;
        return dx * dx + dy * dy >= 0.75f * 0.75f;
    }

    static boolean shouldRefreshApproach(String movement, boolean targetMoved, int elapsedTicks) {
        return elapsedTicks >= APPROACH_REFRESH_TICKS
            && ("Succeeded".equals(movement)
                || (targetMoved && "ManualRoute".equals(movement)));
    }

    static int clampAimSettleTicks(int requested) {
        return Math.max(MIN_AIM_SETTLE_TICKS, Math.min(MAX_AIM_SETTLE_TICKS, requested));
    }

    private void clearMovementIntent() throws ReflectiveOperationException {
        KnoxNpcFactory.stopCombatStep(npc);
        Object body = npc.getBody();
        Object pathfinder = body.getClass().getMethod("getPathFindBehavior2").invoke(body);
        pathfinder.getClass().getMethod("cancel").invoke(pathfinder);
    }

    String observeNativeRecovery(KnoxNpc activeNpc) throws ReflectiveOperationException {
        if (!hasNativeRecoveryOwner(activeNpc)) return "IDLE";
        // Input-only observation: no target health, terminal result, route or
        // combat ownership progression is allowed while Lua waits on recovery.
        clearNativeRecoveryInput(activeNpc.getBody());
        return "NATIVE_RECOVERY";
    }

    private void clearNativeRecoveryInput(Object body) throws ReflectiveOperationException {
        clearAttackIntent(body);
        attackCycleActive=false;
        lastAttackTick=ticks;
        defenseWindowUntil=Math.max(defenseWindowUntil,ticks+ATTACK_RECOVERY_TICKS);
    }

    private void clearAttackIntent() throws ReflectiveOperationException {
        clearAttackIntent(npc.getBody());
    }

    private static void clearAttackIntent(Object body) throws ReflectiveOperationException {
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAuthorizeMeleeAction", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAuthorizeShoveStomp", boolean.class).invoke(body, false);
        body.getClass().getMethod("setDoShove", boolean.class).invoke(body, false);
        body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAttackStarted", boolean.class).invoke(body, false);
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, false);
        body.getClass().getMethod("setZombiesDontAttack", boolean.class).invoke(body, false);
        body.getClass().getField("isCharging").setBoolean(body, false);
        body.getClass().getField("useChargeDelta").setFloat(body, 0.0f);
        body.getClass().getMethod("clearHandToHandAttack").invoke(body);
        body.getClass().getMethod("clearVariable", String.class).invoke(body, "AttackType");
        body.getClass().getMethod(
            "setAttackTargetSquare",
            classFor(body, "zombie.iso.IsoGridSquare")
        ).invoke(body, (Object) null);
        setAiAttackIntent(body, false, false);
    }

    private String finish(String result) {
        // One line per finished encounter: how many swings were actually
        // requested, how far away the first one was, and how much approach work
        // came before it. Nothing reads these back into a decision.
        KnoxAgent.writeLog("NPC combat END " + metricsSuffix());
        reset();
        return result;
    }

    private String metricsSuffix() {
        return " npcId=" + (npc != null ? npc.getId() : "unavailable")
            + " swing=" + swingCount
            + " firstSwingTick=" + firstSwingTick
            + " firstSwingDistance=" + distanceAtFirstSwing
            + " lastSwingDistance=" + distanceAtLastSwing
            + " approachSteps=" + approachSteps
            + " approachRefreshes=" + approachRefreshes;
    }

    private static boolean combatantUnavailable(Object body)
        throws ReflectiveOperationException {
        return unavailable(
            (Boolean) body.getClass().getMethod("isDead").invoke(body),
            body.getClass().getMethod("getCurrentSquare").invoke(body) == null
        );
    }

    private static boolean targetUnavailable(Object combatTarget)
        throws ReflectiveOperationException {
        return !inherits(combatTarget, "zombie.iso.objects.IsoDoor")
            && unavailable(
                false,
                combatTarget.getClass().getMethod("getCurrentSquare").invoke(combatTarget) == null
            );
    }

    static int attackRetryTicks(boolean ranged) {
        return ranged ? ATTACK_RETRY_TICKS : MELEE_RECOVERY_TICKS;
    }

    static int recoveryTicks(boolean ranged) {
        return ranged ? ATTACK_RECOVERY_TICKS : MELEE_RECOVERY_TICKS;
    }

    static boolean unavailable(boolean dead, boolean missingSquare) {
        return dead || missingSquare;
    }

    static float desiredRange(boolean ranged, float maximumRange, float minimumRange) {
        if (!ranged) {
            return Math.max(0.50f, maximumRange - 0.40f);
        }
        float cappedMaximum = Math.max(1.0f, maximumRange);
        float preferred = Math.max(6.0f, cappedMaximum * 0.65f);
        return Math.min(cappedMaximum, Math.max(minimumRange + 1.0f, preferred));
    }

    static float attackEntryThreshold(float desiredRange) {
        return desiredRange + ATTACK_ENTRY_BUFFER;
    }

    // One number for "no progress under injury": sustained hit-reaction with
    // attacks pending is chain-stun, not recovery. Calibrated against a live
    // death (~7 bitten seconds ran ~115 combat ticks with zero swings), while a
    // single bite reaction clears in tens of ticks.
    private static final int INJURY_STALL_TICKS = 90;

    static boolean injuryStallExpired(int consecutiveReactingTicks) {
        return consecutiveReactingTicks > INJURY_STALL_TICKS;
    }

    // A finished route inside native reach is a swing, not a re-route: entry
    // is the conservative band, reach is the native truth. Log-pinned:
    // give-ups at 1.03/1.14 vs entries 0.75/0.90 with 0.9/1.25 reach, after
    // ~100 approach steps and two swings. Ranged keeps its own spacing.
    static boolean arrivedInMeleeReach(boolean rangedWeapon, String movement,
        float targetDistance, float weaponMaxRange) {
        return !rangedWeapon && "Succeeded".equals(movement)
            && targetDistance <= weaponMaxRange;
    }

    // Close the last stretch at combat pace. Walking the final tiles lets a
    // moving target pace the approach forever (the observed orbit at 1-2
    // tiles); running inside firearm steadiness range is unchanged, and the
    // final half tile stays a walk so arrival does not overshoot the swing.
    static String approachPace(boolean rangedWeapon, float targetDistance,
        float attackEntryThreshold) {
        if (!rangedWeapon && targetDistance > attackEntryThreshold + 0.5f) return "run";
        return targetDistance <= 4.0f ? "walk" : "run";
    }


    static float reapproachThreshold(float desiredRange) {
        return desiredRange + REAPPROACH_BUFFER;
    }

    static float combatReapproachRange(boolean ranged, float desiredRange, float maximumRange) {
        return ranged ? Math.max(reapproachThreshold(desiredRange), maximumRange - 0.25f)
            : reapproachThreshold(desiredRange);
    }

    static float rangedSpacingRange(float minimumDistance) {
        return minimumDistance + 0.65f;
    }

    static float minimumRangedDistance(float desiredRange) {
        return Math.max(2.25f, Math.min(3.50f, desiredRange * 0.45f));
    }

    static boolean shouldRepositionRanged(
        boolean ranged,
        float distance,
        float minimumDistance,
        int ticks,
        int lastRepositionTick,
        boolean attackInProgress
    ) {
        return ranged
            && !attackInProgress
            && distance < minimumDistance
            && ticks - lastRepositionTick >= RANGED_REPOSITION_COOLDOWN_TICKS;
    }

    static boolean allowsDirectSwipeFallback(boolean ranged) {
        return !ranged;
    }

    static boolean liveTargetMode(boolean controlledGate) {
        return !controlledGate;
    }

    // A firearm engagement is only worth keeping while it can actually hurt the
    // target. An off-slot shell supplies no aim-control owner to Build 42's
    // ballistics, so shots can cost noise, ammunition and condition and never
    // reduce health. Bounded, not guessed: the request count and elapsed window
    // are both required before the encounter is declared silent.
    static boolean rangedSilentExhausted(
        boolean ranged,
        boolean damageObserved,
        int attackRequests,
        int firstSwingTick,
        int ticks
    ) {
        return ranged && !damageObserved && firstSwingTick >= 0
            && attackRequests >= RANGED_NO_DAMAGE_ATTACKS
            && ticks - firstSwingTick >= RANGED_NO_DAMAGE_TICKS;
    }

    private static void applyReadyPosture(Object body) throws ReflectiveOperationException {
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, true);
        setAiAttackIntent(body, true, false);
    }

    private void applyCombatStance(
        Object body,
        boolean initiate,
        boolean aimAtFloor,
        boolean ranged
    )
        throws ReflectiveOperationException {
        body.getClass().getMethod("setBannedAttacking", boolean.class).invoke(body, false);
        // Despite its legacy name this is Build 42's general player attack gate.
        // ISReloadWeaponAction.attackHook rejects ranged fire when it is false.
        body.getClass().getMethod("setAuthorizeMeleeAction", boolean.class).invoke(body, true);
        body.getClass().getMethod("setAuthorizeShoveStomp", boolean.class)
            // Armed survivors should swing their weapon. Native shove/stomp is
            // reserved for the unarmed fallback and floor attacks.
            .invoke(body, !ranged && (unarmedCombat || aimAtFloor));
        // doShove survives between native attacks. If it remains true when a
        // gun is equipped, Build 42's attackHook takes its melee branch and the
        // survivor appears to fire once without a projectile. Clear it for every
        // armed attack and enable it only for the bare-hands fallback.
        body.getClass().getMethod("setDoShove", boolean.class)
            .invoke(body, !ranged && unarmedCombat);
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, aimAtFloor);
        body.getClass().getMethod("setIsAiming", boolean.class).invoke(body, true);
        body.getClass().getField("isCharging").setBoolean(body, true);
        setAiAttackIntent(body, true, initiate);
    }

    private void requestAttack(Object body, boolean aimAtFloor, boolean ranged)
        throws ReflectiveOperationException {
        body.getClass().getMethod("clearHandToHandAttack").invoke(body);
        body.getClass().getMethod("setAimAtFloor", boolean.class).invoke(body, aimAtFloor);
        body.getClass().getField("useChargeDelta").setFloat(body, 36.0f);
        applyCombatStance(body, false, aimAtFloor, ranged);
        if (!ranged) {
            body.getClass().getMethod("pressedAttack").invoke(body);
            body.getClass().getMethod("setAttackStarted", boolean.class).invoke(body, true);
            body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
            setAiAttackIntent(body, true, true);
        }
    }

    private static boolean isHitReactionAction(String action) {
        return action != null
            && action.toLowerCase(java.util.Locale.ROOT).contains("hitreaction");
    }

    private static boolean nativeInjuryOwnsBody(Object body, String state, String action)
        throws ReflectiveOperationException {
        return isHitReactionAction(state) || isHitReactionAction(action)
            || state.toLowerCase(java.util.Locale.ROOT).contains("onground")
            || action.toLowerCase(java.util.Locale.ROOT).contains("onground")
            // Get-up enters after knockdown flags can clear. Its native enter
            // still blocks movement and explicitly clears attack input.
            || state.equalsIgnoreCase("PlayerGetUpState") || action.equalsIgnoreCase("getup")
            || (Boolean) body.getClass().getMethod("isKnockedDown").invoke(body);
    }

    static boolean hasNativeRecoveryOwner(KnoxNpc npc) throws ReflectiveOperationException {
        Object body=npc.getBody();
        if (combatantUnavailable(body)) return false;
        return nativeInjuryOwnsBody(body,
            String.valueOf(body.getClass().getMethod("getCurrentStateName").invoke(body)),
            String.valueOf(body.getClass().getMethod("getCurrentActionContextStateName").invoke(body)));
    }

    private boolean recoverIdleAttackLatch(Object body) throws ReflectiveOperationException {
        if (attackRequests == 0 || ticks - lastAttackTick <= 180
            || !"idle".equalsIgnoreCase(String.valueOf(body.getClass()
                .getMethod("getCurrentActionContextStateName").invoke(body)))
            || !"IdleState".equalsIgnoreCase(String.valueOf(body.getClass()
                .getMethod("getCurrentStateName").invoke(body)))
            || nativeAttackOwnsBody(body)) return false;
        boolean started = (Boolean) body.getClass().getMethod("isAttackStarted").invoke(body);
        String type = String.valueOf(body.getClass().getMethod("getAttackType").invoke(body));
        if (!started && (type.isEmpty() || "NONE".equalsIgnoreCase(type))) return false;
        // Old request flags are not an animation owner. Recover even after an
        // earlier shot animated or hit; those observations used to disable the watchdog.
        clearNativeRecoveryInput(body);
        attackAnimationObserved = false;
        directStateFallbackUsed = false;
        return true;
    }

    private static boolean nativeAttackOwnsBody(Object body) throws ReflectiveOperationException {
        String action = String.valueOf(body.getClass().getMethod("getCurrentActionContextStateName").invoke(body));
        String state = String.valueOf(body.getClass().getMethod("getCurrentStateName").invoke(body));
        // A hit reaction must remain vulnerable and keep its existing cleanup;
        // stale attack animation/input flags cannot override that native owner.
        if (nativeInjuryOwnsBody(body, state, action)) return false;
        if ((Boolean) body.getClass().getMethod("isPerformingAttackAnimation").invoke(body)
            || (Boolean) body.getClass().getMethod("isPerformingShoveAnimation").invoke(body)
            || (Boolean) body.getClass().getMethod("isPerformingStompAnimation").invoke(body)) return true;
        state = state.toLowerCase(java.util.Locale.ROOT);
        action = action.toLowerCase(java.util.Locale.ROOT);
        // AttackType/attackStarted/isAttacking can remain latched in Idle.
        // They are not evidence that the native graph still owns an attack.
        return state.contains("swipe") || action.equals("swipe") || action.equals("attack")
            || action.equals("shove") || action.equals("stomp");
    }

    private static void enterSwipeState(Object body) throws ReflectiveOperationException {
        ClassLoader loader = body.getClass().getClassLoader();
        Class<?> swipeClass = Class.forName("zombie.ai.states.SwipeStatePlayer", true, loader);
        Object swipeState = swipeClass.getMethod("instance").invoke(null);
        body.getClass().getMethod("changeState", classFor(body, "zombie.ai.State"))
            .invoke(body, swipeState);
        body.getClass().getMethod("setAttackStarted", boolean.class).invoke(body, true);
        body.getClass().getMethod("setInitiateAttack", boolean.class).invoke(body, true);
        setAiAttackIntent(body, true, true);
    }

    private static void setAiAttackIntent(Object body, boolean aiming, boolean initiate)
        throws ReflectiveOperationException {
        Class<?> aiComponentClass = classFor(body, "zombie.characters.component.AIComponent");
        Object componentMap = body.getClass().getMethod("getECSComponentMap").invoke(body);
        Object aiComponent = ((Map<?, ?>) componentMap).get(aiComponentClass);
        if (aiComponent == null) {
            throw new IllegalStateException("NPC has no AIComponent for combat input");
        }
        Object controlVars = aiComponent.getClass().getMethod("getHumanControlVars")
            .invoke(aiComponent);
        if (controlVars == null) {
            throw new IllegalStateException("NPC has no human control variables for combat input");
        }
        controlVars.getClass().getField("aiming").setBoolean(controlVars, aiming);
        controlVars.getClass().getField("melee").setBoolean(controlVars, false);
        controlVars.getClass().getField("bannedAttacking").setBoolean(controlVars, false);
        controlVars.getClass().getField("initiateAttack").setBoolean(controlVars, initiate);
    }

    static boolean defensiveStepStillFacesThreat(float awayX, float awayY,
        float targetDx, float targetDy, float distance) {
        // A normal advancing zombie stays ahead; a substantial flank or a
        // target behind the retreat direction ends the step.
        return distance > .05f && awayX * targetDx + awayY * targetDy <= -.9f * distance;
    }

    // Fail closed when installed geometry or threat facts cannot be read.
    private static float[] defensiveStepDestination(Object body, Object target, float distance) {
        return defensiveStepDestination(body, target, distance, Float.NaN, Float.NaN);
    }

    private static float[] defensiveStepDestination(Object body, Object target, float distance,
        float destinationX, float destinationY) {
        if (!inherits(target, "zombie.characters.IsoZombie") || distance < .05f || distance > .75f)
            return null;
        try {
            if ((Boolean) target.getClass().getMethod("isOnFloor").invoke(target)) return null;
            float x = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
            float y = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
            float z = ((Number) body.getClass().getMethod("getZ").invoke(body)).floatValue();
            float tx = ((Number) target.getClass().getMethod("getX").invoke(target)).floatValue();
            float ty = ((Number) target.getClass().getMethod("getY").invoke(target)).floatValue();
            Object cell = body.getClass().getMethod("getCell").invoke(body);
            Object current = body.getClass().getMethod("getCurrentSquare").invoke(body);
            int nearby = 0; boolean targetFound = false;
            Class<?> square = classFor(body, "zombie.iso.IsoGridSquare");
            var getSquare = cell.getClass().getMethod("getGridSquare", int.class, int.class, int.class);
            var getMoving = square.getMethod("getMovingObjects");
            // A spacing tick only needs contact threats. Query native nearby
            // squares rather than reflecting over the entire loaded zombie list.
            for (int gx=(int)Math.floor(x-2.5f); gx<=(int)Math.floor(x+2.5f); gx++) {
                for (int gy=(int)Math.floor(y-2.5f); gy<=(int)Math.floor(y+2.5f); gy++) {
                    Object localSquare = getSquare.invoke(cell,gx,gy,(int)Math.floor(z));
                    if (localSquare == null) continue;
                    for (Object zombie : (List<?>)getMoving.invoke(localSquare)) {
                        if (!inherits(zombie,"zombie.characters.IsoZombie")) continue;
                        if ((Boolean) zombie.getClass().getMethod("isDead").invoke(zombie)) continue;
                        float zx = ((Number) zombie.getClass().getMethod("getX").invoke(zombie)).floatValue();
                        float zy = ((Number) zombie.getClass().getMethod("getY").invoke(zombie)).floatValue();
                        float zz = ((Number) zombie.getClass().getMethod("getZ").invoke(zombie)).floatValue();
                        if ((int) zz == (int) z && (zx-x)*(zx-x)+(zy-y)*(zy-y) <= 6.25f) {
                            if (++nearby > 1) return null;
                            if (zombie == target) targetFound = true;
                        }
                    }
                }
            }
            if (nearby != 1 || !targetFound) return null;
            float endX = Float.isNaN(destinationX) ? x - (tx-x) / distance * .65f : destinationX;
            float endY = Float.isNaN(destinationY) ? y - (ty-y) / distance * .65f : destinationY;
            int sx = (int) Math.floor(x), sy = (int) Math.floor(y);
            int ex = (int) Math.floor(endX), ey = (int) Math.floor(endY), floor = (int) Math.floor(z);
            if (Math.abs(ex-sx)+Math.abs(ey-sy) > 1) return null;
            Object next = cell.getClass().getMethod("getGridSquare", int.class, int.class, int.class)
                .invoke(cell, ex, ey, floor);
            if (current == null || next == null) return null;
            if ((Boolean) square.getMethod("HasStairs").invoke(current)
                || (Boolean) square.getMethod("HasStairs").invoke(next)
                || !(Boolean) square.getMethod("TreatAsSolidFloor").invoke(next)
                || !(Boolean) square.getMethod("isFree", boolean.class).invoke(next, false)
                || square.getMethod("getRoom").invoke(current) != square.getMethod("getRoom").invoke(next)) return null;
            if (current != next && (!(Boolean) square.getMethod("isFree", boolean.class).invoke(next, true)
                || (Boolean) square.getMethod("isBlockedTo", square).invoke(current, next)
                || (Boolean) square.getMethod("isBlockedTo", square).invoke(next, current)
                || square.getMethod("getDoorTo", square).invoke(current, next) != null
                || square.getMethod("getWindowTo", square).invoke(current, next) != null
                || square.getMethod("getWindowFrameTo", square).invoke(current, next) != null
                || square.getMethod("getWindowThumpableTo", square).invoke(current, next) != null
                || (Boolean) square.getMethod("isHoppableTo", square).invoke(current, next)
                || square.getMethod("getHoppableTo", square).invoke(current, next) != null
                || square.getMethod("getWallHoppableTo", square).invoke(current, next) != null)) return null;
            return new float[] {endX, endY, z};
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            return null;
        }
    }

    private static void faceTarget(Object body, float targetX, float targetY)
        throws ReflectiveOperationException {
        float x = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
        float y = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
        float directionX = targetX - x;
        float directionY = targetY - y;
        float length = (float) Math.sqrt(directionX * directionX + directionY * directionY);
        if (length <= 0.001f) {
            return;
        }
        directionX /= length;
        directionY /= length;
        body.getClass().getMethod("setTargetAndCurrentDirection", float.class, float.class)
            .invoke(body, directionX, directionY);
        body.getClass().getMethod("setForwardDirection", float.class, float.class)
            .invoke(body, directionX, directionY);
        body.getClass().getMethod("setDirectionAngle", float.class)
            .invoke(body, (float) Math.toDegrees(Math.atan2(directionY, directionX)));
    }

    private static float health(Object character) throws ReflectiveOperationException {
        // Human damage lives in BodyDamage; the generic character field can
        // stay at 1 after a real hit. Keep zombie and obstacle health native.
        if (inherits(character, "zombie.characters.IsoPlayer")) {
            return KnoxHealthController.health(character);
        }
        return ((Number) character.getClass().getMethod("getHealth").invoke(character)).floatValue();
    }

    private static boolean targetFinished(Object target) throws ReflectiveOperationException {
        if (inherits(target, "zombie.iso.objects.IsoDoor")) {
            return (Boolean) target.getClass().getMethod("isDestroyed").invoke(target);
        }
        return (Boolean) target.getClass().getMethod("isDead").invoke(target);
    }

    private static boolean inherits(Object value, String className) {
        for (Class<?> type = value.getClass(); type != null; type = type.getSuperclass()) {
            if (className.equals(type.getName())) {
                return true;
            }
        }
        return false;
    }

    private static Class<?> classFor(Object source, String className)
        throws ClassNotFoundException {
        return Class.forName(className, false, source.getClass().getClassLoader());
    }
}
