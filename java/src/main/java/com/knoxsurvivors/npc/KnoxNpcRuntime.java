package com.knoxsurvivors.npc;

import com.knoxsurvivors.agent.KnoxAgent;

/** Mutable engine state owned by one persistent Knox survivor identity. */
final class KnoxNpcRuntime {
    private static final float ARRIVAL_DISTANCE = 0.65f;
    private static final int STUCK_WINDOW_TICKS = 45;
    private static final int TRANSITION_STUCK_WINDOW_TICKS = 180;
    private static final float STUCK_MIN_DISPLACEMENT = 0.12f;

    interface MovementEngine {
        float bodyX(KnoxNpc npc) throws ReflectiveOperationException;

        float bodyY(KnoxNpc npc) throws ReflectiveOperationException;

        int bodyZ(KnoxNpc npc) throws ReflectiveOperationException;

        float targetX(Object square) throws ReflectiveOperationException;

        float targetY(Object square) throws ReflectiveOperationException;

        int targetZ(Object square) throws ReflectiveOperationException;

        void start(KnoxNpc npc, Object square, boolean crossing) throws ReflectiveOperationException;

        String tick(KnoxNpc npc, float remainingDistance, String pace)
            throws ReflectiveOperationException;

        void cancel(KnoxNpc npc) throws ReflectiveOperationException;
    }

    private static final MovementEngine LIVE_MOVEMENT_ENGINE = new MovementEngine() {
        @Override
        public float bodyX(KnoxNpc npc) throws ReflectiveOperationException {
            Object body = npc.getBody();
            return ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
        }

        @Override
        public float bodyY(KnoxNpc npc) throws ReflectiveOperationException {
            Object body = npc.getBody();
            return ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
        }

        @Override
        public int bodyZ(KnoxNpc npc) throws ReflectiveOperationException {
            Object square = npc.getBody().getClass().getMethod("getCurrentSquare")
                .invoke(npc.getBody());
            if (square == null) {
                throw new ReflectiveOperationException("NPC has no current square");
            }
            return ((Number) square.getClass().getMethod("getZ").invoke(square)).intValue();
        }

        @Override
        public float targetX(Object square) throws ReflectiveOperationException {
            return ((Number) square.getClass().getMethod("getX").invoke(square)).floatValue() + 0.5f;
        }

        @Override
        public float targetY(Object square) throws ReflectiveOperationException {
            return ((Number) square.getClass().getMethod("getY").invoke(square)).floatValue() + 0.5f;
        }

        @Override
        public int targetZ(Object square) throws ReflectiveOperationException {
            return ((Number) square.getClass().getMethod("getZ").invoke(square)).intValue();
        }

        @Override
        public void start(KnoxNpc npc, Object square, boolean crossing)
            throws ReflectiveOperationException {
            if (crossing) {
                KnoxNpcFactory.moveAcrossAdjacentEdge(npc, square);
            } else {
                KnoxNpcFactory.moveTo(npc, square);
                npc.clearMovementRoute();
            }
        }

        @Override
        public String tick(KnoxNpc npc, float remainingDistance, String pace)
            throws ReflectiveOperationException {
            return KnoxNpcFactory.tickMovement(npc, remainingDistance, pace);
        }

        @Override
        public void cancel(KnoxNpc npc) throws ReflectiveOperationException {
            KnoxNpcFactory.cancelMovement(npc);
        }
    };

    private KnoxNpc npc;
    private final MovementEngine movementEngine;
    private final KnoxMovementRequest movementRequest = new KnoxMovementRequest();
    private float movementStartX;
    private float movementStartY;
    private String movementControllerState = "NotStarted";
    private float lastProgressX;
    private float lastProgressY;
    private int lastProgressZ;
    private int noProgressTicks;
    /**
     * The square this request was opened for. A captured native route can end
     * short of it (a partial path that stops at a stair square, for example),
     * and the manual drive then reports "Succeeded" somewhere else. Keeping the
     * requested square lets the runtime ask the engine for the next leg instead
     * of failing the whole order.
     */
    private Object movementTargetSquare;
    private int replanAttempts;
    private static final int MAX_SHORT_ROUTE_REPLANS = 3;
    private KnoxSurvivorRecord lastRecord;
    private final KnoxCombatController combatController = new KnoxCombatController();
    private final KnoxCorpseRetirement corpseRetirement = new KnoxCorpseRetirement();

    KnoxNpcRuntime(KnoxNpc npc) {
        this(npc, LIVE_MOVEMENT_ENGINE);
    }

    KnoxNpcRuntime(KnoxNpc npc, MovementEngine movementEngine) {
        this.npc = npc;
        this.movementEngine = movementEngine;
        npc.clearMovementRoute();
    }

    KnoxNpc npc() {
        return npc;
    }

    void replaceNpc(KnoxNpc replacement) {
        combatController.reset();
        npc = replacement;
        resetMovement();
        npc.clearMovementRoute();
    }

    KnoxSurvivorRecord lastRecord() {
        return lastRecord;
    }

    void setLastRecord(KnoxSurvivorRecord record) {
        lastRecord = record;
    }

    KnoxCombatController combat() {
        return combatController;
    }

    KnoxCorpseRetirement corpseRetirement() {
        return corpseRetirement;
    }

    String beginMove(Object square, boolean exactAdjacentCrossing) {
        return beginMove(square, exactAdjacentCrossing, "normal");
    }

    String beginMove(Object square, boolean exactAdjacentCrossing, String pace) {
        return beginMove(square, exactAdjacentCrossing, pace, null);
    }

    String beginMove(Object square, boolean exactAdjacentCrossing, String pace, KnoxMovementArea area) {
        try {
            float targetX = movementEngine.targetX(square);
            float targetY = movementEngine.targetY(square);
            int targetZ = movementEngine.targetZ(square);
            KnoxMovementRequest.Change change = movementRequest.classify(
                targetX,
                targetY,
                targetZ,
                exactAdjacentCrossing
            );
            if (area != null && !area.contains(targetX, targetY, targetZ)) {
                return "MOVE_FAILED DESTINATION_OUTSIDE_DUTY_AREA";
            }
            boolean sameArea = area == null ? npc.movementArea == null : area.sameBounds(npc.movementArea);
            if (change == KnoxMovementRequest.Change.KEEP && !sameArea) {
                change = KnoxMovementRequest.Change.REPLACE;
            }
            // A normal destination that is already under the survivor does not
            // need another native route. Starting one anyway leaves Lua in a
            // BASE_TASK_MOVE/GROUP_FOLLOW state while the engine has no useful
            // distance to cover, which looks like a brief freeze or a route
            // reconsideration. Edge crossings are deliberately excluded: a
            // crossing request must still invoke the native interaction even
            // when the actor is close to the requested edge.
            if (!exactAdjacentCrossing
                && KnoxMovementGeometry.arrived(
                    movementEngine.bodyX(npc),
                    movementEngine.bodyY(npc),
                    movementEngine.bodyZ(npc),
                    targetX,
                    targetY,
                    targetZ,
                    ARRIVAL_DISTANCE
                )) {
                if (change == KnoxMovementRequest.Change.REPLACE) {
                    String cancellationFailure = releaseEngineMovement("MOVE_REPLACE_FAILED");
                    resetMovement();
                    if (cancellationFailure != null) {
                        return cancellationFailure;
                    }
                }
                npc.setMovementPace(pace);
                movementTargetSquare = square;
                replanAttempts = 0;
                movementRequest.activate(targetX, targetY, targetZ, false);
                movementControllerState = "Succeeded";
                return "MOVE_STARTED already_at_target=true " + movementDescription();
            }
            if (change == KnoxMovementRequest.Change.KEEP) {
                npc.setMovementPace(pace);
                return (exactAdjacentCrossing ? "CROSS_STARTED " : "MOVE_STARTED ")
                    + "existing=true " + movementDescription();
            }
            if (change == KnoxMovementRequest.Change.REPLACE) {
                String cancellationFailure = releaseEngineMovement("MOVE_REPLACE_FAILED");
                resetMovement();
                if (cancellationFailure != null) {
                    return cancellationFailure;
                }
            }
            movementStartX = movementEngine.bodyX(npc);
            movementStartY = movementEngine.bodyY(npc);
            lastProgressX = movementStartX;
            lastProgressY = movementStartY;
            lastProgressZ = movementEngine.bodyZ(npc);
            noProgressTicks = 0;
            npc.setMovementPace(pace);
            movementEngine.start(npc, square, exactAdjacentCrossing);
            npc.movementArea = area;
            if (area != null) area.allowsPosition(movementStartX, movementStartY, movementEngine.bodyZ(npc));
            movementTargetSquare = square;
            replanAttempts = 0;
            movementRequest.activate(targetX, targetY, targetZ, exactAdjacentCrossing);
            movementControllerState = "Working";
            String result = (exactAdjacentCrossing ? "CROSS_STARTED " : "MOVE_STARTED ")
                + (change == KnoxMovementRequest.Change.REPLACE ? "replaced=true " : "")
                + movementDescription();
            // Autonomous movement makes many short, normal route requests.  Those are
            // expected gameplay, not diagnostic evidence, and previously drowned out
            // the useful stuck/transition failures in KnoxIsoPlayer.log.  Edge crossings
            // are still important enough to retain because they exercise doors/windows.
            if (exactAdjacentCrossing) {
                KnoxAgent.writeLog("NPC probe " + result);
            }
            return result;
        } catch (Throwable throwable) {
            String startFailure = failure("MOVE_FAILED", throwable);
            String cleanupFailure = releaseEngineMovement("MOVE_START_CLEANUP_FAILED");
            resetMovement();
            return cleanupFailure == null ? startFailure : startFailure + " " + cleanupFailure;
        }
    }

    boolean updateMovementPace(String pace) {
        npc.setMovementPace(pace);
        // A companion may already be standing at its formation slot when the
        // player toggles crouch.  Preserve that requested stance while idle so
        // the next movement request and the visible posture agree.
        try {
            KnoxNpcFactory.applyIdleMovementStance(npc);
        } catch (ReflectiveOperationException ignored) {
            // Pace remains saved even if this Build 42 native posture hook is unavailable.
        }
        return true;
    }

    String tickMovement() {
        if (!movementRequest.isActive()) {
            return "IDLE";
        }
        if (isTerminal(movementControllerState)) {
            return finishMovementRequest(movementControllerState);
        }
        try {
            String previousState = movementControllerState;
            float currentX = movementEngine.bodyX(npc);
            float currentY = movementEngine.bodyY(npc);
            int currentZ = movementEngine.bodyZ(npc);
            float remainingDistance = KnoxMovementGeometry.routeDistance(
                currentX,
                currentY,
                currentZ,
                movementRequest.targetX(),
                movementRequest.targetY(),
                movementRequest.targetZ()
            );
            movementControllerState = movementEngine.tick(
                npc,
                remainingDistance,
                npc.getMovementPace()
            );
            if ("Succeeded".equals(movementControllerState)) {
                currentX = movementEngine.bodyX(npc);
                currentY = movementEngine.bodyY(npc);
                currentZ = movementEngine.bodyZ(npc);
            }            if ("Succeeded".equals(movementControllerState)
                && !KnoxMovementGeometry.arrived(
                    currentX, currentY, currentZ,
                    movementRequest.targetX(), movementRequest.targetY(), movementRequest.targetZ(),
                    ARRIVAL_DISTANCE
                )) {
                // The captured route ended short on the same floor: a partial
                // native path can hand over only its first leg, and the manual
                // drive then declares success before the destination is reached.
                // Re-request the same square so the engine plans the next leg
                // instead of failing the whole order.
                //
                // A completion on another floor keeps the existing rejection: a
                // mismatch there is either an unmodelled floor transition or a
                // stale route, and silently retrying it was explicitly ruled out
                // by the runtime fixture ("engine XY completion on the wrong
                // floor is rejected"). That path needs a stair owner, not a
                // replan loop.
                boolean replanned = false;
                if (replanAttempts < MAX_SHORT_ROUTE_REPLANS && movementTargetSquare != null
                    && currentZ == movementRequest.targetZ()) {
                    try {
                        movementEngine.start(npc, movementTargetSquare, false);
                        replanAttempts++;
                        noProgressTicks = 0;
                        lastProgressX = currentX;
                        lastProgressY = currentY;
                        lastProgressZ = currentZ;
                        movementControllerState = "Working";
                        replanned = true;
                        KnoxAgent.writeLog(
                            "NPC probe movement replanned attempt="
                                + replanAttempts
                                + " "
                                + movementDescription()
                        );
                    } catch (Throwable ignored) {
                        replanned = false;
                    }
                }
                if (!replanned) {
                    movementControllerState = "FailedWrongFloorOrPosition";
                }
            }
            boolean pendingTransition = isPendingTransition(movementControllerState);
            if ((isStuckState(movementControllerState) || pendingTransition) && !KnoxMovementGeometry.arrived(
                currentX,currentY,currentZ,movementRequest.targetX(),movementRequest.targetY(),movementRequest.targetZ(),ARRIVAL_DISTANCE)) {
                if (pendingTransition != isPendingTransition(previousState)) noProgressTicks = 0;
                float progress = distance(currentX, currentY, lastProgressX, lastProgressY);
                if (progress >= STUCK_MIN_DISPLACEMENT || currentZ != lastProgressZ) {
                    lastProgressX = currentX;
                    lastProgressY = currentY;
                    lastProgressZ = currentZ;
                    noProgressTicks = 0;
                } else {
                    noProgressTicks++;
                }
                if (noProgressTicks >= (pendingTransition ? TRANSITION_STUCK_WINDOW_TICKS : STUCK_WINDOW_TICKS)) {
                    String result = (pendingTransition ? "FailedTransitionStalled" : "FailedStuck") + " displacement="
                        + distance(currentX, currentY, movementStartX, movementStartY)
                        + " targetDistance=" + remainingDistance
                        + " state=" + movementControllerState
                        + " position=" + currentX + "," + currentY + "," + currentZ
                        + " " + npc.describeMovementRoute()
                        + " " + KnoxNpcFactory.movementObstacleContext(npc);
                    KnoxAgent.writeLog("NPC probe movement " + npc.describe() + " " + result);
                    return finishMovementRequest(result);
                }
            } else if (!isStuckState(movementControllerState)) {
                // Turning, climbing, and door/window actions legitimately hold the
                // survivor in place. They are governed by their action timeout rather
                // than being mistaken for a blocked locomotion route.
                noProgressTicks = 0;
                lastProgressX = currentX;
                lastProgressY = currentY;
                lastProgressZ = currentZ;
            }
            if (!movementControllerState.equals(previousState)
                && !"ManualRoute".equals(movementControllerState)
                && !"Succeeded".equals(movementControllerState)) {
                KnoxAgent.writeLog(
                    "NPC probe movement controller="
                        + movementControllerState
                        + " "
                        + movementDescription()
                );
            }
            return isTerminal(movementControllerState)
                ? finishMovementRequest(movementControllerState)
                : movementControllerState;
        } catch (Throwable throwable) {
            Throwable cause = rootCause(throwable);
            String cleanupFailure = releaseEngineMovement("MOVE_TICK_CLEANUP_FAILED");
            resetMovement();
            KnoxAgent.writeLog(
                "ERROR NPC probe movement tick failed "
                    + cause.getClass().getName()
                    + ": "
                    + cause.getMessage()
            );
            String result = "TICK_FAILED " + cause.getClass().getName() + ": " + cause.getMessage();
            return cleanupFailure == null ? result : result + " " + cleanupFailure;
        }
    }

    String cancelMovement() {
        String cleanupFailure = releaseEngineMovement("MOVE_CANCEL_FAILED");
        resetMovement();
        return cleanupFailure == null ? "MOVE_CANCELLED " + npc.describe() : cleanupFailure;
    }

    boolean hasTraversalEvidence(String state) {
        return npc.hasMovementTraversalEvidence(state);
    }

    String status() {
        try {
            String live = KnoxNpcFactory.describeLive(npc);
            if (!movementRequest.isActive()) {
                return live + " movement=NOT_REQUESTED";
            }
            Object body = npc.getBody();
            float x = ((Number) body.getClass().getMethod("getX").invoke(body)).floatValue();
            float y = ((Number) body.getClass().getMethod("getY").invoke(body)).floatValue();
            int z = movementEngine.bodyZ(npc);
            float distance = KnoxMovementGeometry.routeDistance(
                x, y, z,
                movementRequest.targetX(), movementRequest.targetY(), movementRequest.targetZ()
            );
            float displacement = distance(x, y, movementStartX, movementStartY);
            String state = KnoxMovementGeometry.arrived(
                x, y, z,
                movementRequest.targetX(), movementRequest.targetY(), movementRequest.targetZ(),
                ARRIVAL_DISTANCE
            ) ? "ARRIVED" : "IN_PROGRESS";
            return live
                + " movement=" + state
                + " controller=" + movementControllerState
                + " target=" + movementRequest.targetX() + "," + movementRequest.targetY()
                    + "," + movementRequest.targetZ()
                + " distance=" + distance
                + " displacement=" + displacement;
        } catch (Throwable throwable) {
            return failure("STATUS_FAILED", throwable);
        }
    }

    void reset() {
        combatController.reset();
        lastRecord = null;
        corpseRetirement.reset();
        resetMovement();
    }

    private void resetMovement() {
        movementRequest.release();
        movementTargetSquare = null;
        replanAttempts = 0;
        npc.movementArea = null;
        movementControllerState = "NotStarted";
        lastProgressX = 0.0f;
        lastProgressY = 0.0f;
        lastProgressZ = 0;
        noProgressTicks = 0;
        npc.setMovementPace("normal");
    }

    private String finishMovementRequest(String terminalState) {
        // Keep failed native climb evidence across route cleanup. Deliberate
        // cancellation/replacement and successful crossings are not failures.
        npc.rememberFailedClimb(terminalState);
        String cleanupFailure = releaseEngineMovement("MOVE_FINISH_CLEANUP_FAILED");
        resetMovement();
        return cleanupFailure == null ? terminalState : "FailedCleanup " + cleanupFailure;
    }

    private String releaseEngineMovement(String failurePrefix) {
        try {
            movementEngine.cancel(npc);
            return null;
        } catch (Throwable throwable) {
            return failure(failurePrefix, throwable);
        }
    }

    private static boolean isPendingTransition(String state) {
        // These describe requested input, not a graph which actually owns the
        // body. Real CLIMBING/OPENING_WINDOW/SMASHING_WINDOW remain untouched.
        return state.startsWith("Transition:TURNING_")
            || state.startsWith("Transition:STARTED_")
            || state.equals("Transition:ManualRoute");
    }

    private static boolean isStuckState(String state) {
        return "Working".equals(state)
            || "ManualRoute".equals(state)
            || "Pathfinding".equalsIgnoreCase(state)
            || "PathFind".equalsIgnoreCase(state);
    }

    private String movementDescription() {
        return npc.describe()
            + " from=" + movementStartX + "," + movementStartY
            + " target=" + movementRequest.targetX() + "," + movementRequest.targetY()
                + "," + movementRequest.targetZ();
    }

    private static boolean isTerminal(String state) {
        return "Succeeded".equals(state) || state.startsWith("Failed");
    }

    private static float distance(float firstX, float firstY, float secondX, float secondY) {
        float deltaX = firstX - secondX;
        float deltaY = firstY - secondY;
        return (float) Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    }

    private static String failure(String prefix, Throwable throwable) {
        Throwable cause = rootCause(throwable);
        String result = prefix + " " + cause.getClass().getName() + ": " + cause.getMessage();
        KnoxAgent.writeLog("ERROR NPC probe " + result);
        return result;
    }

    private static Throwable rootCause(Throwable throwable) {
        Throwable current = throwable;
        while (current.getCause() != null && current.getCause() != current) {
            current = current.getCause();
        }
        return current;
    }
}
