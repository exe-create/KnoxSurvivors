package com.knoxsurvivors.npc;

/** Pure traversal decisions kept separate from reflective engine interaction. */
final class KnoxTraversalPolicy {
    enum DoorAction {
        PASS,
        TRY_NATIVE_OPEN,
        FAIL_BARRICADED
    }

    enum WindowAction {
        TRY_NATIVE_OPEN,
        CLIMB,
        FAIL_BARRICADED,
        FAIL_UNUSABLE
    }

    private KnoxTraversalPolicy() {
    }

    static boolean nativeTraversalBusy(boolean climbing, String stateName, String actionName) {
        if (climbing) return true;
        String state = (String.valueOf(stateName) + " " + String.valueOf(actionName))
            .toLowerCase(java.util.Locale.ROOT);
        return state.contains("climb") || state.contains("vault")
            || state.contains("openwindow") || state.contains("smashwindow");
    }

    static DoorAction doorAction(boolean open, boolean barricaded) {
        if (open) {
            return DoorAction.PASS;
        }
        return barricaded ? DoorAction.FAIL_BARRICADED : DoorAction.TRY_NATIVE_OPEN;
    }

    static WindowAction windowAction(
        boolean open,
        boolean smashed,
        boolean barricaded,
        boolean canClimb,
        String interactionStage
    ) {
        if (barricaded) {
            return WindowAction.FAIL_BARRICADED;
        }
        if (open || smashed) {
            return canClimb ? WindowAction.CLIMB : WindowAction.FAIL_UNUSABLE;
        }
        return "NONE".equals(interactionStage)
            ? WindowAction.TRY_NATIVE_OPEN
            : WindowAction.FAIL_UNUSABLE;
    }
}
