package com.knoxsurvivors.npc;

import com.knoxsurvivors.engine.KnoxIsoPlayerShellDefinition;
import java.lang.reflect.Array;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/** Constructs the smallest off-slot IsoPlayer body needed for the M1 lifecycle probe. */
final class KnoxNpcFactory {
    private static final String ISO_PLAYER_CLASS = "zombie.characters.IsoPlayer";
    private static final String GRID_SQUARE_CLASS = "zombie.iso.IsoGridSquare";

    private KnoxNpcFactory() {
    }

    static KnoxNpc create(String id, Object square) throws ReflectiveOperationException {
        requireClass(square, GRID_SQUARE_CLASS, "spawn square");

        ClassLoader loader = square.getClass().getClassLoader();
        Class<?> isoPlayerClass = Class.forName(ISO_PLAYER_CLASS, false, loader);
        Class<?> isoPlayerShellClass = KnoxIsoPlayerShellDefinition.getOrDefine(loader);
        Class<?> isoCellClass = Class.forName("zombie.iso.IsoCell", false, loader);
        Class<?> survivorDescClass = Class.forName("zombie.characters.SurvivorDesc", false, loader);
        Class<?> survivorFactoryClass = Class.forName(
            "zombie.characters.SurvivorFactory",
            false,
            loader
        );
        Class<?> modelManagerClass = Class.forName(
            "zombie.core.skinnedmodel.ModelManager",
            false,
            loader
        );

        Object[] localPlayersBefore = snapshotLocalPlayers(isoPlayerClass);
        Object playerInstanceBefore = isoPlayerClass.getMethod("getInstance").invoke(null);
        Object expectedPlayerInstance = localPlayersBefore.length > 0
            && localPlayersBefore[0] != null
            ? localPlayersBefore[0]
            : playerInstanceBefore;
        Object cell = invoke(square, "getCell");
        int x = ((Number) invoke(square, "getX")).intValue();
        int y = ((Number) invoke(square, "getY")).intValue();
        int z = ((Number) invoke(square, "getZ")).intValue();
        Object descriptor = survivorFactoryClass.getMethod("CreateSurvivor").invoke(null);

        Constructor<?> constructor = isoPlayerShellClass.getConstructor(
            isoCellClass,
            survivorDescClass,
            int.class,
            int.class,
            int.class,
            boolean.class
        );
        Object body;
        try {
            body = constructor.newInstance(cell, descriptor, x, y, z, false);
        } finally {
            // IsoPlayer's constructor assigns every new instance to the global
            // singleton, even when the object will never own a local-player slot.
            // Restore local player 0 immediately so UI, camera, Lua, and the shell's
            // later update guard begin from the correct owner.
            isoPlayerClass.getMethod("setInstance", isoPlayerClass)
                .invoke(null, expectedPlayerInstance);
        }

        isoPlayerClass.getMethod("setNpc", boolean.class).invoke(body, true);
        isoPlayerClass.getField("remote").setBoolean(body, false);
        isoPlayerClass.getField("playerIndex").setInt(body, allocateOffSlotPlayerIndex(isoPlayerClass));
        isoPlayerClass.getField("serverPlayerIndex").setInt(body, -1);
        isoPlayerClass.getMethod("setOnlineID", short.class).invoke(body, (short) -1);
        isoPlayerClass.getMethod("setUsername", String.class).invoke(body, "Knox Survivor");
        isoPlayerClass.getMethod("setGhostMode", boolean.class).invoke(body, false);

        invoke(body, "setCurrent", square.getClass(), square);
        invoke(body, "setMovingSquareNow");
        // This shell is a survivor, not a protected probe. Build 42 also capability-gates
        // this flag, which made its result differ between normal and debug launches.
        invoke(body, "setZombiesDontAttack", boolean.class, false);
        invoke(body, "setAlphaAndTarget", float.class, 1.0f);
        invoke(cell, "addMovingObject", classFor(body, "zombie.iso.IsoMovingObject"), body);
        Object modelManager = modelManagerClass.getField("instance").get(null);
        invoke(modelManager, "Add", classFor(body, "zombie.characters.IsoGameCharacter"), body);

        if (!sameLocalPlayers(localPlayersBefore, snapshotLocalPlayers(isoPlayerClass))) {
            safelyRemove(body);
            throw new IllegalStateException("IsoPlayer local-player slots changed during NPC creation");
        }
        Object playerInstanceAfter = isoPlayerClass.getMethod("getInstance").invoke(null);
        if (playerInstanceAfter != expectedPlayerInstance) {
            isoPlayerClass.getMethod("setInstance", isoPlayerClass)
                .invoke(null, expectedPlayerInstance);
            safelyRemove(body);
            throw new IllegalStateException("IsoPlayer global instance changed during NPC creation");
        }

        return new KnoxNpc(id, body, x, y, z);
    }

    static void remove(KnoxNpc npc) throws ReflectiveOperationException {
        safelyRemove(npc.getBody());
    }

    static void moveTo(KnoxNpc npc, Object square) throws ReflectiveOperationException {
        requireClass(square, GRID_SQUARE_CLASS, "movement target square");
        float x = ((Number) invoke(square, "getX")).floatValue() + 0.5f;
        float y = ((Number) invoke(square, "getY")).floatValue() + 0.5f;
        float z = ((Number) invoke(square, "getZ")).floatValue();
        invoke(
            npc.getBody(),
            "pathToLocationF",
            float.class,
            float.class,
            float.class,
            x,
            y,
            z
        );
    }

    static void cancelMovement(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        ReflectiveOperationException firstFailure = null;
        try {
            Object pathfinder = invoke(body, "getPathFindBehavior2");
            invoke(pathfinder, "cancel");
        } catch (ReflectiveOperationException failure) {
            firstFailure = failure;
        }
        try {
            invoke(body, "setPath2", classFor(body, "zombie.pathfind.Path"), null);
        } catch (ReflectiveOperationException failure) {
            if (firstFailure == null) {
                firstFailure = failure;
            } else {
                firstFailure.addSuppressed(failure);
            }
        }
        npc.clearMovementRoute();
        try {
            clearHumanMovementIntent(body);
        } catch (ReflectiveOperationException failure) {
            if (firstFailure == null) {
                firstFailure = failure;
            } else {
                firstFailure.addSuppressed(failure);
            }
        }
        if (firstFailure != null) {
            throw firstFailure;
        }
    }

    static void moveToRangeFromCurrentSide(
        KnoxNpc npc,
        Object target,
        Object fallbackApproachSquare,
        float desiredRange
    ) throws ReflectiveOperationException {
        requireClass(fallbackApproachSquare, GRID_SQUARE_CLASS, "fallback approach square");
        Object body = npc.getBody();
        float targetX = ((Number) invoke(target, "getX")).floatValue();
        float targetY = ((Number) invoke(target, "getY")).floatValue();
        float targetZ = ((Number) invoke(target, "getZ")).floatValue();
        float directionX = ((Number) invoke(body, "getX")).floatValue() - targetX;
        float directionY = ((Number) invoke(body, "getY")).floatValue() - targetY;
        float length = (float) Math.sqrt(directionX * directionX + directionY * directionY);
        if (length <= 0.001f) {
            float referenceX = ((Number) invoke(fallbackApproachSquare, "getX")).floatValue() + 0.5f;
            float referenceY = ((Number) invoke(fallbackApproachSquare, "getY")).floatValue() + 0.5f;
            directionX = referenceX - targetX;
            directionY = referenceY - targetY;
            length = (float) Math.sqrt(directionX * directionX + directionY * directionY);
        }
        if (length <= 0.001f) {
            throw new IllegalArgumentException("Cannot determine a current combat approach direction");
        }
        invoke(
            body,
            "pathToLocationF",
            float.class,
            float.class,
            float.class,
            targetX + directionX / length * desiredRange,
            targetY + directionY / length * desiredRange,
            targetZ
        );
    }

    static void followCharacter(KnoxNpc npc, Object target)
        throws ReflectiveOperationException {
        Object body = npc.getBody();
        Class<?> gameCharacterClass = Class.forName(
            "zombie.characters.IsoGameCharacter",
            false,
            body.getClass().getClassLoader()
        );
        if (!gameCharacterClass.isInstance(target)) {
            throw new IllegalArgumentException("Live pursuit target is not an IsoGameCharacter");
        }

        // Combat pursuit belongs entirely to PathFindBehavior2. Do not leave a Knox
        // waypoint route active beside it or the two movement owners will continually
        // replace one another with snapshots of the target's old position.
        npc.clearMovementRoute();
        body.getClass().getMethod("pathToCharacter", gameCharacterClass).invoke(body, target);
        body.getClass().getMethod("setRunning", boolean.class).invoke(body, true);
    }

    static void moveAcrossAdjacentEdge(KnoxNpc npc, Object square)
        throws ReflectiveOperationException {
        requireClass(square, GRID_SQUARE_CLASS, "adjacent crossing target square");
        Object body = npc.getBody();
        Object currentSquare = invoke(body, "getCurrentSquare");
        if (currentSquare == null) {
            throw new IllegalStateException("NPC has no current square for adjacent crossing");
        }

        int currentX = ((Number) invoke(currentSquare, "getX")).intValue();
        int currentY = ((Number) invoke(currentSquare, "getY")).intValue();
        int currentZ = ((Number) invoke(currentSquare, "getZ")).intValue();
        int targetX = ((Number) invoke(square, "getX")).intValue();
        int targetY = ((Number) invoke(square, "getY")).intValue();
        int targetZ = ((Number) invoke(square, "getZ")).intValue();
        if (targetZ != currentZ || Math.abs(targetX - currentX) + Math.abs(targetY - currentY) != 1) {
            throw new IllegalArgumentException(
                "Adjacent crossing target must be one cardinal edge from the NPC"
            );
        }

        Object pathfinder = invoke(body, "getPathFindBehavior2");
        invoke(pathfinder, "cancel");
        invoke(body, "setPath2", classFor(body, "zombie.pathfind.Path"), null);
        clearHumanMovementIntent(body);

        List<float[]> exactRoute = new ArrayList<>(1);
        exactRoute.add(new float[] { targetX + 0.5f, targetY + 0.5f, targetZ });
        npc.setMovementRoute(exactRoute);
    }

    static String tickMovement(KnoxNpc npc) throws ReflectiveOperationException {
        return tickMovement(npc, 0.0f, "normal");
    }

    static String tickMovement(KnoxNpc npc, float remainingDistance, String pace)
        throws ReflectiveOperationException {
        Object body = npc.getBody();
        String nativeState = (String) invoke(body, "getCurrentStateName");
        completeNativeWindowOpening(npc, body, nativeState);
        // Build 42's isClimbing flag is not the action-context owner of fence,
        // wall and window traversal. Observe both native states before touching
        // the route: even a reached node must wait for the crossing to finish.
        if (KnoxTraversalPolicy.nativeTraversalBusy(
            (Boolean) invoke(body, "isClimbing"),
            nativeState,
            (String) invoke(body, "getCurrentActionContextStateName")
        )) {
            npc.setMovementTraversalState("CLIMBING");
            return "Transition:CLIMBING";
        }
        closeOpenedDoorBehind(npc);
        Object pathfinder = invoke(body, "getPathFindBehavior2");

        if (npc.movementArea != null && !npc.movementArea.allowsPosition(
            ((Number) invoke(body, "getX")).floatValue(),
            ((Number) invoke(body, "getY")).floatValue(),
            ((Number) invoke(body, "getZ")).floatValue())) {
            clearHumanMovementIntent(body);
            return "FailedDutyAreaDisplacement";
        }
        if (npc.hasMovementRoute()) {
            return driveCapturedRoute(npc, remainingDistance, pace);
        }

        Object result = invoke(pathfinder, "update");
        String state = result instanceof Enum<?> ? ((Enum<?>) result).name() : String.valueOf(result);
        if ("Working".equals(state)) {
            if (captureEngineRoute(npc, body, pathfinder)) {
                return driveCapturedRoute(npc, remainingDistance, pace);
            }
            clearHumanMovementIntent(body);
            if (npc.movementArea != null && npc.movementArea.isRejected()) return "FailedDutyAreaRoute";
        } else {
            clearHumanMovementIntent(body);
        }
        return state;
    }

    static boolean hasNativeTraversalOwner(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        return KnoxTraversalPolicy.nativeTraversalBusy(
            (Boolean) invoke(body, "isClimbing"),
            (String) invoke(body, "getCurrentStateName"),
            (String) invoke(body, "getCurrentActionContextStateName")
        );
    }

    static void observeNativeAction(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        completeNativeWindowOpening(npc, body, (String) invoke(body, "getCurrentStateName"));
    }

    /** Complete only the native-success world step omitted for off-slot players.
     * Native animation, locking and movement remain owned by OpenWindowState.
     */
    private static void completeNativeWindowOpening(KnoxNpc npc, Object body, String nativeState)
        throws ReflectiveOperationException {
        Object window = npc.getTraversalInteractionTarget();
        if (window == null || !"OPEN_ATTEMPTED".equals(npc.getTraversalInteractionStage())
            || nativeState == null || !nativeState.contains("OpenWindowState")) {
            return;
        }
        // A native success token can outlive actor death/detachment for a
        // teardown frame. It cannot authorize a world effect without the
        // same live, loaded character still owning the opening action.
        if ((Boolean) invoke(body, "isDead") || invoke(body, "getCurrentSquare") == null) return;
        String receipt = String.valueOf(invoke(body, "getVariableString", String.class, "StopAfterAnimLooped"));
        if (!"success".equalsIgnoreCase(receipt)) return;
        Class<?> openingState = classFor(body, "zombie.ai.states.OpenWindowState");
        Object key = openingState.getField("WINDOW").get(null);
        Object nativeWindow = invoke(body, "get", classFor(body, "zombie.ai.State$Param"), key);
        if (nativeWindow != window || ((Number) invoke(window, "getObjectIndex")).intValue() == -1) return;
        if (!(Boolean) invoke(window, "IsOpen")) {
            invoke(window, "ToggleWindow", classFor(body, "zombie.characters.IsoGameCharacter"), body);
        }
        if ((Boolean) invoke(window, "IsOpen")) {
            npc.setTraversalInteractionStage("OPEN_COMPLETED");
            npc.setMovementTraversalState("COMPLETED_WINDOW_OPEN");
        } else {
            // Do not retry a native world mutation every tick or report success.
            // Let the native state exit; the existing route then rejects the edge.
            npc.setTraversalInteractionStage("OPEN_COMPLETION_FAILED");
        }
    }

    /**
     * Close only a self-opened door after crossing its original edge, while
     * still in native interaction reach. Leave occupied doorways open; never
     * chase a stale door or close one remotely after the actor has walked on.
     */
    static void closeOpenedDoorBehind(KnoxNpc npc) {
        if (!npc.hasOpenedDoor()) {
            return;
        }
        try {
            Object body = npc.getBody();
            if (hasNativeTraversalOwner(npc)) return;
            Object door = npc.getOpenedDoor();
            Object square = invoke(door, "getSquare");
            Object current = invoke(body, "getCurrentSquare");
            boolean north = (Boolean) invoke(door, "getNorth");
            if (square == null || current == null
                || ((Number) invoke(door, "getObjectIndex")).intValue() == -1
                || (Boolean) invoke(door, "isDestroyed") || !(Boolean) invoke(door, "IsOpen")
                || (Boolean) invoke(door, "isBarricaded") || (Boolean) invoke(body, "isDead")
                || north != npc.getOpenedDoorNorth()
                || ((Number) invoke(square, "getX")).intValue() != npc.getOpenedDoorX()
                || ((Number) invoke(square, "getY")).intValue() != npc.getOpenedDoorY()
                || ((Number) invoke(square, "getZ")).intValue() != npc.getOpenedDoorZ()
                || ((Number) invoke(body, "getZ")).floatValue() != npc.getOpenedDoorZ()
                || !(Boolean) invoke(door, "isAdjacentToSquare",
                    classFor(body, "zombie.iso.IsoGridSquare"), current)) {
                npc.clearOpenedDoor();
                return;
            }
            Class<?> direction = classFor(body, "zombie.iso.IsoDirections");
            Object other = invoke(square, "getAdjacentSquare", direction,
                direction.getField(north ? "N" : "W").get(null));
            // Both squares must still be loaded. Restrict automatic closing to
            // the two actual edge tiles, even if native reach permits diagonals.
            if (other == null || (current != square && current != other)) {
                npc.clearOpenedDoor();
                return;
            }
            boolean positiveSide = current == square;
            if (positiveSide == npc.getOpenedDoorFromPositiveSide()) return;
            float axis = ((Number) invoke(body, north ? "getY" : "getX")).floatValue();
            int edge = north ? npc.getOpenedDoorY() : npc.getOpenedDoorX();
            // Reach the landing tile's center before swinging the door behind
            // the actor; crossing a square boundary alone is not clearance.
            if (!Float.isFinite(axis)) { npc.clearOpenedDoor(); return; }
            if (positiveSide ? axis < edge + 0.5f : axis > edge - 0.5f) return;
            if ((Boolean) invoke(door, "isObstructed")
                || doorwayHasOtherOccupants(square, body) || doorwayHasOtherOccupants(other, body)) return;
            invoke(door, "ToggleDoor", classFor(body, "zombie.characters.IsoGameCharacter"), body);
        } catch (Throwable ignored) {
            // Stale, streamed-out or destroyed door: drop the record either way.
        }
        npc.clearOpenedDoor();
    }

    private static boolean doorwayHasOtherOccupants(Object square, Object body)
        throws ReflectiveOperationException {
        for (Object occupant : (java.util.Collection<?>) invoke(square, "getMovingObjects")) {
            if (occupant != body) return true;
        }
        return false;
    }

    /** Shared native opening boundary for route edges and Lua recovery. */
    static String openNativeDoor(KnoxNpc npc, Object door) throws ReflectiveOperationException {
        Object body = npc.getBody();
        if (door == null || !classFor(body, "zombie.iso.objects.IsoDoor").isInstance(door)) {
            return "FAILED_INVALID_DOOR";
        }
        if (hasNativeTraversalOwner(npc)) return "DOOR_DEFERRED NATIVE_ACTION";
        Object current = invoke(body, "getCurrentSquare");
        Object square = invoke(door, "getSquare");
        if (current == null || square == null || (Boolean) invoke(body, "isDead")
            || ((Number) invoke(door, "getObjectIndex")).intValue() == -1
            || (Boolean) invoke(door, "isDestroyed")
            || ((Number) invoke(body, "getZ")).floatValue() != ((Number) invoke(square, "getZ")).intValue()
            || !(Boolean) invoke(door, "isAdjacentToSquare", classFor(body, "zombie.iso.IsoGridSquare"), current)) {
            return "FAILED_DOOR_OUT_OF_REACH";
        }
        boolean open = (Boolean) invoke(door, "IsOpen");
        if (open) return "CLEAR";
        if ((Boolean) invoke(door, "isBarricaded")) return "FAILED_BARRICADED_DOOR";
        if (!npc.isDoorWindowOpeningAllowed()) return "FAILED_DOOR_OPENING_DISABLED";
        npc.useTraversalInteractionTarget(door);
        invoke(door, "ToggleDoor", classFor(body, "zombie.characters.IsoGameCharacter"), body);
        if (!(Boolean) invoke(door, "IsOpen")) return "FAILED_LOCKED_DOOR";
        // Only an observed closed -> open transition grants a close-behind receipt.
        boolean north = (Boolean) invoke(door, "getNorth");
        Object openedSquare = invoke(door, "getSquare");
        int x = ((Number) invoke(openedSquare, "getX")).intValue();
        int y = ((Number) invoke(openedSquare, "getY")).intValue();
        npc.rememberOpenedDoor(door, x, y, ((Number) invoke(openedSquare, "getZ")).intValue(), north,
            ((Number) invoke(body, north ? "getY" : "getX")).floatValue() >= (north ? y : x));
        return "OPENING_DOOR";
    }

    static String describeLive(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        Object cell = invoke(body, "getCell");
        Object currentSquare = invoke(body, "getCurrentSquare");
        Object movingSquare = invoke(body, "getMovingSquare");
        boolean inCell = ((java.util.Collection<?>) invoke(cell, "getObjectList")).contains(body);
        boolean inSquare = movingSquare != null
            && ((java.util.Collection<?>) invoke(movingSquare, "getMovingObjects")).contains(body);
        float x = ((Number) invoke(body, "getX")).floatValue();
        float y = ((Number) invoke(body, "getY")).floatValue();
        float alpha = ((Number) invoke(body, "getAlpha")).floatValue();
        boolean activeModel = (Boolean) invoke(body, "hasActiveModel");
        Object pathfinder = invoke(body, "getPathFindBehavior2");
        boolean pathing = (Boolean) invoke(body, "isPathing");
        boolean pathRunning = (Boolean) invoke(body, "isPathfindRunning");
        boolean movingUsingPath = (Boolean) invoke(pathfinder, "isMovingUsingPathFind");
        boolean pathAttached = invoke(body, "getPath2") != null;
        boolean localSlotsSafe = !isInLocalPlayerSlots(body);
        boolean localPlayer = (Boolean) invoke(body, "isLocalPlayer");
        boolean running = (Boolean) invoke(body, "isRunning");
        boolean sprinting = (Boolean) invoke(body, "isSprinting");
        boolean deferredMovement = (Boolean) invoke(body, "isDeferredMovementEnabled");
        boolean animationUpdating = (Boolean) invoke(body, "isAnimationUpdatingThisFrame");
        Class<?> gameClientClass = classFor(body, "zombie.network.GameClient");
        boolean gameClient = gameClientClass.getField("client").getBoolean(null);
        boolean remote = classFor(body, ISO_PLAYER_CLASS).getField("remote").getBoolean(body);
        int playerIndex = classFor(body, ISO_PLAYER_CLASS).getField("playerIndex").getInt(body);
        Object moveDirection = classFor(body, ISO_PLAYER_CLASS).getField("playerMoveDir").get(body);
        float moveX = moveDirection.getClass().getField("x").getFloat(moveDirection);
        float moveY = moveDirection.getClass().getField("y").getFloat(moveDirection);
        Object inputComponent = invoke(body, "getCharacterInputComponent");
        Object aiComponent = getAiComponent(body);
        float strafeX = 0.0f;
        float strafeY = 0.0f;
        if (aiComponent != null) {
            Object controlVars = invoke(aiComponent, "getHumanControlVars");
            if (controlVars != null) {
                strafeX = controlVars.getClass().getField("strafeX").getFloat(controlVars);
                strafeY = controlVars.getClass().getField("strafeY").getFloat(controlVars);
            }
        }
        return "ACTIVE "
            + npc.describe()
            + " class="
            + body.getClass().getName()
            + " live="
            + x
            + ","
            + y
            + " current="
            + (currentSquare != null)
            + " moving="
            + (movingSquare != null)
            + " inCell="
            + inCell
            + " inSquare="
            + inSquare
            + " model="
            + activeModel
            + " alpha="
            + alpha
            + " pathing="
            + pathing
            + " pathRunning="
            + pathRunning
            + " movingUsingPath="
            + movingUsingPath
            + " pathAttached="
            + pathAttached
            + " localSlotsSafe="
            + localSlotsSafe
            + " localPlayer="
            + localPlayer
            + " running="
            + running
            + " sprinting="
            + sprinting
            + " remote="
            + remote
            + " playerIndex="
            + playerIndex
            + " moveDir="
            + moveX
            + ","
            + moveY
            + " strafe="
            + strafeX
            + ","
            + strafeY
            + " inputComponent="
            + (inputComponent != null)
            + " aiComponent="
            + (aiComponent != null)
            + " deferredMovement="
            + deferredMovement
            + " animationUpdating="
            + animationUpdating
            + " gameClient="
            + gameClient
            + " route="
            + npc.describeMovementRoute();
    }

    static String describeRenderBinding(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        Class<?> isoPlayerClass = classFor(body, ISO_PLAYER_CLASS);
        Object instance = isoPlayerClass.getMethod("getInstance").invoke(null);
        Object players = isoPlayerClass.getField("players").get(null);
        Object localPlayer = Array.get(players, 0);
        return "instanceIsLocal0="
            + (instance == localPlayer)
            + " local0="
            + describeRenderObject(localPlayer)
            + " npc="
            + describeRenderObject(body);
    }

    private static String describeRenderObject(Object character)
        throws ReflectiveOperationException {
        if (character == null) {
            return "null";
        }
        int playerIndex = classFor(character, ISO_PLAYER_CLASS)
            .getField("playerIndex")
            .getInt(character);
        return character.getClass().getSimpleName()
            + "{index="
            + playerIndex
            + ",localPlayer="
            + invoke(character, "isLocalPlayer")
            + ",invisible="
            + invoke(character, "isInvisible")
            + ",spriteInvisible="
            + invoke(character, "isSpriteInvisible")
            + ",alpha="
            + invoke(character, "getAlpha", int.class, 0)
            + ",targetAlpha="
            + invoke(character, "getTargetAlpha", int.class, 0)
            + ",activeModel="
            + invoke(character, "hasActiveModel")
            + ",modelManager="
            + invoke(character, "isAddedToModelManager")
            + "}";
    }

    private static boolean captureEngineRoute(KnoxNpc npc, Object body, Object pathfinder)
        throws ReflectiveOperationException {
        Object path = invoke(body, "getPath2");
        if (path == null) {
            return false;
        }

        int size = ((Number) invoke(path, "size")).intValue();
        if (size <= 0) {
            return false;
        }

        List<float[]> nodes = new ArrayList<>(size);
        for (int index = 0; index < size; index++) {
            Object node = invoke(path, "getNode", int.class, index);
            nodes.add(
                new float[] {
                    node.getClass().getField("x").getFloat(node),
                    node.getClass().getField("y").getFloat(node),
                    node.getClass().getField("z").getFloat(node),
                }
            );
        }

        invoke(pathfinder, "cancel");
        invoke(body, "setPath2", classFor(body, "zombie.pathfind.Path"), null);
        return acceptMovementRoute(npc,
            ((Number) invoke(body, "getX")).floatValue(),
            ((Number) invoke(body, "getY")).floatValue(),
            ((Number) invoke(body, "getZ")).floatValue(), nodes);
    }

    static boolean acceptMovementRoute(KnoxNpc npc, float x, float y, float z, List<float[]> nodes) {
        if (npc.movementArea != null && !npc.movementArea.acceptRoute(x, y, z, nodes)) {
            npc.clearMovementRoute();
            return false;
        }
        npc.setMovementRoute(nodes);
        return true;
    }

    private static String driveCapturedRoute(KnoxNpc npc, float remainingDistance, String pace)
        throws ReflectiveOperationException {
        Object body = npc.getBody();
        float x = ((Number) invoke(body, "getX")).floatValue();
        float y = ((Number) invoke(body, "getY")).floatValue();
        Object currentSquare = invoke(body, "getCurrentSquare");
        if (currentSquare == null) {
            clearHumanMovementIntent(body);
            return "FailedNoCurrentSquare";
        }
        int z = ((Number) invoke(currentSquare, "getZ")).intValue();

        float[] node = npc.currentMovementNode();
        while (node != null && KnoxMovementGeometry.nodeReached(
            x, y, z, node[0], node[1], node[2], npc.movementNodeTolerance()
        )) {
            npc.advanceMovementRoute();
            node = npc.currentMovementNode();
        }

        if (node == null) {
            npc.setMovementTraversalState("ARRIVED");
            clearHumanMovementIntent(body);
            return "Succeeded";
        }

        String traversal = handleRouteTransition(npc, body, node);
        npc.setMovementTraversalState(traversal);
        if (traversal.startsWith("FAILED_")) {
            int currentX = (int) Math.floor(x);
            int currentY = (int) Math.floor(y);
            int currentZ = (int) Math.floor(
                ((Number) invoke(body, "getZ")).floatValue()
            );
            npc.rememberTraversalFailure(
                currentX,
                currentY,
                currentZ,
                (int) Math.floor(node[0]),
                (int) Math.floor(node[1]),
                (int) Math.floor(node[2]),
                traversal
            );
            clearHumanMovementIntent(body);
            return "FailedObstacle:" + traversal;
        }
        if (!"CLEAR".equals(traversal)) {
            clearHumanMovementIntent(body);
            return "Transition:" + traversal;
        }

        float routeDistance = Math.max(
            remainingDistance,
            npc.remainingMovementDistance(x, y, z)
        );
        applyHumanMovementIntent(npc, body, node[0], node[1], routeDistance, pace);
        return "ManualRoute";
    }

    private static String handleRouteTransition(KnoxNpc npc, Object body, float[] node)
        throws ReflectiveOperationException {
        Object currentSquare = invoke(body, "getCurrentSquare");
        Object cell = invoke(body, "getCell");
        if (currentSquare == null || cell == null) {
            return "FAILED_NO_CURRENT_SQUARE";
        }

        int currentX = ((Number) invoke(currentSquare, "getX")).intValue();
        int currentY = ((Number) invoke(currentSquare, "getY")).intValue();
        int currentZ = ((Number) invoke(currentSquare, "getZ")).intValue();
        int nextX = (int) Math.floor(node[0]);
        int nextY = (int) Math.floor(node[1]);
        int nextZ = (int) Math.floor(node[2]);
        int deltaX = nextX - currentX;
        int deltaY = nextY - currentY;

        if (deltaX == 0 && deltaY == 0 && nextZ == currentZ) {
            return "CLEAR";
        }
        // Build 42's native path contains the stair-spanning XYZ nodes. Keep
        // consuming that route through ordinary human movement; the engine's
        // stair geometry updates character Z as the survivor walks the stairs.
        // Never snap or mutate Z here.
        if (nextZ != currentZ) {
            return Math.abs(nextZ - currentZ) == 1
                ? "CLEAR"
                : "FAILED_INVALID_Z_CHANGE";
        }
        if (Math.abs(deltaX) > 1 || Math.abs(deltaY) > 1) {
            return "CLEAR";
        }

        Object nextSquare = invoke(
            cell,
            "getGridSquare",
            int.class,
            int.class,
            int.class,
            nextX,
            nextY,
            nextZ
        );
        if (nextSquare == null) {
            return "FAILED_UNLOADED_NEXT_SQUARE";
        }

        if (Math.abs(deltaX) + Math.abs(deltaY) != 1) {
            boolean blocked = (Boolean) invoke(
                currentSquare,
                "isBlockedTo",
                currentSquare.getClass(),
                nextSquare
            );
            return blocked ? "FAILED_BLOCKED_DIAGONAL" : "CLEAR";
        }

        Object door = invoke(currentSquare, "getDoorTo", currentSquare.getClass(), nextSquare);
        Object window = invoke(currentSquare, "getWindowTo", currentSquare.getClass(), nextSquare);
        boolean entryChanged = door != null && (Boolean) invoke(door, "IsOpen")
            || window != null && !(Boolean) invoke(window, "isBarricaded")
                && ((Boolean) invoke(window, "IsOpen") || (Boolean) invoke(window, "isSmashed"));
        if (!entryChanged && npc.isTraversalCoolingDown(
            currentX,
            currentY,
            currentZ,
            nextX,
            nextY,
            nextZ
        )) {
            return "FAILED_EDGE_COOLDOWN";
        }

        if (door != null) {
            npc.useTraversalInteractionTarget(door);
            boolean open = (Boolean) invoke(door, "IsOpen");
            boolean barricaded = (Boolean) invoke(door, "isBarricaded");
            KnoxTraversalPolicy.DoorAction action = KnoxTraversalPolicy.doorAction(
                open,
                barricaded
            );
            if (action == KnoxTraversalPolicy.DoorAction.PASS) {
                return "CLEAR";
            }
            if (action == KnoxTraversalPolicy.DoorAction.FAIL_BARRICADED) {
                return "FAILED_BARRICADED_DOOR";
            }
            if (!open && !npc.isDoorWindowOpeningAllowed()) {
                return "FAILED_DOOR_OPENING_DISABLED";
            }
            faceObject(body, door);
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_DOOR";
            }
            return openNativeDoor(npc, door);
        }

        if (window != null) {
            if (!npc.isClimbingAllowed()) {
                return "FAILED_CLIMBING_DISABLED";
            }
            npc.useTraversalInteractionTarget(window);
            String characterState = String.valueOf(invoke(body, "getCurrentStateName"));
            if (characterState.contains("OpenWindowState")) {
                return "OPENING_WINDOW";
            }
            if (characterState.contains("SmashWindowState")) {
                return "SMASHING_WINDOW";
            }

            boolean open = (Boolean) invoke(window, "IsOpen");
            boolean smashed = (Boolean) invoke(window, "isSmashed");
            boolean barricaded = (Boolean) invoke(window, "isBarricaded");
            boolean canClimb = (Boolean) invoke(
                window,
                "canClimbThrough",
                classFor(body, "zombie.characters.IsoGameCharacter"),
                body
            );
            faceObject(body, window);
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_WINDOW";
            }

            KnoxTraversalPolicy.WindowAction action = KnoxTraversalPolicy.windowAction(
                open,
                smashed,
                barricaded,
                canClimb,
                npc.getTraversalInteractionStage()
            );
            if (action == KnoxTraversalPolicy.WindowAction.FAIL_BARRICADED) {
                return "FAILED_BARRICADED_WINDOW";
            }
            if (action == KnoxTraversalPolicy.WindowAction.FAIL_UNUSABLE) {
                return "FAILED_LOCKED_OR_UNUSABLE_WINDOW";
            }
            if (!open && !smashed && !npc.isDoorWindowOpeningAllowed()) {
                return "FAILED_WINDOW_OPENING_DISABLED";
            }
            if (action == KnoxTraversalPolicy.WindowAction.TRY_NATIVE_OPEN) {
                invoke(
                    body,
                    "openWindow",
                    classFor(body, "zombie.iso.objects.IsoWindow"),
                    window
                );
                npc.setTraversalInteractionStage("OPEN_ATTEMPTED");
                return "STARTED_WINDOW_OPEN";
            }
            invoke(
                body,
                "climbThroughWindow",
                classFor(body, "zombie.iso.objects.IsoWindow"),
                window
            );
            return "STARTED_WINDOW_CLIMB";
        }

        Object windowThumpable = invoke(
            currentSquare,
            "getWindowThumpableTo",
            currentSquare.getClass(),
            nextSquare
        );
        if (windowThumpable != null) {
            npc.useTraversalInteractionTarget(windowThumpable);
            if (!npc.isClimbingAllowed()) {
                return "FAILED_CLIMBING_DISABLED";
            }
            if ((Boolean) invoke(windowThumpable, "isBarricaded")) {
                return "FAILED_BARRICADED_WINDOW";
            }
            faceObject(body, windowThumpable);
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_WINDOW";
            }
            invoke(
                body,
                "climbThroughWindow",
                classFor(body, "zombie.iso.objects.IsoThumpable"),
                windowThumpable
            );
            return "STARTED_WINDOW_CLIMB";
        }

        Object windowFrame = invoke(
            currentSquare,
            "getWindowFrameTo",
            currentSquare.getClass(),
            nextSquare
        );
        if (windowFrame != null) {
            npc.useTraversalInteractionTarget(windowFrame);
            if (!npc.isClimbingAllowed()) {
                return "FAILED_CLIMBING_DISABLED";
            }
            invoke(
                body,
                "climbThroughWindowFrame",
                classFor(body, "zombie.iso.objects.IsoWindowFrame"),
                windowFrame
            );
            return "STARTED_WINDOW_FRAME_CLIMB";
        }

        Object direction = cardinalDirection(body, deltaX, deltaY);
        boolean hoppable = (Boolean) invoke(
            currentSquare,
            "isHoppableTo",
            currentSquare.getClass(),
            nextSquare
        );
        if (hoppable) {
            npc.useTraversalInteractionTarget(currentSquare);
            if (!npc.isClimbingAllowed()) {
                return "FAILED_CLIMBING_DISABLED";
            }
            // The native vault transition is asynchronous.  A second route
            // tick can arrive before the native climb state starts, and
            // issuing climbOverFence again in that gap restarts the animation
            // or leaves the body pressed against the edge until the route
            // watchdog reports FailedStuck.  Keep one request per edge and
            // let the normal movement watchdog handle a genuinely failed
            // native climb.  A successful crossing changes currentSquare and
            // releases this interaction through useTraversalInteractionTarget.
            if ("CLIMB_ATTEMPTED".equals(npc.getTraversalInteractionStage())) {
                return "ManualRoute";
            }
            // isHoppableTo reports a fence-like edge, but does not guarantee
            // that this survivor can vault it. Use Build 42's player-aware
            // check before starting the native climb animation.
            boolean canHop = (Boolean) invoke(
                currentSquare,
                "isPlayerAbleToHopWallTo",
                classFor(body, "zombie.iso.IsoDirections"),
                classFor(body, "zombie.iso.IsoGridSquare"),
                direction,
                nextSquare
            );
            if (!canHop) {
                return "FAILED_UNCLIMBABLE_FENCE";
            }
            // Build 42 calculates a vault-fall chance from the RUN/SPRINT
            // state and the HeavyLoad moodle. NPC route pacing can leave those
            // flags set while the survivor is already at the fence, which
            // makes a normal carried load look overweight and repeatedly
            // flops a climb that should succeed. Vault at walking pace; the
            // next route tick restores the requested pace after the state ends.
            clearHumanMovementIntent(body);
            invoke(
                body,
                "faceDirection",
                classFor(body, "zombie.iso.IsoDirections"),
                direction
            );
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_FENCE";
            }
            invoke(
                body,
                "climbOverFence",
                classFor(body, "zombie.iso.IsoDirections"),
                direction
            );
            npc.setTraversalInteractionStage("CLIMB_ATTEMPTED");
            return "STARTED_FENCE_CLIMB";
        }

        Object wallHoppable = invoke(
            currentSquare,
            "getWallHoppableTo",
            currentSquare.getClass(),
            nextSquare
        );
        if (wallHoppable != null) {
            npc.useTraversalInteractionTarget(wallHoppable);
            if (!npc.isClimbingAllowed()) {
                return "FAILED_CLIMBING_DISABLED";
            }
            // Wall climbing has the same asynchronous native transition as a
            // fence vault. Do not enqueue a second climb while the first one
            // is still resolving.
            if ("CLIMB_ATTEMPTED".equals(npc.getTraversalInteractionStage())) {
                return "ManualRoute";
            }
            // IsoPlayer.canClimbOverWall rejects sprinting before checking the
            // wall. Release approach input first, just as a player must stop
            // sprinting to climb; retain all native safety/fitness checks.
            clearHumanMovementIntent(body);
            invoke(body, "faceDirection", classFor(body, "zombie.iso.IsoDirections"), direction);
            if ((Boolean) invoke(body, "shouldBeTurning")) {
                return "TURNING_TO_WALL";
            }
            boolean canClimb = (Boolean) invoke(
                body,
                "canClimbOverWall",
                classFor(body, "zombie.iso.IsoDirections"),
                direction
            );
            if (!canClimb) {
                return "FAILED_UNCLIMBABLE_WALL";
            }
            invoke(
                body,
                "climbOverWall",
                classFor(body, "zombie.iso.IsoDirections"),
                direction
            );
            npc.setTraversalInteractionStage("CLIMB_ATTEMPTED");
            return "STARTED_WALL_CLIMB";
        }

        // The route edge changed or its world object disappeared. Invalidate any
        // staged interaction without releasing the route's final destination.
        npc.useTraversalInteractionTarget(null);
        boolean blocked = (Boolean) invoke(
            currentSquare,
            "isBlockedTo",
            currentSquare.getClass(),
            nextSquare
        );
        return blocked ? "FAILED_STATIC_BLOCKAGE" : "CLEAR";
    }

    private static void faceObject(Object body, Object object)
        throws ReflectiveOperationException {
        invoke(body, "faceThisObject", classFor(body, "zombie.iso.IsoObject"), object);
    }

    private static Object cardinalDirection(Object body, int deltaX, int deltaY)
        throws ReflectiveOperationException {
        Class<?> directionsClass = classFor(body, "zombie.iso.IsoDirections");
        String name;
        if (deltaX > 0) {
            name = "E";
        } else if (deltaX < 0) {
            name = "W";
        } else if (deltaY < 0) {
            name = "N";
        } else {
            name = "S";
        }
        return directionsClass.getField(name).get(null);
    }

    static KnoxTravelAwareness.Observation scanTravelThreats(
        Object body, Object zombies, Method canSee, float x, float y, int floor
    ) throws ReflectiveOperationException {
        if (zombies == null) return new KnoxTravelAwareness.Observation(0, Float.POSITIVE_INFINITY, false);
        Method size = zombies.getClass().getMethod("size");
        Method get = zombies.getClass().getMethod("get", int.class);
        int count = ((Number) size.invoke(zombies)).intValue();
        int visible = 0;
        float nearestSquared = Float.POSITIVE_INFINITY;
        for (int i = 0; i < count; i++) {
            Object zombie = get.invoke(zombies, i);
            if (zombie == null || (Boolean) invoke(zombie, "isDead")
                || (Boolean) invoke(zombie, "isReanimatedForGrappleOnly")) continue;
            if (((Number) invoke(zombie, "getZ")).intValue() != floor) continue;
            float dx = x - ((Number) invoke(zombie, "getX")).floatValue();
            float dy = y - ((Number) invoke(zombie, "getY")).floatValue();
            float distanceSquared = dx * dx + dy * dy;
            if (distanceSquared > 144.0f) continue;
            // A remote stale target must not disable stealth across the map.
            if (distanceSquared <= 64.0f && invoke(zombie, "getTarget") == body) {
                return new KnoxTravelAwareness.Observation(visible, distanceSquared, true);
            }
            if (Boolean.TRUE.equals(canSee.invoke(body, zombie))) {
                visible++;
                nearestSquared = Math.min(nearestSquared, distanceSquared);
            }
        }
        return new KnoxTravelAwareness.Observation(visible, nearestSquared, false);
    }

    private static void applyHumanMovementIntent(
        KnoxNpc npc,
        Object body,
        float nextX,
        float nextY,
        float routeDistance,
        String pace
    )
        throws ReflectiveOperationException {
        float x = ((Number) invoke(body, "getX")).floatValue();
        float y = ((Number) invoke(body, "getY")).floatValue();
        float deltaX = nextX - x;
        float deltaY = nextY - y;
        float length = (float) Math.sqrt(deltaX * deltaX + deltaY * deltaY);
        if (length <= 0.001f) {
            clearHumanMovementIntent(body);
            return;
        }

        float directionX = deltaX / length;
        float directionY = deltaY / length;
        boolean draggingCorpse = false;
        try {
            draggingCorpse = (Boolean) invoke(body, "isDraggingCorpse");
        } catch (ReflectiveOperationException ignored) {
            // Build 42 currently exposes this on IsoGameCharacter. Keep ordinary
            // movement available if a compatible build omits it.
        }
        if (draggingCorpse) {
            // BwdDrag interprets human input relative to the facing direction.
            // Supplying the ordinary route vector makes the shell walk away from
            // its waypoint until it reaches a wall. Face away from the waypoint
            // and feed the reverse vector so native backward locomotion moves the
            // body and corpse along the captured route.
            directionX = -directionX;
            directionY = -directionY;
        }
        Class<?> isoPlayerClass = classFor(body, ISO_PLAYER_CLASS);
        Object moveDirection = isoPlayerClass.getField("playerMoveDir").get(body);
        moveDirection.getClass().getField("x").setFloat(moveDirection, directionX);
        moveDirection.getClass().getField("y").setFloat(moveDirection, directionY);
        invoke(body, "setJustMoved", boolean.class, true);
        invoke(
            body,
            "setDirectionAngle",
            float.class,
            (float) Math.toDegrees(Math.atan2(directionY, directionX))
        );

        // Vanilla-feel locomotion: walk default, run to close moderate gaps, sprint rarely for long reposition. Respects endurance/fatigue.
        float endurance = 1.0f;
        float fatigue = 0.0f;
        try {
            Object stats = invoke(body, "getStats");
            Class<?> statClass = Class.forName("zombie.characters.CharacterStat", false, body.getClass().getClassLoader());
            Object endKey = statClass.getField("ENDURANCE").get(null);
            endurance = ((Number) stats.getClass().getMethod("get", statClass).invoke(stats, endKey)).floatValue();
            Object fatigueKey = statClass.getField("FATIGUE").get(null);
            fatigue = ((Number) stats.getClass().getMethod("get", statClass).invoke(stats, fatigueKey)).floatValue();
        } catch (ReflectiveOperationException ignored) {
        }
        float health = locomotionHealth(body);
        boolean nativeCanSprint = false;
        try {
            nativeCanSprint = (Boolean) invoke(body, "canSprint");
        } catch (ReflectiveOperationException ignored) {
        }
        KnoxLocomotionPolicy.Decision locomotion = KnoxLocomotionPolicy.decide(
            pace,
            routeDistance,
            endurance,
            fatigue,
            health,
            nativeCanSprint
        );
        boolean shouldRun = !draggingCorpse && locomotion.running();
        boolean shouldSprint = !draggingCorpse && locomotion.sprinting();
        boolean shouldSneak = false;
        boolean urgentMovement = "run".equals(pace) || "sprint".equals(pace) || "catchup".equals(pace);
        try {
            // Lua supplies the actual leader's pace. Do not mirror player slot 0:
            // that player may belong to a different party in split screen.
            if (!npc.isCombatActive() && !urgentMovement && !(Boolean) invoke(body, "isAiming")
                && !(Boolean) invoke(body, "isDraggingCorpse")) {
                int floor = ((Number) invoke(body, "getZ")).intValue();
                long now = System.nanoTime();
                if (npc.travelAwareness.needsRefresh(now, x, y, floor)) {
                    Object cell = invoke(body, "getCell");
                    Object zombies = cell != null ? invoke(cell, "getZombieList") : null;
                    Method canSee = body.getClass().getMethod("CanSee", classFor(body, "zombie.iso.IsoMovingObject"));
                    npc.travelAwareness.update(now, x, y, floor,
                        scanTravelThreats(body, zombies, canSee, x, y, floor));
                }
                shouldSneak = npc.travelAwareness.shouldSneak(now,
                    "cautious".equals(pace), "sneak".equals(pace));
                if (shouldSneak) {
                    shouldRun = false;
                    shouldSprint = false;
                }
            }
        } catch (ReflectiveOperationException ignored) {
            // Missing perception cannot take over a route or override emergency pace.
        }
        if (shouldSprint) {
            shouldRun = true;
        }
        try {
            invoke(body, "setRunning", boolean.class, shouldRun);
            invoke(body, "setSprinting", boolean.class, shouldSprint);
            invoke(body, "setSneaking", boolean.class, shouldSneak);
        } catch (ReflectiveOperationException ignored) {
        }

        Object aiComponent = getAiComponent(body);
        if (aiComponent != null) {
            Object controlVars = invoke(aiComponent, "getHumanControlVars");
            if (controlVars != null) {
                // Build 42 skips normal input processing for isNpc() players. Recreate the
                // same world-to-animation control-space conversion used by IsoPlayer so its
                // NPC update can supply the movement delta later in the frame.
                float animationAngle = ((Number) invoke(body, "getAnimAngleRadians"))
                    .floatValue();
                float controlX = directionX;
                float controlY = -directionY;
                float cosine = (float) Math.cos(animationAngle);
                float sine = (float) Math.sin(animationAngle);
                float strafeX = controlX * cosine - controlY * sine;
                float strafeY = controlX * sine + controlY * cosine;
                controlVars.getClass().getField("justMoved").setBoolean(controlVars, true);
                controlVars.getClass().getField("running").setBoolean(controlVars, shouldRun || shouldSprint);
                controlVars.getClass().getField("strafeX").setFloat(controlVars, strafeX);
                controlVars.getClass().getField("strafeY").setFloat(controlVars, strafeY);
            }
        }
    }

    static float locomotionHealth(Object body) {
        try {
            Object damage = invoke(body, "getBodyDamage");
            float health = ((Number) invoke(damage, "getOverallBodyHealth")).floatValue();
            if (Float.isFinite(health)) return Math.max(0.0f, Math.min(100.0f, health));
        } catch (ReflectiveOperationException | NullPointerException ignored) {
        }
        try {
            // IsoGameCharacter.health starts at 1, unlike BodyDamage's 100-point scale.
            float health = ((Number) invoke(body, "getHealth")).floatValue();
            return Float.isFinite(health) ? Math.max(0.0f, Math.min(100.0f, health * 100.0f)) : 0.0f;
        } catch (ReflectiveOperationException ignored) {
            return 0.0f;
        }
    }

    static void applyIdleMovementStance(KnoxNpc npc) throws ReflectiveOperationException {
        Object body = npc.getBody();
        boolean sneaking = "sneak".equals(npc.getMovementPace());
        invoke(body, "setRunning", boolean.class, false);
        invoke(body, "setSprinting", boolean.class, false);
        invoke(body, "setSneaking", boolean.class, sneaking);
    }

    private static void clearHumanMovementIntent(Object body) throws ReflectiveOperationException {
        Class<?> isoPlayerClass = classFor(body, ISO_PLAYER_CLASS);
        Object moveDirection = isoPlayerClass.getField("playerMoveDir").get(body);
        moveDirection.getClass().getField("x").setFloat(moveDirection, 0.0f);
        moveDirection.getClass().getField("y").setFloat(moveDirection, 0.0f);
        invoke(body, "setJustMoved", boolean.class, false);
        try {
            invoke(body, "setRunning", boolean.class, false);
            invoke(body, "setSprinting", boolean.class, false);
            invoke(body, "setSneaking", boolean.class, false);
        } catch (ReflectiveOperationException ignored) {
        }

        Object aiComponent = getAiComponent(body);
        if (aiComponent != null) {
            Object controlVars = invoke(aiComponent, "getHumanControlVars");
            if (controlVars != null) {
                controlVars.getClass().getField("justMoved").setBoolean(controlVars, false);
                controlVars.getClass().getField("running").setBoolean(controlVars, false);
                controlVars.getClass().getField("strafeX").setFloat(controlVars, 0.0f);
                controlVars.getClass().getField("strafeY").setFloat(controlVars, 0.0f);
            }
        }
    }

    private static Object getAiComponent(Object body) throws ReflectiveOperationException {
        Class<?> aiComponentClass = classFor(body, "zombie.characters.component.AIComponent");
        return invoke(body, "getECSComponent", Class.class, aiComponentClass);
    }

    private static float distance(float firstX, float firstY, float secondX, float secondY) {
        float deltaX = firstX - secondX;
        float deltaY = firstY - secondY;
        return (float) Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    }

    private static void safelyRemove(Object body) throws ReflectiveOperationException {
        try {
            clearHumanMovementIntent(body);
        } catch (Throwable ignored) {
            // World teardown must continue even if the old input components are already gone.
        }
        Class<?> modelManagerClass = classFor(body, "zombie.core.skinnedmodel.ModelManager");
        Object modelManager = modelManagerClass.getField("instance").get(null);
        invoke(modelManager, "Remove", classFor(body, "zombie.characters.IsoGameCharacter"), body);
        invoke(body, "setMovingSquare", classFor(body, GRID_SQUARE_CLASS), null);
        invoke(body, "removeFromWorld");
    }

    private static Object[] snapshotLocalPlayers(Class<?> isoPlayerClass)
        throws ReflectiveOperationException {
        Field playersField = isoPlayerClass.getField("players");
        Object players = playersField.get(null);
        int length = Array.getLength(players);
        Object[] snapshot = new Object[length];
        for (int index = 0; index < length; index++) {
            snapshot[index] = Array.get(players, index);
        }
        return snapshot;
    }

    private static boolean sameLocalPlayers(Object[] before, Object[] after) {
        if (before.length != after.length) {
            return false;
        }
        for (int index = 0; index < before.length; index++) {
            if (before[index] != after[index]) {
                return false;
            }
        }
        return true;
    }

    private static boolean isInLocalPlayerSlots(Object body) throws ReflectiveOperationException {
        Object[] localPlayers = snapshotLocalPlayers(classFor(body, ISO_PLAYER_CLASS));
        for (Object localPlayer : localPlayers) {
            if (localPlayer == body) {
                return true;
            }
        }
        return false;
    }

    private static int allocateOffSlotPlayerIndex(Class<?> isoPlayerClass)
        throws ReflectiveOperationException {
        // Vanilla IsoPlayer.updateCursorVisibility() hides the system cursor whenever
        // playerIndex==0 && isAiming. An off-slot NPC with index 0 therefore hides
        // the real player's cursor while it is in AIMING/ATTACKING. Use the first
        // free local-player slot above 0 so only the real player (slot 0) controls
        // the cursor. The index also owns Knox's isolated zombie-visibility bit, so
        // it must never overlap a real split-screen player.
        Object players = isoPlayerClass.getField("players").get(null);
        int length = Array.getLength(players);
        for (int index = 1; index < length; index++) {
            if (Array.get(players, index) == null) {
                return index;
            }
        }
        throw new IllegalStateException(
            "No unowned IsoPlayer index is available for a Knox NPC"
        );
    }

    private static void requireClass(Object value, String expectedName, String label) {
        if (value == null || !expectedName.equals(value.getClass().getName())) {
            String actual = value == null ? "null" : value.getClass().getName();
            throw new IllegalArgumentException(label + " must be " + expectedName + ", got " + actual);
        }
    }

    private static Class<?> classFor(Object target, String className)
        throws ClassNotFoundException {
        return Class.forName(className, false, target.getClass().getClassLoader());
    }

    private static Object invoke(Object target, String name, Class<?> parameterType, Object argument)
        throws ReflectiveOperationException {
        Method method = target.getClass().getMethod(name, parameterType);
        return method.invoke(target, argument);
    }

    private static Object invoke(
        Object target,
        String name,
        Class<?> firstType,
        Class<?> secondType,
        Object firstArgument,
        Object secondArgument
    ) throws ReflectiveOperationException {
        Method method = target.getClass().getMethod(name, firstType, secondType);
        return method.invoke(target, firstArgument, secondArgument);
    }

    private static Object invoke(
        Object target,
        String name,
        Class<?> firstType,
        Class<?> secondType,
        Class<?> thirdType,
        Class<?> fourthType,
        Class<?> fifthType,
        Object firstArgument,
        Object secondArgument,
        Object thirdArgument,
        Object fourthArgument,
        Object fifthArgument
    ) throws ReflectiveOperationException {
        Method method = target.getClass().getMethod(
            name,
            firstType,
            secondType,
            thirdType,
            fourthType,
            fifthType
        );
        return method.invoke(
            target,
            firstArgument,
            secondArgument,
            thirdArgument,
            fourthArgument,
            fifthArgument
        );
    }

    private static Object invoke(
        Object target,
        String name,
        Class<?> firstType,
        Class<?> secondType,
        Class<?> thirdType,
        Object firstArgument,
        Object secondArgument,
        Object thirdArgument
    ) throws ReflectiveOperationException {
        Method method = target.getClass().getMethod(name, firstType, secondType, thirdType);
        return method.invoke(target, firstArgument, secondArgument, thirdArgument);
    }

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getMethod(name).invoke(target);
    }
}
