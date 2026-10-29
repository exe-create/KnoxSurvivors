package com.knoxsurvivors.runtime;

import java.lang.instrument.Instrumentation;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Proxy;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.jar.JarFile;
import javax.tools.ToolProvider;

/** Isolated bootstrap/packaging evidence, not native gameplay acceptance. */
public final class KnoxRuntimeAdapterVerifier {
    private static int checks;
    private static final String ENTRY = "com.knoxsurvivors.zombiebuddy.Main";
    private static final String AGENT = "com.knoxsurvivors.agent.KnoxAgent";

    public static void main(String[] args) throws Exception {
        Path core = Path.of(args[0]);
        Path workspace = Path.of(args[1]);
        Path root = Path.of(args[2]);
        Files.createDirectories(workspace);
        verifyPackaging(core, root, Path.of(args[3]));
        verifyRuntimeArguments(core);
        for (String mode : List.of("zombie_first", "bridge_first")) {
            run(mode, core, workspace, Path.of(args[4]));
        }
        System.out.println("Runtime adapter PASS checks=" + checks
            + " shared_gameplay=true no_bridge_dependency=true duplicate_guard=true"
            + " official_annotations=true packaging=true"
            + " scope=isolated_bootstrap_only");
    }

    private static void verifyPackaging(Path artifact, Path root, Path payload) throws Exception {
        try (JarFile jar = new JarFile(artifact.toFile())) {
            for (String name : List.of("com/knoxsurvivors/Main.class", ENTRY.replace('.', '/') + ".class",
                    "com/knoxsurvivors/npc/KnoxNpcFactory.class", "com/knoxsurvivors/npc/KnoxTraversalPolicy.class",
                    "com/knoxsurvivors/npc/KnoxCombatController.class"))
                require(jar.getJarEntry(name) != null, "one artifact contains shared implementation and both entries: " + name);
            require(jar.getManifest().getMainAttributes().getValue("Premain-Class") == null,
                "gameplay module is not another instrumentation agent");
            for (var entries = jar.entries(); entries.hasMoreElements();) {
                String name = entries.nextElement().getName();
                require(!name.startsWith("com/knoxbridge/") && !name.startsWith("me/zed_0xff/")
                    && !name.startsWith("net/bytebuddy/"), "no framework libraries bundled");
            }
        }
        for (String relative : List.of("mod.info", "42/mod.info")) {
            Properties info = new Properties();
            try (var input = Files.newInputStream(payload.resolve(relative))) { info.load(input); }
            require("KnoxSurvivors".equals(info.getProperty("id")), "one stable mod/save identity");
            require(info.getProperty("require", "").isBlank(), "neither framework forced by metadata");
            require("media/java/knox-survivors.jar".equals(info.getProperty("javaJarFile")), "ZB selects common artifact");
            require("com.knoxsurvivors.zombiebuddy".equals(info.getProperty("javaPkgName")), "ZB scans its adapter package only");
        }
        Properties descriptor = new Properties();
        try (var in = Files.newInputStream(payload.resolve("42/knoxbridge.properties"))) { descriptor.load(in); }
        require("com.knoxsurvivors.Main".equals(descriptor.getProperty("entrypoint")), "Bridge entry retained");
        require("media/java/knox-survivors.jar".equals(descriptor.getProperty("jar")), "Bridge selects SAME artifact");
        require("system".equals(descriptor.getProperty("classLoader")), "one helper/state classloader");
        try (var files = Files.walk(payload)) {
            var jars = files.filter(p -> p.toString().endsWith(".jar")).toList();
            require(jars.size() == 1 && jars.get(0).getFileName().toString().equals("knox-survivors.jar"), "only one runtime payload");
            require(java.util.Arrays.equals(Files.readAllBytes(artifact), Files.readAllBytes(jars.get(0))), "staged artifact exactly matches build");
        }
        try (var files = Files.walk(root.resolve("mod"))) {
            for (Path source : files.filter(Files::isRegularFile).toList()) {
                require(java.util.Arrays.equals(Files.readAllBytes(source), Files.readAllBytes(payload.resolve(root.resolve("mod").relativize(source)))),
                    "one canonical source payload: " + source.getFileName());
            }
        }
    }
    private static void run(String mode, Path alternate, Path workspace, Path tests) throws Exception {
        Path fixture = Files.createTempDirectory(workspace, mode + "-");
        compile(fixture, "me.zed_0xff.zombie_buddy.Exposer",
            "public static int calls; public static void exposeClass(Class<?> type) {calls++;}");
        var installed = new ArrayList<String>();
        Instrumentation instrumentation = (Instrumentation) Proxy.newProxyInstance(
            ClassLoader.getPlatformClassLoader(), new Class<?>[]{Instrumentation.class}, (proxy, method, values) -> {
                if (method.getName().equals("isRetransformClassesSupported")) return true;
                if (method.getName().equals("getAllLoadedClasses")) return new Class<?>[0];
                if (method.getName().equals("addTransformer")) installed.add(values[0].getClass().getSimpleName());
                if (method.getReturnType() == boolean.class) return false;
                if (method.getReturnType() == long.class) return 0L;
                if (method.getReturnType() == int.class) return 0;
                return null;
            });
        try (var loader = new URLClassLoader(new URL[]{fixture.toUri().toURL(), alternate.toUri().toURL(), tests.toUri().toURL()},
            ClassLoader.getPlatformClassLoader())) {
            Class<?> agent = Class.forName(AGENT, true, loader);
            Class<?> entry = Class.forName(ENTRY, true, loader);
            if (mode.equals("bridge_first")) {
                agent.getMethod("startFromKnoxBridge", Instrumentation.class).invoke(null, instrumentation);
                try { entry.getMethod("main", String[].class).invoke(null, (Object)new String[0]);
                    throw new AssertionError("conflicting runtime accepted");
                } catch (InvocationTargetException e) {
                    require(e.getCause() instanceof IllegalStateException, "conflicting runtime refused");
                }
                require(installed.size() == 2 && watchdogs() == 1, "Bridge retains one patch set/watchdog");
            } else {
                entry.getMethod("main", String[].class).invoke(null, (Object)new String[0]);
                entry.getMethod("main", String[].class).invoke(null, (Object)new String[0]);
                require("zombiebuddy".equals(agent.getMethod("getRuntimeSource").invoke(null)), "ZB owner");
                require(installed.isEmpty() && watchdogs() == 0, "ZB installs no transformers/watchdog");
                require((Boolean)agent.getMethod("usesZombieBuddyPatches").invoke(null), "registered native attempt");
                Class<?> gates = Class.forName("com.knoxsurvivors.agent.KnoxCombatGate", true, loader);
                require(!(Boolean)gates.getMethod("isPatchReady").invoke(null), "registration cannot forge patch evidence");
                try { agent.getMethod("startFromKnoxBridge", Instrumentation.class).invoke(null, instrumentation);
                    throw new AssertionError("Bridge restart accepted");
                } catch (InvocationTargetException e) {
                    require(e.getCause() instanceof IllegalStateException, "cross-runtime restart refused");
                }
            }
            // Run the SAME artifact's existing recovery fixtures after each runtime claims ownership.
            for (String test : List.of("KnoxMovementRequestVerifier", "KnoxTraversalVerifier",
                    "KnoxLocomotionVerifier", "KnoxCombatControllerVerifier")) {
                Class.forName("com.knoxsurvivors.npc." + test, true, loader).getMethod("main", String[].class)
                    .invoke(null, (Object)new String[0]);
                require(true, "shared recovery fixture under " + mode + ": " + test);
            }
        } finally {
            for (Thread thread : Thread.getAllStackTraces().keySet()) {
                if (thread.getName().equals("KnoxSurvivors-LuaBridge")) { thread.interrupt(); thread.join(1000); }
            }
        }
    }
    private static long watchdogs() {
        return Thread.getAllStackTraces().keySet().stream()
            .filter(thread -> thread.getName().equals("KnoxSurvivors-LuaBridge")).count();
    }

    private static void verifyRuntimeArguments(Path core) throws Exception {
        try (var loader = new URLClassLoader(new URL[]{core.toUri().toURL()}, ClassLoader.getPlatformClassLoader())) {
            Class<?> agent = Class.forName(AGENT, true, loader);
            var validate = agent.getDeclaredMethod("validateRuntimeSelection", String.class, List.class);
            validate.setAccessible(true);
            for (String source : List.of("zombiebuddy", "knoxbridge")) {
                for (String argument : List.of("-javaagent:C:/test/ZombieBuddy.jar", "-agentlib:zbNative",
                    "-agentpath:C:/test/zbNative.dll", "-javaagent:C:/test/knoxbridge-agent.jar",
                    "-agentpath:C:/test/knoxbridge-bootstrap.dll", "-javaagent:C:/test/knox-agent.jar")) {
                    boolean zombieArgument = argument.contains("ZombieBuddy") || argument.contains("zbNative");
                    boolean permitted = source.equals("zombiebuddy") == zombieArgument;
                    if (argument.contains("/knox-agent.jar")) permitted = false;
                    Throwable failure = null;
                    try { validate.invoke(null, source, List.of(argument)); }
                    catch (InvocationTargetException e) { failure = e.getCause(); }
                    require(permitted == (failure == null), "runtime argument boundary: " + source + argument);
                }
                validate.invoke(null, source, List.of("-Xmx8g", "-Dexample.path=ZombieBuddy"));
            }
        }
    }

    private static void compile(Path output, String name, String body) throws Exception {
        Path file = output.resolve(name.replace('.', '/') + ".java");
        Files.createDirectories(file.getParent());
        Files.writeString(file, "package " + name.substring(0, name.lastIndexOf('.'))
            + "; public class " + name.substring(name.lastIndexOf('.') + 1) + " {" + body + "}");
        var compiler = ToolProvider.getSystemJavaCompiler();
        require(compiler != null && compiler.run(null, null, null, "--release", "17", "-d", output.toString(), file.toString()) == 0,
            "runtime fixture compiles");
    }

    private static void require(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
}
