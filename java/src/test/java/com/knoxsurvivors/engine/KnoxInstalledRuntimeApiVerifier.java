package com.knoxsurvivors.engine;

import java.lang.reflect.Modifier;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.jar.JarFile;

/** Read-only public API inspection. No framework initialization, approval changes or game launch. */
public final class KnoxInstalledRuntimeApiVerifier {
    public static void main(String[] args) throws Exception {
        boolean required = args[0].equals("--require-zombiebuddy");
        Path game = Path.of(args[1]), framework = Path.of(args[2]);
        boolean supported = false;
        String reason = "framework_not_present";
        if (Files.isRegularFile(framework)) {
            String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(Files.readAllBytes(framework)));
            try (var jar = new JarFile(framework.toFile())) {
                System.out.println("ZombieBuddy binary=" + framework + " sha256=" + hash
                    + " version=" + jar.getManifest().getMainAttributes().getValue("Implementation-Version"));
            }
            try (var loader = new URLClassLoader(new URL[]{framework.toUri().toURL(), game.toUri().toURL()},
                ClassLoader.getPlatformClassLoader())) {
                try {
                    Class<?> patch = Class.forName("me.zed_0xff.zombie_buddy.Patch", false, loader);
                    Class<?> enter = Class.forName(patch.getName() + "$OnEnter", false, loader);
                    Class<?> exit = Class.forName(patch.getName() + "$OnExit", false, loader);
                    Class<?> result = Class.forName(patch.getName() + "$Return", false, loader);
                    Class<?> local = Class.forName(patch.getName() + "$Local", false, loader);
                    Class<?> all = Class.forName(patch.getName() + "$AllArguments", false, loader);
                    Class<?> self = Class.forName(patch.getName() + "$This", false, loader);
                    Class<?> exposer = Class.forName("me.zed_0xff.zombie_buddy.Exposer", false, loader);
                    Class<?> lua = Class.forName(exposer.getName() + "$LuaClass", false, loader);
                    supported = patch.isAnnotation() && exit.isAnnotation() && all.isAnnotation() && self.isAnnotation()
                        && patch.getMethod("className").getReturnType() == String.class
                        && patch.getMethod("methodName").getReturnType() == String.class
                        && enter.getMethod("skipOn").getReturnType() == boolean.class
                        && result.getMethod("readOnly").getReturnType() == boolean.class
                        && local.getMethod("value").getReturnType() == String.class
                        && lua.getMethod("name").getReturnType() == String.class
                        && Modifier.isPublic(exposer.getMethod("exposeClass", Class.class).getModifiers());
                    reason = supported ? "official_patch_and_lua_API_present" : "unsupported_annotation_API";
                } catch (ClassNotFoundException | NoSuchMethodException absent) { reason = "annotation_API_missing"; }
            }
        }
        System.out.println("ZombieBuddy Knox adapter supported=" + supported + " reason=" + reason
            + " scope=public_metadata_only_native_gameplay_NOT_VERIFIED");
        if (required && !supported) {
            System.err.println("Not launching PZ: this ZombieBuddy binary cannot initialize Knox Survivors. "
                + "The official Patch/LuaClass API is required. No private-field or second-agent fallback is used.");
            System.exit(2);
        }
    }
}
