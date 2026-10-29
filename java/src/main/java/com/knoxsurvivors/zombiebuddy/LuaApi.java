package com.knoxsurvivors.zombiebuddy;

import com.knoxsurvivors.bridge.KnoxBridge;
import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.bridge.KnoxBridgeBootstrap;
import me.zed_0xff.zombie_buddy.Exposer;

/** Documented global exposure; reuses the shared bridge and its one NPC registry. */
@Exposer.LuaClass(name = "KnoxRuntimeApi")
public final class LuaApi {
    private LuaApi() { }

    public static KnoxBridge getBridge() {
        if (!KnoxAgent.usesZombieBuddyPatches()) return null;
        try {
            Object current = Class.forName("zombie.Lua.LuaManager", false, LuaApi.class.getClassLoader())
                .getField("env").get(null);
            return KnoxBridgeBootstrap.getBridgeForEnvironment(current);
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("PZ Lua environment is unavailable", exception);
        }
    }
}
