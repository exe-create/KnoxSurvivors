package com.knoxsurvivors.agent;

import java.util.concurrent.atomic.AtomicBoolean;

/** Runtime predicates used by Knox's narrowly-scoped combat patches. */
public final class KnoxCombatGate {
    private static final String SHELL_CLASS = "com.knoxsurvivors.engine.KnoxIsoPlayerShell";
    private static final ThreadLocal<Object> targetVisibilityCandidate = new ThreadLocal<>();
    private static final AtomicBoolean RUNTIME_READY_LOGGED = new AtomicBoolean(false);
    private static volatile boolean strengthPatchReady;
    private static volatile boolean patchReady;
    private static volatile int patchedCallCount;
    private static volatile boolean visibilityPatchReady;
    private static volatile int visibilityPatchedCallCount;

    private KnoxCombatGate() { }

    public static boolean isKnoxShell(Object character) {
        return character != null && SHELL_CLASS.equals(character.getClass().getName());
    }

    public static boolean allowLocalCombatHook(Object character) {
        if (character == null) return false;
        try {
            if ((Boolean) character.getClass().getMethod("isLocalPlayer").invoke(character)) {
                return true;
            }
        } catch (ReflectiveOperationException ignored) {
            return false;
        }
        return isKnoxShell(character);
    }

    /** Calls the installed public native method once at the redirected Hit seam. */
    public static float processSurvivorHitDamage(Object victim, Object weapon, Object attacker,
        float damage, boolean flag, float dot) {
        if (victim == null) throw new NullPointerException("victim");
        try {
            ClassLoader loader = victim.getClass().getClassLoader();
            Class<?> character = Class.forName("zombie.characters.IsoGameCharacter", false, loader);
            Class<?> weaponType = Class.forName("zombie.inventory.types.HandWeapon", false, loader);
            float nativeDamage = ((Number) character.getMethod("processHitDamage", weaponType, character,
                float.class, boolean.class, float.class).invoke(victim, weapon, attacker, damage, flag, dot)).floatValue();
            return KnoxAgent.usesBridgePatches()
                ? scaleSurvivorDamage(victim, weapon, attacker, nativeDamage) : nativeDamage;
        } catch (java.lang.reflect.InvocationTargetException failure) {
            return KnoxCombatGate.<RuntimeException, Float>rethrow(failure.getCause());
        } catch (ReflectiveOperationException failure) {
            throw new IllegalStateException("Native processHitDamage unavailable", failure);
        }
    }

    @SuppressWarnings("unchecked")
    private static <E extends Throwable, R> R rethrow(Throwable failure) throws E {
        throw (E) failure;
    }

    /** Adjust only a registered survivor's eligible melee damage; fail closed on stale context. */
    public static float scaleSurvivorDamage(Object victim, Object weapon, Object attacker, float damage) {
        if (!Float.isFinite(damage) || damage <= 0 || victim == null || victim == attacker
            || !isKnoxShell(attacker) || weapon == null) return damage;
        try {
            ClassLoader loader = attacker.getClass().getClassLoader();
            if (Class.forName("zombie.network.GameClient", false, loader).getField("client").getBoolean(null)
                || Class.forName("zombie.network.GameServer", false, loader).getField("server").getBoolean(null)) return damage;
            Class<?> player = Class.forName("zombie.characters.IsoPlayer", false, loader);
            Class<?> zombie = Class.forName("zombie.characters.IsoZombie", false, loader);
            if (!(zombie.isInstance(victim) || isKnoxShell(victim))
                || (player.isInstance(victim) && !isKnoxShell(victim))) return damage;
            if (!(Boolean) weapon.getClass().getMethod("isMelee").invoke(weapon)
                || (Boolean) weapon.getClass().getMethod("isBareHands").invoke(weapon)
                || (Boolean) weapon.getClass().getMethod("isRanged").invoke(weapon)
                || (Boolean) weapon.getClass().getMethod("isExplosive").invoke(weapon)) return damage;
            for (String name : new String[]{"isDoShove", "isShoveStompAnim", "isPerformingShoveAnimation", "isPerformingStompAnimation"})
                if ((Boolean) attacker.getClass().getMethod(name).invoke(attacker)) return damage;
            for (Object actor : new Object[]{attacker, victim}) {
                if ((Boolean) actor.getClass().getMethod("isDead").invoke(actor)
                    || actor.getClass().getMethod("getCurrentSquare").invoke(actor) == null) return damage;
            }
            Class<?> lua = Class.forName("zombie.Lua.LuaManager", false, loader);
            Object env = lua.getField("env").get(null);
            if (env == null) return damage;
            Object bridge = com.knoxsurvivors.bridge.KnoxBridgeBootstrap.getBridge();
            if (rawGet(env, "KnoxJavaBridge") != bridge) return damage;
            Object sandbox = rawGet(env, "SandboxVars");
            Object settings = rawGet(sandbox, "KnoxSurvivors");
            if (settings == null || Boolean.FALSE.equals(rawGet(settings, "Enabled"))) return damage;
            Object value = rawGet(settings, "SurvivorStrength");
            if (!(value instanceof Number)) return damage;
            double tier = ((Number) value).doubleValue();
            if (tier != Math.rint(tier) || tier < 1 || tier > 4 || tier == 2) return damage;
            if (lua.getField("env").get(null) != env) return damage;
            com.knoxsurvivors.bridge.KnoxBridge current = com.knoxsurvivors.bridge.KnoxBridgeBootstrap.getBridge();
            if (current != bridge || !current.containsActiveBody(attacker)
                || (isKnoxShell(victim) && !current.containsActiveBody(victim))) return damage;
            float scaled = damage * (tier == 1 ? 0.9f : tier == 3 ? 1.1f : 2.0f);
            return Float.isFinite(scaled) ? scaled : damage;
        } catch (ReflectiveOperationException | LinkageError | RuntimeException unavailable) {
            return damage;
        }
    }

    private static Object rawGet(Object table, String key) throws ReflectiveOperationException {
        return table == null ? null : table.getClass().getMethod("rawget", Object.class).invoke(table, key);
    }

    /** Legacy transformer helper. */
    public static int captureTargetVisibilityIndex(Object target) {
        targetVisibilityCandidate.set(target);
        try {
            return ((Number) target.getClass().getMethod("getIndex").invoke(target)).intValue();
        } catch (ReflectiveOperationException exception) {
            targetVisibilityCandidate.remove();
            return -1;
        }
    }

    /** Legacy transformer helper. */
    public static boolean allowTargetVisibility(Object square, int playerIndex) {
        Object target = targetVisibilityCandidate.get();
        targetVisibilityCandidate.remove();
        if (isKnoxShell(target)) return true;
        try {
            return square != null && (Boolean) square.getClass()
                .getMethod("isCouldSee", int.class)
                .invoke(square, playerIndex);
        } catch (ReflectiveOperationException exception) {
            return false;
        }
    }

    public static void clearTargetVisibilityCandidate() {
        targetVisibilityCandidate.remove();
    }

    static void markStrengthPatchReady(boolean ready) { strengthPatchReady = ready; }
    public static boolean isStrengthPatchReady() { return strengthPatchReady; }

    static void markPatchReady(int calls) {
        patchedCallCount = calls;
        patchReady = calls == KnoxSwipeStateTransformer.EXPECTED_PATCH_COUNT;
    }

    static void markVisibilityPatchReady(int calls) {
        visibilityPatchedCallCount = calls;
        visibilityPatchReady = calls == KnoxZombieVisibilityTransformer.EXPECTED_PATCH_COUNT;
    }

    static void markRuntimeReadyIfPatched() {
        if (patchReady && visibilityPatchReady && RUNTIME_READY_LOGGED.compareAndSet(false, true))
            KnoxAgent.writeLog("KnoxBridge required combat patches ready callbacks="
                + patchedCallCount + " visibility=" + visibilityPatchedCallCount);
    }

    public static boolean isPatchReady() {
        return patchReady;
    }

    public static int getPatchedCallCount() {
        return patchedCallCount;
    }

    public static boolean isVisibilityPatchReady() {
        return visibilityPatchReady;
    }

    public static int getVisibilityPatchedCallCount() {
        return visibilityPatchedCallCount;
    }
}
