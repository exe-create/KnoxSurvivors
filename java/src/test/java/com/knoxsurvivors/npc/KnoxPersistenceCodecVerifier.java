package com.knoxsurvivors.npc;

import java.io.StringReader;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;

/** Production Lua + installed B42 table codec. No world, save folder or native actors. */
public final class KnoxPersistenceCodecVerifier {
    public static void main(String[] args) throws Exception {
        Path root=Path.of(args[0]);
        Class<?> table=Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> platformType=Class.forName("se.krka.kahlua.vm.Platform");
        Object platform=Class.forName("se.krka.kahlua.j2se.J2SEPlatform").getConstructor().newInstance();
        Object environment=platform.getClass().getMethod("newTable").invoke(platform);
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"_G",environment);
        Class.forName("se.krka.kahlua.stdlib.BaseLib").getMethod("register",table).invoke(null,environment);
        for (String library : new String[]{"se.krka.kahlua.j2se.MathLib", "se.krka.kahlua.stdlib.StringLib",
                "se.krka.kahlua.stdlib.TableLib", "se.krka.kahlua.stdlib.OsLib",
                "se.krka.kahlua.stdlib.CoroutineLib", "se.krka.kahlua.stdlib.RandomLib"})
            Class.forName(library).getMethod("register",platformType,table).invoke(null,platform,environment);
        Object thread=Class.forName("se.krka.kahlua.vm.KahluaThread")
            .getConstructor(platformType,table).newInstance(platform,environment);
        thread.getClass().getField("debugOwnerThread").set(thread,Thread.currentThread());
        Method compile=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
            .getMethod("loadis",java.io.Reader.class,String.class,table);
        Method call=thread.getClass().getMethod("pcall",Object.class,Object[].class);
        Runner runner=new Runner(compile,call,thread,environment);
        runner.run("stdlib",Files.readString(Path.of(args[1]).resolve("stdlib.lua")));
        runner.run("setup", "require=function() return true end; data={}; "
            +"ModData={getOrCreate=function(k) data[k]=data[k] or {};return data[k] end}; "
            +"Events={OnSave={Add=function(f) savedHook=f end},OnGameStart={Add=function(f) loadedHook=f end}}; "
            +"getGameTime=function() return {getWorldAgeHours=function() return 12 end} end");
        String production=Files.readString(root.resolve("mod/42/media/lua/client/KS_Persistence.lua"));
        runner.run("KS_Persistence",production);
        String fixture=Files.readString(root.resolve("java/fixtures/companion-persistence-codec.lua"));
        String portable = sampleRecord();
        benchmarkRecordLocation(portable);
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"expectedRecord",portable);
        runner.run("seed",fixture);
        runner.run("KS_OrderCatalog",Files.readString(root.resolve("mod/42/media/lua/client/KS_OrderCatalog.lua")));
        runner.run("KS_Controller",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")));
        runner.run("journey",Files.readString(root.resolve("java/fixtures/companion-journey.lua")));
        KnoxSurvivorRecord beforeMeal=KnoxSurvivorRecord.decode(portable);
        var meal=beforeMeal.inventory.consumeSupply("food",.1,KnoxInventorySnapshotVerifier.Item.class);
        if(meal==null || Math.abs(meal.hungerRelief()-.1)>.000001)
            throw new AssertionError("Journey recovery meal has no real native-shaped receipt");
        portable=new KnoxSurvivorRecord(beforeMeal.id,beforeMeal.x,beforeMeal.y,beforeMeal.z,
            beforeMeal.positionX,beforeMeal.positionY,beforeMeal.appearance,meal.inventory(),
            beforeMeal.health,nativePhysiology((float)(.6-meal.hungerRelief()))).encode();
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"expectedRecord",portable);
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"expectedHunger",.6-meal.hungerRelief());
        runner.run("KS_Runtime",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorRuntime.lua")));
        runner.run("KS_Unloaded",Files.readString(root.resolve("mod/42/media/lua/client/KS_UnloadedSurvival.lua")));
        runner.run("save_event",Files.readString(root.resolve("java/fixtures/companion-save-event.lua")));
        Object names=runner.run("KS_Names",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNames.lua")));
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"codecNames",names);
        runner.run("view_require","require=function(name) if name=='KS_SurvivorNames' then return codecNames end return true end");
        runner.run("KS_ViewModel",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorViewModel.lua")));
        runner.run("readiness_view",Files.readString(root.resolve("java/fixtures/companion-readiness-view.lua")));
        Method get=table.getMethod("rawget",Object.class),set=table.getMethod("rawset",Object.class,Object.class);
        int size=0;
        for(int pass=0;pass<2;pass++) {
        Object graph=get.invoke(environment,"data");
        ByteBuffer bytes=ByteBuffer.allocate(8*1024*1024);
        graph.getClass().getMethod("save",ByteBuffer.class).invoke(graph,bytes);
        size=bytes.position();bytes.flip();
        Object restored=platform.getClass().getMethod("newTable").invoke(platform);
        restored.getClass().getMethod("load",ByteBuffer.class,int.class).invoke(restored,bytes,240);
        if(bytes.hasRemaining()) throw new AssertionError("Codec did not consume exact snapshot");
        set.invoke(environment,"data",restored);
        runner.run("reload_production",production);
        runner.run("verify", "verifyPersistedCompanion(); loadedHook(); verifyPersistedCompanion(); verifyReloadedGroupIndex(); verifyReadinessView()");
        }
        runner.run("extract","savedRecord=KnoxPersistence.getRecord('codec-person')");
        String loaded=(String)get.invoke(environment,"savedRecord");
        KnoxSurvivorRecord record=KnoxSurvivorRecord.decode(loaded);
        if(!portable.equals(record.encode())) throw new AssertionError("Portable record changed across B42 codec");
        var physiologyBody=new PhysiologyBody();
        record.physiology.restore(physiologyBody);
        if(!engineBytes(physiologyBody.stats).equals(record.physiology.encode().split("\\|",-1)[2])
            || !engineBytes(physiologyBody.nutrition).equals(record.physiology.encode().split("\\|",-1)[3])
            || Math.abs(physiologyBody.hours-12)>.000001 || physiologyBody.asleep
            || physiologyBody.asleepTime!=0)
            throw new AssertionError("Installed stats/nutrition payload changed across production restore");
        System.out.println("Installed B42 physiology PASS actualStats=true actualNutrition=true productionRestore=true actorFacade=true worldSave=false");
        var body=new KnoxInventorySnapshotVerifier.Body();
        record.inventory.restore(body,KnoxInventorySnapshotVerifier.Item.class);
        if(body.inventory.items.size()!=2 || !body.inventory.items.get(0).favorite
            || !body.inventory.items.get(1).communalBase.equals("home")
            || Math.abs(body.inventory.items.get(1).hunger+.1)>.000001)
            throw new AssertionError("Spent meal duplicated or personal/provision ownership changed");
        if(record.inventory.consumeSupply("food",.8,KnoxInventorySnapshotVerifier.Item.class,"home")!=null)
            throw new AssertionError("Loaded communal reserve was redistributed");
        System.out.println("Portable survivor record PASS nativeShapedItems=true spentMealAbsent=true personal=true reserve=true");
        System.out.println("B42 persistence codec PASS passes=2 bytes="+size+" productionLua=true realTableCodec=true worldSave=false");
    }
    static String sampleRecord() throws Exception {
        var body=new KnoxInventorySnapshotVerifier.Body();
        var personal=new KnoxInventorySnapshotVerifier.Item("Base.PersonalKeepsake");personal.favorite=true;
        body.inventory.AddItem(personal);
        for(int i=0;i<2;i++) {
            var food=new KnoxInventorySnapshotVerifier.Item("Base.Meal"+i);
            food.hunger=-.2f;food.communalBase="home";body.inventory.AddItem(food);
        }
        var receipt=KnoxInventorySnapshot.capture(body,240)
            .consumeSupply("food",.8,KnoxInventorySnapshotVerifier.Item.class,"home");
        if(receipt==null) throw new AssertionError("Initial real-record consumption failed");
        return new KnoxSurvivorRecord("codec-person",105,205,0,105.5f,205.5f,
            KnoxAppearanceSnapshot.decode("1|0|240||QWRh|U3Vydml2b3I||1|1.0"),receipt.inventory(),
            KnoxHealthSnapshot.decode("1|240|91|0|0|"),
            nativePhysiology(.6f)).encode();
    }

    // Actual installed engine data objects; the actor itself remains a facade.
    // Inspected constructors/save/load: no world/update/native actor is started.
    public static final class PhysiologyBody {
        final Object stats,nutrition;
        float asleepTime=123;double hours=2;boolean asleep=true;
        public PhysiologyBody() throws Exception {
            stats=Class.forName("zombie.characters.Stats").getConstructor().newInstance();
            nutrition=Class.forName("zombie.characters.BodyDamage.Nutrition")
                .getConstructor(Class.forName("zombie.characters.IsoPlayer")).newInstance(new Object[]{null});
        }
        public Object getStats() {return stats;}
        public Object getNutrition() {return nutrition;}
        public void setAsleepTime(float value) {asleepTime=value;}
        public void setHoursSurvived(double value) {hours=value;}
        public void setAsleep(boolean value) {asleep=value;}
    }
    private static KnoxPhysiologySnapshot nativePhysiology(float hunger) throws Exception {
        var body=new PhysiologyBody();
        Class<?> stat=Class.forName("zombie.characters.CharacterStat");
        String[] names={"HUNGER","THIRST","FATIGUE","ENDURANCE","PANIC"};
        float[] values={hunger,.3f,.2f,.8f,17f};
        for(int i=0;i<names.length;i++)
            body.stats.getClass().getMethod("set",stat,float.class).invoke(body.stats,stat.getField(names[i]).get(null),values[i]);
        body.nutrition.getClass().getMethod("setWeight",double.class).invoke(body.nutrition,76.5);
        body.nutrition.getClass().getMethod("setCalories",float.class).invoke(body.nutrition,1275f);
        return KnoxPhysiologySnapshot.decode("1|240|"+engineBytes(body.stats)+"|"+engineBytes(body.nutrition)
            +"|0|12|false|"+hunger+"|0.3|0.2|0.8");
    }
    private static String engineBytes(Object state) throws Exception {
        ByteBuffer bytes=ByteBuffer.allocate(65536);
        state.getClass().getMethod("save",ByteBuffer.class).invoke(state,bytes);
        byte[] encoded=new byte[bytes.position()];bytes.flip();bytes.get(encoded);
        return java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(encoded);
    }

    private static void benchmarkRecordLocation(String encoded) throws Exception {
        KnoxNpcRegistry registry=new KnoxNpcRegistry();
        var large=new KnoxInventorySnapshotVerifier.Body();
        for(int i=0;i<240;i++) large.inventory.AddItem(new KnoxInventorySnapshotVerifier.Item("Base.Stock"+i));
        String worst=KnoxSurvivorRecord.decode(encoded).withInventory(KnoxInventorySnapshot.capture(large,240));
        // Warm both production entry paths; retain checksums so work is observed.
        for(int i=0;i<32;i++) {registry.persistentRecordX(encoded);registry.persistentRecordLocation(encoded);}
        for(int size : new int[]{128,512,2048}) compareLocationPaths(registry,encoded,size);
        compareLocationPaths(registry,worst,256);
        boolean rejected=false;
        try {registry.persistentRecordLocation("corrupt");} catch(RuntimeException expected) {rejected=true;}
        if(!rejected) throw new AssertionError("Bulk location bypassed record validation");
    }
    private static void compareLocationPaths(KnoxNpcRegistry registry,String encoded,int count) {
        long before=System.nanoTime();long oldSum=0,newSum=0;
        for(int i=0;i<count;i++) oldSum+=registry.persistentRecordX(encoded)+registry.persistentRecordY(encoded)+registry.persistentRecordZ(encoded);
        long oldNs=System.nanoTime()-before;before=System.nanoTime();
        for(int i=0;i<count;i++) {
            var point=registry.persistentRecordLocation(encoded);newSum+=point.get("x")+point.get("y")+point.get("z");
        }
        long newNs=System.nanoTime()-before;
        if(oldSum!=newSum) throw new AssertionError("Population coordinate paths disagree");
        System.out.println("Record location workload count="+count+" encodedBytes="+encoded.length()
            +" oldCalls="+(count*3)+" newCalls="+count+" oldMs="+oldNs/1_000_000.0+" newMs="+newNs/1_000_000.0
            +" coordinatesEqual=true nativeFrameTime=false");
    }

    private record Runner(Method compile,Method call,Object thread,Object environment) {
        Object run(String name,String source) throws Exception {
            Object closure=compile.invoke(null,new StringReader(source),name,environment);
            Object[] result=(Object[])call.invoke(thread,closure,new Object[0]);
            if(result.length==0 || !Boolean.TRUE.equals(result[0]))
                throw new AssertionError(name+": "+java.util.Arrays.toString(result));
            return result.length>1 ? result[1] : null;
        }
    }
}
