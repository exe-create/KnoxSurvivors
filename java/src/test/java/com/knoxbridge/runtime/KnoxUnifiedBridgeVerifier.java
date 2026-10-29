package com.knoxbridge.runtime;

import java.lang.instrument.Instrumentation;
import java.lang.reflect.Proxy;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** Offline real framework discovery/module loader with simulated Instrumentation; no approval bypass in player code. */
public final class KnoxUnifiedBridgeVerifier {
    public static void main(String[] args) throws Exception {
        try { Class.forName("me.zed_0xff.zombie_buddy.Patch"); throw new AssertionError("ZombieBuddy present in Bridge-only test"); }
        catch (ClassNotFoundException expected) { }
        Path root = Path.of(args[0]).toRealPath();
        var log = new ArrayList<String>();
        var candidates = ModuleDiscovery.inspectEnabledRoots(List.of(root), log::add);
        if (candidates.size() != 1 || candidates.get(0).problem() != null || candidates.get(0).descriptor() == null)
            throw new AssertionError("Unified inventory must contain one compatible module: " + candidates);
        var descriptor = candidates.get(0).descriptor();
        if (!descriptor.jar().getFileName().toString().equals("knox-survivors.jar")) throw new AssertionError("Wrong common JAR");
        var hooks = new ArrayList<String>();
        Instrumentation inst = (Instrumentation)Proxy.newProxyInstance(ClassLoader.getPlatformClassLoader(),
            new Class<?>[]{Instrumentation.class}, (proxy, method, values) -> {
                if (method.getName().equals("isRetransformClassesSupported")) return true;
                if (method.getName().equals("getAllLoadedClasses")) return new Class<?>[0];
                if (method.getName().equals("addTransformer")) hooks.add(values[0].getClass().getSimpleName());
                // The exact artifact is on THIS isolated test JVM's classpath already.
                if (method.getReturnType()==boolean.class) return false;
                if (method.getReturnType()==int.class) return 0;
                if (method.getReturnType()==long.class) return 0L;
                return null;
            });
        try (var loaded = ModuleLoader.load(descriptor, descriptor.jar(), "test-alpha11", new PatchEngine(log::add), inst, log::add,
                Hashing.sha256(descriptor.jar()))) {
            if (!hooks.equals(List.of("KnoxSwipeStateTransformer", "KnoxZombieVisibilityTransformer")))
                throw new AssertionError("Wrong/duplicated hook set: " + hooks);
            loaded.module().initialize(new com.knoxbridge.api.ModuleContext() {
                public String runtimeVersion(){return "test-alpha11";}
                public String moduleId(){return descriptor.id();}
                public String moduleVersion(){return descriptor.version();}
                public java.util.function.Consumer<String> logger(){return log::add;}
                public com.knoxbridge.api.PatchRegistrar patches(){return null;}
                public Instrumentation instrumentation(){return inst;}
            });
            if (hooks.size()!=2) throw new AssertionError("Duplicate module initialization installed extra hooks");
            if (!"knoxbridge".equals(com.knoxsurvivors.agent.KnoxAgent.getRuntimeSource())) throw new AssertionError("Wrong source");
            if (com.knoxsurvivors.agent.KnoxAgent.usesZombieBuddyPatches()) throw new AssertionError("Optional advice active in Bridge");
            long watchdogs=Thread.getAllStackTraces().keySet().stream().filter(t -> t.getName().equals("KnoxSurvivors-LuaBridge")).count();
            if(watchdogs!=1) throw new AssertionError("Expected one shared bridge watchdog");
        } finally {
            for(Thread thread:Thread.getAllStackTraces().keySet()) if(thread.getName().equals("KnoxSurvivors-LuaBridge")){thread.interrupt();thread.join(1000);}
        }
        System.out.println("Unified Bridge PASS alpha11_discovery=true module_loader=true simulated_instrumentation=true ZombieBuddy_absent=true one_hook_set=true native_gameplay=NOT_VERIFIED");
    }
}
