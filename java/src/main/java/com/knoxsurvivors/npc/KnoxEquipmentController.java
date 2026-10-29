package com.knoxsurvivors.npc;

import java.lang.reflect.Method;
import java.util.Collection;

/** Chooses equipment from items the survivor actually carries. */
final class KnoxEquipmentController {
    private static final float MELEE_SWITCH_MARGIN = 1.25f;

    private KnoxEquipmentController() {
    }

    static String equipBestMelee(Object body) throws ReflectiveOperationException {
        Object inventory = invoke(body, "getInventory");
        Object best = null;
        float bestScore = Float.NEGATIVE_INFINITY;
        for (Object weapon : (Collection<?>) invoke(inventory, "getItems")) {
            if (!inherits(weapon, "zombie.inventory.types.HandWeapon")
                || (Boolean) invoke(weapon, "isRanged")
                || (Boolean) invoke(weapon, "isBroken")) {
                continue;
            }
            int conditionMax = ((Number) invoke(weapon, "getConditionMax")).intValue();
            float condition = conditionMax <= 0
                ? 0.0f
                : ((Number) invoke(weapon, "getCondition")).floatValue() / conditionMax;
            float averageDamage = (
                ((Number) invoke(weapon, "getMinDamage")).floatValue()
                    + ((Number) invoke(weapon, "getMaxDamage")).floatValue()
            ) * 0.5f;
            float score = averageDamage * 10.0f
                + condition * 5.0f
                + ((Number) invoke(weapon, "getMaxRange")).floatValue()
                + ((Number) invoke(weapon, "getBaseSpeed")).floatValue()
                + ((Number) invoke(weapon, "getCriticalChance")).floatValue() * 0.02f;
            if (score > bestScore) {
                best = weapon;
                bestScore = score;
            }
        }

        Object current = invoke(body, "getPrimaryHandItem");
        float currentScore = meleeScore(current);
        if (best != null && current == best) {
            return "EQUIPMENT_STABLE " + invoke(best, "getFullType") + " score=" + bestScore;
        }
        if (best != null && currentScore > Float.NEGATIVE_INFINITY
            && bestScore < currentScore + MELEE_SWITCH_MARGIN) {
            return "EQUIPMENT_STABLE " + invoke(current, "getFullType")
                + " score=" + currentScore;
        }
        if (best == null) {
            invokeCompatible(body, "setPrimaryHandItem", (Object) null);
            invokeCompatible(body, "setSecondaryHandItem", (Object) null);
            return "NO_MELEE_WEAPON";
        }

        invokeCompatible(body, "setPrimaryHandItem", best);
        invokeCompatible(
            body,
            "setSecondaryHandItem",
            (Boolean) invoke(best, "isTwoHandWeapon") ? best : null
        );
        invoke(body, "resetModelNextFrame");
        return "EQUIPPED " + invoke(best, "getFullType") + " score=" + bestScore;
    }

    /** Wears an existing carried clothing/container item without creating or deleting gear. */
    static String wearOwnedItem(Object body, String fullType) throws ReflectiveOperationException {
        return wearOwnedItem(body, fullType, -1L);
    }

    /** Selects the exact carried garment/bag chosen by the Lua planner. */
    static String wearOwnedItemById(Object body, String fullType, long itemId)
        throws ReflectiveOperationException {
        if (itemId < 0L) {
            return "WEAR_FAILED INVALID_ITEM_ID";
        }
        return wearOwnedItem(body, fullType, itemId);
    }

    private static String wearOwnedItem(Object body, String fullType, long itemId)
        throws ReflectiveOperationException {
        if (fullType == null || fullType.isBlank()) {
            return "WEAR_FAILED INVALID_ITEM";
        }
        Object inventory = invoke(body, "getInventory");
        Object selected = null;
        Object location = null;
        for (Object item : (Collection<?>) invoke(inventory, "getItems")) {
            if (item == null || !fullType.equals(String.valueOf(invoke(item, "getFullType")))) {
                continue;
            }
            if (itemId >= 0L && ((Number) invoke(item, "getID")).longValue() != itemId) {
                continue;
            }
            location = wearableLocation(item);
            if (location != null) {
                selected = item;
                break;
            }
        }
        if (selected == null || location == null) {
            return "WEAR_FAILED NOT_OWNED_OR_WEARABLE " + fullType;
        }
        Object current = invokeCompatible(body, "getWornItem", location);
        if (current == selected) {
            return "EQUIPMENT_STABLE_WORN " + fullType + " location=" + location;
        }
        invokeCompatibleTwo(body, "setWornItem", location, selected);
        invoke(body, "resetModelNextFrame");
        return "WORN_OWNED " + fullType + " location=" + location;
    }

    /**
     * Equips one already-owned weapon chosen by the Lua action planner.
     *
     * Firearm readiness is intentionally decided on the Lua side because Build 42's
     * native reload actions own magazines, chambers, and timed animation state.  This
     * method only performs the safe, inventory-backed hand transition; it never creates
     * ammunition or changes firearm fields directly.
     */
    static String equipOwnedWeapon(Object body, String fullType) throws ReflectiveOperationException {
        return equipOwnedWeapon(body, fullType, -1L);
    }

    static String equipOwnedWeapon(Object body, String fullType, long itemId)
        throws ReflectiveOperationException {
        if (fullType == null || fullType.isBlank()) {
            return "EQUIP_FAILED INVALID_WEAPON";
        }
        Object inventory = invoke(body, "getInventory");
        Object selected = null;
        for (Object item : (Collection<?>) invoke(inventory, "getItems")) {
            if (item == null || !inherits(item, "zombie.inventory.types.HandWeapon")
                || (Boolean) invoke(item, "isBroken")
                || !fullType.equals(String.valueOf(invoke(item, "getFullType")))) {
                continue;
            }
            if (itemId >= 0L && ((Number) invoke(item, "getID")).longValue() != itemId) {
                continue;
            }
            selected = item;
            break;
        }
        if (selected == null) {
            return "EQUIP_FAILED NOT_OWNED " + fullType;
        }
        invokeCompatible(body, "setPrimaryHandItem", selected);
        invokeCompatible(
            body,
            "setSecondaryHandItem",
            (Boolean) invoke(selected, "isTwoHandWeapon") ? selected : null
        );
        invoke(body, "resetModelNextFrame");
        return "EQUIPPED_WEAPON " + fullType
            + " ranged=" + invoke(selected, "isRanged");
    }

    private static float meleeScore(Object weapon) {
        try {
            if (weapon == null || !inherits(weapon, "zombie.inventory.types.HandWeapon")
                || (Boolean) invoke(weapon, "isRanged")
                || (Boolean) invoke(weapon, "isBroken")) {
                return Float.NEGATIVE_INFINITY;
            }
            int conditionMax = ((Number) invoke(weapon, "getConditionMax")).intValue();
            float condition = conditionMax <= 0
                ? 0.0f
                : ((Number) invoke(weapon, "getCondition")).floatValue() / conditionMax;
            float averageDamage = (((Number) invoke(weapon, "getMinDamage")).floatValue()
                + ((Number) invoke(weapon, "getMaxDamage")).floatValue()) * 0.5f;
            return averageDamage * 10.0f + condition * 5.0f
                + ((Number) invoke(weapon, "getMaxRange")).floatValue()
                + ((Number) invoke(weapon, "getBaseSpeed")).floatValue()
                + ((Number) invoke(weapon, "getCriticalChance")).floatValue() * 0.02f;
        } catch (ReflectiveOperationException exception) {
            return Float.NEGATIVE_INFINITY;
        }
    }

    private static Object wearableLocation(Object item) {
        try {
            Object location = invoke(item, "getBodyLocation");
            if (location != null) {
                return location;
            }
        } catch (ReflectiveOperationException ignored) {
            // Some carried container classes expose only canBeEquipped().
        }
        try {
            return invoke(item, "canBeEquipped");
        } catch (ReflectiveOperationException ignored) {
            return null;
        }
    }

    private static boolean inherits(Object value, String className) {
        Class<?> current = value.getClass();
        while (current != null) {
            if (current.getName().equals(className)) {
                return true;
            }
            current = current.getSuperclass();
        }
        return false;
    }

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getMethod(name).invoke(target);
    }

    private static Object invokeCompatible(Object target, String name, Object argument)
        throws ReflectiveOperationException {
        for (Method method : target.getClass().getMethods()) {
            if (method.getName().equals(name) && method.getParameterCount() == 1) {
                Class<?> parameterType = method.getParameterTypes()[0];
                if (argument == null || parameterType.isInstance(argument)) {
                    return method.invoke(target, argument);
                }
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }

    private static Object invokeCompatibleTwo(Object target, String name, Object first, Object second)
        throws ReflectiveOperationException {
        for (Method method : target.getClass().getMethods()) {
            if (!method.getName().equals(name) || method.getParameterCount() != 2) {
                continue;
            }
            Class<?>[] parameterTypes = method.getParameterTypes();
            if ((first == null || parameterTypes[0].isInstance(first))
                && (second == null || parameterTypes[1].isInstance(second))) {
                return method.invoke(target, first, second);
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }
}
