package com.knoxsurvivors.npc;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.lang.reflect.Method;
import java.lang.reflect.InvocationTargetException;
import java.nio.BufferOverflowException;
import java.nio.ByteBuffer;
import java.util.IdentityHashMap;

/** Portable Knox-owned inventory state for rebuilding a temporary engine body. */
final class KnoxInventorySnapshot {
    static final int SCHEMA_VERSION = 3;
    private static final int VISUAL_BUFFER_BYTES = 64 * 1024;
    private static final int MAX_ITEM_BYTES = 16 * 1024 * 1024;

    private final List<ItemState> items;
    private final int worldVersion;

    private KnoxInventorySnapshot(List<ItemState> items, int worldVersion) {
        this.items = List.copyOf(items);
        this.worldVersion = worldVersion;
    }

    static KnoxInventorySnapshot capture(Object body) throws ReflectiveOperationException {
        Class<?> world = Class.forName("zombie.iso.IsoWorld", false, body.getClass().getClassLoader());
        return capture(body, world.getField("WorldVersion").getInt(null));
    }

    static KnoxInventorySnapshot capture(Object body, int worldVersion) throws ReflectiveOperationException {
        Object inventory = invoke(body, "getInventory");
        Object wornItems = invoke(body, "getWornItems");
        Object primary = invoke(body, "getPrimaryHandItem");
        Object secondary = invoke(body, "getSecondaryHandItem");
        List<ItemState> states = new ArrayList<>();
        for (Object item : (Collection<?>) invoke(inventory, "getItems")) {
            states.add(new ItemState(
                (String) invoke(item, "getFullType"),
                ((Number) invoke(item, "getCondition")).intValue(),
                ((Number) invoke(item, "getUses")).intValue(),
                (Boolean) invoke(item, "isFavorite"),
                (Boolean) invokeCompatible(wornItems, "contains", item),
                item == primary,
                item == secondary,
                "",
                countItemTree(item, new IdentityHashMap<>(), 0),
                captureNativeItem(item)
            ));
        }
        return new KnoxInventorySnapshot(states, worldVersion);
    }

    void restore(Object body) throws ReflectiveOperationException {
        restore(body, Class.forName("zombie.inventory.InventoryItem", false, body.getClass().getClassLoader()));
    }

    void restore(Object body, Class<?> itemClass) throws ReflectiveOperationException {
        Object inventory = invoke(body, "getInventory");
        Object wornItems = invoke(body, "getWornItems");
        // Decode every native root before touching the destination inventory.
        // Native loadItem may silently skip a removed mod item; reject that loss
        // (including missing nested items) and retain the original saved record.
        List<Object> prepared = new ArrayList<>(items.size());
        for (ItemState state : items) {
            Object item = null;
            if (!state.nativeBytes.isEmpty()) {
                item = loadNativeItem(state, itemClass);
            }
            prepared.add(item);
        }
        invokeCompatible(body, "setPrimaryHandItem", (Object) null);
        invokeCompatible(body, "setSecondaryHandItem", (Object) null);
        invoke(wornItems, "clear");
        invoke(inventory, "clear");

        for (int index = 0; index < items.size(); index++) {
            ItemState state = items.get(index);
            Object item = prepared.get(index);
            if (item != null) {
                invokeCompatible(inventory, "AddItem", item);
            } else {
                // Schema 2 did not store native contents. Keep its old restore
                // semantics; data that was never captured cannot be recovered.
                item = inventory.getClass().getMethod("AddItem", String.class)
                    .invoke(inventory, state.fullType);
                if (item != null) {
                    item.getClass().getMethod("setCondition", int.class).invoke(item, state.condition);
                    item.getClass().getMethod("setUses", int.class).invoke(item, state.uses);
                    item.getClass().getMethod("setFavorite", boolean.class).invoke(item, state.favorite);
                    restoreItemVisual(item, state.visual);
                }
            }
            if (item == null) {
                throw new IllegalStateException("Unable to restore inventory item " + state.fullType);
            }
            Object bodyLocation = invoke(item, "getBodyLocation");
            if (bodyLocation == null) {
                bodyLocation = invoke(item, "canBeEquipped");
            }
            if (state.worn && bodyLocation != null) {
                invokeCompatible(body, "setWornItem", bodyLocation, item);
            }
            if (state.primary) {
                invokeCompatible(body, "setPrimaryHandItem", item);
            }
            if (state.secondary) {
                invokeCompatible(body, "setSecondaryHandItem", item);
            }
        }

        inventory.getClass().getMethod("setDrawDirty", boolean.class).invoke(inventory, true);
        invoke(body, "resetModelNextFrame");
    }

    int size() {
        return items.size();
    }

    String primaryType() {
        for (ItemState item : items) {
            if (item.primary) {
                return item.fullType;
            }
        }
        return "none";
    }

    /** Inspect only the detached native primary item; never reconstruct a body or default gear. */
    boolean hasReadyPrimaryWeapon(Class<?> itemClass) throws ReflectiveOperationException {
        ItemState primary = null;
        for (ItemState state : items) {
            if (!state.primary) continue;
            if (primary != null || state.nativeBytes.isEmpty()) return false;
            primary = state;
        }
        if (primary == null) return false;
        Object weapon = loadNativeItem(primary, itemClass);
        if (!(Boolean) invoke(weapon, "IsWeapon") || (Boolean) invoke(weapon, "isBroken")) return false;
        if (!(Boolean) invoke(weapon, "isRanged")) return true;
        // Exact 42.20.3 ISReloadWeaponAction.canShoot, without a player's debug
        // unlimited-ammo bypass. This is readiness only, not reload/firing logic.
        if ((Boolean) invoke(weapon, "isSelectFire") && "Safe".equals(invoke(weapon, "getFireMode"))) return false;
        if ((Boolean) invoke(weapon, "isJammed")) return false;
        return (Boolean) invoke(weapon, "haveChamber")
            ? (Boolean) invoke(weapon, "isRoundChambered")
            : ((Number) invoke(weapon, "getCurrentAmmoCount")).intValue() > 0;
    }

    /**
     * Stable, read-only count summary for the Lua persistence layer. The full
     * snapshot remains authoritative for restoration; this deliberately exposes
     * no mutable inventory API for an unloaded shell.
     */
    String summary() {
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (ItemState item : items) {
            counts.merge(item.fullType, 1, Integer::sum);
        }
        StringBuilder result = new StringBuilder();
        for (Map.Entry<String, Integer> entry : counts.entrySet()) {
            if (!result.isEmpty()) {
                result.append(';');
            }
            result.append(entry.getKey()).append('=').append(entry.getValue());
        }
        return result.toString();
    }

    boolean equivalentAfterRestore(KnoxInventorySnapshot other) {
        return other != null
            && size() == other.size()
            && primaryType().equals(other.primaryType())
            && summary().equals(other.summary());
    }

    /**
     * Returns a new portable inventory after consuming one exact item type.  This is
     * intentionally record-only: unloaded simulation must not materialize a body,
     * create a replacement item, or mutate a loaded world inventory.
     */
    KnoxInventorySnapshot withoutFirst(String fullType) {
        if (fullType == null || fullType.isBlank()) {
            return null;
        }
        List<ItemState> remaining = new ArrayList<>(items.size());
        boolean removed = false;
        for (ItemState item : items) {
            if (!removed && fullType.equals(item.fullType)) {
                removed = true;
                continue;
            }
            remaining.add(item);
        }
        return removed ? new KnoxInventorySnapshot(remaining, worldVersion) : null;
    }

    record Consumption(KnoxInventorySnapshot inventory, double hungerRelief, double thirstRelief, String type) { }
    private record Supply(Object item, Object parent, double benefit) { }

    Consumption consumeSupply(String kind, double requested, Class<?> itemClass)
        throws ReflectiveOperationException {
        return consumeSupply(kind, requested, itemClass, null);
    }

    Consumption consumeSupply(String kind, double requested, Class<?> itemClass, String communalBase)
        throws ReflectiveOperationException {
        return consumeSupply(kind, requested, itemClass, communalBase, 1);
    }

    Consumption consumeSupply(String kind, double requested, Class<?> itemClass, String communalBase, int reserve)
        throws ReflectiveOperationException {
        if (reserve < 1 || reserve > 2) return null;
        if ((!"food".equals(kind) && !"water".equals(kind))
            || !Double.isFinite(requested) || requested <= 0 || requested > 1
            || (communalBase != null && communalBase.isBlank())) return null;
        List<Supply> candidates = new ArrayList<>();
        Object root = null;
        int selected = -1;
        int required = communalBase == null ? 1 : reserve + 1; // retain one actual shareable provision
        for (int index = 0; index < items.size(); index++) {
            ItemState state = items.get(index);
            if (state.nativeBytes.isEmpty()) continue;
            Object restored = loadNativeItem(state, itemClass);
            findSupplies(restored, null, kind, communalBase, candidates, required);
            if (selected < 0 && !candidates.isEmpty()) { selected = index; root = restored; }
            if (candidates.size() >= required) break;
        }
        if (candidates.size() < required) return null;
        int index = selected;
        ItemState state = items.get(index);
        Supply supply = candidates.get(0);
        double hunger = 0, thirst = 0;
        boolean remove = false;
        if ("water".equals(kind)) {
            Object fluid = invoke(supply.item, "getFluidContainer");
            double amount = ((Number) invoke(fluid, "getAmount")).doubleValue();
            double consumed = Math.min(amount, requested * 1.2);
            // Build 42 ISDrinkFromBottle uses 0.12 fluid for 0.1 thirst.
            fluid.getClass().getMethod("adjustAmount", float.class)
                .invoke(fluid, (float) Math.max(0, amount - consumed));
            thirst = consumed / 1.2;
        } else {
            double fraction = Math.min(1, requested / supply.benefit);
            hunger = supply.benefit * fraction;
            thirst = -((Number) invoke(supply.item, "getThirstChange")).doubleValue() * fraction;
            supply.item.getClass().getMethod("multiplyFoodValues", float.class)
                .invoke(supply.item, (float) (1 - fraction));
            remove = fraction >= 1;
            if (remove && supply.parent != null) invokeCompatible(supply.parent, "Remove", supply.item);
        }
        List<ItemState> updated = new ArrayList<>(items);
        if (remove && supply.item == root) {
            updated.remove(index);
        } else {
            updated.set(index, new ItemState(state.fullType, state.condition, state.uses,
                state.favorite, state.worn, state.primary, state.secondary, state.visual,
                countItemTree(root, new IdentityHashMap<>(), 0), captureNativeItem(root)));
        }
        return new Consumption(new KnoxInventorySnapshot(updated, worldVersion), hunger, thirst,
            (String) invoke(supply.item, "getFullType"));
    }

    private static void findSupplies(Object item, Object parent, String kind, String communalBase,
        List<Supply> found, int limit) throws ReflectiveOperationException {
        if (found.size() >= limit) return;
        boolean eligible = true;
        if (communalBase != null) {
            // A protected bag protects its contents too. Mission delivery cargo
            // cannot be reassigned by incidental offscreen sharing.
            if (Boolean.TRUE.equals(invoke(item, "isFavorite"))) return;
            Object data = invoke(item, "getModData");
            if (invokeCompatible(data, "rawget", "KnoxBaseSupplyDelivery") != null) return;
            eligible = communalBase.equals(invokeCompatible(data, "rawget", "KnoxBaseProvision"));
        }
        if (eligible && "water".equals(kind)) {
            Object fluid = invoke(item, "getFluidContainer");
            if (fluid != null) {
                double amount = ((Number) invoke(fluid, "getAmount")).doubleValue();
                Object primary = Double.isFinite(amount) && amount > 0 ? invoke(fluid, "getPrimaryFluid") : null;
                if (Double.isFinite(amount) && amount > 0 && primary != null
                    && "Water".equals(invoke(primary, "getFluidTypeString"))
                    && (Boolean) invokeCompatible(fluid, "isPureFluid", primary)) {
                    found.add(new Supply(item, parent, amount / 1.2)); return;
                }
            }
        } else if (eligible && (Boolean) invoke(item, "IsFood")) {
            double benefit = -((Number) invoke(item, "getHungerChange")).doubleValue();
            if (Double.isFinite(benefit) && benefit > .001
                && Double.isFinite(((Number) invoke(item, "getThirstChange")).doubleValue())
                && !((Boolean) invoke(item, "isRotten")) && !((Boolean) invoke(item, "isPoison"))
                && ((Number) invoke(item, "getPoisonPower")).intValue() == 0
                && (!((Boolean) invoke(item, "isbDangerousUncooked")) || (Boolean) invoke(item, "isCooked"))
                && ((Number) invoke(item, "getUses")).intValue() == 1
                && empty(invoke(item, "getOnEat")) && empty(invoke(item, "getUseOnConsume"))
                && empty(invoke(item, "getReplaceOnUse"))) {
                // Scripted consumption/byproducts need an actual character/action;
                // leave these for loaded self-care rather than silently losing them.
                found.add(new Supply(item, parent, benefit)); return;
            }
        }
        Method getter;
        try { getter = item.getClass().getMethod("getInventory"); }
        catch (NoSuchMethodException leaf) { return; }
        Object container = getter.invoke(item);
        if (container != null) {
            for (Object child : (Collection<?>) invoke(container, "getItems")) {
                findSupplies(child, container, kind, communalBase, found, limit);
                if (found.size() >= limit) return;
            }
        }
    }

    private static boolean empty(Object value) {
        return value == null || value.toString().isEmpty();
    }

    private Object loadNativeItem(ItemState state, Class<?> itemClass) throws ReflectiveOperationException {
        if (worldVersion <= 0 || state.nativeBytes.length() > (MAX_ITEM_BYTES * 4L / 3L + 4)) {
            throw new IllegalArgumentException("Invalid native inventory payload");
        }
        ByteBuffer bytes = ByteBuffer.wrap(Base64.getUrlDecoder().decode(state.nativeBytes));
        Object item = itemClass.getMethod("loadItem", ByteBuffer.class, int.class).invoke(null, bytes, worldVersion);
        if (item == null || bytes.hasRemaining() || !state.fullType.equals(invoke(item, "getFullType"))
            || state.treeCount != countItemTree(item, new IdentityHashMap<>(), 0)) {
            throw new IllegalStateException("Incomplete native inventory restore: " + state.fullType);
        }
        return item;
    }

    String encode() {
        StringBuilder encoded = new StringBuilder(SCHEMA_VERSION + "|" + worldVersion);
        for (ItemState item : items) {
            encoded.append('\n')
                .append(text(item.fullType)).append('|')
                .append(item.condition).append('|')
                .append(item.uses).append('|')
                .append(item.favorite ? 1 : 0).append('|')
                .append(item.worn ? 1 : 0).append('|')
                .append(item.primary ? 1 : 0).append('|')
                .append(item.secondary ? 1 : 0).append('|')
                .append(item.visual).append('|')
                .append(item.treeCount).append('|')
                .append(item.nativeBytes);
        }
        return encoded.toString();
    }

    static KnoxInventorySnapshot decode(String encoded) {
        String[] lines = encoded.split("\\n", -1);
        String[] header = lines[0].split("\\|", -1);
        int version = Integer.parseInt(header[0]);
        if ((version != 2 && version != SCHEMA_VERSION)
            || (version == 2 && header.length != 1)
            || (version == SCHEMA_VERSION && header.length != 2)) {
            throw new IllegalArgumentException("Unsupported inventory snapshot schema");
        }
        int worldVersion = version == 2 ? 0 : Integer.parseInt(header[1]);
        List<ItemState> states = new ArrayList<>();
        for (int index = 1; index < lines.length; index++) {
            String[] fields = lines[index].split("\\|", -1);
            if (fields.length != (version == 2 ? 8 : 10)) {
                throw new IllegalArgumentException("Invalid inventory item record at " + index);
            }
            states.add(new ItemState(
                untext(fields[0]),
                Integer.parseInt(fields[1]),
                Integer.parseInt(fields[2]),
                "1".equals(fields[3]),
                "1".equals(fields[4]),
                "1".equals(fields[5]),
                "1".equals(fields[6]),
                fields[7],
                version == 2 ? 1 : Integer.parseInt(fields[8]),
                version == 2 ? "" : fields[9]
            ));
        }
        return new KnoxInventorySnapshot(states, worldVersion);
    }

    private static String captureNativeItem(Object item) throws ReflectiveOperationException {
        for (int capacity = VISUAL_BUFFER_BYTES; capacity <= MAX_ITEM_BYTES; capacity *= 2) {
            ByteBuffer buffer = ByteBuffer.allocate(capacity);
            try {
                item.getClass().getMethod("saveWithSize", ByteBuffer.class, boolean.class)
                    .invoke(item, buffer, false);
                byte[] bytes = new byte[buffer.position()];
                buffer.flip();
                buffer.get(bytes);
                return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
            } catch (InvocationTargetException failure) {
                if (!(failure.getCause() instanceof BufferOverflowException) || capacity == MAX_ITEM_BYTES) {
                    throw failure;
                }
            }
        }
        throw new IllegalStateException("Native inventory item exceeds serialization budget");
    }

    private static int countItemTree(Object item, IdentityHashMap<Object, Boolean> seen, int depth)
        throws ReflectiveOperationException {
        if (depth > 32 || seen.put(item, Boolean.TRUE) != null) {
            throw new IllegalStateException("Cyclic or excessively nested inventory");
        }
        Method getter;
        try {
            getter = item.getClass().getMethod("getInventory");
        } catch (NoSuchMethodException leafItem) {
            return 1;
        }
        Object container = getter.invoke(item);
        int count = 1;
        if (container != null) {
            for (Object child : (Collection<?>) invoke(container, "getItems")) {
                count += countItemTree(child, seen, depth + 1);
            }
        }
        return count;
    }

    private static String text(String value) {
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }

    private static String untext(String value) {
        return new String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8);
    }

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getMethod(name).invoke(target);
    }

    private static Object invokeCompatible(Object target, String name, Object... arguments)
        throws ReflectiveOperationException {
        for (Method method : target.getClass().getMethods()) {
            if (!method.getName().equals(name) || method.getParameterCount() != arguments.length) {
                continue;
            }
            Class<?>[] parameterTypes = method.getParameterTypes();
            boolean compatible = true;
            for (int index = 0; index < arguments.length; index++) {
                if (arguments[index] != null && !parameterTypes[index].isInstance(arguments[index])) {
                    compatible = false;
                    break;
                }
            }
            if (compatible) {
                return method.invoke(target, arguments);
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }

    private static void restoreItemVisual(Object item, String encoded)
        throws ReflectiveOperationException {
        if (encoded.isEmpty()) {
            return;
        }
        Object visual = invoke(item, "getVisual");
        if (visual == null) {
            throw new IllegalStateException("Saved item visual missing on " + invoke(item, "getFullType"));
        }
        Class<?> isoWorld = Class.forName(
            "zombie.iso.IsoWorld",
            false,
            item.getClass().getClassLoader()
        );
        int worldVersion = isoWorld.getField("WorldVersion").getInt(null);
        ByteBuffer buffer = ByteBuffer.wrap(Base64.getUrlDecoder().decode(encoded));
        visual.getClass().getMethod("load", ByteBuffer.class, int.class)
            .invoke(visual, buffer, worldVersion);
    }

    private record ItemState(
        String fullType,
        int condition,
        int uses,
        boolean favorite,
        boolean worn,
        boolean primary,
        boolean secondary,
        String visual,
        int treeCount,
        String nativeBytes
    ) {
    }
}
