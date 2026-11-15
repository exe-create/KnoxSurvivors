package com.knoxsurvivors.npc;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.LongSupplier;

/** Knox-owned identity paired with a temporary Project Zomboid IsoPlayer body. */
public final class KnoxNpc {
    private final String id;
    private final Object body;
    private final LongSupplier clockMillis;
    private final int spawnX;
    private final int spawnY;
    private final int spawnZ;
    private final List<float[]> movementRoute = new ArrayList<>();
    private int movementRouteIndex;
    private String movementPace = "normal";
    KnoxMovementArea movementArea;
    final KnoxTravelAwareness travelAwareness = new KnoxTravelAwareness();
    private String movementTraversalState = "NONE";
    private final Set<String> movementTraversalEvidence = new LinkedHashSet<>();
    private final Map<String, Long> traversalCooldowns = new LinkedHashMap<>();
    private Object traversalInteractionTarget;
    private String traversalInteractionStage = "NONE";
    private int[] traversalClimbEdge;
    private boolean climbingAllowed = true;
    private boolean doorWindowOpeningAllowed = true;
    // Close-behind bookkeeping: the last door this NPC opened itself, with
    // the square it sits on. Only doors recorded here are ever closed back,
    // so doors the player (or anyone else) left open are never touched.
    private Object lastOpenedDoor;
    private int lastOpenedDoorX;
    private int lastOpenedDoorY;
    private int lastOpenedDoorZ;
    private boolean lastOpenedDoorNorth;
    private boolean lastOpenedDoorFromPositiveSide;
    private boolean hasOpenedDoor;
    private boolean combatActive;
    private boolean hasProtectedArea;
    private int protectedMinX;
    private int protectedMinY;
    private int protectedMaxX;
    private int protectedMaxY;

    KnoxNpc(String id, Object body, int spawnX, int spawnY, int spawnZ) {
        this(id, body, spawnX, spawnY, spawnZ, System::currentTimeMillis);
    }

    KnoxNpc(String id, Object body, int spawnX, int spawnY, int spawnZ, LongSupplier clockMillis) {
        this.id = id;
        this.body = body;
        this.clockMillis = java.util.Objects.requireNonNull(clockMillis);
        this.spawnX = spawnX;
        this.spawnY = spawnY;
        this.spawnZ = spawnZ;
    }

    public String getId() {
        return id;
    }

    Object getBody() {
        return body;
    }

    void setMovementRoute(List<float[]> nodes) {
        movementRoute.clear();
        movementRoute.addAll(nodes);
        movementRouteIndex = 0;
        movementTraversalState = "ROUTE_READY";
        movementTraversalEvidence.clear();
        clearTraversalInteraction();
    }

    boolean isTraversalCoolingDown(
        int currentX,
        int currentY,
        int currentZ,
        int nextX,
        int nextY,
        int nextZ
    ) {
        String key = traversalEdgeKey(currentX, currentY, currentZ, nextX, nextY, nextZ);
        Long until = traversalCooldowns.get(key);
        if (until == null) {
            return false;
        }
        if (clockMillis.getAsLong() >= until) {
            traversalCooldowns.remove(key);
            return false;
        }
        return true;
    }

    void rememberTraversalFailure(
        int currentX,
        int currentY,
        int currentZ,
        int nextX,
        int nextY,
        int nextZ,
        String state
    ) {
        if (state == null || state.isEmpty() || "FAILED_EDGE_COOLDOWN".equals(state)) {
            return;
        }
        long duration = "FAILED_CLIMB_NO_PROGRESS".equals(state) ? 30000L
            : state.contains("LOCKED") || state.contains("BARRICADED") ? 5000L : 1800L;
        long now = clockMillis.getAsLong();
        // A survivor may never revisit a failed edge. Retire old entries when
        // recording a new failure so a long walk cannot retain every old door.
        traversalCooldowns.values().removeIf(until -> until <= now);
        traversalCooldowns.put(
            traversalEdgeKey(currentX, currentY, currentZ, nextX, nextY, nextZ),
            now + duration
        );
    }

    void clearMovementRoute() {
        movementRoute.clear();
        movementRouteIndex = 0;
        movementTraversalState = "NONE";
        // Keep terminal traversal evidence available to the QA bridge until the
        // next route is installed. The old clear here made a successful fence
        // climb disappear between the final native tick and Lua's poll.
        clearTraversalInteraction();
    }

    void setMovementPace(String pace) {
        if (pace == null) {
            movementPace = "normal";
            return;
        }
        String normalized = pace.toLowerCase(java.util.Locale.ROOT);
        movementPace = "walk".equals(normalized)
            || "run".equals(normalized)
            || "sprint".equals(normalized)
            || "catchup".equals(normalized)
            || "cautious".equals(normalized)
            || "sneak".equals(normalized)
            ? normalized
            : "normal";
    }

    String getMovementPace() {
        return movementPace;
    }

    float remainingMovementDistance(float currentX, float currentY, float currentZ) {
        float distance = 0.0f;
        float previousX = currentX;
        float previousY = currentY;
        float previousZ = currentZ;
        for (int index = movementRouteIndex; index < movementRoute.size(); index++) {
            float[] node = movementRoute.get(index);
            distance += KnoxMovementGeometry.routeDistance(
                previousX, previousY, previousZ,
                node[0], node[1], node[2]
            );
            previousX = node[0];
            previousY = node[1];
            previousZ = node[2];
        }
        return distance;
    }

    boolean hasMovementRoute() {
        return movementRouteIndex < movementRoute.size();
    }

    float[] currentMovementNode() {
        return hasMovementRoute() ? movementRoute.get(movementRouteIndex) : null;
    }

    /** The node after the current one, used to decide whether the current node is behind. */
    float[] nextMovementNode() {
        int next = movementRouteIndex + 1;
        return next < movementRoute.size() ? movementRoute.get(next) : null;
    }

    float movementNodeTolerance() {
        return combatActive && movementRouteIndex == movementRoute.size() - 1
            ? 0.04f : 0.35f;
    }

    void advanceMovementRoute() {
        if (hasMovementRoute()) {
            movementRouteIndex++;
            clearTraversalInteraction();
        }
    }

    void useTraversalInteractionTarget(Object target) {
        if (traversalInteractionTarget != target) {
            traversalInteractionTarget = target;
            traversalInteractionStage = "NONE";
            traversalClimbEdge = null;
        }
    }

    void noteClimbEdge(int x, int y, int z, int nextX, int nextY, int nextZ) {
        traversalClimbEdge = new int[] {x, y, z, nextX, nextY, nextZ};
    }

    void rememberFailedClimb(String terminalState) {
        if (traversalClimbEdge == null || !"CLIMB_ATTEMPTED".equals(traversalInteractionStage)
            || !(terminalState.startsWith("FailedStuck") || terminalState.startsWith("FailedTransitionStalled"))) return;
        int[] edge = traversalClimbEdge;
        rememberTraversalFailure(edge[0], edge[1], edge[2], edge[3], edge[4], edge[5], "FAILED_CLIMB_NO_PROGRESS");
    }

    Object getTraversalInteractionTarget() {
        return traversalInteractionTarget;
    }

    boolean isClimbingAllowed() {
        return climbingAllowed;
    }

    boolean isDoorWindowOpeningAllowed() {
        return doorWindowOpeningAllowed;
    }

    boolean isCombatActive() {
        return combatActive;
    }

    void setCombatActive(boolean active) {
        combatActive = active;
    }

    void setClimbingAllowed(boolean allowed) {
        climbingAllowed = allowed;
    }

    void setDoorWindowOpeningAllowed(boolean allowed) {
        doorWindowOpeningAllowed = allowed;
    }

    void rememberOpenedDoor(Object door, int x, int y, int z, boolean north, boolean fromPositiveSide) {
        lastOpenedDoor = door;
        lastOpenedDoorX = x;
        lastOpenedDoorY = y;
        lastOpenedDoorZ = z;
        lastOpenedDoorNorth = north;
        lastOpenedDoorFromPositiveSide = fromPositiveSide;
        hasOpenedDoor = door != null;
    }

    void clearOpenedDoor() {
        lastOpenedDoor = null;
        hasOpenedDoor = false;
    }

    boolean hasOpenedDoor() {
        return hasOpenedDoor && lastOpenedDoor != null;
    }

    Object getOpenedDoor() {
        return lastOpenedDoor;
    }

    int getOpenedDoorX() {
        return lastOpenedDoorX;
    }

    int getOpenedDoorY() {
        return lastOpenedDoorY;
    }

    int getOpenedDoorZ() {
        return lastOpenedDoorZ;
    }

    boolean getOpenedDoorNorth() { return lastOpenedDoorNorth; }

    boolean getOpenedDoorFromPositiveSide() { return lastOpenedDoorFromPositiveSide; }

    void setProtectedArea(int minX, int minY, int maxX, int maxY) {
        protectedMinX = Math.min(minX, maxX);
        protectedMinY = Math.min(minY, maxY);
        protectedMaxX = Math.max(minX, maxX);
        protectedMaxY = Math.max(minY, maxY);
        hasProtectedArea = true;
    }

    void clearProtectedArea() {
        hasProtectedArea = false;
    }

    boolean isProtectedStructureEdge(int currentX, int currentY, int nextX, int nextY) {
        if (!hasProtectedArea) {
            return false;
        }
        return insideProtectedArea(currentX, currentY) || insideProtectedArea(nextX, nextY);
    }

    private boolean insideProtectedArea(int x, int y) {
        return x >= protectedMinX && x <= protectedMaxX
            && y >= protectedMinY && y <= protectedMaxY;
    }

    String getTraversalInteractionStage() {
        return traversalInteractionStage;
    }

    void setTraversalInteractionStage(String stage) {
        traversalInteractionStage = stage;
    }

    private void clearTraversalInteraction() {
        traversalInteractionTarget = null;
        traversalInteractionStage = "NONE";
        traversalClimbEdge = null;
    }

    private static String traversalEdgeKey(
        int currentX,
        int currentY,
        int currentZ,
        int nextX,
        int nextY,
        int nextZ
    ) {
        return currentX + "," + currentY + "," + currentZ
            + "->" + nextX + "," + nextY + "," + nextZ;
    }

    void setMovementTraversalState(String state) {
        movementTraversalState = state;
        if (!"CLEAR".equals(state) && !"ROUTE_READY".equals(state)) {
            movementTraversalEvidence.add(state);
        }
    }

    boolean hasMovementTraversalEvidence(String state) {
        return movementTraversalEvidence.contains(state);
    }

    String describeMovementRoute() {
        float[] node = currentMovementNode();
        String next = node == null ? "none" : node[0] + "," + node[1] + "," + node[2];
        return movementRouteIndex
            + "/"
            + movementRoute.size()
            + " next="
            + next
            + " pace="
            + movementPace
            + " traversal="
            + movementTraversalState
            + " evidence="
            + movementTraversalEvidence;
    }

    public String describe() {
        return id + "@" + spawnX + "," + spawnY + "," + spawnZ;
    }
}
