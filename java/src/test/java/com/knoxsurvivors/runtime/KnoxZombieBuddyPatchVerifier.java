package com.knoxsurvivors.runtime;

import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.*;
import java.util.*;
import javax.tools.ToolProvider;
import me.zed_0xff.zombie_buddy.Patch;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.pool.TypePool;
import net.bytebuddy.jar.asm.*;
import static net.bytebuddy.matcher.ElementMatchers.named;

/** Offline advice binding/semantics, NOT ZombieBuddy's live loader or native gameplay. */
public final class KnoxZombieBuddyPatchVerifier {
    private static int checks;
    private static final String PKG = "com.knoxsurvivors.zombiebuddy.KnoxPatches$";

    public static void main(String[] args) throws Exception {
        Path workspace = Path.of(args[0]), game = Path.of(args[1]), artifact = Path.of(args[2]), framework = Path.of(args[3]);
        Files.createDirectories(workspace);
        Map<String, byte[]> adviceBytes = new HashMap<>();
        Map<String, String[]> targets = new LinkedHashMap<>();
        for (String leaf : List.of("CallbackEligibility", "HumanEligibility", "TargetVisibility")) {
            Class<?> advice = Class.forName(PKG + leaf);
            Patch patch = advice.getAnnotation(Patch.class);
            require(patch != null && patch.isAdvice() && !patch.IKnowWhatIAmDoing(), "ordinary supported advice");
            targets.put(advice.getName(), new String[]{patch.className(), patch.methodName()});
            String resource = advice.getName().replace('.', '/') + ".class";
            try (var input = advice.getClassLoader().getResourceAsStream(resource)) {
                adviceBytes.put(advice.getName(), translate(input.readAllBytes()));
            }
        }
        var adviceLocator = new ClassFileLocator.Compound(new ClassFileLocator.Simple(adviceBytes),
            ClassFileLocator.ForClassLoader.ofSystemLoader());
        // Bind to actual installed engine bytecode without defining/initializing those classes.
        try (var gameLocator = ClassFileLocator.ForJarFile.of(game.toFile())) {
            var locator = new ClassFileLocator.Compound(gameLocator, adviceLocator);
            var pool = TypePool.Default.of(locator);
            for (var target : targets.entrySet()) {
                byte[] bytes = weave(target.getKey(), target.getValue(), locator, adviceLocator);
                require(bytes.length > 0, "advice binds real Build42 target " + target.getValue()[0]);
                Files.write(workspace.resolve(target.getValue()[0] + ".class"), bytes);
            }
            TypeDescription player = pool.describe("zombie.characters.IsoPlayer").resolve();
            require(player.getDeclaredMethods().filter(named("isLocalPlayer")).size() == 3,
                "instance and two static local-player overloads inspected");
            for (String method : List.of("OnAnimEvent_AttackCollisionCheck", "OnAnimEvent_PlaySwingSound", "OnAnimEvent_PlaySwingSoundAlways"))
                require(countCalls(gameLocator, "zombie.ai.states.SwipeStatePlayer", method,
                    "zombie/characters/IsoPlayer", "isLocalPlayer") == 1, "one scoped callback gate: " + method);
            for (String method : List.of("calcValidTarget", "calcHitListShove", "removeTargetObjects"))
                require(countCalls(gameLocator, "zombie.CombatManager", method,
                    "zombie/CombatManager", "checkPVP") == 1, "one scoped human gate: " + method);
            require(countCalls(gameLocator, "zombie.CombatManager", "attackCollisionCheck",
                "zombie/characters/IsoPlayer", "isLocalPlayer") == 5,
                "five impact-method local checks demonstrate why broad advice is unsafe");
        }
        Path fixtures = Files.createTempDirectory(workspace, "fixtures-");
        Map<String, String> sources = new LinkedHashMap<>();
        sources.put("zombie.iso.IsoMovingObject", "public class IsoMovingObject {}");
        sources.put("zombie.network.GameClient", "public class GameClient {public static boolean client;}");
        sources.put("zombie.network.GameServer", "public class GameServer {public static boolean server;}");
        sources.put("zombie.Lua.LuaManager", "public class LuaManager {public static Object env = new Object();}");
        sources.put("zombie.characters.IsoPlayer", "public class IsoPlayer extends zombie.iso.IsoMovingObject { public boolean god,dead; public Object square=new Object(); public boolean isLocalPlayer(){return false;} public static boolean isLocalPlayer(Object p){return false;} public static boolean isLocalPlayer(IsoPlayer p){return false;} public boolean isGodMod(){return god;} public boolean isDead(){return dead;} public Object getCurrentSquare(){return square;} }");
        sources.put("com.knoxsurvivors.engine.KnoxIsoPlayerShell", "public class KnoxIsoPlayerShell extends zombie.characters.IsoPlayer {}");
        sources.put("zombie.ai.states.SwipeStatePlayer", "public class SwipeStatePlayer {public static boolean OnAnimEvent_AttackCollisionCheck(Object p){return zombie.characters.IsoPlayer.isLocalPlayer(p);} public static boolean OnAnimEvent_PlaySwingSound(Object p){return zombie.characters.IsoPlayer.isLocalPlayer(p);} public static boolean OnAnimEvent_PlaySwingSoundAlways(Object p){return zombie.characters.IsoPlayer.isLocalPlayer(p);} public static boolean other(Object p){return zombie.characters.IsoPlayer.isLocalPlayer(p);} public static boolean nested(Object p){return zombie.CombatManager.nestedLocal(p);} }");
        sources.put("zombie.CombatManager", "public class CombatManager { public static boolean nativePVP; public static boolean checkPVP(zombie.iso.IsoMovingObject a,zombie.iso.IsoMovingObject b,boolean c){return nativePVP;} public static boolean calcValidTarget(zombie.iso.IsoMovingObject a,zombie.iso.IsoMovingObject b){return checkPVP(a,b,true);} public static boolean calcHitListShove(zombie.iso.IsoMovingObject a,zombie.iso.IsoMovingObject b){return checkPVP(a,b,true);} public static boolean removeTargetObjects(zombie.iso.IsoMovingObject a,zombie.iso.IsoMovingObject b){return checkPVP(a,b,true);} public static boolean other(zombie.iso.IsoMovingObject a,zombie.iso.IsoMovingObject b){return checkPVP(a,b,true);} public static boolean nestedLocal(Object p){return zombie.characters.IsoPlayer.isLocalPlayer(p);} }");
        sources.put("zombie.characters.IsoZombie", "public class IsoZombie {public Object target,square=new Object(); public int calls; public Object getTarget(){return target;} public Object getCurrentSquare(){return square;} public boolean isTargetVisible(){calls++; return false;} }");
        List<String> options = new ArrayList<>(List.of("--release", "17", "-d", fixtures.toString()));
        for (var entry : sources.entrySet()) {
            Path file = fixtures.resolve(entry.getKey().replace('.', '/') + ".java");
            Files.createDirectories(file.getParent());
            String name = entry.getKey();
            Files.writeString(file, "package " + name.substring(0, name.lastIndexOf('.')) + ";" + entry.getValue());
            options.add(file.toString());
        }
        require(ToolProvider.getSystemJavaCompiler().run(null, null, null, options.toArray(String[]::new)) == 0, "fixtures compile");
        try (var fixtureLocator = new ClassFileLocator.ForFolder(fixtures.toFile())) {
            var locator = new ClassFileLocator.Compound(fixtureLocator, adviceLocator);
            for (var target : targets.entrySet()) {
                Files.write(fixtures.resolve(target.getValue()[0].replace('.', '/') + ".class"),
                    weave(target.getKey(), target.getValue(), locator, adviceLocator));
            }
        }
        try (var loader = new URLClassLoader(new URL[]{fixtures.toUri().toURL(), artifact.toUri().toURL(), framework.toUri().toURL()}, ClassLoader.getPlatformClassLoader())) {
            Object shell = loader.loadClass("com.knoxsurvivors.engine.KnoxIsoPlayerShell").getConstructor().newInstance();
            Class<?> player = loader.loadClass("zombie.characters.IsoPlayer");
            Object normal = player.getConstructor().newInstance();
            Class<?> swipe = loader.loadClass("zombie.ai.states.SwipeStatePlayer");
            require(!(Boolean)swipe.getMethod("OnAnimEvent_AttackCollisionCheck",Object.class).invoke(null,shell),
                "discovered advice inert until its runtime owns startup");
            require(loader.loadClass("com.knoxsurvivors.zombiebuddy.LuaApi").getMethod("getBridge").invoke(null)==null,
                "unclaimed adapter exposes no bridge");
            loader.loadClass("com.knoxsurvivors.agent.KnoxAgent").getMethod("startFromZombieBuddy").invoke(null);
            for (String method : List.of("OnAnimEvent_AttackCollisionCheck", "OnAnimEvent_PlaySwingSound", "OnAnimEvent_PlaySwingSoundAlways")) {
                require((Boolean)swipe.getMethod(method,Object.class).invoke(null,shell), "shell callback eligible: " + method);
                require(!(Boolean)swipe.getMethod(method,Object.class).invoke(null,normal), "normal actor unchanged");
            }
            require(!(Boolean)swipe.getMethod("other",Object.class).invoke(null,shell), "unowned call remains false");
            require(!(Boolean)swipe.getMethod("nested",Object.class).invoke(null,shell), "outer frames cannot authorize nested local check");
            require(!(Boolean)player.getMethod("isLocalPlayer").invoke(shell), "shell never gains local-player identity");
            require(!(Boolean)player.getMethod("isLocalPlayer",Object.class).invoke(null,shell), "arbitrary static query unchanged");
            Class<?> moving = loader.loadClass("zombie.iso.IsoMovingObject"), combat = loader.loadClass("zombie.CombatManager");
            Class<?> policy = loader.loadClass("com.knoxsurvivors.agent.KnoxHumanCombatGate");
            Object owner = new Object();
            policy.getMethod("refresh",Object.class,Object.class,Object.class).invoke(null,owner,shell,normal);
            for (String method : List.of("calcValidTarget","calcHitListShove","removeTargetObjects")) {
                require((Boolean)combat.getMethod(method,moving,moving).invoke(null,shell,normal), "shared policy permits active pair");
            }
            require(!(Boolean)combat.getMethod("other",moving,moving).invoke(null,shell,normal), "other PVP call unchanged");
            player.getField("god").set(normal,true);
            require(!(Boolean)combat.getMethod("calcValidTarget",moving,moving).invoke(null,shell,normal), "godmode protected");
            player.getField("god").set(normal,false);
            policy.getMethod("clear",Object.class).invoke(null,owner);
            require(!(Boolean)combat.getMethod("calcValidTarget",moving,moving).invoke(null,shell,normal), "lease revocation retained");
            Class<?> zombie = loader.loadClass("zombie.characters.IsoZombie"); Object z = zombie.getConstructor().newInstance();
            zombie.getField("target").set(z,shell);
            require((Boolean)zombie.getMethod("isTargetVisible").invoke(z), "client shell avoids indexed visibility");
            require(zombie.getField("calls").getInt(z)==0, "skip native slot-indexed check only for shell");
            zombie.getField("target").set(z,normal);
            require(!(Boolean)zombie.getMethod("isTargetVisible").invoke(z) && zombie.getField("calls").getInt(z)==1, "normal native visibility retained");
            zombie.getField("target").set(z,shell); zombie.getField("square").set(z,null);
            require(!(Boolean)zombie.getMethod("isTargetVisible").invoke(z), "detached zombie uses native method");
            zombie.getField("square").set(z,new Object()); loader.loadClass("zombie.network.GameServer").getField("server").set(null,true);
            require(!(Boolean)zombie.getMethod("isTargetVisible").invoke(z), "server visibility remains native");
            Object env = new Object(); Class<?> bootstrap = loader.loadClass("com.knoxsurvivors.bridge.KnoxBridgeBootstrap");
            Object first = bootstrap.getMethod("getBridgeForEnvironment",Object.class).invoke(null,env);
            require(first==bootstrap.getMethod("getBridge").invoke(null), "single shared registry owner");
            require(first==loader.loadClass("com.knoxsurvivors.zombiebuddy.LuaApi").getMethod("getBridge").invoke(null), "Lua accessor reuses shared instance");
        }
        System.out.println("ZombieBuddy Patch verifier PASS checks="+checks+" official_binary=2.3.4 real_engine_binding=true fixture_semantics=true native_gameplay=NOT_VERIFIED");
    }

    private static byte[] weave(String advice, String[] target, ClassFileLocator locator, ClassFileLocator adviceLocator) throws Exception {
        TypeDescription type = TypePool.Default.of(locator).describe(target[0]).resolve();
        TypeDescription patch = TypePool.Default.of(adviceLocator).describe(advice).resolve();
        return new ByteBuddy().redefine(type,locator).visit(Advice.to(patch,adviceLocator).on(named(target[1]))).make().getBytes();
    }

    private static int countCalls(ClassFileLocator locator, String type, String method, String owner, String name) throws Exception {
        int[] count = {0};
        new ClassReader(locator.locate(type).resolve()).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access, String candidate, String d, String s, String[] e) {
                if (!candidate.equals(method)) return null;
                return new MethodVisitor(Opcodes.ASM9) {
                    @Override public void visitMethodInsn(int opcode, String targetOwner, String targetName, String descriptor, boolean iface) {
                        if (owner.equals(targetOwner) && name.equals(targetName)) count[0]++;
                    }
                };
            }
        }, ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        return count[0];
    }

    // Test-only implementation of the documented Patch aliases. No framework internals or JVM handle.
    // Actual Loader/PatchEngine discovery, retransformation and approvals remain manual runtime gates.
    private static byte[] translate(byte[] bytes) {
        ClassWriter writer=new ClassWriter(0);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9,writer) {
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) {
                return new MethodVisitor(Opcodes.ASM9,super.visitMethod(a,n,d,s,e)) {
                    @Override public AnnotationVisitor visitAnnotation(String desc,boolean visible) {
                        return alias(super.visitAnnotation(remap(desc),visible),desc);
                    }
                    @Override public AnnotationVisitor visitParameterAnnotation(int p,String desc,boolean visible) {
                        return alias(super.visitParameterAnnotation(p,remap(desc),visible),desc);
                    }
                };
            }
        },0);
        return writer.toByteArray();
    }
    private static String remap(String desc) {
        if (!desc.startsWith("Lme/zed_0xff/zombie_buddy/Patch$")) return desc;
        return "Lnet/bytebuddy/asm/Advice$" + desc.substring(desc.indexOf('$')+1).replace("OnEnter;","OnMethodEnter;").replace("OnExit;","OnMethodExit;");
    }
    private static AnnotationVisitor alias(AnnotationVisitor delegate,String desc) {
        return new AnnotationVisitor(Opcodes.ASM9,delegate) {
            @Override public void visit(String n,Object value) {
                if (desc.endsWith("$OnEnter;") && n.equals("skipOn")) {
                    super.visit(n,Type.getType((Boolean)value ? Advice.OnNonDefaultValue.class : void.class));
                } else super.visit(n,value);
            }
        };
    }
    private static void require(boolean condition,String description) {
        checks++; if(!condition) throw new AssertionError(description);
    }
}
