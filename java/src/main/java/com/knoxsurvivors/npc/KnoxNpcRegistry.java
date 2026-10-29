package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;
import java.util.LinkedHashMap;
import java.util.Map;

/** Owns active IsoPlayer shells by persistent Knox survivor identity. */
public final class KnoxNpcRegistry {
    public static final String TEST_SURVIVOR_ID = "ks-test-1";

    private final Map<String, KnoxNpcRuntime> activeNpcs = new LinkedHashMap<>();

    public synchronized String spawnOne(Object square) {
        return spawn(TEST_SURVIVOR_ID, square);
    }

    public synchronized String spawn(String id, Object square) {
        if (!validId(id)) {
            return "SPAWN_FAILED INVALID_ID";
        }
        KnoxNpcRuntime existing = activeNpcs.get(id);
        if (existing != null) {
            return "ALREADY_ACTIVE " + existing.npc().describe();
        }

        try {
            KnoxNpc npc = KnoxNpcFactory.create(id, square);
            activeNpcs.put(id, new KnoxNpcRuntime(npc));
            String result = "SPAWNED " + npc.describe() + " localSlotsUnchanged=true";
            KnoxAgent.writeLog("NPC probe " + result);
            return result;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            String result = "FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
            KnoxAgent.writeLog("ERROR NPC probe " + result);
            return result;
        }
    }

    public synchronized String moveOne(Object square) {
        return move(TEST_SURVIVOR_ID, square);
    }

    public synchronized String crossOneAdjacentEdge(Object square) {
        return cross(TEST_SURVIVOR_ID, square);
    }

    public synchronized String move(String id, Object square) {
        return beginMove(id, square, false, "normal");
    }

    public synchronized String moveWithPace(String id, Object square, String pace) {
        return beginMove(id, square, false, pace);
    }

    public synchronized String moveWithinArea(String id, Object square,
        int minX, int minY, int maxX, int maxY, int z) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) return "MOVE_FAILED NONE_ACTIVE";
        return runtime.beginMove(square, false, "walk", new KnoxMovementArea(minX, minY, maxX, maxY, z));
    }

    public synchronized boolean updateMovementPace(String id, String pace) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        return runtime != null && runtime.updateMovementPace(pace);
    }

    public synchronized String cross(String id, Object square) {
        return beginMove(id, square, true, "walk");
    }

    private String beginMove(String id, Object square, boolean exactAdjacentCrossing, String pace) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "MOVE_FAILED NONE_ACTIVE";
        }
        return runtime.beginMove(square, exactAdjacentCrossing, pace);
    }

    public synchronized boolean hasTraversalEvidence(String state) {
        KnoxNpcRuntime runtime = activeNpcs.get(TEST_SURVIVOR_ID);
        return runtime != null && runtime.hasTraversalEvidence(state);
    }

    public synchronized String tickOne() {
        return tick(TEST_SURVIVOR_ID);
    }

    public synchronized String tick(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        return runtime == null ? "IDLE" : runtime.tickMovement();
    }

    /** Observe a native receipt without running or replacing a movement request. */
    public synchronized String observeNativeAction(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) return "IDLE";
        try {
            KnoxNpcFactory.observeNativeAction(runtime.npc());
            return "NATIVE_ACTION:" + runtime.npc().getTraversalInteractionStage();
        } catch (ReflectiveOperationException failure) {
            return "FAILED_NATIVE_ACTION:" + failure.getClass().getSimpleName();
        }
    }

    /** Clear only stale attack input while native recovery retains the actor. */
    public synchronized String observeNativeRecovery(String id) {
        KnoxNpcRuntime runtime=activeNpcs.get(id);
        if (runtime==null) return "IDLE";
        try { return runtime.combat().observeNativeRecovery(runtime.npc()); }
        catch (ReflectiveOperationException failure) {
            return "FAILED_NATIVE_RECOVERY:"+failure.getClass().getSimpleName();
        }
    }

    public synchronized String cancelMove(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        return runtime == null ? "MOVE_CANCEL_FAILED NONE_ACTIVE" : runtime.cancelMovement();
    }

    public synchronized boolean setClimbingAllowed(String id, boolean allowed) {
        KnoxNpc npc = npc(id);
        if (npc == null) {
            return false;
        }
        npc.setClimbingAllowed(allowed);
        return true;
    }

    public synchronized boolean setDoorWindowOpeningAllowed(String id, boolean allowed) {
        KnoxNpc npc = npc(id);
        if (npc == null) {
            return false;
        }
        npc.setDoorWindowOpeningAllowed(allowed);
        return true;
    }

    public synchronized String openDoor(String id, Object door) {
        KnoxNpc npc = npc(id);
        if (npc == null) return "FAILED_NONE_ACTIVE";
        try { return KnoxNpcFactory.openNativeDoor(npc, door); }
        catch (Throwable failure) { return failure("FAILED_DOOR_OPEN", failure); }
    }

    public synchronized String closeOpenedDoor(String id) {
        KnoxNpc npc = npc(id);
        if (npc == null) return "FAILED_NONE_ACTIVE";
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        return npc.hasOpenedDoor() ? "DOOR_PENDING" : "DOOR_RETIRED";
    }

    public synchronized boolean setProtectedArea(
        String id,
        int minX,
        int minY,
        int maxX,
        int maxY
    ) {
        KnoxNpc npc = npc(id);
        if (npc == null) {
            return false;
        }
        npc.setProtectedArea(minX, minY, maxX, maxY);
        return true;
    }

    public synchronized boolean clearProtectedArea(String id) {
        KnoxNpc npc = npc(id);
        if (npc == null) {
            return false;
        }
        npc.clearProtectedArea();
        return true;
    }

    public synchronized String removeOne() {
        return remove(TEST_SURVIVOR_ID);
    }

    public synchronized String remove(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "NONE_ACTIVE";
        }

        String description = runtime.npc().describe();
        try {
            KnoxNpcFactory.remove(runtime.npc());
            runtime.reset();
            activeNpcs.remove(id);
            KnoxAgent.writeLog("NPC probe REMOVED " + description);
            return "REMOVED " + description;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            KnoxAgent.writeLog(
                "ERROR NPC probe removal failed "
                    + cause.getClass().getName()
                    + ": "
                    + cause.getMessage()
            );
            return "REMOVE_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
        }
    }

    /**
     * Uses the same Build 42 IsoDeadBody constructor used for a dead IsoPlayer. The
     * constructor transfers inventory, worn items, and visual state onto a real,
     * world-owned corpse; only then is the contained NPC shell detached.
     */
    public synchronized String retireAsCorpse(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "NONE_ACTIVE";
        }
        try {
            // The corpse constructor is a one-way native world mutation.  A prior
            // cleanup failure must only retry detaching the contained shell.
            if (runtime.corpseRetirement().corpseCreated()) {
                return finishCorpseRetirement(id, runtime, true);
            }
            Object body = runtime.npc().getBody();
            ClassLoader loader = body.getClass().getClassLoader();
            Class<?> characterClass = Class.forName(
                "zombie.characters.IsoGameCharacter", false, loader
            );
            Class<?> corpseClass = Class.forName(
                "zombie.iso.objects.IsoDeadBody", false, loader
            );
            boolean shouldReanimate = shouldBecomeZombieAfterDeath(body);
            Object corpse = corpseClass.getConstructor(characterClass).newInstance(body);
            runtime.corpseRetirement().markCorpseCreated(shouldReanimate);
            if (shouldReanimate) {
                scheduleNativeReanimation(corpse);
                runtime.corpseRetirement().markReanimationScheduled();
            }
            return finishCorpseRetirement(id, runtime, false);
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            String state = runtime.corpseRetirement().corpseCreated()
                ? "CORPSE_PENDING_CLEANUP"
                : "CORPSE_FAILED";
            KnoxAgent.writeLog(
                "ERROR NPC corpse conversion " + state + " " + cause.getClass().getName()
                    + ": " + cause.getMessage()
            );
            return state + " " + cause.getClass().getName() + ": " + cause.getMessage();
        }
    }

    private String finishCorpseRetirement(String id, KnoxNpcRuntime runtime, boolean cleanupRetry) {
        try {
            KnoxNpcFactory.remove(runtime.npc());
            boolean reanimationScheduled = runtime.corpseRetirement().reanimationScheduled();
            runtime.reset();
            activeNpcs.remove(id);
            KnoxAgent.writeLog(
                "NPC lifecycle CORPSE_CREATED id=" + id
                    + " reanimationScheduled=" + reanimationScheduled
                    + " cleanupRetry=" + cleanupRetry
            );
            return "CORPSE_CREATED id=" + id
                + " reanimationScheduled=" + reanimationScheduled
                + " cleanupRetry=" + cleanupRetry;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            KnoxAgent.writeLog(
                "ERROR NPC corpse cleanup pending " + cause.getClass().getName()
                    + ": " + cause.getMessage()
            );
            return "CORPSE_PENDING_CLEANUP " + cause.getClass().getName()
                + ": " + cause.getMessage();
        }
    }

    /**
     * {@code IsoGameCharacter.DoDeath()} normally decides zombification before the body
     * becomes an {@code IsoDeadBody}. Knox intentionally does not call DoDeath on the
     * contained off-slot shell because that path owns local-player teardown. The native
     * predicate still applies the current transmission sandbox rule, infection state, and
     * fake-infection check; {@code reanimateLater()} then registers the corpse with the
     * engine's normal static updater. No Knox-specific infection or timer is invented.
     */
    static boolean scheduleNativeReanimation(Object body, Object corpse)
        throws ReflectiveOperationException {
        boolean shouldReanimate = shouldBecomeZombieAfterDeath(body);
        if (shouldReanimate) {
            scheduleNativeReanimation(corpse);
        }
        return shouldReanimate;
    }

    private static boolean shouldBecomeZombieAfterDeath(Object body)
        throws ReflectiveOperationException {
        return (Boolean) body.getClass()
            .getMethod("shouldBecomeZombieAfterDeath")
            .invoke(body);
    }

    private static void scheduleNativeReanimation(Object corpse)
        throws ReflectiveOperationException {
        corpse.getClass().getMethod("reanimateLater").invoke(corpse);
    }

    public synchronized String beginCombatOne(Object zombie, Object approachSquare) {
        return beginCombat(TEST_SURVIVOR_ID, zombie, approachSquare, false);
    }

    public synchronized String beginLiveCombatOne(Object zombie, Object approachSquare) {
        return beginCombat(TEST_SURVIVOR_ID, zombie, approachSquare, true);
    }

    public synchronized String beginLiveCombat(String id, Object zombie, Object approachSquare) {
        return beginCombat(id, zombie, approachSquare, true);
    }

    public synchronized String beginLiveCombat(
        String id,
        Object zombie,
        Object approachSquare,
        int aimSettleTicks
    ) {
        return beginCombat(id, zombie, approachSquare, true, aimSettleTicks);
    }

    public synchronized void setPlayerAttackTarget(Object player, String id, boolean allowed) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime != null) com.knoxsurvivors.agent.KnoxHumanCombatGate.setPlayerAttackTarget(
            player, runtime.npc().getBody(), allowed);
    }

    public synchronized String beginLockedDoorCombat(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        try {
            if (KnoxNpcFactory.hasNativeTraversalOwner(runtime.npc())) {
                KnoxNpcFactory.observeNativeAction(runtime.npc());
                return "COMBAT_DEFERRED NATIVE_ACTION";
            }
            if (KnoxCombatController.hasNativeRecoveryOwner(runtime.npc())) {
                return "COMBAT_DEFERRED NATIVE_RECOVERY";
            }
            return runtime.combat().beginLockedDoor(
                runtime.npc(),
                runtime.npc().getTraversalInteractionTarget()
            );
        } catch (Throwable throwable) {
            return failure("COMBAT_FAILED", throwable);
        }
    }

    private String beginCombat(String id, Object zombie, Object approachSquare, boolean live) {
        return beginCombat(id, zombie, approachSquare, live, 18);
    }

    private String beginCombat(
        String id,
        Object zombie,
        Object approachSquare,
        boolean live,
        int aimSettleTicks
    ) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        try {
            if (KnoxNpcFactory.hasNativeTraversalOwner(runtime.npc())) {
                KnoxNpcFactory.observeNativeAction(runtime.npc());
                return "COMBAT_DEFERRED NATIVE_ACTION";
            }
            if (KnoxCombatController.hasNativeRecoveryOwner(runtime.npc())) {
                return "COMBAT_DEFERRED NATIVE_RECOVERY";
            }
            // Combat takes exclusive ownership of pathfinding. A threat can interrupt
            // an ordinary Lua movement decision before tickMovement() observes its
            // terminal state; clear that request here so it cannot survive the fight
            // and reject the next decision as MOVE_ALREADY_REQUESTED.
            String cancelled = runtime.cancelMovement();
            if (cancelled.startsWith("MOVE_CANCEL_FAILED")) {
                return "COMBAT_FAILED " + cancelled;
            }
            return live
                ? runtime.combat().beginLive(
                    runtime.npc(), zombie, approachSquare, aimSettleTicks
                )
                : runtime.combat().begin(runtime.npc(), zombie, approachSquare);
        } catch (Throwable throwable) {
            runtime.combat().reset();
            return failure("COMBAT_FAILED", throwable);
        }
    }

    public synchronized void resetCombatOne() {
        resetCombat(TEST_SURVIVOR_ID);
    }

    public synchronized void resetCombat(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime != null) {
            runtime.combat().reset();
        }
    }

    public synchronized String tickCombatOne() {
        return tickCombat(TEST_SURVIVOR_ID);
    }

    public synchronized String tickCombat(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "COMBAT_FAILED NONE_ACTIVE";
        }
        try {
            return runtime.combat().tick();
        } catch (Throwable throwable) {
            runtime.combat().reset();
            return failure("COMBAT_FAILED", throwable);
        }
    }

    public synchronized Object activeCharacterForAction() {
        return character(TEST_SURVIVOR_ID);
    }

    public synchronized Object character(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        return runtime == null ? null : runtime.npc().getBody();
    }

    public synchronized String prepareHealthGateOne() {
        KnoxNpc npc = npc(TEST_SURVIVOR_ID);
        if (npc == null) {
            return "HEALTH_GATE_FAILED NONE_ACTIVE";
        }
        try {
            return KnoxHealthController.prepareControlledAttack(npc.getBody());
        } catch (Throwable throwable) {
            return failure("HEALTH_GATE_FAILED", throwable);
        }
    }

    public synchronized float healthOne() {
        KnoxNpc npc = requiredNpc(TEST_SURVIVOR_ID);
        if (npc == null) {
            throw new IllegalStateException("No active NPC");
        }
        try {
            return KnoxHealthController.health(npc.getBody());
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("Unable to read NPC health", exception);
        }
    }

    public synchronized int injuredPartsOne() {
        KnoxNpc npc = requiredNpc(TEST_SURVIVOR_ID);
        if (npc == null) {
            throw new IllegalStateException("No active NPC");
        }
        try {
            return KnoxHealthController.injuredParts(npc.getBody());
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("Unable to read NPC injuries", exception);
        }
    }

    public synchronized int bleedingPartsOne() {
        KnoxNpc npc = requiredNpc(TEST_SURVIVOR_ID);
        if (npc == null) {
            throw new IllegalStateException("No active NPC");
        }
        try {
            return KnoxHealthController.bleedingParts(npc.getBody());
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("Unable to read NPC bleeding", exception);
        }
    }

    public synchronized String normalizeMinorInjuryOne() {
        KnoxNpc npc = npc(TEST_SURVIVOR_ID);
        if (npc == null) {
            return "CONTROLLED_INJURY_FAILED NONE_ACTIVE";
        }
        try {
            return KnoxHealthController.normalizeToTreatableScratch(npc.getBody());
        } catch (Throwable throwable) {
            return failure("CONTROLLED_INJURY_FAILED", throwable);
        }
    }

    public synchronized String refreshHealthPresentationOne() {
        KnoxNpc npc = npc(TEST_SURVIVOR_ID);
        if (npc == null) {
            return "HEALTH_PRESENTATION_FAILED NONE_ACTIVE";
        }
        try {
            return KnoxHealthController.refreshPresentation(npc.getBody());
        } catch (Throwable throwable) {
            return failure("HEALTH_PRESENTATION_FAILED", throwable);
        }
    }

    public synchronized String directZombieAtOne(Object zombie) {
        return directZombieAt(TEST_SURVIVOR_ID, zombie);
    }

    public synchronized String directZombieAt(String id, Object zombie) {
        KnoxNpc npc = npc(id);
        if (npc == null) {
            return "ZOMBIE_DIRECT_FAILED NONE_ACTIVE";
        }
        try {
            return KnoxHealthController.directZombieAt(zombie, npc.getBody());
        } catch (Throwable throwable) {
            return failure("ZOMBIE_DIRECT_FAILED", throwable);
        }
    }

    public synchronized String zombieAttackDiagnostics(String id, Object zombie) {
        KnoxNpc npc = npc(id);
        if (npc == null) {
            return "ZOMBIE_ATTACK_DIAGNOSTICS_FAILED NONE_ACTIVE";
        }
        try {
            return KnoxHealthController.zombieAttackDiagnostics(zombie, npc.getBody());
        } catch (Throwable throwable) {
            return failure("ZOMBIE_ATTACK_DIAGNOSTICS_FAILED", throwable);
        }
    }

    public synchronized String combatDiagnostics(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        return runtime == null
            ? "COMBAT_DIAGNOSTICS_FAILED NONE_ACTIVE"
            : runtime.combat().diagnostics();
    }

    public synchronized String seedAndEquipOne() {
        return seedAndEquip(TEST_SURVIVOR_ID);
    }

    public synchronized String seedAndEquip(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "EQUIP_FAILED NONE_ACTIVE";
        }
        try {
            Object body = runtime.npc().getBody();
            Object inventory = body.getClass().getMethod("getInventory").invoke(body);
            inventory.getClass().getMethod("AddItem", String.class).invoke(inventory, "Base.Hammer");
            inventory.getClass().getMethod("AddItem", String.class).invoke(inventory, "Base.BaseballBat");
            String equipped = KnoxEquipmentController.equipBestMelee(body);
            KnoxSurvivorRecord record = captureRecord(runtime.npc());
            runtime.setLastRecord(record);
            String result = equipped + " items=" + record.inventory.size();
            KnoxAgent.writeLog("NPC equipment " + result);
            return result;
        } catch (Throwable throwable) {
            return failure("EQUIP_FAILED", throwable);
        }
    }

    public synchronized String equipBest(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "EQUIP_FAILED NONE_ACTIVE";
        }
        try {
            String equipped = KnoxEquipmentController.equipBestMelee(runtime.npc().getBody());
            runtime.setLastRecord(captureRecord(runtime.npc()));
            logEquipmentResult(id, equipped);
            return equipped;
        } catch (Throwable throwable) {
            return failure("EQUIP_FAILED", throwable);
        }
    }

    /** Equips an existing, validated inventory weapon selected by a gameplay controller. */
    public synchronized String equipOwnedWeapon(String id, String fullType) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "EQUIP_FAILED NONE_ACTIVE";
        }
        try {
            String equipped = KnoxEquipmentController.equipOwnedWeapon(
                runtime.npc().getBody(),
                fullType
            );
            if (equipped.startsWith("EQUIPPED_WEAPON")) {
                runtime.setLastRecord(captureRecord(runtime.npc()));
            }
            logEquipmentResult(id, equipped);
            return equipped;
        } catch (Throwable throwable) {
            return failure("EQUIP_FAILED", throwable);
        }
    }

    public synchronized String equipOwnedWeaponById(String id, String fullType, long itemId) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "EQUIP_FAILED NONE_ACTIVE";
        }
        try {
            String equipped = KnoxEquipmentController.equipOwnedWeapon(
                runtime.npc().getBody(), fullType, itemId
            );
            if (equipped.startsWith("EQUIPPED_WEAPON")) {
                runtime.setLastRecord(captureRecord(runtime.npc()));
            }
            logEquipmentResult(id, equipped);
            return equipped;
        } catch (Throwable throwable) {
            return failure("EQUIP_FAILED", throwable);
        }
    }

    /** Wears one existing carried item chosen by the Lua equipment policy. */
    public synchronized String wearOwnedItem(String id, String fullType) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "WEAR_FAILED NONE_ACTIVE";
        }
        try {
            String result = KnoxEquipmentController.wearOwnedItem(
                runtime.npc().getBody(),
                fullType
            );
            if (result.startsWith("WORN_OWNED")) {
                runtime.setLastRecord(captureRecord(runtime.npc()));
            }
            logEquipmentResult(id, result);
            return result;
        } catch (Throwable throwable) {
            return failure("WEAR_FAILED", throwable);
        }
    }

    /** Wears an exact carried item and retains the ordinary native snapshot. */
    public synchronized String wearOwnedItemById(String id, String fullType, long itemId) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "WEAR_FAILED NONE_ACTIVE";
        }
        try {
            String result = KnoxEquipmentController.wearOwnedItemById(
                runtime.npc().getBody(), fullType, itemId
            );
            if (result.startsWith("WORN_OWNED")) {
                runtime.setLastRecord(captureRecord(runtime.npc()));
            }
            logEquipmentResult(id, result);
            return result;
        } catch (Throwable throwable) {
            return failure("WEAR_FAILED", throwable);
        }
    }

    /** Developer-only real-item kit used to verify the native reload/fire path. */
    public synchronized String seedFirearmTestKit(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        if (runtime == null) {
            return "FIREARM_KIT_FAILED NONE_ACTIVE";
        }
        try {
            Object inventory = runtime.npc().getBody().getClass().getMethod("getInventory").invoke(
                runtime.npc().getBody()
            );
            inventory.getClass().getMethod("AddItem", String.class).invoke(inventory, "Base.Pistol");
            inventory.getClass().getMethod("AddItem", String.class).invoke(inventory, "Base.9mmClip");
            for (int index = 0; index < 24; index++) {
                inventory.getClass().getMethod("AddItem", String.class)
                    .invoke(inventory, "Base.Bullets9mm");
            }
            runtime.setLastRecord(captureRecord(runtime.npc()));
            // Newly created Build 42 magazines start empty.  Keep the pistol,
            // empty magazine and loose rounds separate so the QA duel must use
            // the native reload/chamber path before either survivor can fire.
            String result = "FIREARM_KIT_ADDED pistol=true unloadedMagazine=true looseRounds=24";
            logEquipmentResult(id, result);
            return result;
        } catch (Throwable throwable) {
            return failure("FIREARM_KIT_FAILED", throwable);
        }
    }

    public synchronized boolean isOneFemale() {
        return isFemale(TEST_SURVIVOR_ID);
    }

    public synchronized boolean isFemale(String id) {
        KnoxNpc npc = requiredNpc(id);
        if (npc == null) {
            throw new IllegalStateException("No active NPC");
        }
        try {
            return (Boolean) npc.getBody().getClass().getMethod("isFemale")
                .invoke(npc.getBody());
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("Unable to read NPC gender", exception);
        }
    }

    public synchronized String wearOneItem(String fullType) {
        return wearItem(TEST_SURVIVOR_ID, fullType);
    }

    public synchronized String wearItem(String id, String fullType) {
        return wearItem(id, fullType, false);
    }

    public synchronized String dressItem(String id, String fullType) {
        return wearItem(id, fullType, true);
    }

    private String wearItem(String id, String fullType, boolean replaceExisting) {
        KnoxNpc npc = npc(id);
        if (npc == null) {
            return "WEAR_FAILED NONE_ACTIVE";
        }
        try {
            Object body = npc.getBody();
            Object inventory = body.getClass().getMethod("getInventory").invoke(body);
            Object item = inventory.getClass().getMethod("AddItem", String.class)
                .invoke(inventory, fullType);
            if (item == null) {
                return "WEAR_FAILED ITEM_NOT_CREATED " + fullType;
            }
            Object location = item.getClass().getMethod("getBodyLocation").invoke(item);
            if (location == null) {
                location = item.getClass().getMethod("canBeEquipped").invoke(item);
            }
            if (location == null) {
                return "WEAR_FAILED NO_BODY_LOCATION " + fullType;
            }
            Object previous = replaceExisting
                ? invokeCompatibleOne(body, "getWornItem", location)
                : null;
            invokeCompatible(body, "setWornItem", location, item);
            if (previous != null && previous != item) {
                invokeCompatibleOne(inventory, "Remove", previous);
            }
            body.getClass().getMethod("resetModelNextFrame").invoke(body);
            return "WORN " + fullType + " location=" + location;
        } catch (Throwable throwable) {
            return failure("WEAR_FAILED " + fullType, throwable);
        }
    }

    public synchronized String recreateOne() {
        KnoxNpcRuntime runtime = activeNpcs.get(TEST_SURVIVOR_ID);
        if (runtime == null) {
            return "RECREATE_FAILED NONE_ACTIVE";
        }
        try {
            KnoxNpc current = runtime.npc();
            KnoxSurvivorRecord before = captureRecord(current);
            Object square = current.getBody().getClass().getMethod("getCurrentSquare")
                .invoke(current.getBody());
            KnoxNpcFactory.remove(current);
            KnoxNpc replacement = KnoxNpcFactory.create(before.id, square);
            runtime.replaceNpc(replacement);
            restoreExactPosition(replacement.getBody(), before);
            before.appearance.restore(replacement.getBody());
            before.inventory.restore(replacement.getBody());
            if (before.health != null) {
                before.health.restore(replacement.getBody());
            }
            if (before.physiology != null) {
                before.physiology.restore(replacement.getBody());
            }
            KnoxSurvivorRecord after = captureRecord(replacement);
            // Native recreation can normalize serialized bytes while preserving
            // the gameplay state. Compare stable identity, equipment, health,
            // physiology, and position instead of requiring byte-for-byte engine
            // serialization equality.
            boolean matches = before.equivalentAfterRestore(after);
            runtime.setLastRecord(after);
            String result = "RECREATED matches=" + matches
                + " id=" + after.id
                + " location=" + after.x + "," + after.y + "," + after.z
                + " items=" + after.inventory.size()
                + " primary=" + after.inventory.primaryType();
            KnoxAgent.writeLog("NPC persistence " + result);
            return result;
        } catch (Throwable throwable) {
            return failure("RECREATE_FAILED", throwable);
        }
    }

    public synchronized String capturePersistentRecord() {
        return capturePersistentRecord(TEST_SURVIVOR_ID);
    }

    public synchronized String capturePersistentRecord(String id) {
        try {
            KnoxNpcRuntime runtime = activeNpcs.get(id);
            if (runtime == null) {
                return "";
            }
            KnoxSurvivorRecord record = captureRecord(runtime.npc());
            runtime.setLastRecord(record);
            return record.encode();
        } catch (Throwable throwable) {
            return failure("CAPTURE_FAILED", throwable);
        }
    }

    public synchronized String restorePersistentRecord(String encoded, Object square) {
        KnoxNpc restored = null;
        try {
            KnoxSurvivorRecord record = KnoxSurvivorRecord.decode(encoded);
            if (activeNpcs.containsKey(record.id)) {
                return "RESTORE_FAILED ALREADY_ACTIVE id=" + record.id;
            }
            int squareX = ((Number) square.getClass().getMethod("getX").invoke(square)).intValue();
            int squareY = ((Number) square.getClass().getMethod("getY").invoke(square)).intValue();
            int squareZ = ((Number) square.getClass().getMethod("getZ").invoke(square)).intValue();
            if (record.x != squareX || record.y != squareY || record.z != squareZ) {
                return "RESTORE_FAILED LOCATION_MISMATCH";
            }
            restored = KnoxNpcFactory.create(record.id, square);
            KnoxNpcRuntime runtime = new KnoxNpcRuntime(restored);
            restoreExactPosition(restored.getBody(), record);
            record.appearance.restore(restored.getBody());
            record.inventory.restore(restored.getBody());
            if (record.health != null) {
                record.health.restore(restored.getBody());
            }
            if (record.physiology != null) {
                record.physiology.restore(restored.getBody());
            }
            runtime.setLastRecord(captureRecord(restored));
            activeNpcs.put(record.id, runtime);
            String result = "RESTORED id=" + record.id
                + " location=" + record.x + "," + record.y + "," + record.z
                + " items=" + record.inventory.size()
                + " primary=" + record.inventory.primaryType()
                + " appearance=" + record.appearance.summary()
                + " " + (record.health == null ? "health=migrated_default" : record.health.summary())
                + " " + (record.physiology == null
                    ? "physiology=migrated_default"
                    : record.physiology.summary());
            KnoxAgent.writeLog("NPC persistence " + result);
            return result;
        } catch (Throwable throwable) {
            if (restored != null) {
                try {
                    KnoxNpcFactory.remove(restored);
                } catch (Throwable cleanupFailure) {
                    KnoxAgent.writeLog(
                        "ERROR NPC restore cleanup failed "
                            + rootCause(cleanupFailure).getClass().getName()
                    );
                }
            }
            return failure("RESTORE_FAILED", throwable);
        }
    }

    /** One complete record validation/decode for all coordinates in a population scan. */
    public synchronized Map<String, Integer> persistentRecordLocation(String encoded) {
        KnoxSurvivorRecord record = KnoxSurvivorRecord.decode(encoded);
        return Map.of("x", record.x, "y", record.y, "z", record.z);
    }

    public synchronized int persistentRecordX(String encoded) {
        return KnoxSurvivorRecord.decode(encoded).x;
    }

    public synchronized int persistentRecordY(String encoded) {
        return KnoxSurvivorRecord.decode(encoded).y;
    }

    public synchronized int persistentRecordZ(String encoded) {
        return KnoxSurvivorRecord.decode(encoded).z;
    }

    public synchronized String persistentRecordId(String encoded) {
        return KnoxSurvivorRecord.decode(encoded).id;
    }

    public synchronized String persistentRecordInventorySummary(String encoded) {
        return KnoxSurvivorRecord.decode(encoded).inventorySummary();
    }

    public synchronized boolean storedRecordWeaponReady(String id, String encoded) {
        try {
            KnoxSurvivorRecord record = KnoxSurvivorRecord.decode(encoded);
            if (!record.id.equals(id) || activeNpcs.containsKey(id)) return false;
            return record.inventory.hasReadyPrimaryWeapon(Class.forName("zombie.inventory.InventoryItem"));
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            // Unsupported/missing items and legacy snapshots defer dispatch.
            return false;
        }
    }

    /**
     * Removes one exact item from an unloaded survivor record. A blank response
     * means no matching item was present, so callers can leave persistent needs
     * unchanged rather than inventing a consumed resource.
     */
    public synchronized String consumePersistentRecordItem(String encoded, String fullType) {
        return KnoxSurvivorRecord.decode(encoded).consumeInventoryItem(fullType);
    }

    public synchronized Map<String, Object> consumePersistentRecordSupply(String encoded, String kind, double amount) {
        return consumePersistentRecordSupply(encoded, kind, amount, null, 1);
    }

    public synchronized Map<String, Object> consumePersistentRecordBaseSupply(String encoded, String kind, double amount, String baseId, int reserve) {
        if (baseId == null || baseId.isBlank()) return null;
        return consumePersistentRecordSupply(encoded, kind, amount, baseId, reserve);
    }

    private Map<String, Object> consumePersistentRecordSupply(String encoded, String kind, double amount, String baseId, int reserve) {
        try {
            KnoxSurvivorRecord record = KnoxSurvivorRecord.decode(encoded);
            if (activeNpcs.containsKey(record.id)) return null;
            KnoxInventorySnapshot.Consumption used = record.inventory.consumeSupply(
                kind, amount, Class.forName("zombie.inventory.InventoryItem"), baseId, reserve);
            if (used == null) return null;
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("record", record.withInventory(used.inventory()));
            result.put("hungerRelief", used.hungerRelief());
            result.put("thirstRelief", used.thirstRelief());
            result.put("itemType", used.type());
            return result;
        } catch (ReflectiveOperationException | RuntimeException invalidStoredSupply) {
            // The original encoded inventory remains untouched. Missing mod types
            // and unsupported item callbacks must not grant food/water relief.
            return null;
        }
    }

    /** Moves only a stored record after unloaded simulation selects a loaded safe square. */
    public synchronized String relocatePersistentRecord(
        String encoded,
        int x,
        int y,
        int z
    ) {
        return KnoxSurvivorRecord.decode(encoded).relocated(x, y, z);
    }

    public synchronized int activeCount() {
        return activeNpcs.size();
    }

    public synchronized String activeIds() {
        return String.join(",", activeNpcs.keySet());
    }

    public synchronized String renderDiagnostics() {
        if (activeNpcs.isEmpty()) {
            return "RENDER_DIAGNOSTICS NONE_ACTIVE";
        }
        StringBuilder result = new StringBuilder("RENDER_DIAGNOSTICS");
        for (Map.Entry<String, KnoxNpcRuntime> entry : activeNpcs.entrySet()) {
            try {
                result.append(" [")
                    .append(entry.getKey())
                    .append(' ')
                    .append(KnoxNpcFactory.describeRenderBinding(entry.getValue().npc()))
                    .append(']');
            } catch (Throwable throwable) {
                result.append(" [")
                    .append(entry.getKey())
                    .append(" ERROR ")
                    .append(rootCause(throwable).getMessage())
                    .append(']');
            }
        }
        return result.toString();
    }

    public synchronized String equipmentStatus() {
        KnoxNpc npc = npc(TEST_SURVIVOR_ID);
        if (npc == null) {
            return "NONE_ACTIVE";
        }
        try {
            KnoxSurvivorRecord record = captureRecord(npc);
            return "ACTIVE id=" + record.id
                + " location=" + record.x + "," + record.y + "," + record.z
                + " items=" + record.inventory.size()
                + " primary=" + record.inventory.primaryType();
        } catch (Throwable throwable) {
            return failure("STATUS_FAILED", throwable);
        }
    }

    public synchronized String status() {
        return status(TEST_SURVIVOR_ID);
    }

    public synchronized String status(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        return runtime == null ? "NONE_ACTIVE" : runtime.status();
    }

    public synchronized void abandonForEnvironmentChange() {
        com.knoxsurvivors.agent.KnoxHumanCombatGate.clearPlayerAttacks();
        if (activeNpcs.isEmpty()) {
            return;
        }
        for (KnoxNpcRuntime runtime : activeNpcs.values()) {
            String description = runtime.npc().describe();
            runtime.reset();
            KnoxAgent.writeLog(
                "NPC probe ABANDONED_STALE_REFERENCE "
                    + description
                    + " environmentChanged=true"
            );
        }
        activeNpcs.clear();
    }

    private static KnoxSurvivorRecord captureRecord(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        Object square = body.getClass().getMethod("getCurrentSquare").invoke(body);
        float positionX = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
        float positionY = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
        float positionZ = ((Number) body.getClass().getMethod("getZ").invoke(body)).floatValue();
        if (!Float.isFinite(positionX) || !Float.isFinite(positionY) || !Float.isFinite(positionZ)) {
            throw new IllegalStateException("NPC has no finite position to persist");
        }

        int x;
        int y;
        int z;
        if (square != null) {
            x = ((Number) square.getClass().getMethod("getX").invoke(square)).intValue();
            y = ((Number) square.getClass().getMethod("getY").invoke(square)).intValue();
            z = ((Number) square.getClass().getMethod("getZ").invoke(square)).intValue();
        } else {
            // A streamed-out IsoPlayer can lose getCurrentSquare() before Lua's next
            // population pass. Its body still retains the last world position, so use
            // that position as a transactional persistence fallback instead of losing
            // the survivor or looping CAPTURE_FAILED forever.
            x = (int) Math.floor(positionX);
            y = (int) Math.floor(positionY);
            z = (int) Math.floor(positionZ);
            KnoxAgent.writeLog(
                "NPC persistence capture fallback id=" + npc.getId()
                    + " reason=no_current_square position="
                    + positionX + "," + positionY + "," + positionZ
            );
        }
        return new KnoxSurvivorRecord(
            npc.getId(),
            x,
            y,
            z,
            positionX,
            positionY,
            KnoxAppearanceSnapshot.capture(body),
            KnoxInventorySnapshot.capture(body),
            KnoxHealthSnapshot.capture(body),
            KnoxPhysiologySnapshot.capture(body)
        );
    }

    private static void restoreExactPosition(Object body, KnoxSurvivorRecord record)
        throws ReflectiveOperationException {
        body.getClass().getMethod("setX", float.class).invoke(body, record.positionX);
        body.getClass().getMethod("setY", float.class).invoke(body, record.positionY);
        body.getClass().getMethod("setMovingSquareNow").invoke(body);
    }

    private static Object invokeCompatible(
        Object target,
        String name,
        Object firstArgument,
        Object secondArgument
    ) throws ReflectiveOperationException {
        for (java.lang.reflect.Method method : target.getClass().getMethods()) {
            if (!method.getName().equals(name) || method.getParameterCount() != 2) {
                continue;
            }
            Class<?>[] types = method.getParameterTypes();
            if (types[0].isInstance(firstArgument) && types[1].isInstance(secondArgument)) {
                return method.invoke(target, firstArgument, secondArgument);
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }

    private static Object invokeCompatibleOne(Object target, String name, Object argument)
        throws ReflectiveOperationException {
        for (java.lang.reflect.Method method : target.getClass().getMethods()) {
            if (!method.getName().equals(name) || method.getParameterCount() != 1) {
                continue;
            }
            Class<?> type = method.getParameterTypes()[0];
            if (argument == null || type.isInstance(argument)) {
                return method.invoke(target, argument);
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }

    private static String failure(String prefix, Throwable throwable) {
        Throwable cause = rootCause(throwable);
        String result = prefix + " " + throwable.getClass().getName() + ": "
            + throwable.getMessage();
        if (cause != throwable) {
            result += " root=" + cause.getClass().getName() + ": " + cause.getMessage();
        }
        KnoxAgent.writeLog("ERROR NPC probe " + result);
        return result;
    }

    /**
     * An unarmed survivor is a normal gameplay state, not an equipment failure.
     * Keep meaningful equipment transitions in the diagnostic log without producing
     * repeated long-session noise while autonomy asks an unarmed survivor to fight.
     */
    private static void logEquipmentResult(String id, String result) {
        if (!"NO_MELEE_WEAPON".equals(result)) {
            KnoxAgent.writeLog("NPC equipment id=" + id + " " + result);
        }
    }

    private KnoxNpc npc(String id) {
        KnoxNpcRuntime runtime = activeNpcs.get(id);
        return runtime == null ? null : runtime.npc();
    }

    private KnoxNpc requiredNpc(String id) {
        KnoxNpc npc = npc(id);
        if (npc == null) {
            throw new IllegalStateException("No active NPC: " + id);
        }
        return npc;
    }

    private static boolean validId(String id) {
        return id != null && id.matches("[A-Za-z0-9_-]{1,64}");
    }

    private static Throwable rootCause(Throwable throwable) {
        Throwable current = throwable;
        while (current.getCause() != null && current.getCause() != current) {
            current = current.getCause();
        }
        return current;
    }
}
