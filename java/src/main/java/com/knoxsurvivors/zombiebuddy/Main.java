package com.knoxsurvivors.zombiebuddy;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.bridge.KnoxBridge;
import me.zed_0xff.zombie_buddy.Exposer;

/** Invoked by ZombieBuddy only after its normal exact-JAR approval/loading flow. */
public final class Main {
    private Main() { }
    public static void main(String[] arguments) {
        KnoxAgent.startFromZombieBuddy();
        Exposer.exposeClass(KnoxBridge.class);
        // ZombieBuddy discovers @Patch and @LuaClass itself after Main returns.
        // No second agent, private framework access, or manual PatchEngine invocation.
    }
}
