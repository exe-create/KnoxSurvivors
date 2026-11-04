package com.knoxsurvivors.npc;

/** Focused pace and physical-eligibility checks without a running game. */
public final class KnoxLocomotionVerifier {
    private KnoxLocomotionVerifier() {
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        verifyPaceThresholds();
        verifyPhysicalEligibility();
        verifyNativeHealthScale();
        verifyTravelAwareness();
        System.out.println(
            "KnoxLocomotionVerifier PASS walk=true run=true sprint=true"
                + " downgrade=true condition=true stealth=true perception=true throttle=true"
        );
    }

    private static void verifyPaceThresholds() {
        require(decide("normal", 20.0f).running() == false,
            "normal pace walks regardless of route length");
        KnoxLocomotionPolicy.Decision run = decide("run", 6.0f);
        require(run.running() && !run.sprinting(), "moderate catch-up runs");
        KnoxLocomotionPolicy.Decision sprint = decide("sprint", 15.0f);
        require(sprint.running() && sprint.sprinting(), "far eligible catch-up sprints");
        KnoxLocomotionPolicy.Decision closing = decide("sprint", 5.0f);
        require(closing.running() && closing.sprinting(),
            "a nearby formation gap can retain requested sprint pace");
        KnoxLocomotionPolicy.Decision arrival = decide("sprint", 2.0f);
        require(!arrival.running() && !arrival.sprinting(),
            "a companion stops cleanly once it reaches the formation slot");
        require(!decide("sprint", 1.0f).running(),
            "catch-up drops to walking near the destination");
    }

    private static void verifyPhysicalEligibility() {
        KnoxLocomotionPolicy.Decision tired = KnoxLocomotionPolicy.decide(
            "sprint", 15.0f, 0.60f, 0.80f, 100.0f, true
        );
        require(tired.running() && !tired.sprinting(),
            "fatigue blocks sprint but still permits a run");
        KnoxLocomotionPolicy.Decision exhausted = KnoxLocomotionPolicy.decide(
            "sprint", 15.0f, 0.15f, 0.20f, 100.0f, true
        );
        require(!exhausted.running() && !exhausted.sprinting(),
            "low endurance forces walking");
        KnoxLocomotionPolicy.Decision injured = KnoxLocomotionPolicy.decide(
            "sprint", 15.0f, 0.80f, 0.20f, 20.0f, true
        );
        require(injured.running() && !injured.sprinting(),
            "low health blocks sprint");
        KnoxLocomotionPolicy.Decision engineDenied = KnoxLocomotionPolicy.decide(
            "sprint", 15.0f, 0.80f, 0.20f, 100.0f, false
        );
        require(engineDenied.running() && !engineDenied.sprinting(),
            "native canSprint remains authoritative");
    }

    public static final class NativeHealth {
        public float getHealth() { return 1.0f; }
    }

    public static final class BodyHealth {
        private final float health;
        BodyHealth(float health) { this.health = health; }
        public float getOverallBodyHealth() { return health; }
    }

    public static final class InjuredHuman {
        public float getHealth() { return 1.0f; }
        public BodyHealth getBodyDamage() { return new BodyHealth(20.0f); }
    }

    private static void verifyNativeHealthScale() {
        float healthy = KnoxNpcFactory.locomotionHealth(new NativeHealth());
        require(healthy == 100.0f, "native health 1 means full health, not one percent");
        require(KnoxLocomotionPolicy.decide("sprint", 15, .8f, .2f, healthy, true).sprinting(),
            "healthy native character can actually sprint through the factory adapter");
        float injured = KnoxNpcFactory.locomotionHealth(new InjuredHuman());
        require(injured == 20.0f, "real BodyDamage overrides raw character health");
        require(!KnoxLocomotionPolicy.decide("sprint", 15, .8f, .2f, injured, true).sprinting(),
            "real injury still prevents sprinting");
        require(KnoxNpcFactory.locomotionHealth(new Object()) == 0.0f,
            "unreadable health fails conservatively");
    }

    public static final class TravelThreat {
        float x, y, z;
        boolean dead, proxy, visible = true;
        Object target;
        int targetReads;
        TravelThreat(float x, float y, float z) { this.x=x; this.y=y; this.z=z; }
        public boolean isDead() { return dead; }
        public boolean isReanimatedForGrappleOnly() { return proxy; }
        public float getX() { return x; }
        public float getY() { return y; }
        public float getZ() { return z; }
        public Object getTarget() { targetReads++; return target; }
    }

    public static final class TravelObserver {
        int sightChecks;
        public boolean CanSee(TravelThreat threat) { sightChecks++; return threat.visible; }
    }

    private static void verifyTravelAwareness() throws ReflectiveOperationException {
        KnoxNpc npc = new KnoxNpc("travel", new Object(), 0, 0, 0);
        npc.setMovementPace("cautious");
        require("cautious".equals(npc.getMovementPace()) && !decide(npc.getMovementPace(), 80).running(),
            "routine cautious routes do not become runs just because they are long");
        npc.setMovementPace("sneak");
        require("sneak".equals(npc.getMovementPace()), "the actual leader can request sneaking");
        TravelObserver observer = new TravelObserver();
        java.lang.reflect.Method canSee = TravelObserver.class.getMethod("CanSee", TravelThreat.class);
        TravelThreat quiet = new TravelThreat(6,0,0);
        java.util.ArrayList<TravelThreat> threats = new java.util.ArrayList<>();
        threats.add(quiet);
        KnoxTravelAwareness.Observation seen = KnoxNpcFactory.scanTravelThreats(observer, threats, canSee, 0,0,0);
        require(seen.visible()==1 && !seen.detected(), "native adapter records a visible unnoticed zombie");
        KnoxTravelAwareness awareness = npc.travelAwareness;
        long now = 1_000_000_000L;
        require(awareness.needsRefresh(now,0,0,0), "a new body needs a real sample");
        awareness.update(now,0,0,0,seen);
        require(awareness.shouldSneak(now,true,false), "one nearby visible zombie warrants cautious travel");
        require(!awareness.shouldSneak(now,false,false), "ordinary non-cautious pace retains the crowd threshold");
        require(!awareness.needsRefresh(now+100_000_000L,1,0,0), "movement frames reuse the bounded sample");
        require(awareness.needsRefresh(now+250_000_000L,1,0,0), "perception refreshes every quarter second");
        require(awareness.needsRefresh(now+1,0,0,1), "stairs invalidate the old floor sample");
        require(awareness.needsRefresh(now+1,5,0,0), "large displacement invalidates the old location");
        KnoxTravelAwareness.Observation empty = new KnoxTravelAwareness.Observation(0,Float.POSITIVE_INFINITY,false);
        awareness.update(now+300_000_000L,0,0,0,empty);
        require(awareness.shouldSneak(now+400_000_000L,true,false), "brief sight loss cannot toggle posture every frame");
        require(awareness.shouldSneak(now+1_600_000_000L,true,false), "cautious travel stays crouched through a clear stretch");
        KnoxTravelAwareness cold = new KnoxTravelAwareness();
        cold.update(now,0,0,0,empty);
        require(cold.shouldSneak(now,true,false), "an ordinary travel leg crouches before anything is seen");
        require(!cold.shouldSneak(now,false,false), "an ordinary pace is not a stealth posture in clear terrain");
        require(awareness.shouldSneak(now+1_600_000_000L,false,true), "an explicit leader sneak still applies in clear terrain");
        quiet.target=observer;
        KnoxTravelAwareness.Observation detected=KnoxNpcFactory.scanTravelThreats(observer,threats,canSee,0,0,0);
        awareness.update(now+2_000_000_000L,0,0,0,detected);
        require(!awareness.shouldSneak(now+2_000_000_000L,true,true), "an active nearby attacker releases sneaking");
        quiet.target=null; quiet.x=1;
        awareness.update(now+3_000_000_000L,0,0,0,KnoxNpcFactory.scanTravelThreats(observer,threats,canSee,0,0,0));
        require(!awareness.shouldSneak(now+3_000_000_000L,true,true), "contact danger never causes crouch-walking");
        TravelThreat proxy=new TravelThreat(3,0,0); proxy.proxy=true; proxy.target=observer;
        TravelThreat far=new TravelThreat(40,0,0); far.target=observer;
        TravelThreat upstairs=new TravelThreat(1,0,1); upstairs.target=observer;
        TravelThreat hidden=new TravelThreat(5,0,0); hidden.visible=false;
        threats.clear(); threats.add(proxy); threats.add(far); threats.add(upstairs); threats.add(hidden);
        observer.sightChecks=0;
        KnoxTravelAwareness.Observation clear=KnoxNpcFactory.scanTravelThreats(observer,threats,canSee,0,0,0);
        require(clear.visible()==0 && !clear.detected() && observer.sightChecks==1,
            "proxy, wrong-floor, remote and unseen zombies do not create omniscient sneaking");
        require(proxy.targetReads==0 && far.targetReads==0 && upstairs.targetReads==0,
            "cheap physical filters precede target and native sight calls");
        proxy.proxy=false; proxy.target=null;
        require(KnoxNpcFactory.scanTravelThreats(observer,threats,canSee,0,0,0).visible()==1,
            "a real reanimated zombie is still visible danger");
        awareness.update(now+4_000_000_000L,0,0,1,detected);
        require(!awareness.shouldSneak(now+4_000_000_000L,true,false), "being spotted on the new floor still releases the crouch");
    }

    private static KnoxLocomotionPolicy.Decision decide(String pace, float distance) {
        return KnoxLocomotionPolicy.decide(pace, distance, 0.80f, 0.20f, 100.0f, true);
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
