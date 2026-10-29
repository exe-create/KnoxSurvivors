package com.knoxsurvivors.npc;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

/** Exercises Knox's codec/handoff against a native-method-shaped item fixture. */
public final class KnoxInventorySnapshotVerifier {
    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }

    public static void main(String[] args) throws Exception {
        Body source = new Body();
        Item gun = new Item("Base.Pistol");
        gun.rounds = 7;
        gun.chambered = true;
        gun.condition = 4;
        gun.favorite = true;
        Item bag = new Item("Base.Bag_Schoolbag");
        bag.inventory = new Container();
        Item water = new Item("Base.WaterBottle");
        water.fluid = .375f;
        Item food = new Item("Base.Apple");
        food.hunger = -.08f;
        food.age = 2.5f;
        food.rotten = true;
        bag.inventory.AddItem(water);
        bag.inventory.AddItem(food);
        // Force the bounded serializer to grow beyond its initial 64 KiB buffer.
        bag.padding = "x".repeat(90000);
        source.inventory.AddItem(gun);
        source.inventory.AddItem(bag);
        source.primary = gun;
        source.secondary = gun;
        source.worn.items.add(bag);
        KnoxInventorySnapshot captured = KnoxInventorySnapshot.capture(source, 240);
        String encoded = captured.encode();
        require(encoded.startsWith("3|240\n"), "native world version missing");
        Body destination = new Body();
        KnoxInventorySnapshot.decode(encoded).restore(destination, Item.class);
        Item restoredGun = destination.inventory.items.get(0);
        Item restoredBag = destination.inventory.items.get(1);
        require(restoredGun != gun && restoredGun.rounds == 7 && restoredGun.chambered,
            "round/chamber state lost or original live item reused");
        require(restoredGun.condition == 4 && restoredGun.favorite, "native item properties lost");
        require(destination.primary == restoredGun && destination.secondary == restoredGun,
            "hand identity binding lost");
        require(destination.worn.items.contains(restoredBag), "worn bag binding lost");
        require(restoredBag.inventory.items.size() == 2 && restoredBag.padding.length() == 90000,
            "nested contents or expanded buffer lost");
        require(restoredBag.inventory.items.get(0).fluid == .375f, "actual water quantity lost");
        Item restoredFood = restoredBag.inventory.items.get(1);
        require(restoredFood.age == 2.5f && restoredFood.hunger == -.08f && restoredFood.rotten,
            "actual food state lost");
        require(Item.loadedVersion == 240, "load did not use recorded native version");
        require(captured.encode().equals(encoded) && source.inventory.items.size() == 2,
            "capture/restore mutated original snapshot or source inventory");

        // Removed mod items can make native load silently omit children. Do not
        // clear the destination or accept a smaller bag in that case.
        Body untouched = new Body();
        Item sentinel = new Item("Base.Sentinel");
        untouched.inventory.AddItem(sentinel);
        Item.dropChild = true;
        boolean rejected = false;
        try { captured.restore(untouched, Item.class); }
        catch (IllegalStateException expected) { rejected = true; }
        Item.dropChild = false;
        require(rejected && untouched.inventory.items.get(0) == sentinel,
            "partial native load destroyed existing inventory");
        Item.failLoad = true;
        rejected = false;
        try { captured.restore(untouched, Item.class); }
        catch (IllegalStateException expected) { rejected = true; }
        Item.failLoad = false;
        require(rejected && untouched.inventory.items.get(0) == sentinel, "missing root item accepted");

        String legacy = "2\n" + Base64.getUrlEncoder().withoutPadding()
            .encodeToString("Base.Hammer".getBytes(StandardCharsets.UTF_8)) + "|3|2|1|0|1|0|";
        Body oldSave = new Body();
        KnoxInventorySnapshot.decode(KnoxInventorySnapshot.decode(legacy).encode()).restore(oldSave, Item.class);
        require(oldSave.primary != null && oldSave.primary.condition == 3 && oldSave.primary.uses == 2
            && oldSave.primary.favorite, "schema-2 migration lost supported fields");
        KnoxInventorySnapshot remaining = captured.withoutFirst("Base.Pistol");
        Body afterMutation = new Body();
        KnoxInventorySnapshot.decode(remaining.encode()).restore(afterMutation, Item.class);
        require(afterMutation.inventory.items.size() == 1
            && afterMutation.inventory.items.get(0).inventory.items.size() == 2,
            "record-only mutation discarded unrelated native bag contents");
        require(captured.withoutFirst("Base.NotPresent") == null, "missing item reported consumed");

        Body supplies = new Body();
        Item supplyBag = new Item("Base.Bag");
        supplyBag.inventory = new Container();
        Item bottle = new Item("Base.Bottle");
        bottle.fluid = .3f;
        Item apple = new Item("Base.Apple");
        apple.hunger = -.1f;
        apple.thirst = -.02f;
        supplyBag.inventory.AddItem(bottle);
        supplyBag.inventory.AddItem(apple);
        supplies.inventory.AddItem(supplyBag);
        KnoxInventorySnapshot inventory = KnoxInventorySnapshot.capture(supplies, 240);
        String originalSupplies = inventory.encode();
        KnoxInventorySnapshot.Consumption sip = inventory.consumeSupply("water", .1, Item.class);
        require(Math.abs(sip.thirstRelief() - .1) < .000001, "drink relief was not proportional");
        Body afterSip = new Body();
        sip.inventory().restore(afterSip, Item.class);
        require(Math.abs(afterSip.inventory.items.get(0).inventory.items.get(0).fluid - .18) < .000001,
            "sip discarded bottle or wrong fluid amount");
        KnoxInventorySnapshot.Consumption finishBottle = sip.inventory().consumeSupply("water", .8, Item.class);
        require(finishBottle.thirstRelief() < .16, "small remainder granted full thirst relief");
        require(finishBottle.inventory().consumeSupply("water", .5, Item.class) == null,
            "empty bottle provided another drink");
        Body emptyBottle = new Body();
        finishBottle.inventory().restore(emptyBottle, Item.class);
        require(emptyBottle.inventory.items.get(0).inventory.items.size() == 2,
            "empty reusable bottle was deleted");
        KnoxInventorySnapshot.Consumption bite = inventory.consumeSupply("food", .04, Item.class);
        require(Math.abs(bite.thirstRelief() - .008) < .000001, "food hydration ignored");
        Body afterBite = new Body();
        bite.inventory().restore(afterBite, Item.class);
        require(Math.abs(afterBite.inventory.items.get(0).inventory.items.get(1).hunger + .06) < .000001,
            "partial food was replaced by a fresh default or lost");
        KnoxInventorySnapshot.Consumption finishFood = bite.inventory().consumeSupply("food", .8, Item.class);
        require(finishFood.hungerRelief() < .061, "small food granted a full meal reset");
        Body mealFinished = new Body();
        finishFood.inventory().restore(mealFinished, Item.class);
        require(mealFinished.inventory.items.get(0).inventory.items.size() == 1,
            "finished nested food was not removed from actual saved bag");
        require(inventory.encode().equals(originalSupplies) && bottle.fluid == .3f,
            "detached supply operation mutated live/source items");
        require(KnoxInventorySnapshot.decode(legacy).consumeSupply("food", .1, Item.class) == null,
            "legacy record invented resource contents");
        require(inventory.consumeSupply("water", Double.NaN, Item.class) == null,
            "nonfinite consumption accepted");
        for (String type : List.of("Base.TaintedBottle", "Base.OilBottle", "Base.MixedBottle")) {
            Body unsafe = new Body();
            Item item = new Item(type); item.fluid = 1;
            unsafe.inventory.AddItem(item);
            require(KnoxInventorySnapshot.capture(unsafe, 240).consumeSupply("water", .5, Item.class) == null,
                "unsafe/non-water fluid consumed: " + type);
        }
        for (String type : List.of("Base.PoisonFood", "Base.RawFood", "Base.ScriptedFood", "Base.BowlFood")) {
            Body unsafe = new Body();
            Item item = new Item(type); item.hunger = -.5f;
            unsafe.inventory.AddItem(item);
            require(KnoxInventorySnapshot.capture(unsafe, 240).consumeSupply("food", .5, Item.class) == null,
                "unsafe or callback-dependent food consumed: " + type);
        }
        require(captured.consumeSupply("food", .5, Item.class) == null, "rotten saved food consumed");

        // A shared base is not a claim on somebody's personal inventory.
        Body shared = new Body();
        Item personal = new Item("Base.PersonalMeal"); personal.hunger=-.2f;
        shared.inventory.AddItem(personal);
        Item communalA = new Item("Base.CommunalMealA"); communalA.hunger=-.2f; communalA.communalBase="home";
        Item communalB = new Item("Base.CommunalMealB"); communalB.hunger=-.2f; communalB.communalBase="home";
        shared.inventory.AddItem(communalA); shared.inventory.AddItem(communalB);
        KnoxInventorySnapshot offered=KnoxInventorySnapshot.capture(shared,240);
        require(offered.consumeSupply("food",.8,Item.class,"other") == null,"foreign base claimed provisions");
        require(offered.consumeSupply("food",.8,Item.class,"home",2) == null,"needy donor lost extra reserve");
        KnoxInventorySnapshot.Consumption given=offered.consumeSupply("food",.8,Item.class,"home");
        require(given != null && given.type().equals("Base.CommunalMealA"),"shared operation chose a personal meal");
        Body delivered=new Body(); KnoxInventorySnapshot.decode(given.inventory().encode()).restore(delivered,Item.class);
        require(delivered.inventory.items.size()==2 && delivered.inventory.items.get(0).type.equals("Base.PersonalMeal")
            && delivered.inventory.items.get(1).communalBase.equals("home"),"shared receipt/roundtrip lost ownership or personal stock");
        require(given.inventory().consumeSupply("food",.8,Item.class,"home")==null,"last communal reserve was redistributed");
        communalA.favorite=true;
        require(KnoxInventorySnapshot.capture(shared,240).consumeSupply("food",.8,Item.class,"home")==null,"favorite allocation shared");
        communalA.favorite=false; communalA.mission=true;
        require(KnoxInventorySnapshot.capture(shared,240).consumeSupply("food",.8,Item.class,"home")==null,"mission cargo donated");
        communalA.mission=false;
        Item protectedBag=new Item("Base.ProtectedBag");protectedBag.favorite=true;protectedBag.inventory=new Container();
        protectedBag.inventory.AddItem(communalA);protectedBag.inventory.AddItem(communalB);
        Body protectedOwner=new Body();protectedOwner.inventory.AddItem(protectedBag);
        require(KnoxInventorySnapshot.capture(protectedOwner,240).consumeSupply("food",.8,Item.class,"home")==null,
            "protected bag contents shared");
        require(KnoxInventorySnapshot.capture(protectedOwner,240).consumeSupply("food",.1,Item.class)!=null,
            "own survival was disabled by protection against other people's claims");

        // Controlled detached-record workload: actual fixture deserializations,
        // not native frame timing. Early receipt stops; an absent claim scans once.
        Body large = new Body();
        for (int i=0;i<240;i++) {
            Item item=new Item("Base.LoadMeal"+i);item.hunger=-.2f;
            item.communalBase=i<2 ? "home" : "";
            large.inventory.AddItem(item);
        }
        KnoxInventorySnapshot largeRecord=KnoxInventorySnapshot.capture(large,240);
        int loadsBefore=Item.loadCalls;
        long started=System.nanoTime();
        for (int i=0;i<100;i++) require(largeRecord.consumeSupply("food",.1,Item.class,"home")!=null,
            "bounded early communal receipt failed");
        int earlyLoads=Item.loadCalls-loadsBefore;
        require(earlyLoads==200,"shared lookup continued after reserve proof");
        loadsBefore=Item.loadCalls;
        for (int i=0;i<100;i++) require(largeRecord.consumeSupply("food",.1,Item.class,"foreign")==null,
            "worst-case scan invented foreign supply");
        require(Item.loadCalls-loadsBefore==24000,"absent claim rescanned native roots");
        System.out.println("Resource fixture workload PASS trials=200 items=240 earlyLoads="+earlyLoads
            +" absentLoads="+(Item.loadCalls-loadsBefore)+" elapsedMs="+(System.nanoTime()-started)/1_000_000);

        Item cyclic = new Item("Base.Cycle");
        cyclic.inventory = new Container();
        cyclic.inventory.AddItem(cyclic);
        Body corrupt = new Body();
        corrupt.inventory.AddItem(cyclic);
        rejected = false;
        try { KnoxInventorySnapshot.capture(corrupt, 240); }
        catch (IllegalStateException expected) { rejected = true; }
        require(rejected, "cyclic inventory entered recursive serializer");
        Body walletOwner = new Body();
        Item wallet = new Item("Base.Wallet");
        wallet.inventory = new Container();
        wallet.inventory.AddItem(new Item("Base.Money"));
        wallet.inventory.AddItem(new Item("Base.Money"));
        wallet.inventory.AddItem(new Item("Base.GoldCoin"));
        Item backpack = new Item("Base.Bag_Schoolbag");
        backpack.inventory = new Container();
        walletOwner.inventory.AddItem(wallet);
        walletOwner.inventory.AddItem(backpack);
        walletOwner.setWornItem("knoxsurvivors:wallet", wallet);
        walletOwner.setWornItem("Back", backpack);
        String walletRecord = KnoxInventorySnapshot.capture(walletOwner, 240).encode();
        Body walletRestored = new Body();
        KnoxInventorySnapshot.decode(walletRecord).restore(walletRestored, Item.class);
        Item restoredWallet = walletRestored.inventory.items.get(0);
        require(walletRestored.worn.locations.get("knoxsurvivors:wallet") == restoredWallet
            && walletRestored.worn.locations.get("Back") == walletRestored.inventory.items.get(1),
            "wallet and backpack did not restore to distinct native locations");
        require(restoredWallet.inventory.items.size() == 3
            && restoredWallet.inventory.items.get(0).type.equals("Base.Money")
            && restoredWallet.inventory.items.get(1).type.equals("Base.Money")
            && restoredWallet.inventory.items.get(2).type.equals("Base.GoldCoin"),
            "wallet money/coin contents lost during snapshot reconstruction");
        require(KnoxInventorySnapshot.capture(walletRestored, 240).encode().equals(walletRecord),
            "wallet round trip duplicated or changed currency");
        require(captured.hasReadyPrimaryWeapon(Item.class), "saved chambered gun should qualify");
        require(captured.encode().equals(encoded) && gun.rounds == 7 && gun.chambered,
            "readiness inspection modified source ammunition or encoded snapshot");
        require(!KnoxInventorySnapshot.decode(legacy).hasReadyPrimaryWeapon(Item.class),
            "legacy snapshot invented loaded ammunition");
        Body readiness = new Body();
        Item weapon = new Item("Base.Pistol");
        readiness.inventory.AddItem(weapon); readiness.primary = weapon;
        require(!KnoxInventorySnapshot.capture(readiness, 240).hasReadyPrimaryWeapon(Item.class), "empty gun qualified");
        weapon.rounds = 9;
        require(!KnoxInventorySnapshot.capture(readiness, 240).hasReadyPrimaryWeapon(Item.class), "unchambered gun qualified");
        weapon.chambered = true;
        require(KnoxInventorySnapshot.capture(readiness, 240).hasReadyPrimaryWeapon(Item.class), "chambered gun rejected");
        weapon.condition = 0;
        require(!KnoxInventorySnapshot.capture(readiness, 240).hasReadyPrimaryWeapon(Item.class), "broken gun qualified");
        for (String type : List.of("Base.Bat", "Base.JammedGun", "Base.SafeGun", "Base.Revolver", "Base.Bag")) {
            Body sample = new Body(); Item candidate = new Item(type);
            candidate.rounds = 2; candidate.chambered = true;
            sample.inventory.AddItem(candidate); sample.primary = candidate;
            boolean expected = type.equals("Base.Bat") || type.equals("Base.Revolver");
            require(KnoxInventorySnapshot.capture(sample, 240).hasReadyPrimaryWeapon(Item.class) == expected,
                "wrong saved weapon readiness: " + type);
            sample.primary = null;
            require(!KnoxInventorySnapshot.capture(sample, 240).hasReadyPrimaryWeapon(Item.class), "spare item became equipped");
        }
        System.out.println("Inventory snapshot PASS native-payload=true nested=true equipment=true legacy=true preflight=true bounded-buffer=true real-supplies=true wallet=true stored-weapon-readiness=true");
    }

    public static final class Body {
        final Container inventory = new Container();
        final Worn worn = new Worn();
        Item primary, secondary;
        public Container getInventory() { return inventory; }
        public Worn getWornItems() { return worn; }
        public Item getPrimaryHandItem() { return primary; }
        public Item getSecondaryHandItem() { return secondary; }
        public void setPrimaryHandItem(Item item) { primary = item; }
        public void setSecondaryHandItem(Item item) { secondary = item; }
        public void setWornItem(String location, Item item) { worn.items.add(item); worn.locations.put(location, item); }
        public void resetModelNextFrame() { }
    }

    public static final class Worn {
        final List<Item> items = new ArrayList<>();
        final java.util.Map<String, Item> locations = new java.util.HashMap<>();
        public boolean contains(Item item) { return items.contains(item); }
        public void clear() { items.clear(); locations.clear(); }
    }

    public static final class Container {
        final List<Item> items = new ArrayList<>();
        public List<Item> getItems() { return items; }
        public Item AddItem(Item item) { items.add(item); return item; }
        public Item AddItem(String type) { return AddItem(new Item(type)); }
        public void clear() { items.clear(); }
        public void setDrawDirty(boolean dirty) { }
        public void Remove(Item item) { items.remove(item); }
    }

    public static final class Item {
        static int loadedVersion, loadCalls;
        static boolean dropChild, failLoad;
        final String type;
        int condition = 10, uses = 1, rounds;
        float fluid, hunger, age, thirst;
        boolean favorite, chambered, rotten;
        String padding = "";
        String communalBase = "";
        boolean mission;
        Container inventory;
        Item(String type) { this.type = type; }
        public String getFullType() { return type; }
        public int getCondition() { return condition; }
        public boolean IsWeapon() { return type.equals("Base.Bat") || type.equals("Base.Pistol") || type.endsWith("Gun") || type.equals("Base.Revolver"); }
        public boolean isBroken() { return condition <= 0; }
        public boolean isRanged() { return !type.equals("Base.Bat"); }
        public boolean isSelectFire() { return type.equals("Base.SafeGun"); }
        public String getFireMode() { return "Safe"; }
        public boolean isJammed() { return type.equals("Base.JammedGun"); }
        public boolean haveChamber() { return !type.equals("Base.Revolver"); }
        public boolean isRoundChambered() { return chambered; }
        public int getCurrentAmmoCount() { return rounds; }
        public int getUses() { return uses; }
        public boolean isFavorite() { return favorite; }
        public ItemData getModData() { return new ItemData(this); }
        public void setCondition(int value) { condition = value; }
        public void setUses(int value) { uses = value; }
        public void setFavorite(boolean value) { favorite = value; }
        public Container getInventory() { return inventory; }
        public String getBodyLocation() { return inventory != null && !type.equals("Base.Wallet") ? "Back" : null; }
        public String canBeEquipped() { return type.equals("Base.Wallet") ? "knoxsurvivors:wallet" : null; }
        public FluidContainer getFluidContainer() { return new FluidContainer(this); }
        public boolean IsFood() { return hunger < 0; }
        public float getHungerChange() { return hunger; }
        public float getThirstChange() { return thirst; }
        public boolean isRotten() { return rotten; }
        public boolean isPoison() { return type.contains("Poison"); }
        public int getPoisonPower() { return 0; }
        public boolean isbDangerousUncooked() { return type.contains("Raw"); }
        public boolean isCooked() { return false; }
        public String getOnEat() { return type.contains("Scripted") ? "callback" : null; }
        public String getUseOnConsume() { return null; }
        public String getReplaceOnUse() { return type.contains("Bowl") ? "Base.Bowl" : null; }
        public void multiplyFoodValues(float factor) { hunger *= factor; thirst *= factor; }
        public void saveWithSize(ByteBuffer bytes, boolean network) {
            if (network) throw new IllegalStateException("inventory save used network mode");
            int start = bytes.position();
            bytes.putInt(0);
            put(bytes, type);
            bytes.putInt(condition).putInt(uses).putInt(rounds);
            bytes.putFloat(fluid).putFloat(hunger).putFloat(age).putFloat(thirst);
            bytes.put((byte) (favorite ? 1 : 0)).put((byte) (chambered ? 1 : 0)).put((byte) (rotten ? 1 : 0));
            put(bytes, padding);
            put(bytes, communalBase); bytes.put((byte)(mission ? 1 : 0));
            bytes.putInt(inventory == null ? -1 : inventory.items.size());
            if (inventory != null) for (Item child : inventory.items) child.saveWithSize(bytes, network);
            bytes.putInt(start, bytes.position() - start - 4);
        }
        public static Item loadItem(ByteBuffer bytes, int version) {
            loadCalls++;
            loadedVersion = version;
            int size = bytes.getInt();
            if (failLoad) { bytes.position(bytes.position() + size); return null; }
            Item item = new Item(get(bytes));
            item.condition = bytes.getInt(); item.uses = bytes.getInt(); item.rounds = bytes.getInt();
            item.fluid = bytes.getFloat(); item.hunger = bytes.getFloat(); item.age = bytes.getFloat(); item.thirst = bytes.getFloat();
            item.favorite = bytes.get() != 0; item.chambered = bytes.get() != 0; item.rotten = bytes.get() != 0;
            item.padding = get(bytes);
            item.communalBase = get(bytes); item.mission = bytes.get()!=0;
            int count = bytes.getInt();
            if (count >= 0) {
                item.inventory = new Container();
                for (int i = 0; i < count; i++) {
                    Item child = loadItem(bytes, version);
                    if (!dropChild || i != 0) item.inventory.AddItem(child);
                }
            }
            return item;
        }
        private static void put(ByteBuffer bytes, String text) {
            byte[] value = text.getBytes(StandardCharsets.UTF_8);
            bytes.putInt(value.length).put(value);
        }
        private static String get(ByteBuffer bytes) {
            byte[] value = new byte[bytes.getInt()];
            bytes.get(value);
            return new String(value, StandardCharsets.UTF_8);
        }
    }

    public static final class ItemData {
        final Item item;
        ItemData(Item item) { this.item=item; }
        public Object rawget(Object key) {
            if ("KnoxBaseProvision".equals(key)) return item.communalBase.isEmpty() ? null : item.communalBase;
            if ("KnoxBaseSupplyDelivery".equals(key)) return item.mission ? "mission" : null;
            return null;
        }
    }

    public static final class FluidContainer {
        private final Item owner;
        FluidContainer(Item owner) { this.owner = owner; }
        public float getAmount() { return owner.fluid; }
        public Fluid getPrimaryFluid() { return new Fluid(owner.type.contains("Oil") ? "Gasoline"
            : owner.type.contains("Tainted") ? "TaintedWater" : "Water"); }
        public boolean isPureFluid(Fluid fluid) { return !owner.type.contains("Mixed"); }
        public void adjustAmount(float amount) { owner.fluid = amount; }
    }
    public static final class Fluid {
        private final String type;
        Fluid(String type) { this.type = type; }
        public String getFluidTypeString() { return type; }
    }
}
