package com.knoxsurvivors.zombiebuddy;

import me.zed_0xff.zombie_buddy.Patch;

/** Method advice only; native attack, damage, inventory and AI implementations remain authoritative. */
public final class KnoxPatches {
    private KnoxPatches() { }

    @Patch(className = "zombie.characters.IsoPlayer", methodName = "isLocalPlayer")
    public static final class CallbackEligibility {
        @Patch.OnExit
        public static void exit(@Patch.AllArguments Object[] arguments,
                                @Patch.Return(readOnly = false) boolean result) {
            if (!result && arguments.length == 1 && KnoxHooks.allowCallback(arguments[0])) result = true;
        }
    }

    @Patch(className = "zombie.CombatManager", methodName = "checkPVP")
    public static final class HumanEligibility {
        @Patch.OnExit
        public static void exit(@Patch.AllArguments Object[] arguments,
                                @Patch.Return(readOnly = false) boolean result) {
            if (arguments.length == 3) {
                Boolean override = KnoxHooks.humanOverride(arguments[0], arguments[1]);
                if (override != null) result = override;
            }
        }
    }

    @Patch(className = "zombie.characters.IsoZombie", methodName = "isTargetVisible")
    public static final class TargetVisibility {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This Object zombie, @Patch.Local("knoxVisible") boolean bypass) {
            bypass = KnoxHooks.clientShellVisibility(zombie);
            return bypass;
        }

        @Patch.OnExit
        public static void exit(@Patch.Local("knoxVisible") boolean bypass,
                                @Patch.Return(readOnly = false) boolean result) {
            if (bypass) result = true;
        }
    }
}
