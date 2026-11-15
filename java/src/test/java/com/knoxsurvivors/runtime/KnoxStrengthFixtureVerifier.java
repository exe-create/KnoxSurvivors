package com.knoxsurvivors.runtime;

import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.*;
import java.util.*;
import javax.tools.ToolProvider;

/** Executes the same native-shaped hit fixture through each actual adapter seam. */
public final class KnoxStrengthFixtureVerifier {
    @FunctionalInterface public interface Transform { byte[] apply(Path fixtureClasses, byte[] original) throws Exception; }
    public static void verify(Path root, Path artifact, Path framework, boolean buddy, Transform transform) throws Exception {
        Path parent = root.resolve("java/build/strength-fixtures");
        Files.createDirectories(parent);
        Path out=Files.createTempDirectory(parent, buddy ? "woven-" : "redirect-");
        List<String> args=new ArrayList<>(List.of("--release","17","-d",out.toString()));
        try(var files=Files.walk(root.resolve("java/fixtures/strength-java"))){
            files.filter(p->p.toString().endsWith(".java")).sorted().forEach(p->args.add(p.toString()));
        }
        if(ToolProvider.getSystemJavaCompiler().run(null,null,null,args.toArray(String[]::new))!=0)
            throw new AssertionError("strength fixture compilation failed");
        Path target=out.resolve("zombie/characters/IsoGameCharacter.class");
        Files.write(target,transform.apply(out,Files.readAllBytes(target)));
        try(var loader=new URLClassLoader(new URL[]{out.toUri().toURL(),artifact.toUri().toURL(),framework.toUri().toURL()},ClassLoader.getPlatformClassLoader())){
            try {loader.loadClass("fixture.StrengthFixture").getMethod("run",boolean.class).invoke(null,buddy);}
            catch(java.lang.reflect.InvocationTargetException e){throw new AssertionError("strength fixture failed",e.getCause());}
        }
    }
}
