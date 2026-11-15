package com.knoxsurvivors.agent;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.Set;

/**
 * Redirects three animation callback checks plus the exact standing-target impact-audio
 * check to a predicate that recognizes the Knox shell. Native callback/audio bodies remain intact.
 */
public final class KnoxSwipeStateTransformer implements ClassFileTransformer {
    static final int EXPECTED_PATCH_COUNT = 3;
    private static final String TARGET_CLASS = "zombie/ai/states/SwipeStatePlayer";
    private static final String IMPACT_CLASS = "zombie/CombatManager";
    private static final String DAMAGE_CLASS = "zombie/characters/IsoGameCharacter";
    private static final String ORIGINAL_OWNER = "zombie/characters/IsoPlayer";
    private static final String ORIGINAL_NAME = "isLocalPlayer";
    private static final String ORIGINAL_DESCRIPTOR =
        "(Lzombie/characters/IsoGameCharacter;)Z";
    private static final String HELPER_OWNER = "com/knoxsurvivors/agent/KnoxCombatGate";
    private static final String HELPER_NAME = "allowLocalCombatHook";
    private static final String HELPER_DESCRIPTOR = "(Ljava/lang/Object;)Z";
    private static final Set<String> PATCHED_METHODS = Set.of(
        "OnAnimEvent_AttackCollisionCheck",
        "OnAnimEvent_PlaySwingSound",
        "OnAnimEvent_PlaySwingSoundAlways"
    );

    private static volatile int lastPatchCount;

    @Override
    public byte[] transform(
        ClassLoader loader,
        String className,
        Class<?> classBeingRedefined,
        ProtectionDomain protectionDomain,
        byte[] classfileBuffer
    ) {
        if (!TARGET_CLASS.equals(className) && !IMPACT_CLASS.equals(className) && !DAMAGE_CLASS.equals(className)) {
            return null;
        }
        if (DAMAGE_CLASS.equals(className)) {
            try {
                byte[] patched = patchStrengthForVerification(classfileBuffer);
                KnoxCombatGate.markStrengthPatchReady(true);
                KnoxAgent.writeLog("survivor strength damage seam PASS calls=1");
                return patched;
            } catch (Throwable failure) {
                KnoxCombatGate.markStrengthPatchReady(false);
                KnoxAgent.writeLog("ERROR survivor strength damage seam " + failure);
                return null;
            }
        }
        if (IMPACT_CLASS.equals(className)) {
            try {
                byte[] patched = patchHumanForVerification(patchImpactForVerification(classfileBuffer));
                KnoxAgent.writeLog("combat impact sound and human-pair gates PASS calls=4");
                return patched;
            } catch (IOException exception) {
                KnoxAgent.writeLog("ERROR combat impact sound patch " + exception.getMessage());
                return null;
            }
        }
        try {
            PatchResult result = patch(classfileBuffer);
            lastPatchCount = result.count;
            KnoxCombatGate.markPatchReady(result.count);
            KnoxCombatGate.markRuntimeReadyIfPatched();
            if (result.count != EXPECTED_PATCH_COUNT) {
                KnoxAgent.writeLog(
                    "ERROR combat callback patch expected="
                        + EXPECTED_PATCH_COUNT
                        + " actual="
                        + result.count
                );
                return null;
            }
            KnoxAgent.writeLog("combat callback patch PASS calls=" + result.count);
            return result.bytes;
        } catch (Throwable throwable) {
            KnoxCombatGate.markPatchReady(0);
            KnoxAgent.writeLog(
                "ERROR combat callback patch "
                    + throwable.getClass().getName()
                    + ": "
                    + throwable.getMessage()
            );
            return null;
        }
    }

    static int getLastPatchCount() {
        return lastPatchCount;
    }

    static byte[] patchForVerification(byte[] bytes) throws IOException {
        PatchResult result = patch(bytes);
        lastPatchCount = result.count;
        return result.bytes;
    }

    private static PatchResult patch(byte[] original) throws IOException {
        return patch(original, false);
    }

    static byte[] patchImpactForVerification(byte[] original) throws IOException {
        PatchResult result = patch(original, true);
        if (result.count != 1) throw new IOException("Expected one installed impact audio gate, got " + result.count);
        return result.bytes;
    }

    private static PatchResult patch(byte[] original, boolean impact) throws IOException {
        return patch(original, impact, false, false);
    }

    static byte[] patchHumanForVerification(byte[] original) throws IOException {
        PatchResult result = patch(original, false, true, false);
        if (result.count != 3) throw new IOException("Expected three human eligibility gates, got " + result.count);
        return result.bytes;
    }

    static byte[] patchStrengthForVerification(byte[] original) throws IOException {
        PatchResult result = patch(original, false, false, true);
        if (result.count != 1) throw new IOException("Expected one survivor strength damage seam, got " + result.count);
        return result.bytes;
    }

    private static PatchResult patch(byte[] original, boolean impact, boolean human, boolean strength) throws IOException {
        ConstantPool pool = ConstantPool.read(original);
        int originalMethodRef = pool.findMethodRef(
            strength ? DAMAGE_CLASS : human ? "zombie/CombatManager" : ORIGINAL_OWNER,
            strength ? "processHitDamage" : human ? "checkPVP" : ORIGINAL_NAME,
            strength ? "(Lzombie/inventory/types/HandWeapon;Lzombie/characters/IsoGameCharacter;FZF)F"
                : human ? "(Lzombie/iso/IsoMovingObject;Lzombie/iso/IsoMovingObject;Z)Z"
                : impact ? "()Z" : ORIGINAL_DESCRIPTOR
        );
        if (originalMethodRef < 0) {
            throw new IOException(strength ? "Survivor strength processHitDamage reference was not found" : "IsoPlayer.isLocalPlayer combat gate was not found");
        }

        int helperMethodRef = pool.count + 5;
        ByteArrayOutputStream additions = new ByteArrayOutputStream();
        try (DataOutputStream output = new DataOutputStream(additions)) {
            int ownerUtf8 = pool.count;
            int ownerClass = pool.count + 1;
            int nameUtf8 = pool.count + 2;
            int descriptorUtf8 = pool.count + 3;
            int nameAndType = pool.count + 4;
            writeUtf8(output, human ? "com/knoxsurvivors/agent/KnoxHumanCombatGate" : HELPER_OWNER);
            output.writeByte(7);
            output.writeShort(ownerUtf8);
            writeUtf8(output, strength ? "processSurvivorHitDamage" : human ? "checkPVP" : HELPER_NAME);
            writeUtf8(output, strength ? "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;FZF)F" : human ? "(Ljava/lang/Object;Ljava/lang/Object;Z)Z" : HELPER_DESCRIPTOR);
            output.writeByte(12);
            output.writeShort(nameUtf8);
            output.writeShort(descriptorUtf8);
            output.writeByte(10);
            output.writeShort(ownerClass);
            output.writeShort(nameAndType);
        }

        byte[] expanded = new byte[original.length + additions.size()];
        System.arraycopy(original, 0, expanded, 0, 8);
        writeU2(expanded, 8, pool.count + 6);
        System.arraycopy(original, 10, expanded, 10, pool.endOffset - 10);
        byte[] appended = additions.toByteArray();
        System.arraycopy(appended, 0, expanded, pool.endOffset, appended.length);
        System.arraycopy(
            original,
            pool.endOffset,
            expanded,
            pool.endOffset + appended.length,
            original.length - pool.endOffset
        );

        int count = patchMethodCode(
            expanded,
            pool,
            pool.endOffset + appended.length,
            originalMethodRef,
            helperMethodRef,
            impact, human, strength
        );
        return new PatchResult(expanded, count);
    }

    private static int patchMethodCode(
        byte[] bytes,
        ConstantPool pool,
        int classBodyOffset,
        int originalMethodRef,
        int helperMethodRef,
        boolean impact, boolean human, boolean strength
    ) throws IOException {
        int cursor = classBodyOffset + 6;
        int interfaceCount = readU2(bytes, cursor);
        cursor += 2 + interfaceCount * 2;
        int fieldCount = readU2(bytes, cursor);
        cursor += 2;
        for (int index = 0; index < fieldCount; index++) {
            cursor = skipMember(bytes, cursor);
        }

        int methodCount = readU2(bytes, cursor);
        cursor += 2;
        int patched = 0;
        for (int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
            cursor += 2;
            int nameIndex = readU2(bytes, cursor);
            cursor += 2;
            int descriptorIndex = readU2(bytes, cursor);
            cursor += 2;
            int attributeCount = readU2(bytes, cursor);
            cursor += 2;
            String methodName = pool.utf8(nameIndex);
            for (int attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
                int attributeNameIndex = readU2(bytes, cursor);
                long attributeLength = readU4(bytes, cursor + 2);
                int content = cursor + 6;
                int humanOffset = humanGateOffset(methodName, pool.utf8(descriptorIndex));
                if ((strength ? "Hit".equals(methodName) && "(Lzombie/inventory/types/HandWeapon;Lzombie/characters/IsoGameCharacter;FZFZ)F".equals(pool.utf8(descriptorIndex)) : human ? humanOffset >= 0 : impact ? "attackCollisionCheck".equals(methodName) : PATCHED_METHODS.contains(methodName))
                    && "Code".equals(pool.utf8(attributeNameIndex))) {
                    int codeLength = (int) readU4(bytes, content + 4);
                    int codeStart = content + 8;
                    int codeEnd = codeStart + codeLength;
                    if (strength) {
                        for (int offset = codeStart; offset + 2 < codeEnd; offset++) {
                            if (offset >= codeStart + 8 && hasStrengthArguments(bytes, offset - 8)
                                && (bytes[offset] & 0xff) == 0xb6 && readU2(bytes, offset + 1) == originalMethodRef) {
                                bytes[offset] = (byte) 0xb8;
                                writeU2(bytes, offset + 1, helperMethodRef);
                                patched++;
                            }
                        }
                        cursor = content + Math.toIntExact(attributeLength);
                        continue;
                    }
                    if (human) {
                        int offset = codeStart + humanOffset;
                        if (offset + 2 < codeEnd && (bytes[offset] & 0xff) == 0xb8
                            && readU2(bytes, offset + 1) == originalMethodRef) {
                            writeU2(bytes, offset + 1, helperMethodRef);
                            patched++;
                        }
                        cursor = content + Math.toIntExact(attributeLength);
                        continue;
                    }
                    if (impact) {
                        // Exact impact-audio branch shape: aload receiver; isLocalPlayer;
                        // ifeq; aload_2; HandWeapon.getHitFloorSound. Locate it by bytecode
                        // structure because the installed build moved isLocalPlayer after
                        // the isRanged/isNpc checks and changed the branch offset.
                        int hitFloorSoundRef = pool.findMethodRef("zombie/inventory/types/HandWeapon", "getHitFloorSound", "()Ljava/lang/String;");
                        int match = -1;
                        int matchCount = 0;
                        for (int call = codeStart + 2; call + 10 < codeEnd; call++) {
                            if (!isAloadReceiver(bytes, call - 2)
                                || (bytes[call] & 0xff) != 0xb6
                                || readU2(bytes, call + 1) != originalMethodRef
                                || (bytes[call + 3] & 0xff) != 0x99
                                || (bytes[call + 6] & 0xff) != 0x2c
                                || (bytes[call + 7] & 0xff) != 0xb6
                                || readU2(bytes, call + 8) != hitFloorSoundRef) continue;
                            match = call;
                            matchCount++;
                        }
                        if (matchCount == 1) {
                            bytes[match] = (byte) 0xb8;
                            writeU2(bytes, match + 1, helperMethodRef);
                            patched++;
                        }
                        cursor = content + Math.toIntExact(attributeLength);
                        continue;
                    }
                    for (int offset = codeStart; offset + 2 < codeEnd; offset++) {
                        if ((bytes[offset] & 0xFF) == 0xB8
                            && readU2(bytes, offset + 1) == originalMethodRef) {
                            writeU2(bytes, offset + 1, helperMethodRef);
                            patched++;
                        }
                    }
                }
                cursor = content + Math.toIntExact(attributeLength);
            }
        }
        return patched;
    }

    private static boolean hasStrengthArguments(byte[] bytes, int offset) {
        int[] expected = {0x2a, 0x2b, 0x2c, 0x25, 0x15, 0x04, 0x17, 0x05};
        for (int index = 0; index < expected.length; index++) {
            if ((bytes[offset + index] & 0xff) != expected[index]) return false;
        }
        return true;
    }

    private static boolean isAloadReceiver(byte[] bytes, int start) {
        int opcode = bytes[start] & 0xff;
        if (opcode >= 0x2a && opcode <= 0x2d) return true; // aload_0 through aload_3
        if (opcode == 0x19) return true; // aload index
        return start >= 2 && (bytes[start - 2] & 0xff) == 0xc4
            && (bytes[start - 1] & 0xff) == 0x19; // wide aload index
    }

    private static int humanGateOffset(String name, String descriptor) {
        if (name.equals("calcValidTarget") && descriptor.equals(
            "(Lzombie/characters/IsoLivingCharacter;Lzombie/inventory/types/HandWeapon;Lzombie/iso/IsoMovingObject;F)Lzombie/network/fields/hit/HitInfo;")) return 66;
        if (name.equals("calcHitListShove") && descriptor.equals(
            "(Lzombie/characters/IsoGameCharacter;Lzombie/network/fields/hit/AttackVars;Ljava/util/List;)V")) return 213;
        if (name.equals("removeTargetObjects") && descriptor.equals(
            "(Lzombie/iso/IsoMovingObject;Lzombie/characters/IsoGameCharacter;Z)Z")) return 100;
        return -1;
    }

    private static int skipMember(byte[] bytes, int cursor) {
        cursor += 6;
        int attributeCount = readU2(bytes, cursor);
        cursor += 2;
        for (int index = 0; index < attributeCount; index++) {
            long length = readU4(bytes, cursor + 2);
            cursor += 6 + Math.toIntExact(length);
        }
        return cursor;
    }

    private static void writeUtf8(DataOutputStream output, String value) throws IOException {
        output.writeByte(1);
        output.writeUTF(value);
    }

    private static int readU2(byte[] bytes, int offset) {
        return ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
    }

    private static long readU4(byte[] bytes, int offset) {
        return ((long) (bytes[offset] & 0xFF) << 24)
            | ((long) (bytes[offset + 1] & 0xFF) << 16)
            | ((long) (bytes[offset + 2] & 0xFF) << 8)
            | (bytes[offset + 3] & 0xFFL);
    }

    private static void writeU2(byte[] bytes, int offset, int value) {
        bytes[offset] = (byte) (value >>> 8);
        bytes[offset + 1] = (byte) value;
    }

    private record PatchResult(byte[] bytes, int count) {
    }

    private static final class ConstantPool {
        final int count;
        final int endOffset;
        final int[] tags;
        final int[] first;
        final int[] second;
        final String[] utf8;

        private ConstantPool(
            int count,
            int endOffset,
            int[] tags,
            int[] first,
            int[] second,
            String[] utf8
        ) {
            this.count = count;
            this.endOffset = endOffset;
            this.tags = tags;
            this.first = first;
            this.second = second;
            this.utf8 = utf8;
        }

        static ConstantPool read(byte[] bytes) throws IOException {
            if (readU4(bytes, 0) != 0xCAFEBABEL) {
                throw new IOException("Invalid class file magic");
            }
            int count = readU2(bytes, 8);
            int[] tags = new int[count];
            int[] first = new int[count];
            int[] second = new int[count];
            String[] utf8 = new String[count];
            int cursor = 10;
            for (int index = 1; index < count; index++) {
                int tag = bytes[cursor++] & 0xFF;
                tags[index] = tag;
                switch (tag) {
                    case 1 -> {
                        int length = readU2(bytes, cursor);
                        cursor += 2;
                        utf8[index] = new String(
                            bytes,
                            cursor,
                            length,
                            java.nio.charset.StandardCharsets.UTF_8
                        );
                        cursor += length;
                    }
                    case 3, 4 -> cursor += 4;
                    case 5, 6 -> {
                        cursor += 8;
                        index++;
                    }
                    case 7, 8, 16, 19, 20 -> {
                        first[index] = readU2(bytes, cursor);
                        cursor += 2;
                    }
                    case 9, 10, 11, 12, 17, 18 -> {
                        first[index] = readU2(bytes, cursor);
                        second[index] = readU2(bytes, cursor + 2);
                        cursor += 4;
                    }
                    case 15 -> cursor += 3;
                    default -> throw new IOException("Unsupported constant-pool tag " + tag);
                }
            }
            return new ConstantPool(count, cursor, tags, first, second, utf8);
        }

        String utf8(int index) {
            return index > 0 && index < utf8.length ? utf8[index] : null;
        }

        int findMethodRef(String owner, String name, String descriptor) {
            for (int index = 1; index < count; index++) {
                if (tags[index] != 10) {
                    continue;
                }
                int classIndex = first[index];
                int nameAndTypeIndex = second[index];
                if (tags[classIndex] == 7
                    && owner.equals(utf8(first[classIndex]))
                    && tags[nameAndTypeIndex] == 12
                    && name.equals(utf8(first[nameAndTypeIndex]))
                    && descriptor.equals(utf8(second[nameAndTypeIndex]))) {
                    return index;
                }
            }
            return -1;
        }
    }
}
