package com.knoxsurvivors.npc;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;

/** Exact wearable identity checks using plain reflection-compatible item objects. */
public final class KnoxEquipmentControllerVerifier {
    private static int checks;

    private KnoxEquipmentControllerVerifier() {
    }

    public static void main(String[] arguments) throws Exception {
        verifyLegacyTypeCompatibility();
        verifyExactDuplicateIdentity();
        verifyExactRefusalsAndRootMembership();
        System.out.println("KnoxEquipmentControllerVerifier PASS checks=" + checks);
    }

    private static void verifyLegacyTypeCompatibility() throws Exception {
        PlainItem first = new PlainItem("Base.TestJacket", 101L, "Torso");
        PlainItem second = new PlainItem("Base.TestJacket", 102L, "Torso");
        FakeBody body = new FakeBody(Arrays.asList(first, second));

        String result = KnoxEquipmentController.wearOwnedItem(body, "Base.TestJacket");

        require(result.startsWith("WORN_OWNED Base.TestJacket"),
            "legacy type-only wear API remains compatible");
        require(body.getWornItem("Torso") == first,
            "legacy type-only API keeps its first matching selection behavior");
    }

    private static void verifyExactDuplicateIdentity() throws Exception {
        PlainItem first = new PlainItem("Base.TestJacket", 201L, "Torso");
        PlainItem selected = new PlainItem("Base.TestJacket", 202L, "Torso");
        PlainItem unrelated = new PlainItem("Base.TestBag", 203L, "Back");
        PlainItem oldTorso = new PlainItem("Base.OldShirt", 204L, "Torso");
        FakeBody body = new FakeBody(Arrays.asList(null, first, selected, unrelated));
        body.worn.put("Torso", oldTorso);
        body.worn.put("Back", unrelated);

        Method exact = exactWearMethod();
        String result = (String) exact.invoke(null, body, "Base.TestJacket", 202L);

        require(result.startsWith("WORN_OWNED Base.TestJacket"),
            "exact-ID wearable reports the existing native result format");
        require(body.getWornItem("Torso") == selected,
            "exact-ID wearable selects the requested second same-type root item");
        require(body.getWornItem("Back") == unrelated,
            "wearing the exact torso item preserves unrelated worn state");
        require(body.modelResets == 1,
            "exact wearable invokes the real equipment mutation boundary once");
    }

    private static void verifyExactRefusalsAndRootMembership() throws Exception {
        PlainItem first = new PlainItem("Base.TestJacket", 301L, "Torso");
        PlainItem second = new PlainItem("Base.TestJacket", 302L, "Torso");
        FakeBody body = new FakeBody(Arrays.asList(first, second));
        PlainItem oldTorso = new PlainItem("Base.OldShirt", 303L, "Torso");
        body.worn.put("Torso", oldTorso);
        Method exact = exactWearMethod();

        String missing = (String) exact.invoke(null, body, "Base.TestJacket", -1L);
        require(missing.startsWith("WEAR_FAILED"),
            "negative/missing item ID fails closed");
        require(body.getWornItem("Torso") == oldTorso && body.modelResets == 0,
            "missing item ID causes no equipment mutation");

        String typeMismatch = (String) exact.invoke(null, body, "Base.OtherJacket", 302L);
        require(typeMismatch.startsWith("WEAR_FAILED"),
            "matching ID with a different full type is rejected");
        require(body.getWornItem("Torso") == oldTorso && body.modelResets == 0,
            "type mismatch causes no equipment mutation");

        PlainItem outsideRoot = new PlainItem("Base.TestJacket", 302L, "Torso");
        FakeBody rootOnly = new FakeBody(Arrays.asList(first));
        rootOnly.worn.put("Torso", oldTorso);
        String absent = (String) exact.invoke(null, rootOnly, "Base.TestJacket", outsideRoot.id);
        require(absent.startsWith("WEAR_FAILED"),
            "exact item not present in root inventory is rejected");
        require(rootOnly.getWornItem("Torso") == oldTorso && rootOnly.modelResets == 0,
            "root-absent item causes no equipment mutation");

        PlainItem invalidId = new PlainItem("Base.TestJacket", -1L, "Torso");
        FakeBody unreadable = new FakeBody(Arrays.asList(null, invalidId, second));
        unreadable.worn.put("Torso", oldTorso);
        String noNegativeId = (String) exact.invoke(null, unreadable,
            "Base.TestJacket", -1L);
        require(noNegativeId.startsWith("WEAR_FAILED"),
            "negative item ID fails closed");
        require(unreadable.getWornItem("Torso") == oldTorso && unreadable.modelResets == 0,
            "null entries are skipped and invalid ID leaves equipment unchanged");
    }

    private static Method exactWearMethod() throws Exception {
        Method method = KnoxEquipmentController.class.getDeclaredMethod(
            "wearOwnedItemById", Object.class, String.class, long.class);
        method.setAccessible(true);
        return method;
    }

    private static void require(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }

    /** Plain object with the public methods the production reflection uses. */
    public static final class PlainItem {
        private final String fullType;
        private final long id;
        private final String location;

        public PlainItem(String fullType, long id, String location) {
            this.fullType = fullType;
            this.id = id;
            this.location = location;
        }

        public String getFullType() { return fullType; }
        public long getID() { return id; }
        public String getBodyLocation() { return location; }
        public String canBeEquipped() { return location; }
    }

    public static final class FakeInventory {
        private final Collection<Object> items;

        public FakeInventory(Collection<Object> items) {
            this.items = new ArrayList<>(items);
        }

        public Collection<Object> getItems() { return items; }
    }

    public static final class FakeBody {
        private final FakeInventory inventory;
        private final Map<String, Object> worn = new LinkedHashMap<>();
        private int modelResets;

        public FakeBody(Collection<Object> items) {
            inventory = new FakeInventory(items);
        }

        public FakeInventory getInventory() { return inventory; }
        public Object getWornItem(String location) { return worn.get(location); }
        public void setWornItem(String location, Object item) { worn.put(location, item); }
        public void resetModelNextFrame() { modelResets++; }
    }
}
