package com.knoxsurvivors.npc;

/** Focused ownership-state regression checks that do not require a running game. */
public final class KnoxMovementRequestVerifier {
    private KnoxMovementRequestVerifier() {
    }

    public static void main(String[] args) {
        verifyOwnershipMetadata();
        verifyZLevelGeometry();
        verifySparseRouteEdges();
        verifyRuntimeLifecycle();
        verifyPendingTransitionRecovery();
        verifyRouteStartDoesNotReverse();
        verifyDutyArea();
        System.out.println(
            "KnoxMovementRequestVerifier PASS duplicate=true replacement=true cleanup=true"
                + " resume=true zLevel=true"
        );
    }

    private static void verifyDutyArea() {
        KnoxNpc npc = new KnoxNpc("patrol", new Object(), 2, 2, 0);
        npc.movementArea = new KnoxMovementArea(0, 0, 10, 10, 0);
        require(KnoxNpcFactory.acceptMovementRoute(npc, 2.5f, 2.5f, 0, java.util.List.of(
            new float[] { 2.5f, 2.5f, 0 }, new float[] { 8.5f, 8.5f, 0 }
        )), "native nodes within the duty area are accepted");
        require(npc.hasMovementRoute(), "accepted native route reaches the movement driver");
        require(!KnoxNpcFactory.acceptMovementRoute(npc, 2.5f, 2.5f, 0, java.util.List.of(
            new float[] { 2.5f, 2.5f, 0 }, new float[] { -1.5f, 8.5f, 0 },
            new float[] { 8.5f, 8.5f, 0 }
        )), "an engine shortcut out and back into the area is rejected");
        require(!npc.hasMovementRoute() && npc.movementArea.isRejected(),
            "rejected native route never reaches ordinary human movement");
        npc.movementArea = new KnoxMovementArea(0, 0, 10, 10, 0);
        require(KnoxNpcFactory.acceptMovementRoute(npc, -5.5f, 2.5f, 0, java.util.List.of(
            new float[] { -5.5f, 2.5f, 0 }, new float[] { 1.5f, 2.5f, 0 },
            new float[] { 8.5f, 8.5f, 0 }
        )), "an outside survivor can approach and enter the duty area");
        require(npc.movementArea.allowsPosition(-1.5f, 2.5f, 0)
            && npc.movementArea.allowsPosition(1.5f, 2.5f, 0)
            && !npc.movementArea.allowsPosition(-0.1f, 2.5f, 0),
            "after entering, displacement outside ends duty movement");
        npc.movementArea = new KnoxMovementArea(10, 10, 0, 0, 0);
        require(npc.movementArea.contains(10.5f, 10.5f, 0)
            && !npc.movementArea.contains(11f, 10.5f, 0), "inclusive tiles normalize reversed bounds");
        require(!KnoxNpcFactory.acceptMovementRoute(npc, 2.5f, 2.5f, 0, java.util.List.of(
            new float[] { 2.5f, 2.5f, 1 }, new float[] { 8.5f, 8.5f, 0 }
        )), "same XY on another floor is not an in-area patrol route");
        npc.movementArea = new KnoxMovementArea(0, 0, 10, 10, 0);
        require(!KnoxNpcFactory.acceptMovementRoute(npc, 2.5f, 2.5f, 0, java.util.List.of(
            new float[] { Float.NaN, 2, 0 }
        )), "invalid engine nodes fail closed");
        FakeMovementEngine engine = new FakeMovementEngine();
        KnoxNpcRuntime runtime = new KnoxNpcRuntime(npc, engine);
        Target post = new Target(5, 5, 0);
        KnoxMovementArea area = new KnoxMovementArea(0, 0, 10, 10, 0);
        require(runtime.beginMove(post, false, "walk", area).startsWith("MOVE_STARTED"), "bounded route starts");
        require(runtime.beginMove(post, false, "walk", new KnoxMovementArea(0,0,10,10,0)).contains("existing=true")
            && engine.starts==1, "duplicate area orders do not continually replace the route");
        require(runtime.beginMove(post, false, "walk", new KnoxMovementArea(0,0,6,6,0)).contains("replaced=true")
            && engine.starts==2 && engine.cancels==1, "changed permission replaces even the same target");
        require(runtime.beginMove(new Target(20,20,0),false,"walk",area).startsWith("MOVE_FAILED"),
            "bounded request rejects a destination outside the selected area");
        require(runtime.beginMove(post,false).contains("replaced=true") && npc.movementArea==null,
            "needs and new ordinary orders release the prior patrol restriction");
        runtime.cancelMovement();
        require(npc.movementArea==null, "cancellation never leaves a stale duty area");
    }

    private static void verifySparseRouteEdges() {
        float[][] cases = {
            { .5f, .5f, 10.5f, .5f, 1, 0 },
            { .5f, .5f, -10.5f, .5f, -1, 0 },
            { .9f, .2f, 5.5f, 3.5f, 1, 0 },
            { .2f, .9f, 3.5f, 5.5f, 0, 1 },
            { .5f, .5f, 9.5f, 9.5f, 1, 1 },
            { -.2f, -.8f, -9.5f, -2.5f, -2, -1 },
            { .2f, .2f, .8f, .8f, 0, 0 },
            { 0, .5f, -10, .5f, -1, 0 },
        };
        for (float[] c : cases) {
            int[] next = KnoxMovementGeometry.nextRouteTile(c[0], c[1], c[2], c[3]);
            require(next[0] == (int)c[4] && next[1] == (int)c[5],
                "sparse path checks its first real tile edge before applying movement");
        }
        System.out.println("Sparse route edges PASS long_segments=true cardinal_and_corner=true negative_coordinates=true");
    }

    private static void verifyZLevelGeometry() {
        require(KnoxMovementGeometry.arrived(10.5f, 20.5f, 1, 10.5f, 20.5f, 1, 0.65f),
            "same XYZ within tolerance arrives");
        require(!KnoxMovementGeometry.arrived(10.5f, 20.5f, 0, 10.5f, 20.5f, 1, 0.65f),
            "same XY on the wrong floor does not arrive");
        require(!KnoxMovementGeometry.arrived(.95f,.5f,0,1.5f,.5f,0,.65f),
            "distance tolerance cannot claim arrival across an adjacent wall/window edge");
        require(!KnoxMovementGeometry.arrived(-.05f,.5f,0,.5f,.5f,0,.65f),
            "tile containment uses floor coordinates, including negatives");
        require(!KnoxMovementGeometry.nodeReached(
            10.5f, 20.5f, 0, 10.5f, 20.5f, 1, 0.35f
        ), "stair node is retained until its floor is reached");
        require(KnoxMovementGeometry.nodeReached(
            10.5f, 20.5f, 1, 10.5f, 20.5f, 1, 0.35f
        ), "floor transition releases the reached stair node");
    }

    private static void verifyOwnershipMetadata() {
        KnoxMovementRequest request = new KnoxMovementRequest();

        require(request.classify(10.5f, 20.5f, 0, false)
            == KnoxMovementRequest.Change.START, "inactive request starts");
        request.activate(10.5f, 20.5f, 0, false);
        require(request.isActive(), "request owns movement after activation");
        require(request.classify(10.5f, 20.5f, 0, false)
            == KnoxMovementRequest.Change.KEEP, "duplicate destination is suppressed");
        require(request.classify(11.5f, 20.5f, 0, false)
            == KnoxMovementRequest.Change.REPLACE, "changed destination replaces owner");
        require(request.classify(10.5f, 20.5f, 1, false)
            == KnoxMovementRequest.Change.REPLACE, "changed destination floor replaces owner");
        require(request.classify(10.5f, 20.5f, 0, true)
            == KnoxMovementRequest.Change.REPLACE, "crossing mode replaces normal movement");

        request.release();
        require(!request.isActive(), "completion or cancellation releases ownership");
        require(request.classify(11.5f, 20.5f, 0, false)
            == KnoxMovementRequest.Change.START, "released request can recover");

        request.activate(11.5f, 20.5f, 0, false);
        request.release();
        require(!request.isActive(), "failure cleanup releases ownership");
        request.activate(12.5f, 20.5f, 0, false);
        require(request.isActive(), "movement can resume after interruption");
    }

    private static void verifyRuntimeLifecycle() {
        FakeMovementEngine arrivedEngine = new FakeMovementEngine();
        KnoxNpcRuntime arrivedRuntime = new KnoxNpcRuntime(
            new KnoxNpc("already-arrived", new Object(), 0, 0, 0),
            arrivedEngine
        );
        require(arrivedRuntime.beginMove(new Target(0, 0, 0), false)
                .contains("already_at_target=true"),
            "already-arrived normal orders complete without starting a native route");
        require(arrivedEngine.starts == 0
                && "Succeeded".equals(arrivedRuntime.tickMovement())
                && "IDLE".equals(arrivedRuntime.tickMovement()),
            "already-arrived movement releases ownership through the normal success path");

        FakeMovementEngine engine = new FakeMovementEngine();
        KnoxNpcRuntime runtime = new KnoxNpcRuntime(
            new KnoxNpc("movement-test", new Object(), 0, 0, 0),
            engine
        );
        Target first = new Target(10, 20, 0);
        Target replacement = new Target(10, 20, 1);

        require(runtime.beginMove(first, false).startsWith("MOVE_STARTED "),
            "first request starts");
        require(runtime.updateMovementPace("sprint")
            && "sprint".equals(runtime.npc().getMovementPace()),
            "active request accepts a pace-only update without replacement");
        require(runtime.beginMove(first, false).startsWith("MOVE_STARTED existing=true "),
            "duplicate request remains owned without restart");
        require(engine.starts == 1 && engine.cancels == 0,
            "duplicate request does not touch engine ownership");

        require(runtime.beginMove(replacement, false).startsWith("MOVE_STARTED replaced=true "),
            "replacement request starts after cancellation");
        require(engine.starts == 2 && engine.cancels == 1,
            "replacement cleans old engine request exactly once");
        require(engine.target.z == 1, "destination Z survives request construction");

        engine.tickResult = "Succeeded";
        engine.completeOnWrongFloor = true;
        require(runtime.tickMovement().startsWith("FailedWrongFloorOrPosition"),
            "engine XY completion on the wrong floor is rejected");
        require(engine.cancels == 2 && "IDLE".equals(runtime.tickMovement()),
            "wrong-floor completion releases ownership through normal failure cleanup");

        engine.completeOnWrongFloor = false;
        require(runtime.beginMove(replacement, false).startsWith("MOVE_STARTED "),
            "cross-floor request retries after bounded controller recovery");
        require("Succeeded".equals(runtime.tickMovement()), "correct-floor success is reported");
        require(engine.cancels == 3 && "IDLE".equals(runtime.tickMovement()),
            "success cleans engine state and releases ownership");

        require(runtime.beginMove(first, false).startsWith("MOVE_STARTED "),
            "new request starts after success");
        engine.failTick = true;
        require(runtime.tickMovement().startsWith("TICK_FAILED "),
            "tick exception is reported as failure");
        require(engine.cancels == 4 && "IDLE".equals(runtime.tickMovement()),
            "failure cleans engine state and releases ownership");

        engine.failTick = false;
        require(runtime.beginMove(replacement, false).startsWith("MOVE_STARTED "),
            "movement resumes after failed request");
        require(runtime.cancelMovement().startsWith("MOVE_CANCELLED "),
            "explicit interruption cancels request");
        require("IDLE".equals(runtime.tickMovement()),
            "interruption leaves no orphaned owner");
    }

    private static void verifyPendingTransitionRecovery() {
        for (String transition : java.util.List.of("Transition:TURNING_TO_WINDOW",
                "Transition:STARTED_WINDOW_CLIMB", "Transition:ManualRoute")) {
            FakeMovementEngine engine=new FakeMovementEngine();
            engine.x=.95f; engine.tickResult=transition;
            KnoxNpcRuntime runtime=new KnoxNpcRuntime(new KnoxNpc("transition",new Object(),0,0,0),engine);
            require(runtime.beginMove(new Target(1,0,0),false).startsWith("MOVE_STARTED") && engine.starts==1,
                "a nearby destination across the tile edge still requires native movement");
            for(int tick=0;tick<179;tick++) require(runtime.tickMovement().equals(transition),
                "pending input gets a bounded grace period");
            require(runtime.tickMovement().startsWith("FailedTransitionStalled") && engine.cancels==1,
                "unadmitted transition must fail through ordinary cleanup");
            require(runtime.tickMovement().equals("IDLE"),"failed transition releases movement ownership");
        }
        FakeMovementEngine engine=new FakeMovementEngine();
        engine.tickResult="Transition:CLIMBING";
        KnoxNpcRuntime runtime=new KnoxNpcRuntime(new KnoxNpc("native-climb",new Object(),0,0,0),engine);
        runtime.beginMove(new Target(4,0,2),false);
        for(int tick=0;tick<400;tick++) require(runtime.tickMovement().equals("Transition:CLIMBING"),
            "real native crossing cannot be cancelled by the pending-input watchdog");
        engine.tickResult="Working";
        for(int tick=0;tick<44;tick++) require(runtime.tickMovement().equals("Working"),"locomotion gets its own progress window");
        engine.z=1;
        for(int tick=0;tick<44;tick++) require(runtime.tickMovement().equals("Working"),"vertical floor progress resets the stuck budget");
        require(engine.cancels==0,"native crossing and floor progress preserve the same route");
        System.out.println("Movement recovery PASS pending_transitions_bounded=true native_crossing_preserved=true floor_progress=true no_cross_wall_arrival=true");
    }

    private static void verifyRouteStartDoesNotReverse() {
        KnoxNpc npc=new KnoxNpc("moving-follower",new Object(),0,0,0);
        float[] start={.5f,.5f,0}, forward={2.5f,.5f,0};
        require(KnoxNpcFactory.acceptMovementRoute(npc,.95f,.5f,0,java.util.List.of(start,forward))
            && npc.currentMovementNode()==forward,"moving follower skips a backward start-tile marker");
        KnoxNpcFactory.acceptMovementRoute(npc,.95f,.5f,0,java.util.List.of(start));
        require(npc.currentMovementNode()==start,"final work target in the current tile is retained");
        KnoxNpcFactory.acceptMovementRoute(npc,.95f,.5f,0,java.util.List.of(start,new float[]{2.5f,.5f,1}));
        require(npc.currentMovementNode()==start,"stair entry marker is preserved");
        KnoxNpcFactory.acceptMovementRoute(npc,.95f,.5f,0,java.util.List.of(start,new float[]{-2.5f,.5f,0}));
        require(npc.currentMovementNode()==start,"real reverse route still turns toward its destination");
        System.out.println("Follow route start PASS no_artificial_reverse=true final_goal=true stairs=true actual_reverse=true");
    }

    private static final class Target {
        private final int x;
        private final int y;
        private final int z;

        private Target(int x, int y, int z) {
            this.x = x;
            this.y = y;
            this.z = z;
        }
    }

    private static final class FakeMovementEngine implements KnoxNpcRuntime.MovementEngine {
        private int starts;
        private int cancels;
        private boolean failTick;
        private String tickResult = "Working";
        private boolean completeOnWrongFloor;
        private float x = 0.5f;
        private float y = 0.5f;
        private int z;
        private Target target;

        @Override
        public float bodyX(KnoxNpc npc) {
            return x;
        }

        @Override
        public float bodyY(KnoxNpc npc) {
            return y;
        }

        @Override
        public int bodyZ(KnoxNpc npc) {
            return z;
        }

        @Override
        public float targetX(Object square) {
            return ((Target) square).x + 0.5f;
        }

        @Override
        public float targetY(Object square) {
            return ((Target) square).y + 0.5f;
        }

        @Override
        public int targetZ(Object square) {
            return ((Target) square).z;
        }

        @Override
        public void start(KnoxNpc npc, Object square, boolean crossing) {
            starts++;
            target = (Target) square;
        }

        @Override
        public String tick(KnoxNpc npc, float remainingDistance, String pace)
            throws ReflectiveOperationException {
            if (failTick) {
                throw new ReflectiveOperationException("synthetic tick failure");
            }
            if ("Succeeded".equals(tickResult)) {
                x = target.x + 0.5f;
                y = target.y + 0.5f;
                if (!completeOnWrongFloor) {
                    z = target.z;
                }
            }
            return tickResult;
        }

        @Override
        public void cancel(KnoxNpc npc) {
            cancels++;
        }

    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
