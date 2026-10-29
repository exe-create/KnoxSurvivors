package com.knoxsurvivors.bridge;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.engine.KnoxShellVisibility;
import com.knoxsurvivors.npc.KnoxNpcRegistry;

/**
 * Single Java object exposed to Project Zomboid Lua.
 *
 * <p>Gameplay capabilities will be added here only after each preceding bridge and lifecycle
 * milestone is verified in game.</p>
 */
public final class KnoxBridge {
    public static final String RUNTIME_VERSION = "0.3.0-rc1";

    private long pingCount;
    private final KnoxNpcRegistry npcRegistry = new KnoxNpcRegistry();

    public synchronized String ping() {
        pingCount++;
        KnoxAgent.writeLog("Lua bridge ping count=" + pingCount);
        return "Knox Survivors Runtime " + RUNTIME_VERSION;
    }

    public String getRuntimeVersion() {
        return RUNTIME_VERSION;
    }

    public String getRuntimeSource() {
        return KnoxAgent.getRuntimeSource();
    }

    public boolean isRuntimeLoaded() {
        return true;
    }

    /** Native ordinary-speech intelligibility, not a Knox hearing radius or radio receipt. */
    public boolean canHearOrder(Object speaker, Object listener) {
        if (speaker == null || listener == null) return false;
        try {
            ClassLoader loader = listener.getClass().getClassLoader();
            Class<?> player = Class.forName("zombie.characters.IsoPlayer", false, loader);
            Class<?> object = Class.forName("zombie.iso.IsoObject", false, loader);
            if (!player.isInstance(listener) || !object.isInstance(speaker)) return false;
            if (Boolean.TRUE.equals(listener.getClass().getMethod("isAsleep").invoke(listener))
                || Boolean.TRUE.equals(listener.getClass().getMethod("isDead").invoke(listener))
                || Boolean.TRUE.equals(speaker.getClass().getMethod("isDead").invoke(speaker))
                || listener.getClass().getMethod("getCurrentSquare").invoke(listener) == null
                || speaker.getClass().getMethod("getCurrentSquare").invoke(speaker) == null) return false;
            Class<?> trait = Class.forName("zombie.scripting.objects.CharacterTrait", false, loader);
            Object deaf = trait.getField("DEAF").get(null);
            if (deaf == null || Boolean.TRUE.equals(listener.getClass()
                .getMethod("hasTrait", trait).invoke(listener, deaf))) return false;
            Class<?> say = Class.forName("zombie.chat.defaultChats.SayChat", false, loader);
            Object settings = say.getMethod("getDefaultSettings").invoke(null);
            float range = ((Number) settings.getClass().getMethod("getRange").invoke(settings)).floatValue();
            if (!Float.isFinite(range) || range <= 0) return false;
            Class<?> utility = Class.forName("zombie.chat.ChatUtility", false, loader);
            float scramble = ((Number) utility.getMethod("getScrambleValue", object, player, float.class)
                .invoke(null, speaker, listener, range)).floatValue();
            return Float.isFinite(scramble) && scramble == 0;
        } catch (ReflectiveOperationException | LinkageError | RuntimeException unavailable) {
            return false;
        }
    }

    public synchronized long getPingCount() {
        return pingCount;
    }

    public String spawnTestNpc(Object square) {
        return npcRegistry.spawnOne(square);
    }

    public String spawnNpc(String id, Object square) {
        return npcRegistry.spawn(id, square);
    }

    public String removeTestNpc() {
        return npcRegistry.removeOne();
    }

    public String removeNpc(String id) {
        return npcRegistry.remove(id);
    }

    /** Converts a dead survivor shell into the game's normal lootable corpse before teardown. */
    public String retireNpcAsCorpse(String id) {
        return npcRegistry.retireAsCorpse(id);
    }

    public String moveTestNpc(Object square) {
        return npcRegistry.moveOne(square);
    }

    public String moveNpc(String id, Object square) {
        return npcRegistry.move(id, square);
    }

    public String moveNpcWithPace(String id, Object square, String pace) {
        return npcRegistry.moveWithPace(id, square, pace);
    }

    public String moveNpcWithinArea(String id, Object square,
        int minX, int minY, int maxX, int maxY, int z) {
        return npcRegistry.moveWithinArea(id, square, minX, minY, maxX, maxY, z);
    }

    public boolean setNpcMovementPace(String id, String pace) {
        return npcRegistry.updateMovementPace(id, pace);
    }

    public String crossTestNpc(Object square) {
        return npcRegistry.crossOneAdjacentEdge(square);
    }

    public String crossNpc(String id, Object square) {
        return npcRegistry.cross(id, square);
    }

    public String tickTestNpc() {
        return npcRegistry.tickOne();
    }

    public String tickNpc(String id) {
        return npcRegistry.tick(id);
    }

    public String observeNpcNativeAction(String id) {
        return npcRegistry.observeNativeAction(id);
    }

    public String observeNpcNativeRecovery(String id) {
        return npcRegistry.observeNativeRecovery(id);
    }

    public String cancelNpcMove(String id) {
        return npcRegistry.cancelMove(id);
    }

    public boolean setNpcClimbingAllowed(String id, boolean allowed) {
        return npcRegistry.setClimbingAllowed(id, allowed);
    }

    public boolean setNpcDoorWindowOpeningAllowed(String id, boolean allowed) {
        return npcRegistry.setDoorWindowOpeningAllowed(id, allowed);
    }

    public String openNpcDoor(String id, Object door) {
        return npcRegistry.openDoor(id, door);
    }

    public String closeNpcOpenedDoor(String id) {
        return npcRegistry.closeOpenedDoor(id);
    }

    public boolean setNpcProtectedArea(String id, int minX, int minY, int maxX, int maxY) {
        return npcRegistry.setProtectedArea(id, minX, minY, maxX, maxY);
    }

    public boolean clearNpcProtectedArea(String id) {
        return npcRegistry.clearProtectedArea(id);
    }

    /** Keeps player-owned followers readable even when the fog-of-war briefly occludes them. */
    public boolean setNpcPartyVisible(String id, boolean visible) {
        Object character = npcRegistry.character(id);
        if (character == null) {
            return false;
        }
        KnoxShellVisibility.setPartyVisible(character, visible);
        return true;
    }

    public String getTestNpcStatus() {
        return npcRegistry.status();
    }

    public String getNpcStatus(String id) {
        return npcRegistry.status(id);
    }

    public int getActiveNpcCount() {
        return npcRegistry.activeCount();
    }

    public String getActiveNpcIds() {
        return npcRegistry.activeIds();
    }

    public String getRenderDiagnostics() {
        return npcRegistry.renderDiagnostics();
    }

    public boolean hasTestNpcTraversalEvidence(String state) {
        return npcRegistry.hasTraversalEvidence(state);
    }

    public String seedAndEquipTestNpc() {
        return npcRegistry.seedAndEquipOne();
    }

    public String seedAndEquipNpc(String id) {
        return npcRegistry.seedAndEquip(id);
    }

    public String equipBestNpc(String id) {
        return npcRegistry.equipBest(id);
    }

    /** Equip a real carried weapon chosen by the Lua planner. */
    public String equipNpcOwnedWeapon(String id, String fullType) {
        return npcRegistry.equipOwnedWeapon(id, fullType);
    }

    /** Equip the exact real inventory weapon selected by the Lua firearm planner. */
    public String equipNpcOwnedWeaponById(String id, String fullType, long itemId) {
        return npcRegistry.equipOwnedWeaponById(id, fullType, itemId);
    }

    /** Wears an existing owned clothing or container item without creating gear. */
    public String wearNpcOwnedItem(String id, String fullType) {
        return npcRegistry.wearOwnedItem(id, fullType);
    }

    /** Wears the exact carried garment/bag selected by the Lua planner. */
    public String wearNpcOwnedItemById(String id, String fullType, long itemId) {
        return npcRegistry.wearOwnedItemById(id, fullType, itemId);
    }

    /** Developer-only real-item kit for the native firearm test path. */
    public String seedNpcFirearmTestKit(String id) {
        return npcRegistry.seedFirearmTestKit(id);
    }

    public boolean isTestNpcFemale() {
        return npcRegistry.isOneFemale();
    }

    public boolean isNpcFemale(String id) {
        return npcRegistry.isFemale(id);
    }

    public String wearTestNpcItem(String fullType) {
        return npcRegistry.wearOneItem(fullType);
    }

    public String wearNpcItem(String id, String fullType) {
        return npcRegistry.wearItem(id, fullType);
    }

    public String dressNpcItem(String id, String fullType) {
        return npcRegistry.dressItem(id, fullType);
    }

    public String recreateTestNpc() {
        return npcRegistry.recreateOne();
    }

    public String getTestNpcEquipmentStatus() {
        return npcRegistry.equipmentStatus();
    }

    public String beginTestNpcCombat(Object zombie, Object approachSquare) {
        return npcRegistry.beginCombatOne(zombie, approachSquare);
    }

    public String beginTestNpcLiveCombat(Object zombie, Object approachSquare) {
        return npcRegistry.beginLiveCombatOne(zombie, approachSquare);
    }

    public void resetTestNpcCombat() {
        npcRegistry.resetCombatOne();
    }

    public String tickTestNpcCombat() {
        return npcRegistry.tickCombatOne();
    }

    public Object getTestNpcCharacterForAction() {
        return npcRegistry.activeCharacterForAction();
    }

    public Object getNpcCharacter(String id) {
        return npcRegistry.character(id);
    }

    public String prepareTestNpcHealthGate() {
        return npcRegistry.prepareHealthGateOne();
    }

    public float getTestNpcHealth() {
        return npcRegistry.healthOne();
    }

    public String refreshTestNpcHealthPresentation() {
        return npcRegistry.refreshHealthPresentationOne();
    }

    public int getTestNpcInjuredPartCount() {
        return npcRegistry.injuredPartsOne();
    }

    public int getTestNpcBleedingPartCount() {
        return npcRegistry.bleedingPartsOne();
    }

    public String normalizeTestNpcMinorInjury() {
        return npcRegistry.normalizeMinorInjuryOne();
    }

    public String directTestZombieAtNpc(Object zombie) {
        return npcRegistry.directZombieAtOne(zombie);
    }

    public String directZombieAtNpc(String id, Object zombie) {
        return npcRegistry.directZombieAt(id, zombie);
    }

    public String getZombieAttackDiagnostics(String id, Object zombie) {
        return npcRegistry.zombieAttackDiagnostics(id, zombie);
    }

    public String getNpcCombatDiagnostics(String id) {
        return npcRegistry.combatDiagnostics(id);
    }

    public String captureTestNpcRecord() {
        return npcRegistry.capturePersistentRecord();
    }

    public String captureNpcRecord(String id) {
        return npcRegistry.capturePersistentRecord(id);
    }

    public String restoreTestNpcRecord(String encoded, Object square) {
        return npcRegistry.restorePersistentRecord(encoded, square);
    }

    public java.util.Map<String, Integer> getNpcRecordLocation(String encoded) {
        return npcRegistry.persistentRecordLocation(encoded);
    }

    public int getTestNpcRecordX(String encoded) {
        return npcRegistry.persistentRecordX(encoded);
    }

    public int getTestNpcRecordY(String encoded) {
        return npcRegistry.persistentRecordY(encoded);
    }

    public int getTestNpcRecordZ(String encoded) {
        return npcRegistry.persistentRecordZ(encoded);
    }

    public String getNpcRecordId(String encoded) {
        return npcRegistry.persistentRecordId(encoded);
    }

    /** Read-only inventory counts from a portable stored survivor record. */
    public String getNpcRecordInventorySummary(String encoded) {
        return npcRegistry.persistentRecordInventorySummary(encoded);
    }

    /** Read-only native weapon readiness for a confirmed inactive identity. */
    public boolean isStoredNpcWeaponReady(String id, String encoded) {
        return npcRegistry.storedRecordWeaponReady(id, encoded);
    }

    /** Consumes one real stored item without reconstructing the survivor body. */
    public String consumeNpcRecordItem(String encoded, String fullType) {
        return npcRegistry.consumePersistentRecordItem(encoded, fullType);
    }

    /** Consumes real saved food/fluid without creating an IsoPlayer or default supplies. */
    public java.util.Map<String, Object> consumeNpcRecordSupply(String encoded, String kind, double amount) {
        return npcRegistry.consumePersistentRecordSupply(encoded, kind, amount);
    }

    /** Shares only explicitly allocated native base provisions, retaining a spare. */
    public java.util.Map<String, Object> consumeNpcRecordBaseSupply(String encoded, String kind, double amount, String baseId, int reserve) {
        return npcRegistry.consumePersistentRecordBaseSupply(encoded, kind, amount, baseId, reserve);
    }

    public String relocateNpcRecord(String encoded, int x, int y, int z) {
        return npcRegistry.relocatePersistentRecord(encoded, x, y, z);
    }

    public String beginNpcLiveCombat(String id, Object target, Object approachSquare) {
        return npcRegistry.beginLiveCombat(id, target, approachSquare);
    }

    public String beginNpcLiveCombatWithAim(
        String id,
        Object target,
        Object approachSquare,
        int aimSettleTicks
    ) {
        return npcRegistry.beginLiveCombat(id, target, approachSquare, aimSettleTicks);
    }

    public boolean beginPlayerHumanAttack(Object player) {
        return com.knoxsurvivors.agent.KnoxHumanCombatGate.beginPlayerAttack(player);
    }

    public void setPlayerHumanAttackTarget(Object player, String survivorId, boolean allowed) {
        npcRegistry.setPlayerAttackTarget(player, survivorId, allowed);
    }

    public String beginNpcLockedDoorCombat(String id) {
        return npcRegistry.beginLockedDoorCombat(id);
    }

    public String tickNpcCombat(String id) {
        return npcRegistry.tickCombat(id);
    }

    public void resetNpcCombat(String id) {
        npcRegistry.resetCombat(id);
    }

    void abandonForEnvironmentChange() {
        npcRegistry.abandonForEnvironmentChange();
    }

    @Override
    public synchronized String toString() {
        return "KnoxBridge{version=" + RUNTIME_VERSION + ", pingCount=" + pingCount + "}";
    }
}
