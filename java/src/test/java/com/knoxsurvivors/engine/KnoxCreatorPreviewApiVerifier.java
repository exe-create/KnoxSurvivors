package com.knoxsurvivors.engine;

import com.knoxsurvivors.bridge.KnoxBridge;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/** Exercises installed engine setters on inert objects, without a game or graphics context. */
public final class KnoxCreatorPreviewApiVerifier {
    public static void main(String[] args) throws Exception {
        Class<?> unsafeType = Class.forName("sun.misc.Unsafe");
        Field singleton = unsafeType.getDeclaredField("theUnsafe");
        singleton.setAccessible(true);
        Object unsafe = singleton.get(null);
        Method allocate = unsafeType.getMethod("allocateInstance", Class.class);
        Class<?> uiType = Class.forName("zombie.ui.UI3DModel");
        Class<?> modelType = Class.forName("zombie.core.skinnedmodel.advancedanimation.AnimatedModel");
        Object ui = allocate.invoke(unsafe, uiType);
        Object model = allocate.invoke(unsafe, modelType);
        Field modelField = uiType.getDeclaredField("animatedModel");
        modelField.setAccessible(true);
        modelField.set(ui, model);
        Field primary = modelType.getDeclaredField("primaryHandModelName");
        Field secondary = modelType.getDeclaredField("secondaryHandModelName");
        primary.setAccessible(true);
        secondary.setAccessible(true);
        Field debug = Class.forName("zombie.core.Core").getField("debug");
        boolean originalDebug = debug.getBoolean(null);
        try {
            debug.setBoolean(null, false);
            KnoxBridge bridge = new KnoxBridge();
            require(!bridge.setCreatorPreviewHands(null, "a", "b"), "null rejected");
            require(!bridge.setCreatorPreviewHands(new Object(), "a", "b"), "wrong type rejected");
            require(bridge.setCreatorPreviewHands(ui, "Axe", "Torch"), "set succeeds without debug");
            require("Axe".equals(primary.get(model)), "primary native value");
            require("Torch".equals(secondary.get(model)), "secondary native value");
            require(bridge.setCreatorPreviewHands(ui, null, null), "clear succeeds");
            require(primary.get(model) == null && secondary.get(model) == null, "both native values cleared");
            modelField.set(ui, null);
            require(!bridge.setCreatorPreviewHands(ui, "a", "b"), "missing model rejected");
        } finally {
            debug.setBoolean(null, originalDebug);
        }
        System.out.println("PASS creator preview bridge native setters (inert objects, debug off)");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
