package com.knoxsurvivors.npc;

/** Z-aware movement comparisons shared by runtime ownership and captured native routes. */
final class KnoxMovementGeometry {
    private KnoxMovementGeometry() {
    }

    static boolean arrived(
        float currentX,
        float currentY,
        int currentZ,
        float targetX,
        float targetY,
        int targetZ,
        float tolerance
    ) {
        return currentZ == targetZ
            && Math.floor(currentX) == Math.floor(targetX)
            && Math.floor(currentY) == Math.floor(targetY)
            && distance2d(currentX, currentY, targetX, targetY) <= tolerance;
    }

    static boolean nodeReached(
        float currentX,
        float currentY,
        int currentZ,
        float nodeX,
        float nodeY,
        float nodeZ,
        float tolerance
    ) {
        if (currentZ != floorZ(nodeZ)) {
            return false;
        }
        // Captured route nodes are tile granular. A body that is running can
        // cross a node's centre between two controller ticks, leaving that node
        // just behind it: the next intent then aims backwards, the survivor
        // turns around and runs back, and the pair repeats as an oscillation
        // that reads as running back and forth. Standing anywhere in the node's
        // tile is therefore arrival; the next node is always ahead, so the route
        // can only continue forward. Wall and window edges cannot be skipped by
        // this, because a node across an edge is a different tile.
        if (Math.floor(currentX) == Math.floor(nodeX)
            && Math.floor(currentY) == Math.floor(nodeY)) {
            return true;
        }
        return false;
    }

    static float routeDistance(
        float firstX,
        float firstY,
        float firstZ,
        float secondX,
        float secondY,
        float secondZ
    ) {
        float dx = firstX - secondX;
        float dy = firstY - secondY;
        float dz = firstZ - secondZ;
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    static int floorZ(float z) {
        return (int) Math.floor(z);
    }

    /**
     * A node the body has already moved past along the segment toward the next
     * node. Captured routes regularly begin a fraction of a tile behind the body,
     * and a running body drifts across tile corners, so the old "body stands in
     * the node's tile" test missed both cases: the follower then turned around to
     * walk back to a node behind it. Same floor, a different next tile, and
     * positive progress along node -> next are required. Only release when the
     * body occupies the successor tile; lateral projection alone can skip a bend
     * and its wall or window edge. Sparse segments may retain a passed node until
     * the successor tile is reached, rather than guessing intervening clearance.
     */
    static boolean nodeBehind(float x, float y, float z, float[] node, float[] next, float radius) {
        if (node == null || next == null || node.length < 3 || next.length < 3) return false;
        if (floorZ(z) != floorZ(node[2]) || floorZ(z) != floorZ(next[2])) return false;
        if (Math.floor(node[0]) == Math.floor(next[0])
            && Math.floor(node[1]) == Math.floor(next[1])) return false;
        if (Math.floor(x) != Math.floor(next[0]) || Math.floor(y) != Math.floor(next[1])) return false;
        if (distance2d(x, y, node[0], node[1]) > radius) return false;
        return (next[0] - node[0]) * (x - node[0])
            + (next[1] - node[1]) * (y - node[1]) > 0;
    }

    static boolean startNodeBehind(float x,float y,float z,float[] first,float[] next) {
        if (first == null || next == null || first.length < 3 || next.length < 3) return false;
        boolean insideFirstTile = floorZ(z) == floorZ(first[2]) && floorZ(z) == floorZ(next[2])
            && Math.floor(x) == Math.floor(first[0]) && Math.floor(y) == Math.floor(first[1])
            && (Math.floor(x) != Math.floor(next[0]) || Math.floor(y) != Math.floor(next[1]))
            && (first[0]-x)*(next[0]-x)+(first[1]-y)*(next[1]-y) < 0;
        return insideFirstTile || nodeBehind(x, y, z, first, next, 1.5f);
    }

    /** First tile boundary on a native route segment, including long sparse segments. */
    static int[] nextRouteTile(float x, float y, float targetX, float targetY) {
        int tileX = (int) Math.floor(x), tileY = (int) Math.floor(y);
        float dx = targetX - x, dy = targetY - y;
        float tx = dx == 0 ? Float.POSITIVE_INFINITY
            : ((dx > 0 ? tileX + 1 : tileX) - x) / dx;
        float ty = dy == 0 ? Float.POSITIVE_INFINITY
            : ((dy > 0 ? tileY + 1 : tileY) - y) / dy;
        if (tx > 1 && ty > 1) return new int[] {tileX, tileY};
        if (tx <= ty + .00001f && dx != 0) tileX += dx > 0 ? 1 : -1;
        if (ty <= tx + .00001f && dy != 0) tileY += dy > 0 ? 1 : -1;
        return new int[] {tileX, tileY};
    }

    private static float distance2d(float firstX, float firstY, float secondX, float secondY) {
        float dx = firstX - secondX;
        float dy = firstY - secondY;
        return (float) Math.sqrt(dx * dx + dy * dy);
    }
}
