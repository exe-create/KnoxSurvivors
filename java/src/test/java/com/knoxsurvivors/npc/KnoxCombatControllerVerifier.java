package com.knoxsurvivors.npc;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import zombie.iso.IsoGridSquare;

/** Focused terminal combat cleanup checks that do not require a running game. */
public final class KnoxCombatControllerVerifier {
    private KnoxCombatControllerVerifier() {
    }

    public static void main(String[] arguments) throws Exception {
        verifyNativeAttackOwnership();
        verifyTraversalOwnsCombat();
        verifyTargetRetirementWaitsForNativeAttack();
        verifyNativeHitReactionStateOwnsBody();
        verifyObstacleRecoveryOwnsBody();
        verifyRecoveryAdmissionRetainsRoute();
        verifyRecoveryObservationPreservesResults();
        verifyDamageLogBudget();
        Method targetHealth = KnoxCombatController.class.getDeclaredMethod("health", Object.class);
        targetHealth.setAccessible(true);
        zombie.characters.IsoPlayer human = new zombie.characters.IsoPlayer();
        human.damage.health = 85.0f;
        require((Float) targetHealth.invoke(null, human) == 85.0f,
            "human combat must observe BodyDamage rather than stale generic health");
        human.damage.health = 75.0f;
        require((Float) targetHealth.invoke(null, human) == 75.0f && human.getHealth() == 1.0f,
            "real human health loss is visible without mutating generic health");
        human.damage.health = .5f;
        require((Float) targetHealth.invoke(null, human) == .5f,
            "critical native human health is not normalized into a healthy value");
        Method targetFinished = KnoxCombatController.class.getDeclaredMethod("targetFinished", Object.class);
        targetFinished.setAccessible(true);
        require(!(Boolean) targetFinished.invoke(null, human),
            "damage or critical health cannot fabricate a defeated human target");
        human.dead = true;
        require((Boolean) targetFinished.invoke(null, human), "actual native death finishes a human target");
        require((Float) targetHealth.invoke(null, new GenericHealthTarget()) == 47.0f,
            "nonhuman zombie and obstacle health retains its native generic owner");
        require(KnoxCombatController.recoveryTicks(false) == 30
            && KnoxCombatController.recoveryTicks(true) == 24,
            "small melee recovery increase must not slow firearms");
        require(KnoxCombatController.clampAimSettleTicks(0) == 8
            && KnoxCombatController.clampAimSettleTicks(18) == 18
            && KnoxCombatController.clampAimSettleTicks(99) == 30,
            "aim settle input remains bounded for native combat");
        FakeBody body = new FakeBody();
        KnoxNpc npc = new KnoxNpc("combat-verifier", body, 10, 20, 0);
        npc.setMovementRoute(List.of(new float[] {11.5f, 20.5f, 0.0f}));

        KnoxCombatController controller = new KnoxCombatController();
        Field npcField = KnoxCombatController.class.getDeclaredField("npc");
        npcField.setAccessible(true);
        npcField.set(controller, npc);
        Field combatWeaponField = KnoxCombatController.class.getDeclaredField("combatWeapon");
        combatWeaponField.setAccessible(true);
        combatWeaponField.set(controller, new Object());
        npc.setCombatActive(true);
        controller.reset();

        require(!body.isAiming, "terminal cleanup clears aiming");
        require(!body.authorizeMelee, "terminal cleanup clears melee authorization");
        require(!body.authorizeShoveStomp, "terminal cleanup clears shove/stomp authorization");
        require(!body.initiateAttack, "terminal cleanup clears attack initiation");
        require(!body.attackStarted, "terminal cleanup clears attack-started flag");
        require(!body.aimAtFloor, "terminal cleanup clears floor aim");
        require(!body.isCharging && body.useChargeDelta == 0.0f,
            "terminal cleanup clears charge input");
        require(body.attackType.isEmpty(), "terminal cleanup clears AttackType");
        require(body.attackTargetSquare == null, "terminal cleanup clears attack target square");
        require(!body.controlVars.aiming && !body.controlVars.initiateAttack,
            "terminal cleanup clears AI attack input");
        require(!body.controlVars.melee && !body.controlVars.bannedAttacking,
            "terminal cleanup clears stale AI melee gates");
        require(body.pathfinder.cancelled, "terminal cleanup cancels combat pathfinder");
        require(!npc.hasMovementRoute(), "terminal cleanup releases combat route");
        require(combatWeaponField.get(controller) == null,
            "terminal cleanup releases ranged weapon ownership");
        require(!npc.isCombatActive(),
            "terminal cleanup releases combat locomotion ownership");
        require(KnoxCombatController.unavailable(true, false),
            "dead combatant is immediately invalid");
        require(KnoxCombatController.unavailable(false, true),
            "detached combatant is immediately invalid");
        require(!KnoxCombatController.unavailable(false, false),
            "live loaded combatant remains valid");
        float meleeRange = KnoxCombatController.desiredRange(false, 1.25f, 0.0f);
        float attackEntry = KnoxCombatController.attackEntryThreshold(meleeRange);
        float reapproach = KnoxCombatController.reapproachThreshold(meleeRange);
        require(Math.abs(meleeRange - 0.85f) < 0.0001f,
            "melee policy keeps a safe margin inside native adjusted reach");
        require(attackEntry < reapproach,
            "attack entry is closer than reapproach hysteresis");
        require(attackEntry < 1.25f,
            "attack entry remains inside native melee reach");
        npc.setMovementRoute(List.of(new float[] {meleeRange, 0, 0}));
        npc.setCombatActive(true);
        require(meleeRange + npc.movementNodeTolerance() < attackEntry,
            "final combat waypoint cannot finish outside attack-entry tolerance");
        npc.setCombatActive(false);
        require(npc.movementNodeTolerance() == 0.35f,
            "ordinary route arrival tolerance is unchanged");
        require(KnoxCombatController.shouldRefreshApproach("Succeeded", false, 30),
            "completed stale approach is reconsidered instead of waiting forever");
        require(KnoxCombatController.shouldRefreshApproach("ManualRoute", true, 30),
            "moving zombie refreshes a live route at bounded cadence");
        require(!KnoxCombatController.shouldRefreshApproach("ManualRoute", true, 29),
            "moving target cannot refresh every frame");
        require(!KnoxCombatController.shouldRefreshApproach("Transition:CLIMBING", true, 90),
            "target movement does not cancel an active traversal");
        require(!KnoxCombatController.targetMovedSinceApproach(0.5f, 0, 0, 0),
            "small target drift does not cause route churn");
        require(KnoxCombatController.targetMovedSinceApproach(0.8f, 0, 0, 0),
            "meaningful target movement causes bounded re-engagement");
        float desiredRange = KnoxCombatController.desiredRange(true, 15.0f, 0.0f);
        float minimumRange = KnoxCombatController.minimumRangedDistance(desiredRange);
        require(desiredRange > minimumRange && desiredRange <= 15.0f,
            "firearm policy chooses a useful bounded firing range");
        require(KnoxCombatController.shouldRepositionRanged(
            true, minimumRange - 0.1f, minimumRange, 61, 0, false
        ), "close ready firearm requests bounded reposition");
        require(!KnoxCombatController.shouldRepositionRanged(
            true, minimumRange - 0.1f, minimumRange, 30, 0, false
        ), "firearm reposition cooldown prevents request churn");
        require(!KnoxCombatController.shouldRepositionRanged(
            true, minimumRange - 0.1f, minimumRange, 61, 0, true
        ), "active firearm attack is not interrupted by reposition");
        require(!KnoxCombatController.shouldRepositionRanged(
            false, 0.5f, minimumRange, 61, 0, false
        ), "melee positioning is not changed by firearm policy");
        Method requestAttack = KnoxCombatController.class.getDeclaredMethod(
            "requestAttack", Object.class, boolean.class, boolean.class
        );
        requestAttack.setAccessible(true);
        Field unarmedField = KnoxCombatController.class.getDeclaredField("unarmedCombat");
        unarmedField.setAccessible(true);
        unarmedField.setBoolean(controller, false);
        requestAttack.invoke(controller, body, false, true);
        require(body.authorizeMelee,
            "Build 42 general attack authorization remains enabled for firearms");
        require(!body.authorizeShoveStomp,
            "firearm request does not authorize shove/stomp");
        require(!body.doShove,
            "firearm request clears stale shove mode before native attackHook");
        require(body.pressedAttackCount == 0,
            "Java firearm request yields to native Lua attack hook");
        unarmedField.setBoolean(controller, true);
        requestAttack.invoke(controller, body, false, false);
        require(body.authorizeShoveStomp,
            "unarmed standing request authorizes native shove/stomp");
        require(body.doShove,
            "unarmed request explicitly selects the native shove path");
        require(body.pressedAttackCount == 1,
            "unarmed request enters the native hand-to-hand attack path");
        Method clearAttack = KnoxCombatController.class.getDeclaredMethod("clearAttackIntent");
        clearAttack.setAccessible(true);
        npcField.set(controller, npc);
        clearAttack.invoke(controller);
        require(!body.isAiming && !body.controlVars.aiming
                && !body.controlVars.initiateAttack && !body.initiateAttack,
            "ranged reposition can clear every native attack input before movement");
        require(!KnoxCombatController.allowsDirectSwipeFallback(true),
            "ranged attack cannot fall through to the melee SwipeState fallback");
        require(KnoxCombatController.allowsDirectSwipeFallback(false),
            "existing melee fallback remains available");
        require(KnoxCombatController.liveTargetMode(false),
            "live combat mode permits an engine human target");
        require(!KnoxCombatController.liveTargetMode(true),
            "controlled zombie gate remains zombie-only");

        Method ready = KnoxCombatController.class.getDeclaredMethod("applyReadyPosture", Object.class);
        ready.setAccessible(true);
        ready.invoke(null, body);
        require(body.isAiming && body.controlVars.aiming, "recovery retains native aiming posture");
        require(!body.controlVars.initiateAttack && !body.initiateAttack && !body.attackStarted
            && body.attackType.isEmpty(), "ready posture cannot rearm the completed attack or block bite gate");
        System.out.println(
            "KnoxCombatControllerVerifier PASS attackFlags=true route=true ownership=true ranged=true stealth=true"
        );
    }

    private static void verifyTraversalOwnsCombat() throws Exception {
        for (String state : List.of("ClimbOverFenceState", "ClimbThroughWindowState", "OpenWindowState", "SmashWindowState", "flag-only")) {
            for (boolean contextOnly : List.of(false, true)) {
                FakeBody body = new FakeBody();
                body.state = contextOnly || state.equals("flag-only") ? "IdleState" : state;
                body.action = contextOnly && !state.equals("flag-only") ? state : "idle";
                body.climbing = state.equals("flag-only");
                body.attackStarted = false;
                body.attackType = "";
                body.isAiming = false;
                body.controlVars.aiming = false;
                body.initiateAttack = false;
                body.controlVars.initiateAttack = false;
                FakeTarget target = new FakeTarget();
                KnoxNpc npc = new KnoxNpc("crossing-combat", body, 10, 20, 0);
                KnoxNpcRuntime runtime = new KnoxNpcRuntime(npc);
                npc.setMovementRoute(List.of(new float[] {11.5f,20.5f,0}));
                KnoxNpcRegistry registry = new KnoxNpcRegistry();
                Field active = KnoxNpcRegistry.class.getDeclaredField("activeNpcs");
                active.setAccessible(true);
                @SuppressWarnings("unchecked")
                Map<String,KnoxNpcRuntime> entries = (Map<String,KnoxNpcRuntime>) active.get(registry);
                entries.put("crossing-combat",runtime);
                require(registry.beginLiveCombat("crossing-combat",target,new IsoGridSquare())
                    .startsWith("COMBAT_DEFERRED") && npc.hasMovementRoute() && !body.pathfinder.cancelled,
                    "combat admission cannot cancel an engine-owned crossing route");
                require(registry.beginLockedDoorCombat("crossing-combat")
                    .startsWith("COMBAT_DEFERRED") && npc.hasMovementRoute() && !body.pathfinder.cancelled,
                    "obstacle combat must also wait for native traversal ownership");
                KnoxCombatController combat = new KnoxCombatController();
                combatField("npc").set(combat,npc);
                combatField("target").set(combat,target);
                combatField("phase").set(combat,"ATTACKING");
                combatField("liveCombat").setBoolean(combat,true);
                combatField("desiredAttackRange").setFloat(combat,.85f);
                combatField("ticks").setInt(combat,60);
                combatField("lastTargetHealth").setFloat(combat,100);
                String result=combat.tick();
                require(result.startsWith("COMBAT_NATIVE_ACTION") && !body.isAiming
                    && !body.controlVars.aiming && body.pressedAttackCount==0
                    && body.pathRequests==0 && !body.pathfinder.cancelled && npc.hasMovementRoute(),
                    "native traversal must retain input/movement ownership even with an adjacent combat target: " + state);
                body.state="IdleState";body.action="idle";body.climbing=false;
                combat.tick();
                require(body.pressedAttackCount==1,"actual native release resumes the same combat owner");
            }
        }
    }

    private static void verifyNativeAttackOwnership() throws Exception {
        // Exercise the real tick, including the movement/request side effects.
        for (String owner : List.of("attacking", "started", "animation", "idle", "displaced")) {
            FakeBody body = new FakeBody();
            body.attackStarted = owner.equals("started");
            body.attacking = owner.equals("attacking");
            body.attackAnimation = owner.equals("animation");
            body.attackType = owner.equals("animation") || owner.equals("idle") ? "" : "swing";
            FakeTarget target = new FakeTarget();
            if (owner.equals("started") || owner.equals("displaced")) target.x = 13.0f;
            KnoxCombatController combat = new KnoxCombatController();
            combatField("npc").set(combat, new KnoxNpc("attack-ownership", body, 10, 20, 0));
            combatField("target").set(combat, target);
            combatField("approachSquare").set(combat, new IsoGridSquare());
            combatField("phase").set(combat, "ATTACKING");
            combatField("liveCombat").setBoolean(combat, true);
            combatField("desiredAttackRange").setFloat(combat, .85f);
            combatField("ticks").setInt(combat, 60);
            combatField("lastTargetHealth").setFloat(combat, 100);
            combatField("attackRequests").setInt(combat, owner.equals("animation") ? 0 : 3);
            String result = combat.tick();
            if (owner.equals("idle")) {
                require(body.pathRequests == 0 && body.pressedAttackCount == 1,
                    "attack requests without damage do not justify moving away from melee range");
            } else if (owner.equals("displaced")) {
                require(result.startsWith("COMBAT_REAPPROACHING") && body.pathRequests == 1,
                    "actual loss of reach still permits one approach");
                require(Math.abs(body.pathY - 20) < .001f && body.pathX < target.x,
                    "reapproach stays on the survivor's current side, not the fallback tile's side");
            } else {
                require(body.pathRequests == 0 && body.pressedAttackCount == 0,
                    "native " + owner + " owns the attack until completion: " + result);
                require(body.attackStarted == owner.equals("started"),
                    "recovery must not clear native attack-start ownership");
            }
        }
        System.out.println("Combat native ownership PASS active/requested/animated attacks; movement requires real range change");
    }

    private static void verifyTargetRetirementWaitsForNativeAttack() throws Exception {
        for (boolean targetDead : List.of(true, false)) {
            for (String owner : List.of("state", "attack", "shove", "stomp", "animation", "shove-animation", "stomp-animation")) {
                FakeBody body = new FakeBody();
                body.state = owner.equals("state") ? "SwipeStatePlayer" : "IdleState";
                body.action = List.of("attack", "shove", "stomp").contains(owner) ? owner : "idle";
                body.attackAnimation = owner.equals("animation");
                body.shoveAnimation = owner.equals("shove-animation");
                body.stompAnimation = owner.equals("stomp-animation");
                FakeTarget target = new FakeTarget();
                target.dead = targetDead;
                target.missingSquare = !targetDead;
                KnoxNpc npc = new KnoxNpc("native-terminal", body, 10,20,0);
                npc.setCombatActive(true);
                npc.setMovementRoute(List.of(new float[] {11.5f,20.5f,0}));
                KnoxCombatController combat = new KnoxCombatController();
                combatField("npc").set(combat,npc);
                combatField("target").set(combat,target);
                combatField("phase").set(combat,"ATTACKING");
                combatField("liveCombat").setBoolean(combat,true);
                combatField("lastTargetHealth").setFloat(combat,100);
                combatField("attackRequests").setInt(combat,1);
                combatField("damageObserved").setBoolean(combat,true);
                String deferred = combat.tick();
                require(deferred.startsWith("COMBAT_NATIVE_ATTACK") && body.attackStarted
                    && body.attackType.equals("swing") && !body.pathfinder.cancelled
                    && npc.hasMovementRoute() && npc.isCombatActive() && body.pressedAttackCount==0,
                    "target death/unload cannot retire the native graph before release: " + owner);
                body.state="IdleState";body.action="idle";
                body.attackAnimation=false;body.shoveAnimation=false;body.stompAnimation=false;
                // Stale idle input latches deliberately remain true. They must
                // not retain an obsolete target after actual native release.
                body.attacking=true;
                String retired=combat.tick();
                require(retired.startsWith(targetDead ? "COMBAT_SUCCEEDED" : "COMBAT_FAILED")
                    && !body.attackStarted && body.attackType.isEmpty() && body.pathfinder.cancelled
                    && !npc.hasMovementRoute() && !npc.isCombatActive(),
                    "actual graph release performs the original terminal cleanup once");
                require(combat.tick().equals("COMBAT_IDLE"),"retired combat cannot reenter native attack");
            }
        }
        for (String unavailable : List.of("dead-actor", "unloaded-actor", "hit-reaction")) {
            FakeBody body=new FakeBody();
            body.attackAnimation=true;
            body.dead=unavailable.equals("dead-actor");
            body.missingSquare=unavailable.equals("unloaded-actor");
            if (unavailable.equals("hit-reaction")) body.action="zombie-hitreaction";
            FakeTarget target=new FakeTarget();target.missingSquare=true;
            KnoxNpc npc=new KnoxNpc("terminal-unavailable",body,10,20,0);
            KnoxCombatController combat=new KnoxCombatController();
            combatField("npc").set(combat,npc);combatField("target").set(combat,target);
            combatField("liveCombat").setBoolean(combat,true);
            require(combat.tick().startsWith("COMBAT_FAILED") && !body.attackStarted
                && body.attackType.isEmpty() && body.pathfinder.cancelled,
                "native attack wait cannot retain dead/unloaded actors or suppress hit-reaction cleanup: " + unavailable);
        }
        System.out.println("Combat terminal handoff PASS native_graph=true idle_latches=false actor_cleanup=true hit_reaction=true");
    }

    private static void verifyNativeHitReactionStateOwnsBody() throws Exception {
        for (String injury : List.of("PlayerHitReactionState", "PlayerOnGroundState", "knocked-down", "PlayerGetUpState", "context-getup")) {
        for (String context : List.of("idle", "attack")) {
            FakeBody body=new FakeBody();
            body.state=injury.equals("knocked-down") || injury.equals("context-getup") ? "IdleState" : injury;
            body.action=injury.equals("context-getup") ? "getup" : context;
            body.knockedDown=injury.equals("knocked-down");
            body.isAiming=false;body.controlVars.aiming=false;
            body.attackStarted=false;body.attackType="";
            FakeTarget target=new FakeTarget();
            KnoxNpc npc=new KnoxNpc("native-injury-owner",body,10,20,0);
            KnoxCombatController combat=new KnoxCombatController();
            combatField("npc").set(combat,npc);combatField("target").set(combat,target);
            combatField("liveCombat").setBoolean(combat,true);
            combatField("phase").set(combat,"ATTACKING");
            combatField("lastTargetHealth").setFloat(combat,100);
            combatField("desiredAttackRange").setFloat(combat,.85f);
            combatField("ticks").setInt(combat,60);
            String result=combat.tick();
            require(result.startsWith("COMBAT_REACTING") && !body.isAiming && !body.controlVars.aiming
                && body.pressedAttackCount==0 && body.pathRequests==0 && body.attackType.isEmpty(),
                "native injury must retain ownership despite lagging context: " + injury + "/" + context);
            if (injury.equals("PlayerGetUpState") || injury.equals("context-getup")) {
                body.state="IdleState";body.action="idle";
                for (int tick=0;tick<60 && body.pressedAttackCount==0;tick++) combat.tick();
                require(body.pressedAttackCount==1,
                    "the original combat owner must resume after actual get-up release and existing recovery delay");
                body.state=injury.equals("context-getup") ? "IdleState" : injury;
                body.action=injury.equals("context-getup") ? "getup" : context;
            }
            // A stale native attack animation cannot make an obsolete target
            // hold injury cleanup just because its action context lags.
            target.missingSquare=true;body.attackAnimation=true;
            require(combat.tick().startsWith("COMBAT_FAILED") && body.pathfinder.cancelled,
                "native injury state must supersede stale attack flags at target retirement");
        }
        }
        System.out.println("Native injury owner PASS state_and_context=true no_aim_or_attack=true terminal_cleanup=true");
    }

    private static void verifyObstacleRecoveryOwnsBody() throws Exception {
        for (String recovery : List.of("PlayerHitReactionState","PlayerOnGroundState","PlayerGetUpState","knocked-down")) {
            FakeBody body=new FakeBody();
            body.state=recovery.equals("knocked-down") ? "IdleState" : recovery;
            body.action="idle";body.knockedDown=recovery.equals("knocked-down");
            body.isAiming=false;body.controlVars.aiming=false;body.attackStarted=false;body.attackType="";
            FakeDoorTarget door=new FakeDoorTarget();
            KnoxNpc npc=new KnoxNpc("door-recovery",body,10,20,0);
            KnoxCombatController combat=new KnoxCombatController();
            combatField("npc").set(combat,npc);combatField("target").set(combat,door);
            combatField("liveCombat").setBoolean(combat,false);combatField("obstacleTarget").setBoolean(combat,true);
            combatField("phase").set(combat,"ATTACKING");combatField("lastTargetHealth").setFloat(combat,100);
            combatField("desiredAttackRange").setFloat(combat,.85f);combatField("ticks").setInt(combat,60);
            String result=combat.tick();
            require(result.startsWith("COMBAT_REACTING") && !body.isAiming && !body.controlVars.aiming
                && body.pressedAttackCount==0 && body.pathRequests==0 && body.attackType.isEmpty(),
                "real obstacle combat mode must yield its inputs during native recovery: " + recovery);
            body.state="IdleState";body.knockedDown=false;
            for (int tick=0;tick<60 && body.pressedAttackCount==0;tick++) combat.tick();
            require(body.pressedAttackCount==1,"obstacle combat resumes after actual native recovery release");
            body.dead=true;body.state="PlayerGetUpState";
            require(combat.tick().startsWith("COMBAT_FAILED") && body.pathfinder.cancelled,
                "unavailable obstacle attacker must still clean up during recovery");
        }
        System.out.println("Obstacle recovery PASS actual_mode=true no_aim_or_attack=true release=true actor_cleanup=true");
    }

    private static void verifyRecoveryAdmissionRetainsRoute() throws Exception {
        for (String recovery : List.of("PlayerHitReactionState", "PlayerOnGroundState", "PlayerGetUpState", "context-getup", "knocked-down")) {
            FakeBody body=new FakeBody();
            body.state=recovery.equals("context-getup") || recovery.equals("knocked-down") ? "IdleState" : recovery;
            body.action=recovery.equals("context-getup") ? "getup" : "idle";
            body.knockedDown=recovery.equals("knocked-down");
            body.attackStarted=false;body.attackType="";body.isAiming=false;body.controlVars.aiming=false;
            KnoxNpc npc=new KnoxNpc("recovering-admission",body,10,20,0);
            KnoxNpcRuntime runtime=new KnoxNpcRuntime(npc);
            npc.setMovementRoute(List.of(new float[]{11.5f,20.5f,0}));
            KnoxNpcRegistry registry=new KnoxNpcRegistry();
            Field active=KnoxNpcRegistry.class.getDeclaredField("activeNpcs");active.setAccessible(true);
            @SuppressWarnings("unchecked")
            Map<String,KnoxNpcRuntime> entries=(Map<String,KnoxNpcRuntime>)active.get(registry);
            entries.put("recovering-admission",runtime);
            Object human=new zombie.characters.IsoPlayer();
            String result=registry.beginLiveCombat("recovering-admission",human,new IsoGridSquare());
            require(result.startsWith("COMBAT_DEFERRED") && npc.hasMovementRoute() && !body.pathfinder.cancelled
                && !body.isAiming && !body.controlVars.aiming && body.pressedAttackCount==0,
                "native recovery admission must preserve the existing route before Registry cancellation: " + recovery);
            require(registry.beginLockedDoorCombat("recovering-admission").startsWith("COMBAT_DEFERRED")
                && npc.hasMovementRoute() && !body.pathfinder.cancelled,
                "locked-door combat must defer before replacing a native recovery owner: " + recovery);
            require(new KnoxCombatController().beginLive(npc,human,new IsoGridSquare()).startsWith("COMBAT_DEFERRED"),
                "direct live admission must not reset or arm a recovering body: " + recovery);
            require(new KnoxCombatController().beginLockedDoor(npc,new KnoxTraversalVerifier.DoorToken())
                .startsWith("COMBAT_DEFERRED"),"direct door admission must preserve native recovery: " + recovery);
            body.state="IdleState";body.action="idle";body.knockedDown=false;
            require(!KnoxCombatController.hasNativeRecoveryOwner(npc),"actual recovery release must stop deferring admission");
            body.state="PlayerGetUpState";body.dead=true;
            require(!KnoxCombatController.hasNativeRecoveryOwner(npc),"dead actor cleanup must not wait for recovery");
            require(registry.beginLiveCombat("recovering-admission",human,new IsoGridSquare()).startsWith("COMBAT_FAILED")
                && body.pathfinder.cancelled && !npc.hasMovementRoute(),
                "dead actor admission must still retire native movement instead of deferring forever");
            body.dead=false;body.missingSquare=true;
            require(!KnoxCombatController.hasNativeRecoveryOwner(npc),"detached actor cleanup must not wait for recovery");
            body.pathfinder.cancelled=false;
            npc.setMovementRoute(List.of(new float[]{11.5f,20.5f,0}));
            require(registry.beginLiveCombat("recovering-admission",human,new IsoGridSquare()).startsWith("COMBAT_FAILED")
                && body.pathfinder.cancelled && !npc.hasMovementRoute(),
                "unloaded actor admission must still retire native movement");
        }
        System.out.println("Recovery admission PASS registry_route=true direct_admission=true actual_release=true actor_cleanup=true");
    }

    private static void verifyRecoveryObservationPreservesResults() throws Exception {
        for (boolean obstacle : List.of(false,true)) {
        for (String recovery : List.of("PlayerHitReactionState","PlayerOnGroundState","PlayerGetUpState","context-getup","knocked-down")) {
            FakeBody body=new FakeBody();
            body.state=recovery.equals("context-getup") || recovery.equals("knocked-down") ? "IdleState" : recovery;
            body.action=recovery.equals("context-getup") ? "getup" : "idle";
            body.knockedDown=recovery.equals("knocked-down");body.attackAnimation=true;
            KnoxNpc npc=new KnoxNpc("recovery-observation",body,10,20,0);
            KnoxNpcRuntime runtime=new KnoxNpcRuntime(npc);
            npc.setMovementRoute(List.of(new float[]{11.5f,20.5f,0}));npc.setCombatActive(true);
            KnoxNpcRegistry registry=new KnoxNpcRegistry();
            Field active=KnoxNpcRegistry.class.getDeclaredField("activeNpcs");active.setAccessible(true);
            @SuppressWarnings("unchecked")
            Map<String,KnoxNpcRuntime> entries=(Map<String,KnoxNpcRuntime>)active.get(registry);
            entries.put("recovery-observation",runtime);
            Object target;
            if (obstacle) { FakeDoorTarget door=new FakeDoorTarget();door.destroyed=true;target=door; }
            else { FakeTarget zombie=new FakeTarget();zombie.dead=true;target=zombie; }
            KnoxCombatController combat=runtime.combat();
            combatField("npc").set(combat,npc);combatField("target").set(combat,target);
            combatField("phase").set(combat,"ATTACKING");combatField("lastTargetHealth").setFloat(combat,100);
            combatField("obstacleTarget").setBoolean(combat,obstacle);combatField("liveCombat").setBoolean(combat,!obstacle);
            for (int observation=0;observation<2;observation++) {
                require(registry.observeNativeRecovery("recovery-observation").equals("NATIVE_RECOVERY"),
                    "live registered native recovery is an input-only observation");
                require(combatField("target").get(combat)==target && combatField("npc").get(combat)==npc
                    && combatField("phase").get(combat).equals("ATTACKING")
                    && combatField("lastTargetHealth").getFloat(combat)==100 && npc.isCombatActive(),
                    "recovery observation cannot consume target death/door completion or damage attribution");
                require(npc.hasMovementRoute() && !body.pathfinder.cancelled && body.pathRequests==0
                    && !body.isAiming && !body.controlVars.aiming && !body.attackStarted && body.attackType.isEmpty()
                    && body.pressedAttackCount==0 && body.attackAnimation,
                    "observer clears stale inputs while retaining route and native animation ownership");
            }
            body.state="IdleState";body.action="idle";body.knockedDown=false;body.attackAnimation=false;
            require(registry.observeNativeRecovery("recovery-observation").equals("IDLE"),
                "released recovery cannot mutate input or advance combat");
            require(registry.tickCombat("recovery-observation").startsWith("COMBAT_FAILED TARGET_DIED_WITHOUT_NPC_DAMAGE"),
                "the existing full tick must still deliver its unconsumed native terminal result after release");
            require(registry.tickCombat("recovery-observation").equals("COMBAT_IDLE"),
                "the normal combat owner consumes the result once");
        }
        }
        for (boolean dead : List.of(false,true)) {
            FakeBody body=new FakeBody();body.state="PlayerGetUpState";body.action="getup";
            body.dead=dead;body.missingSquare=!dead;
            KnoxNpc npc=new KnoxNpc("unavailable-observation",body,10,20,0);
            KnoxCombatController combat=new KnoxCombatController();
            require(combat.observeNativeRecovery(npc).equals("IDLE") && body.isAiming && body.attackType.equals("swing"),
                "dead or detached actor cannot authorize a native recovery mutation");
        }
        System.out.println("Recovery observation PASS no_terminal_consumption=true route_retained=true native_inputs_cleared=true unavailable_rejected=true");
    }

    private static void verifyDamageLogBudget() throws Exception {
        String priorDirectory = System.getProperty("knox.logDirectory");
        Path directory = Files.createTempDirectory("knox-combat-log-verifier-");
        Path log = directory.resolve("KnoxIsoPlayer.log");
        try {
            System.setProperty("knox.logDirectory", directory.toString());
            KnoxCombatController combat = new KnoxCombatController();
            Field health = combatField("lastTargetHealth");
            Field tick = combatField("ticks");
            Field requests = combatField("attackRequests");
            Field observed = combatField("damageObserved");
            health.setFloat(combat, 100.0f);
            tick.setInt(combat, 1);
            combat.observeTargetHealth(100.0f);
            require(!Files.exists(log) && !observed.getBoolean(combat),
                "unchanged native health cannot create damage evidence or disk writes");
            for (int sample = 1; sample <= 600; sample++) {
                tick.setInt(combat, sample);
                requests.setInt(combat, sample % 11);
                float current = 100.0f - sample / 10.0f;
                combat.observeTargetHealth(current);
                require(observed.getBoolean(combat) && health.getFloat(combat) == current,
                    "every decrease updates combat evidence despite diagnostic coalescing");
            }
            require(Files.readAllLines(log).size() == 10,
                "600 changing-health ticks emit ten bounded progress logs, not 600 writes");
            tick.setInt(combat, 601);
            combat.observeTargetHealth(0.0f);
            require(Files.readAllLines(log).size() == 11,
                "zero native health is logged immediately inside the progress interval");
            require(Files.readString(log).contains("samples=60"),
                "coalesced diagnostics report the observed sample count");
            combat.reset();
            require(!observed.getBoolean(combat) && health.getFloat(combat) == 0.0f,
                "reset clears evidence for the next encounter");
            health.setFloat(combat, 100.0f);
            tick.setInt(combat, 1);
            combat.observeTargetHealth(99.0f);
            require(Files.readAllLines(log).size() == 12,
                "the first decrease of a new encounter is never suppressed by old timestamps");
            System.out.println("Combat damage log budget PASS samples=600 progressWrites=10 nativeEvidence=unchanged");
        } finally {
            if (priorDirectory == null) System.clearProperty("knox.logDirectory");
            else System.setProperty("knox.logDirectory", priorDirectory);
            Files.deleteIfExists(log);
            Files.deleteIfExists(directory);
        }
    }

    private static Field combatField(String name) throws Exception {
        Field field = KnoxCombatController.class.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    public static final class GenericHealthTarget {
        public float getHealth() { return 47.0f; }
    }

    public static final class FakeTarget {
        float x = 10.5f;
        boolean dead, missingSquare;
        public float getX() { return x; }
        public float getY() { return 20.0f; }
        public float getZ() { return 0; }
        public float getHealth() { return 100; }
        public boolean isDead() { return dead; }
        public boolean isOnFloor() { return false; }
        public IsoGridSquare getCurrentSquare() { return missingSquare ? null : new IsoGridSquare(); }
    }

    public static final class FakeDoorTarget extends zombie.iso.objects.IsoDoor {
        boolean destroyed;
        public float getX() { return 10.5f; }
        public float getY() { return 20; }
        public float getZ() { return 0; }
        public int getHealth() { return 100; }
        public boolean isDestroyed() { return destroyed; }
        public IsoGridSquare getSquare() { return new IsoGridSquare(); }
    }

    public static final class FakeBody {
        public boolean isCharging = true;
        public float useChargeDelta = 36.0f;
        boolean isAiming = true;
        boolean authorizeMelee = true;
        boolean authorizeShoveStomp = true;
        boolean initiateAttack = true;
        boolean attackStarted = true;
        boolean attacking;
        boolean attackAnimation;
        boolean shoveAnimation, stompAnimation, dead, missingSquare;
        boolean knockedDown;
        int pathRequests;
        boolean climbing;
        String state = "SwipeStatePlayer";
        String action = "attack";
        float pathX, pathY;
        boolean aimAtFloor = true;
        boolean doShove = true;
        boolean zombiesDontAttack = true;
        boolean bannedAttacking;
        int pressedAttackCount;
        String attackType = "swing";
        IsoGridSquare attackTargetSquare;
        final FakePathfinder pathfinder = new FakePathfinder();
        final FakeControlVars controlVars = new FakeControlVars();
        final FakeAiComponent aiComponent = new FakeAiComponent(controlVars);

        public float getX() { return 10; }
        public float getY() { return 20; }
        public boolean isDead() { return dead; }
        public boolean isKnockedDown() { return knockedDown; }
        public IsoGridSquare getCurrentSquare() { return missingSquare ? null : new IsoGridSquare(); }
        public Object getPrimaryHandItem() { return null; }
        public boolean isAttacking() { return attacking; }
        public boolean isAttackStarted() { return attackStarted; }
        public boolean isPerformingAttackAnimation() { return attackAnimation; }
        public boolean isPerformingShoveAnimation() { return shoveAnimation; }
        public boolean isPerformingStompAnimation() { return stompAnimation; }
        public boolean isInitiateAttack() { return initiateAttack; }
        public String getAttackType() { return attackType; }
        public String getCurrentActionContextStateName() { return action; }
        public String getCurrentStateName() { return state; }
        public boolean isClimbing() { return climbing; }
        public void setTargetAndCurrentDirection(float x, float y) { }
        public void setForwardDirection(float x, float y) { }
        public void setDirectionAngle(float angle) { }
        public void setRunning(boolean running) { }
        public void pathToLocationF(float x, float y, float z) { pathRequests++; pathX = x; pathY = y; }

        public void setIsAiming(boolean value) { isAiming = value; }
        public void setAuthorizeMeleeAction(boolean value) { authorizeMelee = value; }
        public void setAuthorizeShoveStomp(boolean value) { authorizeShoveStomp = value; }
        public void setInitiateAttack(boolean value) { initiateAttack = value; }
        public void setAttackStarted(boolean value) { attackStarted = value; }
        public void setAimAtFloor(boolean value) { aimAtFloor = value; }
        public void setDoShove(boolean value) { doShove = value; }
        public void setZombiesDontAttack(boolean value) { zombiesDontAttack = value; }
        public void setBannedAttacking(boolean value) { bannedAttacking = value; }
        public void pressedAttack() { pressedAttackCount++; }
        public void clearHandToHandAttack() { }
        public void clearVariable(String name) {
            if ("AttackType".equals(name)) {
                attackType = "";
            }
        }
        public void setAttackTargetSquare(IsoGridSquare square) { attackTargetSquare = square; }
        public Object getECSComponentMap() throws ClassNotFoundException {
            return Map.of(
                Class.forName("zombie.characters.component.AIComponent"),
                aiComponent
            );
        }
        public FakePathfinder getPathFindBehavior2() { return pathfinder; }
    }

    public static final class FakePathfinder {
        boolean cancelled;
        public void cancel() { cancelled = true; }
    }

    public static final class FakeAiComponent {
        private final FakeControlVars controlVars;
        FakeAiComponent(FakeControlVars controlVars) { this.controlVars = controlVars; }
        public FakeControlVars getHumanControlVars() { return controlVars; }
    }

    public static final class FakeControlVars {
        public boolean aiming = true;
        public boolean melee = true;
        public boolean bannedAttacking = true;
        public boolean initiateAttack = true;
    }
}
