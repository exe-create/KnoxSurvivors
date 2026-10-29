package com.knoxsurvivors.zombiebuddy;

import com.knoxsurvivors.agent.KnoxCombatGate;
import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.agent.KnoxHumanCombatGate;
import java.util.Set;

/** Restricts method advice to the call sites owned by the existing narrow Bridge patches. */
public final class KnoxHooks {
    private static final StackWalker WALKER = StackWalker.getInstance();
    private static final Set<String> CALLBACKS = Set.of("OnAnimEvent_AttackCollisionCheck",
        "OnAnimEvent_PlaySwingSound", "OnAnimEvent_PlaySwingSoundAlways");
    private static final Set<String> HUMAN_CHECKS = Set.of("calcValidTarget", "calcHitListShove", "removeTargetObjects");

    private KnoxHooks() { }

    public static boolean allowCallback(Object character) {
        return KnoxAgent.usesZombieBuddyPatches() && KnoxCombatGate.isKnoxShell(character)
            && callerIs("zombie.ai.states.SwipeStatePlayer", CALLBACKS);
    }

    public static Boolean humanOverride(Object attacker, Object victim) {
        if (!KnoxAgent.usesZombieBuddyPatches()) return null;
        if (!KnoxCombatGate.isKnoxShell(attacker) && !KnoxCombatGate.isKnoxShell(victim)) return null;
        if (!callerIs("zombie.CombatManager", HUMAN_CHECKS)) return null;
        return KnoxHumanCombatGate.overridePVP(attacker, victim);
    }

    private static boolean callerIs(String owner, Set<String> methods) {
        // Advice is inlined into the predicate. Only its immediate caller qualifies;
        // an outer callback cannot grant local-player status inside nested combat code.
        return WALKER.walk(frames -> frames
            .dropWhile(frame -> frame.getClassName().equals(KnoxHooks.class.getName()))
            .skip(1) // the native predicate receiving the inlined advice
            .findFirst().map(frame -> frame.getClassName().equals(owner)
                && methods.contains(frame.getMethodName())).orElse(false));
    }

    public static boolean clientShellVisibility(Object zombie) {
        if (!KnoxAgent.usesZombieBuddyPatches()) return false;
        try {
            Class<?> type = zombie.getClass();
            if ((Boolean) Class.forName("zombie.network.GameServer", false, type.getClassLoader())
                .getField("server").get(null)) return false;
            Object target = type.getMethod("getTarget").invoke(zombie);
            return KnoxCombatGate.isKnoxShell(target)
                && type.getMethod("getCurrentSquare").invoke(zombie) != null;
        } catch (ReflectiveOperationException | RuntimeException exception) {
            return false;
        }
    }
}
