package com.knoxsurvivors.engine;

import java.io.Reader;
import java.lang.reflect.InvocationTargetException;
import java.nio.file.Files;
import java.nio.file.Path;

/** Checks the shipped scripts with the installed game's compiler, without running a world. */
public final class KnoxLuaCompilerVerifier {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Expected mod source directory");
        var compiler = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod(
                "loadis", Reader.class, String.class, Class.forName("se.krka.kahlua.vm.KahluaTable"));
        int checked = 0;
        int failed = 0;
        try (var paths = Files.walk(Path.of(args[0]))) {
            for (var path : paths.filter(Files::isRegularFile)
                    .filter(p -> p.toString().endsWith(".lua")).sorted().toList()) {
                checked++;
                try (var reader = Files.newBufferedReader(path)) {
                    compiler.invoke(null, reader, path.toString(), null);
                } catch (InvocationTargetException failure) {
                    failed++;
                    System.err.println("FAIL " + path + ": " + failure.getCause());
                }
            }
        }
        if (checked == 0) throw new IllegalStateException("No Lua sources found");
        System.out.println("Build 42 Lua compiler: " + checked + " sources, " + failed + " failures");
        if (failed != 0) throw new AssertionError("Game Lua compilation failed");
    }
}
