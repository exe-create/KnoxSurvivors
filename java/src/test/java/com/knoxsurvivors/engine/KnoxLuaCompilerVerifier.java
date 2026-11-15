package com.knoxsurvivors.engine;

import java.io.Reader;
import java.lang.reflect.InvocationTargetException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * Checks the shipped scripts with the installed game's compiler, without running a world.
 *
 * <p>Also holds a top-level local budget. Build 42's compiler rejects a chunk at two hundred
 * top-level locals ("Index 200 out of bounds for length 200" in LexState.new_localvar, measured
 * in-game 2026-11-09 on KS_SurvivorAutonomyController.lua), while compiling the same file here
 * accepts exactly two hundred. The gate therefore keeps a margin below the in-game ceiling.
 */
public final class KnoxLuaCompilerVerifier {
    private static final int TOP_LEVEL_LOCAL_BUDGET = 190;

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
                int locals = countTopLevelLocals(path);
                if (locals > TOP_LEVEL_LOCAL_BUDGET) {
                    failed++;
                    System.err.println("FAIL " + path + ": " + locals + " top-level locals (budget "
                            + TOP_LEVEL_LOCAL_BUDGET + "; Build 42 rejects the chunk at 200)");
                    continue;
                }
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

    /** Counts `local` declarations at column zero, ignoring comments and quoted text. */
    private static int countTopLevelLocals(Path path) throws Exception {
        List<String> lines = new ArrayList<>(Files.readAllLines(path));
        int count = 0;
        boolean inLongComment = false;
        boolean inLongString = false;
        for (String line : lines) {
            StringBuilder code = new StringBuilder();
            int index = 0;
            while (index < line.length()) {
                if (inLongComment) {
                    int close = line.indexOf("]]", index);
                    if (close < 0) { index = line.length(); break; }
                    inLongComment = false;
                    index = close + 2;
                    continue;
                }
                if (inLongString) {
                    int close = line.indexOf("]]", index);
                    if (close < 0) { index = line.length(); break; }
                    inLongString = false;
                    index = close + 2;
                    continue;
                }
                char ch = line.charAt(index);
                if (ch == '-' && line.startsWith("--", index)) {
                    int longOpen = line.indexOf("[[", index);
                    if (longOpen == index + 2) { inLongComment = true; index = longOpen + 2; continue; }
                    break;
                }
                if (ch == '[' && line.startsWith("[[", index)) { inLongString = true; index += 2; continue; }
                if (ch == '"' || ch == '\'') {
                    index++;
                    while (index < line.length() && line.charAt(index) != ch) {
                        if (line.charAt(index) == '\\') index++;
                        index++;
                    }
                    index++;
                    continue;
                }
                code.append(ch);
                index++;
            }
            String stripped = code.toString();
            if (stripped.equals(stripped.stripLeading()) && stripped.startsWith("local")) {
                char next = stripped.length() > 5 ? stripped.charAt(5) : ' ';
                if (stripped.length() == 5 || Character.isWhitespace(next)) count++;
            }
        }
        return count;
    }
}
