package com.knoxsurvivors.bridge;

import com.knoxsurvivors.agent.KnoxAgent;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.util.Collection;

/** Exposes the Knox bridge only after Project Zomboid has initialized a stable Lua environment. */
public final class KnoxBridgeBootstrap {
    private static final String LUA_MANAGER_CLASS = "zombie.Lua.LuaManager";
    private static final long POLL_MILLIS = 250L;
    private static final int REQUIRED_STABLE_POLLS = 4;
    private static final KnoxBridge BRIDGE = new KnoxBridge();
    private static Object adapterEnvironment;

    private KnoxBridgeBootstrap() { }

    /** Both integrations expose this one instance; it owns the only NPC registry. */
    public static KnoxBridge getBridge() { return BRIDGE; }

    public static synchronized KnoxBridge getBridgeForEnvironment(Object current) {
        if (current == null) return null;
        if (adapterEnvironment != null && adapterEnvironment != current) BRIDGE.abandonForEnvironmentChange();
        adapterEnvironment = current;
        return BRIDGE;
    }

    /** Uses instrumentation to observe already-loaded game classes. */
    public static void start(Instrumentation instrumentation) {
        startWatchdog(instrumentation);
    }

    private static void startWatchdog(Instrumentation instrumentation) {
        Thread watchdog = new Thread(
            () -> exposeWhenReady(instrumentation),
            "KnoxSurvivors-LuaBridge"
        );
        watchdog.setDaemon(true);
        watchdog.start();
        KnoxAgent.writeLog("Lua bridge watchdog started source=" + KnoxAgent.getRuntimeSource());
    }

    private static void exposeWhenReady(Instrumentation instrumentation) {
        Object previousEnvironment = null;
        Object previousExposer = null;
        int previousLoadedCount = -1;
        int stablePolls = 0;
        Object exposedEnvironment = null;
        boolean bridgeClassExposed = false;
        long lastFailureLogMillis = 0L;
        Class<?> luaManagerClass = null;

        while (!Thread.currentThread().isInterrupted()) {
            try {
                if (luaManagerClass == null) {
                    luaManagerClass = findLuaManagerClass(instrumentation);
                }
                if (luaManagerClass == null) {
                    sleep();
                    continue;
                }

                Object environment = luaManagerClass.getField("env").get(null);
                Object exposer = luaManagerClass.getField("exposer").get(null);
                Object loaded = luaManagerClass.getField("loaded").get(null);
                Object exposerEnvironment = exposer == null
                    ? null
                    : getInheritedField(exposer, "environment");
                int loadedCount = loaded instanceof Collection<?>
                    ? ((Collection<?>) loaded).size()
                    : 0;

                if (environment == null || exposer == null || loadedCount == 0) {
                    previousEnvironment = null;
                    previousExposer = null;
                    previousLoadedCount = -1;
                    stablePolls = 0;
                    sleep();
                    continue;
                }
                if (!bridgeClassExposed && exposerEnvironment != environment) {
                    sleep();
                    continue;
                }

                if (environment != previousEnvironment
                    || exposer != previousExposer
                    || loadedCount != previousLoadedCount) {
                    previousEnvironment = environment;
                    previousExposer = exposer;
                    previousLoadedCount = loadedCount;
                    stablePolls = 0;
                    sleep();
                    continue;
                }

                stablePolls++;
                if (stablePolls < REQUIRED_STABLE_POLLS) {
                    sleep();
                    continue;
                }

                Object exposedBridge = environment.getClass().getMethod("rawget", Object.class)
                    .invoke(environment, "KnoxJavaBridge");
                if (environment == exposedEnvironment && exposedBridge == BRIDGE) {
                    sleep();
                    continue;
                }

                if (exposedEnvironment != null && environment != exposedEnvironment) {
                    BRIDGE.abandonForEnvironmentChange();
                }

                if (luaManagerClass.getField("env").get(null) != environment) {
                    previousEnvironment = null;
                    previousExposer = null;
                    previousLoadedCount = -1;
                    stablePolls = 0;
                    sleep();
                    continue;
                }

                if (exposerEnvironment == environment) {
                    exposer.getClass().getMethod("setExposed", Class.class)
                        .invoke(exposer, KnoxBridge.class);
                    exposer.getClass().getMethod("exposeLikeJava", Class.class)
                        .invoke(exposer, KnoxBridge.class);
                    bridgeClassExposed = true;
                }
                environment.getClass().getMethod("rawset", Object.class, Object.class)
                    .invoke(environment, "KnoxJavaBridge", BRIDGE);

                exposedBridge = environment.getClass().getMethod("rawget", Object.class)
                    .invoke(environment, "KnoxJavaBridge");
                if (exposedBridge == BRIDGE) {
                    exposedEnvironment = environment;
                    KnoxAgent.writeLog("Lua bridge exposed global=KnoxJavaBridge");
                }
            } catch (Throwable throwable) {
                Throwable cause = unwrapInvocationTarget(throwable);
                if (isLuaEnvironmentTransition(cause)) {
                    previousEnvironment = null;
                    previousExposer = null;
                    previousLoadedCount = -1;
                    stablePolls = 0;
                    sleep();
                    continue;
                }
                long now = System.currentTimeMillis();
                if (now - lastFailureLogMillis >= 5_000L) {
                    KnoxAgent.writeLog("Lua bridge exposure attempt failed: "
                        + cause.getClass().getName() + ": " + cause.getMessage());
                    lastFailureLogMillis = now;
                }
            }
            sleep();
        }
    }

    private static Throwable unwrapInvocationTarget(Throwable throwable) {
        Throwable current = throwable;
        while (current instanceof InvocationTargetException
            && ((InvocationTargetException) current).getCause() != null) {
            current = ((InvocationTargetException) current).getCause();
        }
        return current;
    }

    private static boolean isLuaEnvironmentTransition(Throwable throwable) {
        return throwable instanceof NullPointerException
            && throwable.getMessage() != null
            && throwable.getMessage().contains("because \"env\" is null");
    }

    private static Object getInheritedField(Object target, String fieldName)
        throws ReflectiveOperationException {
        Class<?> current = target.getClass();
        while (current != null) {
            try {
                Field field = current.getDeclaredField(fieldName);
                field.setAccessible(true);
                return field.get(target);
            } catch (NoSuchFieldException notOnThisClass) {
                current = current.getSuperclass();
            }
        }
        throw new NoSuchFieldException(fieldName);
    }

    private static Class<?> findLuaManagerClass(Instrumentation instrumentation) {
        for (Class<?> loadedClass : instrumentation.getAllLoadedClasses()) {
            if (LUA_MANAGER_CLASS.equals(loadedClass.getName())) return loadedClass;
        }
        return null;
    }

    private static void sleep() {
        try {
            Thread.sleep(POLL_MILLIS);
        } catch (InterruptedException interruptedException) {
            Thread.currentThread().interrupt();
        }
    }
}
