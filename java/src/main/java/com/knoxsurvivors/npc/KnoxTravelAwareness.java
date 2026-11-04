package com.knoxsurvivors.npc;

/**
 * Transient perception for one loaded body; never part of a save or movement owner.
 *
 * <p>Cautious travel is a posture, not a reaction. A survivor crouches while it
 * walks an ordinary travel leg, because being quiet between houses is the whole
 * point, and it straightens up the moment a zombie has the body as its target or
 * stands within arm's reach: crouching at something that has already seen you
 * only makes the retreat slower. The old rule did the opposite - it crouched
 * only after a zombie had wandered into the survivor's own view and then stood up
 * 1.5 s later - which reads in play as random crouching that arrives too late.
 */
final class KnoxTravelAwareness {
    private static final long SCAN_INTERVAL_NANOS = 250_000_000L;
    record Observation(int visible, float nearestSquared, boolean detected) { }

    private boolean sampled;
    private long nextScan;
    private float x;
    private float y;
    private int z;
    private Observation observation = new Observation(0, Float.POSITIVE_INFINITY, false);

    boolean needsRefresh(long now, float currentX, float currentY, int currentZ) {
        float dx = currentX - x;
        float dy = currentY - y;
        return !sampled || now >= nextScan || currentZ != z || dx * dx + dy * dy > 16.0f;
    }

    void update(long now, float currentX, float currentY, int currentZ, Observation next) {
        sampled = true;
        nextScan = now + SCAN_INTERVAL_NANOS;
        x = currentX;
        y = currentY;
        z = currentZ;
        observation = next;
    }

    boolean shouldSneak(long now, boolean cautiousPace, boolean orderedSneak) {
        // Detection ends stealth. Contact danger is the same story: crouch-walking
        // into something already within two tiles is not caution.
        if (!sampled || observation.detected() || observation.nearestSquared() <= 4.0f) return false;
        if (orderedSneak) return true;
        if (cautiousPace) return true;
        // A pace that is not cautious is not a stealth posture; only a crowd in
        // plain sight makes an ordinary walk crouch.
        return observation.visible() >= 3;
    }
}
