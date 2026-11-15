package com.knoxsurvivors.npc;

import java.util.List;

/** Focused traversal-policy and route-continuation checks without a running game. */
public final class KnoxTraversalVerifier {
    private KnoxTraversalVerifier() {
    }

    public static void main(String[] args) {
        verifyNonDestructivePolicy();
        verifyNativeRopeAdmission();
        verifyFurnitureStallContext();
        verifyExactEdgeSuppression();
        verifyCooldownRetention();
        verifyInteractionOwnershipAndRouteContinuation();
        verifyNativeTraversalOwnsMovement();
        verifyNativeWindowCompletionReceipt();
        verifySparseWindowAndLanding();
        verifyCloseBehind();
        verifyRecoveryDoorAdmission();
        verifyDiagonalCornerCut();
        verifySparseDoorwayPace();
        verifyFinalRouteArrival();
        System.out.println(
            "KnoxTraversalVerifier PASS native=true nondestructive=true"
                + " exactEdge=true continuation=true interruption=true"
        );
    }

    private static void verifySparseWindowAndLanding() {
        try {
            PendingWindowActor actor = new PendingWindowActor();
            PendingWindow window = new PendingWindow();
            actor.here.window = window;
            KnoxNpc npc = new KnoxNpc("sparse-window", actor, 0, 0, 0);
            npc.useTraversalInteractionTarget(window);
            npc.setTraversalInteractionStage("CLIMB_ATTEMPTED");
            var transition = KnoxNpcFactory.class.getDeclaredMethod(
                "handleRouteTransition", KnoxNpc.class, Object.class, float[].class);
            transition.setAccessible(true);
            for (int i=0; i<3; i++) {
                require("ManualRoute".equals(transition.invoke(null, npc, actor, new float[]{10.5f,.5f,0})),
                    "long native segment must observe the pending window edge, never restart its climb");
            }
            require(actor.cell.queries == 3, "the first adjacent tile, not the distant path endpoint, is checked");
            zombie.iso.IsoGridSquare landing = new zombie.iso.IsoGridSquare(1,0,0);
            require(KnoxNpcFactory.windowLandingClear(actor,landing), "empty landing is usable");
            WindowActor occupant = new WindowActor();
            landing.moving.add(occupant);
            require(!KnoxNpcFactory.windowLandingClear(actor,landing), "a live body blocks the landing");
            occupant.dead = true;
            require(KnoxNpcFactory.windowLandingClear(actor,landing), "dead bodies do not become a fabricated live threat");
            System.out.println("Window edge PASS sparse_segment=true pending_climb_preserved=true occupied_landing_rejected=true");
        } catch (ReflectiveOperationException failure) {
            throw new AssertionError("sparse window fixture failed", failure);
        }
    }

    public static final class PendingWindow {
        public boolean IsOpen() { return true; }
        public boolean isSmashed() { return false; }
        public boolean isBarricaded() { return false; }
    }
    public static final class PendingWindowCell {
        int queries;
        public zombie.iso.IsoGridSquare getGridSquare(int x,int y,int z) {
            require(x==1 && y==0 && z==0,"only adjacent sparse edge is queried");
            queries++;
            return new zombie.iso.IsoGridSquare(x,y,z);
        }
    }
    public static final class PendingWindowActor {
        final zombie.iso.IsoGridSquare here = new zombie.iso.IsoGridSquare(0,0,0);
        final PendingWindowCell cell = new PendingWindowCell();
        public float getX() { return .5f; }
        public float getY() { return .5f; }
        public zombie.iso.IsoGridSquare getCurrentSquare() { return here; }
        public PendingWindowCell getCell() { return cell; }
        public String getCurrentStateName() { return "IdleState"; }
    }

    private static void verifyFurnitureStallContext() {
        String context=KnoxNpcFactory.movementObstacleContext(new KnoxNpc("furniture-context",new FurnitureActor(),0,0,0));
        require(context.contains("couch_tile") && context.contains("count=20"), "stall context captures real sprite facts");
        require(context.length()<420 && !context.contains("\n"), "stall evidence remains bounded and single-line");
        require(KnoxNpcFactory.movementObstacleContext(new KnoxNpc("unreadable",new Object(),0,0,0)).equals("objects=unreadable"),
            "unavailable geometry must never turn a movement refusal into a diagnostic exception");
    }
    public static final class FurnitureActor {
        public FurnitureActor getCurrentSquare() { return this; }
        public List<Object> getObjects() { return java.util.Collections.nCopies(20,new FurnitureSprite()); }
    }
    public static final class FurnitureSprite {
        public FurnitureSprite getSprite() { return this; }
        public String getName() { return "couch_tile\n" + "a".repeat(100); }
    }

    private static void verifyNativeRopeAdmission() {
        try {
            var transition=KnoxNpcFactory.class.getDeclaredMethod("handleRouteTransition",KnoxNpc.class,Object.class,float[].class);
            transition.setAccessible(true);
            for (boolean down : List.of(false,true)) {
                RopeActor actor=new RopeActor(down ? 1 : 0);
                KnoxNpc npc=new KnoxNpc("rope",actor,0,0,down ? 1 : 0);
                float[] node={.5f,.5f,down ? 0 : 1};
                String started=String.valueOf(transition.invoke(null,npc,actor,node));
                require(started.equals(down ? "STARTED_ROPE_DESCENT" : "STARTED_ROPE_CLIMB") && actor.calls==1,
                    "native-admitted rope direction starts exactly its native action");
                require("ManualRoute".equals(transition.invoke(null,npc,actor,node)) && actor.calls==1,
                    "an admitted rope transition cannot restart before native ownership settles");
                npc.clearMovementRoute();npc.setClimbingAllowed(false);
                require("FAILED_CLIMBING_DISABLED".equals(transition.invoke(null,npc,actor,node)) && actor.calls==1,
                    "companion climb permission also governs sheet ropes");
                npc.setClimbingAllowed(true);actor.allowed=false;
                require("CLEAR".equals(transition.invoke(null,npc,actor,node)) && actor.calls==1,
                    "stairs retain existing route behavior when native rope validation refuses");
            }
        } catch (ReflectiveOperationException failure) {throw new AssertionError("native rope fixture failed",failure);}
    }
    public static final class RopeActor extends zombie.characters.IsoPlayer {
        final zombie.iso.IsoGridSquare square;
        boolean allowed=true;int calls;
        RopeActor(int z) { square=new zombie.iso.IsoGridSquare(0,0,z); }
        public zombie.iso.IsoGridSquare getCurrentSquare() { return square; }
        public Object getCell() { return this; }
        public boolean canClimbSheetRope(zombie.iso.IsoGridSquare value) { return allowed && value==square; }
        public boolean canClimbDownSheetRope(zombie.iso.IsoGridSquare value) { return allowed && value==square; }
        public void climb() { calls++; }
        public void climbDown() { calls++; }
        public void setJustMoved(boolean value) { }
        public void setRunning(boolean value) { }
        public void setSprinting(boolean value) { }
        public void setSneaking(boolean value) { }
        public Object getECSComponent(Class<?> type) { return null; }
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

        require(KnoxTraversalPolicy.windowAction(false, false, false, false, true, "NONE")
            == KnoxTraversalPolicy.WindowAction.TRY_NATIVE_OPEN,
            "closed window delegates one open attempt to native logic");
        require(KnoxTraversalPolicy.windowAction(
            false, false, false, false, true, "OPEN_ATTEMPTED"
        ) == KnoxTraversalPolicy.WindowAction.FAIL_UNUSABLE,
            "failed window open does not authorize smashing");
        require(KnoxTraversalPolicy.windowAction(true, false, false, true, true, "OPEN_COMPLETED")
            == KnoxTraversalPolicy.WindowAction.CLIMB, "open climbable window climbs");
        require(KnoxTraversalPolicy.windowAction(false, true, false, true, false, "NONE")
            == KnoxTraversalPolicy.WindowAction.CLEAR_GLASS, "remaining broken glass must be cleared before climbing");
        require(KnoxTraversalPolicy.windowAction(true, true, false, true, false, "GLASS_REQUIRED")
            == KnoxTraversalPolicy.WindowAction.CLEAR_GLASS, "opening a smashed window does not bypass glass removal");
        require(KnoxTraversalPolicy.windowAction(false, true, false, true, true, "NONE")
            == KnoxTraversalPolicy.WindowAction.CLIMB, "broken climbable window climbs");
        require(KnoxTraversalPolicy.windowAction(false, false, true, false, false, "NONE")
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

    private static void verifyCooldownRetention() {
        long[] now = {0};
        KnoxNpc npc = new KnoxNpc("cooldown-retention", new Object(), 0, 0, 0, () -> now[0]);
        for (int edge = 0; edge < 1000; edge++) {
            now[0] += 100;
            npc.rememberTraversalFailure(edge, 0, 0, edge + 1, 0, 0, "FAILED_LOCKED_DOOR");
        }
        try {
            var field = KnoxNpc.class.getDeclaredField("traversalCooldowns");
            field.setAccessible(true);
            var retained = (java.util.Map<?, ?>) field.get(npc);
            require(retained.size() == 50,
                "expired distinct edges must be retired without revisiting them");
            require(npc.isTraversalCoolingDown(999, 0, 0, 1000, 0, 0),
                "cleanup must retain a still-active failed edge");
            now[0] += 5000;
            require(!npc.isTraversalCoolingDown(999, 0, 0, 1000, 0, 0),
                "the exact expiry boundary permits retry");
            npc.rememberTraversalFailure(2000, 0, 0, 2001, 0, 0, "FAILED_WINDOW");
            require(retained.size() == 1, "a new failure cannot retain expired history");
            now[0] += 1800;
            require(!npc.isTraversalCoolingDown(2000, 0, 0, 2001, 0, 0),
                "ordinary failures retain their existing shorter cooldown");
            System.out.println("Traversal retention PASS distinctEdges=1000 retainedRecent=50 clock=controlled nativePerformance=false");
        } catch (ReflectiveOperationException failure) {
            throw new AssertionError("cooldown retention fixture failed", failure);
        }
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

    private static void verifyDiagonalCornerCut() {
        try {
            var transition = KnoxNpcFactory.class.getDeclaredMethod(
                "handleRouteTransition", KnoxNpc.class, Object.class, float[].class);
            transition.setAccessible(true);
            // Open diagonal: direct and both cardinal corner-cut steps clear.
            CornerCell open = new CornerCell();
            open.add(0, 0, 0); open.add(1, 0, 0); open.add(0, 1, 0); open.add(1, 1, 0);
            CornerActor openActor = new CornerActor(open, 0, 0);
            KnoxNpc openNpc = new KnoxNpc("corner-open", openActor, 0, 0, 0);
            require("CLEAR".equals(transition.invoke(null, openNpc, openActor, new float[]{1.5f, 1.5f, 0})),
                "an open diagonal still routes directly");
            // Wall corner cut: the diagonal reads clear but the east edge is a wall.
            CornerCell corner = new CornerCell();
            corner.add(0, 0, 0); corner.add(1, 0, 0); corner.add(0, 1, 0); corner.add(1, 1, 0);
            corner.block(0, 0, 0, 1, 0, 0);
            corner.block(1, 0, 0, 1, 1, 0);
            CornerActor cornerActor = new CornerActor(corner, 0, 0);
            KnoxNpc cornerNpc = new KnoxNpc("corner-cut", cornerActor, 0, 0, 0);
            require("FAILED_BLOCKED_DIAGONAL".equals(
                transition.invoke(null, cornerNpc, cornerActor, new float[]{1.5f, 1.5f, 0})),
                "a diagonal clipping a wall corner fails by name instead of wedging");
            // This segment enters the open south lane before reaching the diagonal
            // tile. The east wall belongs to a different edge.
            require("CLEAR".equals(transition.invoke(null, cornerNpc, cornerActor, new float[]{1.1f, 1.9f, 0})),
                "an adjacent diagonal destination checks the first crossed cardinal edge");
            // Sealed diagonal keeps its existing failure name.
            CornerCell sealed = new CornerCell();
            sealed.add(0, 0, 0); sealed.add(1, 0, 0); sealed.add(0, 1, 0); sealed.add(1, 1, 0);
            sealed.block(0, 0, 0, 1, 1, 0);
            CornerActor sealedActor = new CornerActor(sealed, 0, 0);
            KnoxNpc sealedNpc = new KnoxNpc("corner-sealed", sealedActor, 0, 0, 0);
            require("FAILED_BLOCKED_DIAGONAL".equals(
                transition.invoke(null, sealedNpc, sealedActor, new float[]{1.5f, 1.5f, 0})),
                "a sealed diagonal still fails by name");
            // Unloaded corner square fails closed, never clips through fog.
            CornerCell fog = new CornerCell();
            fog.add(0, 0, 0); fog.add(0, 1, 0); fog.add(1, 1, 0);
            CornerActor fogActor = new CornerActor(fog, 0, 0);
            KnoxNpc fogNpc = new KnoxNpc("corner-fog", fogActor, 0, 0, 0);
            require("FAILED_BLOCKED_DIAGONAL".equals(
                transition.invoke(null, fogNpc, fogActor, new float[]{1.5f, 1.5f, 0})),
                "a diagonal past an unstreamed corner fails closed");
            // Cardinal steps are untouched: the same wall still admits the open lane.
            CornerActor laneActor = new CornerActor(corner, 0, 0);
            KnoxNpc laneNpc = new KnoxNpc("corner-lane", laneActor, 0, 0, 0);
            require("CLEAR".equals(transition.invoke(null, laneNpc, laneActor, new float[]{0.5f, 1.5f, 0})),
                "the open cardinal lane around the corner still routes");
            System.out.println("Diagonal corner PASS open=true cut_rejected=true sealed=true unloaded=true lane_kept=true");
        } catch (ReflectiveOperationException failure) {
            throw new AssertionError("diagonal corner fixture failed", failure);
        }
    }

    private static void verifySparseDoorwayPace() {
        try {
            var doorway = KnoxNpcFactory.class.getDeclaredMethod(
                "doorwayEdgeAhead", Object.class, float.class, float.class);
            doorway.setAccessible(true);
            for (int direction : List.of(-1, 1)) {
                CornerCell cell = new CornerCell();
                cell.add(0, 0, 0); cell.add(direction, 0, 0); cell.add(0, direction, 0);
                RouteActor actor = new RouteActor(cell, .5f, .5f, 0);
                cell.getGridSquare(0, 0, 0).doorTo = cell.getGridSquare(direction, 0, 0);
                require((Boolean) doorway.invoke(null, actor, direction * 8 + .5f, .5f),
                    "a sparse route recognizes the immediate doorway in either direction");
                require((Boolean) doorway.invoke(null, actor, direction * 1.4f + .5f, direction * .6f + .5f),
                    "an angled adjacent route recognizes its first crossed doorway");
                require(!(Boolean) doorway.invoke(null, actor, .5f, direction * 8 + .5f),
                    "a nearby doorway off the route cannot slow an open lane");
                require(!(Boolean) doorway.invoke(null, actor, direction * 8 + .5f, direction * 8 + .5f),
                    "an exact diagonal corner does not guess a cardinal doorway");
                require(!(Boolean) doorway.invoke(null, actor, .6f, .5f),
                    "a same-tile goal does not inspect a remote doorway");
                cell.getGridSquare(0, 0, 0).doorTo = null;
                require(!(Boolean) doorway.invoke(null, actor, direction * 8 + .5f, .5f),
                    "a sparse route without a doorway keeps ordinary pacing");
                cell.squares.remove(direction + ",0,0");
                require(!(Boolean) doorway.invoke(null, actor, direction * 8 + .5f, .5f),
                    "an unloaded first edge cannot invent a doorway");
            }
            System.out.println("Sparse doorway PASS immediate_edge=true directions=true angled=true no_guess=true");
        } catch (ReflectiveOperationException failure) {
            throw new AssertionError("sparse doorway fixture failed", failure);
        }
    }

    private static void verifyFinalRouteArrival() {
        try {
            var drive = KnoxNpcFactory.class.getDeclaredMethod(
                "driveCapturedRoute", KnoxNpc.class, float.class, String.class);
            drive.setAccessible(true);
            CornerCell cell = new CornerCell();
            cell.add(10, 20, 0); cell.add(10, 20, 1); cell.add(11, 20, 0);
            RouteActor actor = new RouteActor(cell, 10.1f, 20.5f, 0);
            KnoxNpc npc = new KnoxNpc("precise-combat-goal", actor, 10, 20, 0);
            npc.setCombatActive(true);
            npc.setMovementRoute(List.of(new float[]{10.8f, 20.5f, 0}));
            require("ManualRoute".equals(drive.invoke(null, npc, .7f, "run"))
                && npc.hasMovementRoute() && actor.playerMoveDir.x > 0,
                "a combat final goal in the current tile retains movement until precise arrival");
            actor.x = 10.75f;
            require("ManualRoute".equals(drive.invoke(null, npc, .05f, "run")),
                "a combat final goal outside its existing tolerance remains active");
            actor.x = 10.78f;
            require("Succeeded".equals(drive.invoke(null, npc, .02f, "run"))
                && !npc.hasMovementRoute() && actor.playerMoveDir.x == 0,
                "a combat final goal inside its existing tolerance releases movement");
            actor.x = 10.1f;
            npc.setCombatActive(false);
            actor.x = 10.01f; actor.y = 20.01f;
            npc.setMovementRoute(List.of(new float[]{10.5f, 20.5f, 0}));
            require("ManualRoute".equals(drive.invoke(null, npc, .693f, "run")) && npc.hasMovementRoute(),
                "an ordinary final goal in the same tile outside runtime arrival cannot repeatedly finish early");
            actor.x = 10.3f; actor.y = 20.3f;
            require("Succeeded".equals(drive.invoke(null, npc, .283f, "run")),
                "an ordinary final goal inside its existing node tolerance releases movement");
            actor.x = 10.1f; actor.y = 20.5f;
            npc.setMovementRoute(List.of(new float[]{10.8f, 20.5f, 0}, new float[]{11.5f, 20.5f, 0}));
            require("ManualRoute".equals(drive.invoke(null, npc, 1.4f, "run"))
                && npc.currentMovementNode()[0] == 11.5f,
                "ordinary intermediate nodes retain forward tile-based release");
            npc.setCombatActive(true);
            npc.setMovementRoute(List.of(new float[]{10.8f, 20.5f, 0}, new float[]{11.5f, 20.5f, 0}));
            require("ManualRoute".equals(drive.invoke(null, npc, 1.4f, "run"))
                && npc.currentMovementNode()[0] == 11.5f,
                "intermediate combat nodes retain forward tile-based release");
            CornerCell blockedCell = new CornerCell();
            blockedCell.add(0, 0, 0); blockedCell.add(1, 0, 0); blockedCell.add(0, 1, 0);
            blockedCell.block(0, 0, 0, 1, 0, 0);
            RouteActor blockedActor = new RouteActor(blockedCell, .9f, .9f, 0);
            KnoxNpc blockedNpc = new KnoxNpc("corner-blocked-edge", blockedActor, 0, 0, 0);
            float[] corner = {1.1f, .9f, 0};
            blockedNpc.setMovementRoute(List.of(corner, new float[]{1.1f, 1.5f, 0}));
            require("FailedObstacle:FAILED_STATIC_BLOCKAGE".equals(drive.invoke(null, blockedNpc, 1, "walk"))
                && blockedNpc.currentMovementNode() == corner,
                "corner node stays current and its blocked edge is observed");
            npc.setMovementRoute(List.of(new float[]{11.1f, 20.5f, 1}));
            require("ManualRoute".equals(drive.invoke(null, npc, 1, "run")) && npc.hasMovementRoute(),
                "a combat final goal on a different floor cannot count as arrival");
            System.out.println("Route arrival PASS precise_final=true tolerance=true ordinary=true intermediate=true floor=true");
        } catch (ReflectiveOperationException failure) {
            throw new AssertionError("final route arrival fixture failed", failure);
        }
    }

    public static final class RouteActor extends zombie.characters.IsoPlayer {
        final CornerCell cell;
        float x, y;
        final int z;
        RouteActor(CornerCell cell, float x, float y, int z) {
            this.cell = cell; this.x = x; this.y = y; this.z = z;
        }
        public float getX() { return x; }
        public float getY() { return y; }
        public float getZ() { return z; }
        public CornerSquare getCurrentSquare() { return cell.getGridSquare((int)Math.floor(x), (int)Math.floor(y), z); }
        public CornerCell getCell() { return cell; }
        public boolean isAiming() { return false; }
        public void setDirectionAngle(float angle) { }
        public void setJustMoved(boolean value) { }
        public void setRunning(boolean value) { }
        public void setSprinting(boolean value) { }
        public void setSneaking(boolean value) { }
        public Object getECSComponent(Class<?> type) { return null; }
    }

    /** Directional wall-corner doubles: no game actor or world is constructed. */
    public static final class CornerSquare {
        final int x, y, z;
        final java.util.Set<String> blockedTo = new java.util.HashSet<>();
        CornerSquare doorTo;
        CornerSquare(int x, int y, int z) { this.x = x; this.y = y; this.z = z; }
        public int getX() { return x; }
        public int getY() { return y; }
        public int getZ() { return z; }
        public boolean isBlockedTo(CornerSquare next) {
            return next != null && blockedTo.contains(next.x + "," + next.y + "," + next.z);
        }
        public Object getDoorTo(CornerSquare next) { return next == doorTo ? doorTo : null; }
        public Object getWindowTo(CornerSquare next) { return null; }
        public Object getWindowThumpableTo(CornerSquare next) { return null; }
        public Object getWindowFrameTo(CornerSquare next) { return null; }
        public boolean isHoppableTo(CornerSquare next) { return false; }
        public Object getWallHoppableTo(CornerSquare next) { return null; }
    }
    public static final class CornerCell {
        final java.util.Map<String, CornerSquare> squares = new java.util.HashMap<>();
        void add(int x, int y, int z) { squares.put(x + "," + y + "," + z, new CornerSquare(x, y, z)); }
        void block(int fromX, int fromY, int fromZ, int toX, int toY, int toZ) {
            CornerSquare from = squares.get(fromX + "," + fromY + "," + fromZ);
            if (from != null) from.blockedTo.add(toX + "," + toY + "," + toZ);
        }
        public CornerSquare getGridSquare(int x, int y, int z) {
            return squares.get(x + "," + y + "," + z);
        }
    }
    public static final class CornerActor {
        final CornerCell cell;
        final float x, y;
        CornerActor(CornerCell cell, int tileX, int tileY) {
            this.cell = cell;
            this.x = tileX + 0.5f;
            this.y = tileY + 0.5f;
        }
        public CornerSquare getCurrentSquare() { return cell.getGridSquare(0, 0, 0); }
        public CornerCell getCell() { return cell; }
        public float getX() { return x; }
        public float getY() { return y; }
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
            require(KnoxTraversalPolicy.windowAction(window.open, false, false, true, true,
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
