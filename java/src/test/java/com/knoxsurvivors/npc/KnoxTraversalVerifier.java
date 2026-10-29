package com.knoxsurvivors.npc;

import java.util.List;

/** Focused traversal-policy and route-continuation checks without a running game. */
public final class KnoxTraversalVerifier {
    private KnoxTraversalVerifier() {
    }

    public static void main(String[] args) {
        verifyNonDestructivePolicy();
        verifyExactEdgeSuppression();
        verifyInteractionOwnershipAndRouteContinuation();
        verifyNativeTraversalOwnsMovement();
        verifyNativeWindowCompletionReceipt();
        verifyCloseBehind();
        verifyRecoveryDoorAdmission();
        System.out.println(
            "KnoxTraversalVerifier PASS native=true nondestructive=true"
                + " exactEdge=true continuation=true interruption=true"
        );
    }

    private static void verifyNonDestructivePolicy() {
        require(KnoxTraversalPolicy.doorAction(true, false)
            == KnoxTraversalPolicy.DoorAction.PASS, "open door passes");
        require(KnoxTraversalPolicy.doorAction(false, false)
            == KnoxTraversalPolicy.DoorAction.TRY_NATIVE_OPEN,
            "closed door delegates one open attempt to native logic");
        require(KnoxTraversalPolicy.doorAction(false, true)
            == KnoxTraversalPolicy.DoorAction.FAIL_BARRICADED,
            "barricaded door fails without damage");

        require(KnoxTraversalPolicy.windowAction(false, false, false, false, "NONE")
            == KnoxTraversalPolicy.WindowAction.TRY_NATIVE_OPEN,
            "closed window delegates one open attempt to native logic");
        require(KnoxTraversalPolicy.windowAction(
            false, false, false, false, "OPEN_ATTEMPTED"
        ) == KnoxTraversalPolicy.WindowAction.FAIL_UNUSABLE,
            "failed window open does not authorize smashing");
        require(KnoxTraversalPolicy.windowAction(true, false, false, true, "OPEN_COMPLETED")
            == KnoxTraversalPolicy.WindowAction.CLIMB, "open climbable window climbs");
        require(KnoxTraversalPolicy.windowAction(false, true, false, true, "NONE")
            == KnoxTraversalPolicy.WindowAction.CLIMB, "broken climbable window climbs");
        require(KnoxTraversalPolicy.windowAction(false, false, true, false, "NONE")
            == KnoxTraversalPolicy.WindowAction.FAIL_BARRICADED,
            "barricaded window fails without damage");
    }

    private static void verifyExactEdgeSuppression() {
        KnoxNpc npc = new KnoxNpc("edge-test", new Object(), 0, 0, 0);
        npc.rememberTraversalFailure(1, 1, 0, 2, 1, 0, "FAILED_LOCKED_DOOR");
        require(npc.isTraversalCoolingDown(1, 1, 0, 2, 1, 0),
            "failed edge enters cooldown");
        require(!npc.isTraversalCoolingDown(1, 1, 0, 1, 2, 0),
            "different edge remains available for alternate route");
    }

    private static void verifyInteractionOwnershipAndRouteContinuation() {
        KnoxNpc npc = new KnoxNpc("route-test", new Object(), 0, 0, 0);
        Object firstEdge = new Object();
        Object replacementEdge = new Object();
        npc.setMovementRoute(List.of(
            new float[] { 1.5f, 0.5f, 0.0f },
            new float[] { 2.5f, 0.5f, 0.0f }
        ));
        npc.useTraversalInteractionTarget(firstEdge);
        npc.setTraversalInteractionStage("OPEN_ATTEMPTED");
        npc.useTraversalInteractionTarget(firstEdge);
        require("OPEN_ATTEMPTED".equals(npc.getTraversalInteractionStage()),
            "same edge retains its native interaction stage");
        npc.setTraversalInteractionStage("CLIMB_ATTEMPTED");
        npc.useTraversalInteractionTarget(firstEdge);
        require("CLIMB_ATTEMPTED".equals(npc.getTraversalInteractionStage()),
            "same fence edge keeps one pending native climb request");
        npc.useTraversalInteractionTarget(replacementEdge);
        require("NONE".equals(npc.getTraversalInteractionStage()),
            "changed world edge invalidates stale interaction intent");

        npc.advanceMovementRoute();
        require(npc.hasMovementRoute(),
            "crossing one obstacle node preserves the final route destination");
        require(npc.getTraversalInteractionTarget() == null,
            "crossed edge releases temporary traversal ownership");

        npc.useTraversalInteractionTarget(firstEdge);
        npc.setTraversalInteractionStage("OPEN_ATTEMPTED");
        npc.clearMovementRoute();
        require(!npc.hasMovementRoute() && npc.getTraversalInteractionTarget() == null
            && "NONE".equals(npc.getTraversalInteractionStage()),
            "interruption releases route and traversal sub-action together");
    }

    private static void verifyRecoveryDoorAdmission() {
        try {
            for (String scenario : List.of("open", "pre-opened", "noop", "far", "floor", "disabled", "barricade", "native-owner", "removed", "invalid")) {
                DoorActor actor = new DoorActor();
                DoorToken door = new DoorToken();
                door.open = false;
                actor.square = door.square;
                KnoxNpc npc = new KnoxNpc("recovery-door", actor, 10,20,0);
                KnoxNpcRuntime runtime = new KnoxNpcRuntime(npc);
                npc.setMovementRoute(List.of(new float[] {10.5f,19.5f,0}));
                KnoxNpcRegistry registry = new KnoxNpcRegistry();
                java.lang.reflect.Field active = KnoxNpcRegistry.class.getDeclaredField("activeNpcs");
                active.setAccessible(true);
                @SuppressWarnings("unchecked")
                java.util.Map<String,KnoxNpcRuntime> entries = (java.util.Map<String,KnoxNpcRuntime>) active.get(registry);
                entries.put("recovery-door",runtime);
                require(registry.openDoor("missing",door).equals("FAILED_NONE_ACTIVE"),
                    "recovery cannot substitute another NPC for a missing actor");
                switch (scenario) {
                    case "pre-opened" -> door.open = true;
                    case "noop" -> door.allowToggle = false;
                    case "far" -> door.adjacent = false;
                    case "floor" -> actor.z = 1;
                    case "disabled" -> npc.setDoorWindowOpeningAllowed(false);
                    case "barricade" -> door.barricaded = true;
                    case "native-owner" -> actor.state = "ClimbThroughWindowState";
                    case "removed" -> door.index = -1;
                }
                String result = registry.openDoor("recovery-door", scenario.equals("invalid") ? new Object() : door);
                boolean opened = scenario.equals("open");
                require(result.equals("OPENING_DOOR") == opened && npc.hasOpenedDoor() == opened,
                    "only actual admitted native opening grants the shared receipt: " + scenario);
                require(door.toggles == (opened || scenario.equals("noop") ? 1 : 0),
                    "recovery must not mutate a rejected native boundary: " + scenario);
                require(npc.hasMovementRoute(), "door observation must not replace the native route");
                if (opened) {
                    actor.square = door.other; actor.y = 19.5f;
                    require(registry.closeOpenedDoor("recovery-door").equals("DOOR_RETIRED"),
                        "retirement is not an invented native-close success receipt");
                    require(!door.open && !npc.hasOpenedDoor() && door.toggles==2,
                        "Lua-style recovery opening uses the same crossing-aware native close owner");
                }
            }
        } catch (ReflectiveOperationException failure) { throw new AssertionError("native door recovery fixture failed",failure); }
    }

    private static void verifyCloseBehind() {
        for (boolean north : List.of(true, false)) {
            for (boolean fromPositive : List.of(true, false)) {
                verifyCloseBehind(north, fromPositive);
            }
        }
    }

    private static void verifyCloseBehind(boolean north, boolean fromPositive) {
        DoorActor actor = new DoorActor();
        DoorToken door = new DoorToken();
        door.north = north;
        door.other = new zombie.iso.IsoGridSquare(north ? 10 : 9, north ? 19 : 20, 0);
        door.square.neighbor = door.other;
        door.other.neighbor = door.square;
        KnoxNpc npc = new KnoxNpc("door-crossing", actor, 10, 20, 0);
        npc.rememberOpenedDoor(door, 10, 20, 0, north, fromPositive);
        actor.square = fromPositive ? door.square : door.other;
        actor.x = actor.square.getX() + 0.5f;
        actor.y = actor.square.getY() + 0.5f;
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 0 && npc.hasOpenedDoor(), "opening side must wait for a real crossing");
        actor.square = fromPositive ? door.other : door.square;
        // A boundary transition is not yet a fully cleared doorway.
        actor.x = north ? 10.5f : (fromPositive ? 9.9f : 10.1f);
        actor.y = north ? (fromPositive ? 19.9f : 20.1f) : 20.5f;
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 0 && npc.hasOpenedDoor(), "must clear the doorway before closing");
        actor.x = actor.square.getX() + 0.5f;
        actor.y = actor.square.getY() + 0.5f;
        door.other.moving.add(new Object());
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 0 && npc.hasOpenedDoor(), "other doorway users retain passage");
        door.other.moving.clear();
        door.square.moving.add(new Object());
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 0, "both doorway squares must be clear");
        door.square.moving.clear();
        door.square.moving.add(actor);
        door.obstructed = true;
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 0 && npc.hasOpenedDoor(), "native obstruction keeps the doorway open");
        door.obstructed = false;
        actor.state = "ClimbOverFenceState";
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 0 && npc.hasOpenedDoor(), "native action retains its own inputs");
        actor.state = "IdleState";
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 1 && !door.open && !npc.hasOpenedDoor(),
            "completed crossing closes a self-opened door while still in native reach");
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 1, "completed close-behind cannot toggle again");
        door.open = true;
        KnoxNpcFactory.closeOpenedDoorBehind(npc);
        require(door.toggles == 1 && door.open, "pre-opened doors without a receipt stay open");

        for (String invalid : List.of("far", "floor", "removed", "destroyed", "barricaded", "closed", "native-reach", "moved", "unloaded", "no-square", "orientation", "noop")) {
            DoorActor staleActor = new DoorActor();
            DoorToken staleDoor = new DoorToken();
            staleActor.square = staleDoor.other;
            staleActor.y = 19.5f;
            KnoxNpc stale = new KnoxNpc("stale-door", staleActor, 10, 20, 0);
            stale.rememberOpenedDoor(staleDoor, 10, 20, 0, true, true);
            switch (invalid) {
                case "far" -> { staleActor.square = new zombie.iso.IsoGridSquare(10, 24, 0); staleActor.y = 24.5f; }
                case "floor" -> staleActor.z = 1;
                case "removed" -> staleDoor.index = -1;
                case "destroyed" -> staleDoor.destroyed = true;
                case "barricaded" -> staleDoor.barricaded = true;
                case "closed" -> staleDoor.open = false;
                case "native-reach" -> staleDoor.adjacent = false;
                case "moved" -> staleDoor.square = new zombie.iso.IsoGridSquare(11, 20, 0);
                case "unloaded" -> staleDoor.square.neighbor = null;
                case "no-square" -> staleActor.square = null;
                case "orientation" -> staleDoor.north = false;
                case "noop" -> staleDoor.allowToggle = false;
            }
            KnoxNpcFactory.closeOpenedDoorBehind(stale);
            require(!stale.hasOpenedDoor() && staleDoor.toggles == (invalid.equals("noop") ? 1 : 0),
                "invalid/no-op receipt must retire without remote mutation or repeated attempts: " + invalid);
        }
    }

    public static final class DoorActor extends zombie.characters.IsoGameCharacter {
        float x = 10.5f, y = 20.5f, z;
        String state = "IdleState";
        zombie.iso.IsoGridSquare square;
        public float getX() { return x; }
        public float getY() { return y; }
        public float getZ() { return z; }
        public zombie.iso.IsoGridSquare getCurrentSquare() { return square; }
        public boolean isDead() { return false; }
        public boolean isClimbing() { return false; }
        public String getCurrentStateName() { return state; }
        public String getCurrentActionContextStateName() { return state; }
    }

    public static final class DoorToken extends zombie.iso.objects.IsoDoor {
        zombie.iso.IsoGridSquare square = new zombie.iso.IsoGridSquare(10,20,0);
        zombie.iso.IsoGridSquare other = new zombie.iso.IsoGridSquare(10,19,0);
        boolean north = true, open = true, obstructed, barricaded, adjacent = true, destroyed, allowToggle = true;
        int index = 1, toggles;
        DoorToken() { square.neighbor = other; other.neighbor = square; }
        public zombie.iso.IsoGridSquare getSquare() { return square; }
        public boolean getNorth() { return north; }
        public boolean IsOpen() { return open; }
        public boolean isBarricaded() { return barricaded; }
        public boolean isObstructed() { return obstructed; }
        public boolean isDestroyed() { return destroyed; }
        public int getObjectIndex() { return index; }
        public boolean isAdjacentToSquare(zombie.iso.IsoGridSquare current) { return adjacent; }
        public void ToggleDoor(zombie.characters.IsoGameCharacter actor) { toggles++; if (allowToggle) open = !open; }
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }

    private static void verifyNativeTraversalOwnsMovement() {
        require(!KnoxTraversalPolicy.nativeTraversalBusy(false, "IdleState", "idle"),
            "landing releases native traversal ownership");
        require(!KnoxTraversalPolicy.nativeTraversalBusy(false, null, null),
            "absent state names do not manufacture traversal");
        require(KnoxTraversalPolicy.nativeTraversalBusy(true, "IdleState", "idle"),
            "an explicit native climbing flag still owns movement");
        for (String state : List.of("ClimbOverFenceState", "ClimbOverWallState",
            "ClimbThroughWindowState", "VaultState", "OpenWindowState", "SmashWindowState")) {
            for (boolean actionContextOnly : List.of(false, true)) {
                TraversalActor actor = new TraversalActor(
                    actionContextOnly ? "IdleState" : state,
                    actionContextOnly ? state : "idle", false
                );
                KnoxNpc npc = new KnoxNpc("native-state", actor, 0, 0, 0);
                npc.setMovementRoute(List.of(new float[] { 0.5f, 0.5f, 0 }));
                try {
                    String result = KnoxNpcFactory.tickMovement(npc, 0, "normal");
                    require("Transition:CLIMBING".equals(result),
                        "native state owns traversal even when isClimbing is false: " + state);
                    require(npc.hasMovementRoute() && npc.currentMovementNode() != null,
                        "crossing cannot advance/complete the route before native state exits");
                    require(npc.hasMovementTraversalEvidence("CLIMBING"),
                        "native traversal evidence remains available to lifecycle ownership");
                } catch (ReflectiveOperationException failure) {
                    throw new AssertionError("route queried locomotion during " + state, failure);
                }
            }
        }
    }

    private static void verifyNativeWindowCompletionReceipt() {
        try {
            WindowActor actor = new WindowActor();
            WindowToken window = new WindowToken();
            actor.window = window;
            KnoxNpc npc = new KnoxNpc("window-receipt", actor, 0, 0, 0);
            KnoxNpcRuntime runtime = new KnoxNpcRuntime(npc);
            npc.setMovementRoute(List.of(new float[] { 1.5f, 0.5f, 0 }));
            npc.useTraversalInteractionTarget(window);
            npc.setTraversalInteractionStage("OPEN_ATTEMPTED");
            actor.completion = "success";
            // Observation also works while Lua waits on a pending order and
            // no native movement request is being polled by the controller.
            KnoxNpcRegistry registry = new KnoxNpcRegistry();
            java.lang.reflect.Field active = KnoxNpcRegistry.class.getDeclaredField("activeNpcs");
            active.setAccessible(true);
            @SuppressWarnings("unchecked")
            java.util.Map<String, KnoxNpcRuntime> entries = (java.util.Map<String, KnoxNpcRuntime>) active.get(registry);
            entries.put("window-receipt", runtime);
            require("NATIVE_ACTION:OPEN_COMPLETED".equals(registry.observeNativeAction("window-receipt")),
                "native observation must not require an active movement request");
            String result = KnoxNpcFactory.tickMovement(npc, 0, "normal");
            require(window.open && window.toggles == 1,
                "native opening success must complete the off-slot world-state step before the traversal guard");
            require(result.startsWith("Transition:") && npc.hasMovementRoute(),
                "completion receipt must not advance movement during native opening");
            require("OPEN_COMPLETED".equals(npc.getTraversalInteractionStage()), "completion must be recorded once");
            KnoxNpcFactory.tickMovement(npc, 0, "normal");
            require(window.toggles == 1 && window.open, "repeated native success must not close the window again");
            actor.state = "ClimbThroughWindowState";
            KnoxNpcFactory.tickMovement(npc, 0, "normal");
            require(npc.hasMovementRoute(), "the native crossing retains the remaining Follow route");
            require(KnoxTraversalPolicy.windowAction(window.open, false, false, true,
                npc.getTraversalInteractionStage()) == KnoxTraversalPolicy.WindowAction.CLIMB,
                "the verified open window remains available to the native climb path");

            for (String rejection : List.of("failure", "missing", "different-window", "removed", "toggle-noop", "stale-stage", "different-state", "dead-actor", "detached-actor")) {
                WindowActor rejectedActor = new WindowActor();
                WindowToken rejectedWindow = new WindowToken();
                rejectedActor.window = rejectedWindow;
                rejectedActor.completion = rejection.equals("failure") ? "fail" : "success";
                if (rejection.equals("missing")) rejectedActor.completion = "";
                if (rejection.equals("different-window")) rejectedActor.window = new WindowToken();
                if (rejection.equals("removed")) rejectedWindow.index = -1;
                if (rejection.equals("toggle-noop")) rejectedWindow.allowToggle = false;
                if (rejection.equals("different-state")) rejectedActor.state = "SmashWindowState";
                rejectedActor.dead = rejection.equals("dead-actor");
                rejectedActor.detached = rejection.equals("detached-actor");
                KnoxNpc rejected = new KnoxNpc("rejected-window", rejectedActor, 0, 0, 0);
                rejected.setMovementRoute(List.of(new float[] { 1.5f, 0.5f, 0 }));
                rejected.useTraversalInteractionTarget(rejectedWindow);
                rejected.setTraversalInteractionStage(rejection.equals("stale-stage") ? "NONE" : "OPEN_ATTEMPTED");
                KnoxNpcFactory.tickMovement(rejected, 0, "normal");
                require(!rejectedWindow.open && rejected.hasMovementRoute(),
                    "no opening may be fabricated and native movement stays paused: " + rejection);
                require(!"OPEN_COMPLETED".equals(rejected.getTraversalInteractionStage()),
                    "no-op native world change cannot become completion: " + rejection);
                KnoxNpcFactory.tickMovement(rejected, 0, "normal");
                require(rejectedWindow.toggles <= 1, "native completion is never retried within the same action: " + rejection);
            }
            for (String unavailable : List.of("dead", "detached", "unreadable-square")) {
                WindowActor staleActor = new WindowActor();
                staleActor.dead = unavailable.equals("dead");
                staleActor.detached = unavailable.equals("detached");
                staleActor.unreadableSquare = unavailable.equals("unreadable-square");
                WindowToken staleWindow = new WindowToken();
                staleActor.window=staleWindow;staleActor.completion="success";
                KnoxNpc staleNpc=new KnoxNpc("stale-native-receipt",staleActor,0,0,0);
                KnoxNpcRuntime staleRuntime=new KnoxNpcRuntime(staleNpc);
                staleNpc.useTraversalInteractionTarget(staleWindow);
                staleNpc.setTraversalInteractionStage("OPEN_ATTEMPTED");
                entries.put("stale-native-receipt",staleRuntime);
                registry.observeNativeAction("stale-native-receipt");
                require(!staleWindow.open && staleWindow.toggles==0
                    && !staleNpc.getTraversalInteractionStage().equals("OPEN_COMPLETED"),
                    "standalone receipt observation cannot mutate the world for an unavailable actor: " + unavailable);
            }
        } catch (ReflectiveOperationException failure) {
            throw new AssertionError("native-window receipt fixture failed", failure);
        }
    }

    /** Native-shaped receipt doubles. No game actor/world is constructed. */
    public static final class WindowActor extends zombie.characters.IsoGameCharacter {
        String state = "OpenWindowState";
        String completion = "";
        Object window;
        boolean dead, detached, unreadableSquare;
        public boolean isDead() { return dead; }
        public zombie.iso.IsoGridSquare getCurrentSquare() {
            if (unreadableSquare) throw new IllegalStateException("streamed body square unavailable");
            return detached ? null : new zombie.iso.IsoGridSquare();
        }
        public boolean isClimbing() { return false; }
        public String getCurrentStateName() { return state; }
        public String getCurrentActionContextStateName() { return state; }
        public String getVariableString(String name) { return completion; }
        public Object get(zombie.ai.State.Param<?> key) { return window; }
    }
    public static final class WindowToken {
        boolean open;
        boolean allowToggle = true;
        int index = 1;
        int toggles;
        public boolean IsOpen() { return open; }
        public int getObjectIndex() { return index; }
        public void ToggleWindow(zombie.characters.IsoGameCharacter actor) {
            toggles++;
            if (allowToggle) open = !open;
        }
    }

    /** Only traversal observations exist: a route/path query during crossing is a failure. */
    public static final class TraversalActor {
        private final String state;
        private final String action;
        private final boolean climbing;

        TraversalActor(String state, String action, boolean climbing) {
            this.state = state;
            this.action = action;
            this.climbing = climbing;
        }

        public String getCurrentStateName() { return state; }
        public String getCurrentActionContextStateName() { return action; }
        public boolean isClimbing() { return climbing; }
    }
}
