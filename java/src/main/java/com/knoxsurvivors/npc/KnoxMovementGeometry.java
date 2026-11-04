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
        return currentZ == floorZ(nodeZ)
            && distance2d(currentX, currentY, nodeX, nodeY) <= tolerance;
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

    static boolean startNodeBehind(float x,float y,float z,float[] first,float[] next) {
        if (first == null || next == null || first.length < 3 || next.length < 3) return false;
        return floorZ(z) == floorZ(first[2]) && floorZ(z) == floorZ(next[2])
            && Math.floor(x) == Math.floor(first[0]) && Math.floor(y) == Math.floor(first[1])
            && (Math.floor(x) != Math.floor(next[0]) || Math.floor(y) != Math.floor(next[1]))
            && (first[0]-x)*(next[0]-x)+(first[1]-y)*(next[1]-y) < 0;
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
