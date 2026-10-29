package com.knoxsurvivors.runtime;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.bridge.KnoxBridgeBootstrap;
import java.nio.file.Path;
import java.util.Set;
import java.util.stream.Collectors;
import me.zed_0xff.zombie_buddy.PatchEngine;

/** Actual released package scanner/main; no JVM agent, approval changes or game launch. */
public final class KnoxUnifiedZombieBuddyVerifier {
    public static void main(String[] args) throws Exception {
        try { Class.forName("com.knoxbridge.api.KnoxModule"); throw new AssertionError("Bridge API present in ZB-only test"); }
        catch (ClassNotFoundException expected) { }
        Path jar = Path.of(args[0]).toRealPath();
        if (!Path.of(KnoxAgent.class.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath().equals(jar))
            throw new AssertionError("Shared implementation must load from the actual unified artifact");
        com.knoxsurvivors.zombiebuddy.Main.main(new String[0]);
        var patches = PatchEngine.collectPatches("com.knoxsurvivors.zombiebuddy", KnoxAgent.class.getClassLoader());
        Set<String> found = patches.stream().map(Class::getSimpleName).collect(Collectors.toSet());
        if (!found.equals(Set.of("CallbackEligibility", "HumanEligibility", "TargetVisibility")))
            throw new AssertionError("Released scanner did not discover all adapter advice: " + found);
        com.knoxsurvivors.zombiebuddy.Main.main(new String[0]);
        if (!"zombiebuddy".equals(KnoxAgent.getRuntimeSource())) throw new AssertionError("Wrong owner");
        if (KnoxBridgeBootstrap.getBridge() != KnoxBridgeBootstrap.getBridgeForEnvironment(new Object()))
            throw new AssertionError("Duplicate registry owner");
        if (Thread.getAllStackTraces().keySet().stream().anyMatch(t -> t.getName().equals("KnoxSurvivors-LuaBridge")))
            throw new AssertionError("ZB path started Bridge watchdog");
        // Read metadata with the installed engine parser; not a Properties approximation.
        Class<?> choose = Class.forName("zombie.gameStates.ChooseGameInfo");
        Class<?> fs = Class.forName("zombie.ZomboidFileSystem");
        // The real reader resolves filenames through this filesystem, as normal boot does.
        // Only initialize its file index; do not start a game state or actor.
        fs.getMethod("init").invoke(fs.getField("instance").get(null));
        Object mod = choose.getMethod("readModInfo", String.class).invoke(null, args[1]);
        if (mod == null) throw new AssertionError("Installed PZ parser rejected the unified mod");
        Object required = mod.getClass().getMethod("getRequire").invoke(mod);
        if (required != null && !((java.util.List<?>)required).isEmpty())
            throw new AssertionError("Game parser found a mandatory framework dependency: " + required);
        System.out.println("Unified ZB PASS official_2.3.4_scanner=true bridge_API_absent=true one_registry=true real_mod_parser=true native_gameplay=NOT_VERIFIED");
    }
}
