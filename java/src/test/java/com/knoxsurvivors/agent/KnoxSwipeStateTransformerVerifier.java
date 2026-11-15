package com.knoxsurvivors.agent;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.zip.ZipFile;

public final class KnoxSwipeStateTransformerVerifier {
    private KnoxSwipeStateTransformerVerifier() {
    }

    public static void main(String[] arguments) throws Exception {
        if (arguments.length != 4) {
            throw new IllegalArgumentException(
                "Expected game jar, project root, artifact and ZombieBuddy jar"
            );
        }
        byte[] original;
        byte[] impactOriginal;
        byte[] damageOriginal;
        try (ZipFile gameJar = new ZipFile(Path.of(arguments[0]).toFile())) {
            original = gameJar.getInputStream(
                gameJar.getEntry("zombie/ai/states/SwipeStatePlayer.class")
            ).readAllBytes();
            impactOriginal = gameJar.getInputStream(gameJar.getEntry("zombie/CombatManager.class")).readAllBytes();
            damageOriginal = gameJar.getInputStream(gameJar.getEntry("zombie/characters/IsoGameCharacter.class")).readAllBytes();
        }
        verifyStrengthShape(damageOriginal);
        byte[] damage = KnoxSwipeStateTransformer.patchStrengthForVerification(damageOriginal);
        if (Arrays.equals(damage, damageOriginal)) throw new AssertionError("Strength seam not patched");
        try {
            KnoxSwipeStateTransformer.patchStrengthForVerification(damage);
            throw new AssertionError("Strength shape must fail closed");
        } catch (java.io.IOException expected) { }
        byte[] patched = KnoxSwipeStateTransformer.patchForVerification(original);
        byte[] impact = KnoxSwipeStateTransformer.patchImpactForVerification(impactOriginal);
        byte[] human = KnoxSwipeStateTransformer.patchHumanForVerification(impact);
        if (Arrays.equals(human, impact)) throw new AssertionError("Human pair gates not patched");
        try {
            KnoxSwipeStateTransformer.patchHumanForVerification(human);
            throw new AssertionError("Human gate shape must fail closed");
        } catch (java.io.IOException expected) { }
        verifyPairs();
        verifyPlayerAttacks();
        if (Arrays.equals(impact, impactOriginal)) throw new AssertionError("Impact audio gate not patched");
        try {
            KnoxSwipeStateTransformer.patchImpactForVerification(impact);
            throw new AssertionError("Unexpected engine shape must fail closed");
        } catch (java.io.IOException expected) {
            // Already redirected gate must not patch another local-player check.
        }
        System.out.println("combat impact transformer verified calls=1 fail_closed=true");
        if (KnoxSwipeStateTransformer.getLastPatchCount()
            != KnoxSwipeStateTransformer.EXPECTED_PATCH_COUNT) {
            throw new AssertionError(
                "Unexpected patched call count " + KnoxSwipeStateTransformer.getLastPatchCount()
            );
        }
        if (Arrays.equals(original, patched)) {
            throw new AssertionError("Transformer did not change SwipeStatePlayer");
        }
        com.knoxsurvivors.runtime.KnoxStrengthFixtureVerifier.verify(Path.of(arguments[1]), Path.of(arguments[2]), Path.of(arguments[3]), false,
            (classes, bytes) -> KnoxSwipeStateTransformer.patchStrengthForVerification(bytes));
        System.out.println(
            "combat transformer verified calls=" + KnoxSwipeStateTransformer.getLastPatchCount()
        );
    }

    private static void verifyStrengthShape(byte[] original) throws Exception {
        byte[] prefix = {(byte)0x2a,(byte)0x2b,(byte)0x2c,(byte)0x25,(byte)0x15,4,(byte)0x17,5,(byte)0xb6};
        int position = -1, count = 0;
        for (int i=0;i+22<original.length;i++) {
            boolean match=true;
            for (int j=0;j<prefix.length;j++) if (original[i+j]!=prefix[j]) { match=false; break; }
            if (!match) continue;
            byte[] candidate=original.clone(); candidate[i]=0x2b;
            try { KnoxSwipeStateTransformer.patchStrengthForVerification(candidate); }
            catch (java.io.IOException expected) { position=i; count++; }
        }
        if (count != 1) throw new AssertionError("Installed strength argument shape must be unique: " + count);
        byte[] wrong=original.clone(); wrong[position]=0x2b;
        failsWithoutMutation(wrong, "wrong argument shape");
        byte[] duplicate=original.clone(); System.arraycopy(original,position,duplicate,position+11,11);
        failsWithoutMutation(duplicate, "duplicate strength call");
        byte[] missing=KnoxSwipeStateTransformer.patchStrengthForVerification(original);
        failsWithoutMutation(missing, "missing target call");
        System.out.println("strength shape verified wrong=true duplicate=true missing=true original_unchanged=true");
    }

    private static void failsWithoutMutation(byte[] input, String label) throws Exception {
        byte[] before=input.clone();
        try {
            KnoxSwipeStateTransformer.patchStrengthForVerification(input);
            throw new AssertionError(label + " must fail closed");
        } catch (java.io.IOException expected) { }
        if (!Arrays.equals(before,input)) throw new AssertionError(label + " mutated original");
    }

    private static void verifyPairs() {
        if (!KnoxHumanCombatGate.usesPair(true, false, false, true, true)
            || KnoxHumanCombatGate.usesPair(false, false, false, true, true)
            || KnoxHumanCombatGate.usesPair(true, true, false, true, true)
            || KnoxHumanCombatGate.usesPair(true, false, true, true, true)
            || KnoxHumanCombatGate.usesPair(true, false, false, false, true)
            || KnoxHumanCombatGate.usesPair(true, false, false, true, false))
            throw new AssertionError("Only a registered single-player human pair uses the adapter");
        if (!KnoxHumanCombatGate.canHit(false, false, false, true, true)
            || KnoxHumanCombatGate.canHit(true, false, false, true, true)
            || KnoxHumanCombatGate.canHit(false, true, false, true, true)
            || KnoxHumanCombatGate.canHit(false, false, true, true, true)
            || KnoxHumanCombatGate.canHit(false, false, false, false, true)
            || KnoxHumanCombatGate.canHit(false, false, false, true, false))
            throw new AssertionError("Godmode/dead/detached bodies cannot bypass native protection");
        KnoxHumanCombatGate.Pairs pairs = new KnoxHumanCombatGate.Pairs();
        Object owner = new Object(), npc = new Object(), target = new Object(), other = new Object();
        pairs.put(owner, npc, target, 0);
        if (!pairs.contains(npc, target, 1) || !pairs.contains(target, npc, 1)
            || pairs.contains(npc, other, 1)) throw new AssertionError("Exact pair/self-defense scope");
        pairs.put(owner, npc, other, 2);
        if (pairs.contains(npc, target, 3) || !pairs.contains(npc, other, 3))
            throw new AssertionError("Replacing target must revoke previous pair");
        pairs.remove(owner);
        if (pairs.contains(npc, other, 4)) throw new AssertionError("Reset must revoke pair");
        pairs.put(owner, npc, target, 5);
        if (pairs.contains(npc, target, 5 + KnoxHumanCombatGate.Pairs.TTL))
            throw new AssertionError("Orphaned lease must expire");
        pairs.put(owner, npc, npc, 6);
        if (pairs.contains(npc, npc, 7)) throw new AssertionError("Self hit cannot be authorized");
        System.out.println("human pair gates verified calls=3 scope=true replacement=true cleanup=true expiry=true");
    }

    private static void verifyPlayerAttacks() {
        KnoxHumanCombatGate.PlayerAttacks attacks = new KnoxHumanCombatGate.PlayerAttacks();
        Object player = new Object(), otherPlayer = new Object(), npc = new Object(), ally = new Object();
        attacks.set(player, npc, true, 0);
        if (attacks.permission(player, npc, 0) != null) throw new AssertionError("No attack owner");
        attacks.begin(player, 1);
        attacks.set(player, npc, true, 1);
        attacks.set(player, ally, false, 1);
        if (!Boolean.TRUE.equals(attacks.permission(player, npc, 2))
            || !Boolean.FALSE.equals(attacks.permission(player, ally, 2))
            || attacks.permission(npc, player, 2) != null
            || attacks.permission(otherPlayer, npc, 2) != null)
            throw new AssertionError("Player permission must be directional and protect allies");
        attacks.begin(player, 3);
        if (attacks.permission(player, npc, 3) != null) throw new AssertionError("Hit point rebuild clears windup state");
        attacks.set(player, npc, false, 3);
        if (!Boolean.FALSE.equals(attacks.permission(player, npc, 3))) throw new AssertionError("Recruitment revokes permission");
        if (attacks.permission(player, npc, 3 + KnoxHumanCombatGate.PlayerAttacks.TTL) != null)
            throw new AssertionError("Missed attack expires");
        attacks.begin(player, 4);
        attacks.set(player, npc, true, 4);
        attacks.clear();
        if (attacks.permission(player, npc, 5) != null) throw new AssertionError("World teardown clears attacks");
        System.out.println("player attack eligibility verified directional=true friendly=true expiry=true cleanup=true");
    }
}
