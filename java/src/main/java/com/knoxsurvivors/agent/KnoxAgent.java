package com.knoxsurvivors.agent;

import com.knoxsurvivors.bridge.KnoxBridgeBootstrap;
import java.io.IOException;
import java.lang.instrument.Instrumentation;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.lang.management.ManagementFactory;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

/** Knox Survivors engine integration bootstrap. */
public final class KnoxAgent {
    private static final String LOG_NAME = "KnoxIsoPlayer.log";
    private static final String GAME_MODE = "pz-game";
    private static final Set<String> RETRANSFORM_TARGETS = Set.of(
        "zombie.ai.states.SwipeStatePlayer",
        "zombie.CombatManager",
        "zombie.characters.IsoZombie"
    );
    private static final AtomicBoolean STARTED = new AtomicBoolean(false);
    private static volatile String runtimeSource = "none";
    private static volatile boolean runtimeStarted;

    private KnoxAgent() { }

    /** Legacy Knox Launcher / direct -javaagent entry point. */
    public static void premain(String arguments, Instrumentation instrumentation) {
        startRuntime("legacy-javaagent", arguments, instrumentation, false);
    }

    /** Legacy dynamic-attach entry point. */
    public static void agentmain(String arguments, Instrumentation instrumentation) {
        startRuntime("legacy-agentmain", arguments, instrumentation, true);
    }

    /** Entry point for the KnoxBridge module. */
    public static void startFromKnoxBridge(Instrumentation instrumentation) {
        startRuntime("knoxbridge", GAME_MODE, instrumentation, true);
    }

    /** ZombieBuddy owns patch installation and Lua exposure; Knox requests no JVM handle. */
    public static void startFromZombieBuddy() {
        validateRuntimeSelection("zombiebuddy", ManagementFactory.getRuntimeMXBean().getInputArguments());
        if (!STARTED.compareAndSet(false, true)) {
            if (!"zombiebuddy".equals(runtimeSource) || !runtimeStarted)
                throw new IllegalStateException("Knox runtime already claimed by " + runtimeSource);
            return;
        }
        runtimeSource = "zombiebuddy";
        runtimeStarted = true;
        writeLog("runtime start source=zombiebuddy patch_api=annotations registration_requested "
            + "native_application=NOT_VERIFIED impact_audio=unchanged_native");
    }

    /**
     * Admission to a native attempt, not evidence that framework advice applied successfully.
     * ZombieBuddy owns advice installation and exposes no per-patch completion receipt.
     * Native attack/damage observations remain authoritative; never set transformer counters here.
     */
    public static boolean usesZombieBuddyPatches() {
        return runtimeStarted && "zombiebuddy".equals(runtimeSource);
    }

    public static boolean isLegacyRuntimeActive() {
        return runtimeSource.startsWith("legacy-");
    }

    public static String getRuntimeSource() {
        return runtimeSource;
    }

    private static void startRuntime(
        String source,
        String arguments,
        Instrumentation instrumentation,
        boolean retransformLoadedTargets
    ) {
        validateRuntimeSelection(source, ManagementFactory.getRuntimeMXBean().getInputArguments());
        writeLog("runtime bootstrap source=" + source + " arguments=" + String.valueOf(arguments));

        if (!GAME_MODE.equals(arguments)) {
            writeLog("runtime bootstrap ignored because mode is not " + GAME_MODE);
            return;
        }
        if (instrumentation == null) {
            writeLog("ERROR runtime bootstrap received null Instrumentation");
            return;
        }
        if (!STARTED.compareAndSet(false, true)) {
            if (!source.equals(runtimeSource) || !runtimeStarted) {
                throw new IllegalStateException("Knox runtime already claimed by " + runtimeSource
                    + "; cannot start " + source + ". Quit PZ and select exactly one Java runtime.");
            }
            writeLog("runtime already started; duplicate bootstrap ignored source=" + source);
            return;
        }
        runtimeSource = source;

        boolean canRetransform = retransformLoadedTargets
            && instrumentation.isRetransformClassesSupported();
        if (retransformLoadedTargets && !canRetransform) {
            writeLog("ERROR runtime source=" + source
                + " does not support class retransformation; loaded combat classes may not patch");
        }

        try {
            instrumentation.addTransformer(new KnoxSwipeStateTransformer(), canRetransform);
            instrumentation.addTransformer(new KnoxZombieVisibilityTransformer(), canRetransform);
            writeLog("combat callback transformer installed retransform=" + canRetransform);
            writeLog("zombie visibility transformer installed retransform=" + canRetransform);

            if (canRetransform) retransformLoadedTargets(instrumentation);

            verifyIsoPlayerClass();
            KnoxBridgeBootstrap.start(instrumentation);
            runtimeStarted = true;
            writeLog("runtime start PASS source=" + source);
        } catch (Throwable throwable) {
            writeLog("ERROR runtime start source=" + source + " "
                + throwable.getClass().getName() + ": " + throwable.getMessage());
            throw new IllegalStateException("Knox runtime initialization failed; restart PZ before retrying", throwable);
        }
    }

    static void validateRuntimeSelection(String source, List<String> arguments) {
        for (String argument : arguments) {
            String value = argument.toLowerCase(java.util.Locale.ROOT);
            if (!value.startsWith("-javaagent:") && !value.startsWith("-agentpath:")
                && !value.startsWith("-agentlib:")) continue;
            boolean zombieBuddy = value.contains("zombiebuddy") || value.contains("zbnative");
            boolean knoxBridge = value.contains("knoxbridge-agent") || value.contains("knoxbridge-bootstrap");
            boolean legacyKnox = value.contains("knox-agent");
            if ((source.equals("zombiebuddy") && (knoxBridge || legacyKnox))
                || (source.equals("knoxbridge") && (zombieBuddy || legacyKnox))
                || (source.startsWith("legacy-") && (zombieBuddy || knoxBridge))) {
                throw new IllegalStateException("Conflicting Java runtime argument: " + argument
                    + ". Knox Survivors requires exactly one runtime per PZ process.");
            }
        }
    }

    private static void retransformLoadedTargets(Instrumentation instrumentation) {
        int loadedTargets = 0;
        int requested = 0;
        for (Class<?> loadedClass : instrumentation.getAllLoadedClasses()) {
            if (!RETRANSFORM_TARGETS.contains(loadedClass.getName())) continue;
            loadedTargets++;
            if (!instrumentation.isModifiableClass(loadedClass)) {
                writeLog("ERROR target class is not modifiable: " + loadedClass.getName());
                continue;
            }
            try {
                instrumentation.retransformClasses(loadedClass);
                requested++;
                writeLog("retransform PASS class=" + loadedClass.getName());
            } catch (Throwable throwable) {
                writeLog("ERROR retransform class=" + loadedClass.getName() + " "
                    + throwable.getClass().getName() + ": " + throwable.getMessage());
            }
        }
        writeLog("retransform scan complete targetsLoaded=" + loadedTargets + " requested=" + requested);
    }

    private static void verifyIsoPlayerClass() {
        try {
            ClassLoader loader = Thread.currentThread().getContextClassLoader();
            if (loader == null) loader = ClassLoader.getSystemClassLoader();
            Class.forName("zombie.characters.IsoPlayer", false, loader);
            writeLog("verified class zombie.characters.IsoPlayer");
        } catch (ClassNotFoundException exception) {
            writeLog("ERROR missing zombie.characters.IsoPlayer: " + exception);
        }
    }

    public static void writeLog(String message) {
        String line = Instant.now() + " [KnoxSurvivors] " + message + System.lineSeparator();
        try {
            String logDirectory = System.getProperty("knox.logDirectory");
            Path logFile = (logDirectory == null || logDirectory.isBlank()
                ? Path.of(System.getProperty("user.home"), "Zomboid")
                : Path.of(logDirectory)).resolve(LOG_NAME);
            Files.createDirectories(logFile.getParent());
            Files.writeString(logFile, line, StandardCharsets.UTF_8,
                StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (IOException | java.nio.file.InvalidPathException exception) {
            System.err.print(line);
            exception.printStackTrace(System.err);
        }
    }
}
