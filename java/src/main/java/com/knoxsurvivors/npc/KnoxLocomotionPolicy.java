package com.knoxsurvivors.npc;

import java.util.Locale;

/** Pure walk/run/sprint selection for an already-owned movement request. */
final class KnoxLocomotionPolicy {
    private static final float RUN_REMAINING_DISTANCE = 2.0f;
    // Formation slots sit only a few tiles behind a sprinting leader.  Requiring
    // an eight-tile gap made an explicit sprint request visibly lag behind.
    private static final float SPRINT_REMAINING_DISTANCE = 2.5f;

    static final class Decision {
        private final boolean running;
        private final boolean sprinting;

        private Decision(boolean running, boolean sprinting) {
            this.running = running;
            this.sprinting = sprinting;
        }

        boolean running() {
            return running;
        }

        boolean sprinting() {
            return sprinting;
        }
    }

    private KnoxLocomotionPolicy() {
    }

    static Decision decide(
        String pace,
        float remainingDistance,
        float endurance,
        float fatigue,
        float health,
        boolean nativeCanSprint
    ) {
        return decide(pace, remainingDistance, endurance, fatigue, health,
            nativeCanSprint, false);
    }

    /**
     * The same rule with one more observed fact: the next route edge crosses a
     * doorway. A body running through a door frame clips the wall beside it,
     * which the player reads as sprinting into a wall and getting stuck, so that
     * single edge is walked and the requested pace resumes on the far side.
     */
    static Decision decide(
        String pace,
        float remainingDistance,
        float endurance,
        float fatigue,
        float health,
        boolean nativeCanSprint,
        boolean doorwayAhead
    ) {
        String requested = pace == null ? "normal" : pace.toLowerCase(Locale.ROOT);
        boolean catchUp = "catchup".equals(requested);
        boolean asksToRun = "run".equals(requested) || "sprint".equals(requested)
            || (catchUp && remainingDistance > 3.0f);
        boolean asksToSprint = "sprint".equals(requested)
            || (catchUp && remainingDistance > 10.0f);

        // An unreadable stat is unknown, not rested: a failed read must never
        // present as a stamina allowance the engine never confirmed.
        boolean staminaKnown = Float.isFinite(endurance) && Float.isFinite(fatigue);
        boolean canRun = staminaKnown && endurance > 0.22f && fatigue < 0.88f && health > 15.0f;
        boolean canSprint = staminaKnown && nativeCanSprint
            && endurance > 0.48f && fatigue < 0.72f && health > 25.0f;
        boolean sprinting = !doorwayAhead
            && asksToSprint
            && remainingDistance > SPRINT_REMAINING_DISTANCE
            && canSprint;
        boolean running = !doorwayAhead
            && asksToRun
            && remainingDistance > RUN_REMAINING_DISTANCE
            && canRun;
        return new Decision(running || sprinting, sprinting);
    }
}
