package com.knoxsurvivors.engine;

import java.nio.file.Path;
import java.util.List;

/** Real installed class metadata/parser checks only; does not start the game or create actors. */
public final class KnoxInstalledCompanionApiVerifier {
    public static void main(String[] args) throws Exception {
        Path gameJar = Path.of(args[0]).toRealPath();
        ClassLoader loader = KnoxInstalledCompanionApiVerifier.class.getClassLoader();
        Class<?> character = Class.forName("zombie.characters.IsoGameCharacter", false, loader);
        Class<?> player = Class.forName("zombie.characters.IsoPlayer", false, loader);
        Class<?> role = Class.forName("zombie.characters.Role", false, loader);
        if (player.getField("role").getType() != role) throw new AssertionError("NPC role field changed");
        Object npcRole = role.getConstructor(String.class).newInstance("Knox Survivor");
        if (!((java.util.Set<?>) role.getMethod("getCapabilities").invoke(npcRole)).isEmpty()) {
            throw new AssertionError("New NPC roles must have no privileged capabilities");
        }
        Class<?> wornItems = character.getMethod("getWornItems").getReturnType();
        wornItems.getMethod("getItemByIndex", int.class);
        Class<?> gridSquare = Class.forName("zombie.iso.IsoGridSquare", false, loader);
        Class<?> cell = Class.forName("zombie.iso.IsoCell", false, loader);
        method(cell,"getMinZ",int.class);
        method(cell,"getMaxZ",int.class);
        Class<?> core = Class.forName("zombie.core.Core", false, loader);
        method(core,"getScreenWidth",int.class);
        method(core,"getScreenHeight",int.class);
        Class<?> luaGlobals = Class.forName("zombie.Lua.LuaManager$GlobalObject",false,loader);
        method(luaGlobals,"getCore",core);
        method(gridSquare, "isBlockedTo", boolean.class, gridSquare);
        method(gridSquare, "isHoppableTo", boolean.class, gridSquare);
        gridSquare.getMethod("getDoorTo", gridSquare);
        Class<?> bodyPart = Class.forName("zombie.characters.BodyDamage.BodyPart", false, loader);
        method(bodyPart, "bitten", boolean.class);
        method(bodyPart, "isInfectedWound", boolean.class);
        method(bodyPart, "getAlcoholLevel", float.class);
        method(bodyPart, "getBandageLife", float.class);
        method(character, "getReduceInfectionPower", float.class);
        Class<?> moodleType = Class.forName("zombie.scripting.objects.MoodleType",false,loader);
        moodleType.getField("HYPERTHERMIA");moodleType.getField("HYPOTHERMIA");
        method(character.getMethod("getMoodles").getReturnType(),"getMoodleLevel",int.class,moodleType);

        Class<?> metaGrid = Class.forName("zombie.iso.IsoMetaGrid", false, loader);
        metaGrid.getMethod("getBuildings");
        Class<?> buildingDef = Class.forName("zombie.iso.BuildingDef", false, loader);
        buildingDef.getMethod("getRooms");
        buildingDef.getMethod("getID");
        Class<?> building = Class.forName("zombie.iso.areas.IsoBuilding", false, loader);
        method(building,"getDef",buildingDef);
        Class<?> container = Class.forName("zombie.inventory.ItemContainer", false, loader);
        method(container,"getCapacityWeight",float.class);
        method(container,"getMaxWeight",float.class);
        method(container,"getFreeCapacity",float.class,character);
        method(container,"isInCharacterInventory",boolean.class,character);
        Class<?> roomDef = Class.forName("zombie.iso.RoomDef", false, loader);
        roomDef.getMethod("getName");
        roomDef.getMethod("getRects");
        method(character, "setPerformingAttackAnimation", void.class, boolean.class);
        method(character, "setPerformingShoveAnimation", void.class, boolean.class);
        method(character, "setPerformingStompAnimation", void.class, boolean.class);
        method(player, "clearHandToHandAttack", void.class);
        Class<?> object = Class.forName("zombie.iso.IsoObject", false, loader);
        Class<?> trait = Class.forName("zombie.scripting.objects.CharacterTrait", false, loader);
        Class<?> utility = Class.forName("zombie.chat.ChatUtility", false, loader);
        Class<?> say = Class.forName("zombie.chat.defaultChats.SayChat", false, loader);
        Class<?> chatSettings = Class.forName("zombie.chat.ChatSettings", false, loader);
        method(utility, "getScrambleValue", float.class, object, player, float.class);
        method(say, "getDefaultSettings", chatSettings);
        method(chatSettings, "getRange", float.class);
        method(character, "hasTrait", boolean.class, trait);
        method(character, "isAsleep", boolean.class);
        if (trait.getField("DEAF").getType() != trait) throw new AssertionError("DEAF trait API changed");
        Class<?> direction = Class.forName("zombie.iso.IsoDirections", false, loader);
        for (Class<?> type : List.of(character, player, direction)) {
            Path origin = Path.of(type.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath();
            if (!origin.equals(gameJar)) throw new AssertionError("Mock/stale engine class: " + type.getName());
        }
        method(character, "getCurrentStateName", String.class);
        Class<?> food = Class.forName("zombie.inventory.types.Food", false, loader);
        method(food, "canAge", boolean.class);
        method(food, "getOffAgeMax", int.class);
        method(character, "getCurrentActionContextStateName", String.class);
        method(character, "isClimbing", boolean.class);
        method(player, "isPerformingAttackAnimation", boolean.class);
        method(player, "isPerformingShoveAnimation", boolean.class);
        method(player, "isPerformingStompAnimation", boolean.class);
        method(character, "climbOverFence", void.class, direction);
        method(player, "climbOverWall", boolean.class, direction);
        method(player, "canClimbOverWall", boolean.class, direction);
        method(player, "setNpc", void.class, boolean.class);
        method(character, "pathToLocationF", void.class, float.class, float.class, float.class);
        Class<?> pathfinder = character.getMethod("getPathFindBehavior2").getReturnType();
        method(pathfinder, "cancel", void.class);
        pathfinder.getMethod("update");
        System.out.println("Installed companion API PASS source=" + gameJar
            + " state_observation=true traversal=true npc_flag=true pathfinder=true");

        // Read the fixture with PZ's actual active-mod parser, not a reimplementation.
        Class<?> stateParam = Class.forName("zombie.ai.State$Param", false, loader);
        Class<?> opening = Class.forName("zombie.ai.states.OpenWindowState", false, loader);
        Class<?> window = Class.forName("zombie.iso.objects.IsoWindow", false, loader);
        if (opening.getField("WINDOW").getType() != stateParam) throw new AssertionError("Native opening window key changed");
        method(character, "get", Object.class, stateParam);
        method(window, "getObjectIndex", int.class);
        method(window, "IsOpen", boolean.class);
        method(window, "isGlassRemoved", boolean.class);
        method(window, "removeBrokenGlass", void.class);
        Class<?> ropeSquare = Class.forName("zombie.iso.IsoGridSquare", false, loader);
        method(character, "canClimbSheetRope", boolean.class, ropeSquare);
        method(character, "canClimbDownSheetRope", boolean.class, ropeSquare);
        method(character, "climb", void.class);
        method(character, "climbDown", void.class);
        method(window, "ToggleWindow", void.class, character);
        Class<?> door = Class.forName("zombie.iso.objects.IsoDoor", false, loader);
        Class<?> square = Class.forName("zombie.iso.IsoGridSquare", false, loader);
        method(door, "getNorth", boolean.class);
        method(door, "getSquare", square);
        method(door, "getObjectIndex", int.class);
        method(door, "isDestroyed", boolean.class);
        method(door, "isObstructed", boolean.class);
        method(door, "isBarricaded", boolean.class);
        method(door, "IsOpen", boolean.class);
        method(door, "isAdjacentToSquare", boolean.class, square);
        method(door, "ToggleDoor", void.class, character);
        method(square, "getAdjacentSquare", square, direction);
        method(square, "getMovingObjects", java.util.ArrayList.class);
        for (Class<?> type : List.of(opening, stateParam, window, door, square)) {
            Path origin = Path.of(type.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath();
            if (!origin.equals(gameJar)) throw new AssertionError("Mock/stale native-window API: " + type.getName());
        }
        Class<?> active = Class.forName("zombie.modding.ActiveMods", true, loader);
        Class<?> file = Class.forName("zombie.modding.ActiveModsFile", true, loader);
        Object mods = active.getConstructor(String.class).newInstance("knox-recovery-verifier");
        Object reader = file.getConstructor().newInstance();
        Object read = file.getMethod("read", String.class, active).invoke(reader, args[1], mods);
        Object ids = active.getMethod("getMods").invoke(mods);
        if (!Boolean.TRUE.equals(read) || !List.of("KnoxSurvivors").equals(ids)) {
            throw new AssertionError("Installed active-mod parser rejected companion fixture: " + ids);
        }
        System.out.println("Installed active-mod parser PASS ids=" + ids
            + " scope=non-GUI_no-gameplay");
    }

    private static void method(Class<?> type, String name, Class<?> result, Class<?>... parameters)
        throws ReflectiveOperationException {
        if (type.getMethod(name, parameters).getReturnType() != result) {
            throw new AssertionError("Unexpected installed API return type: " + name);
        }
    }
}
