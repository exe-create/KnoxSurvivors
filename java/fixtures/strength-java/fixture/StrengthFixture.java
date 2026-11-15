package fixture;
import zombie.characters.*;
import zombie.inventory.types.HandWeapon;
import zombie.Lua.LuaManager;
import com.knoxsurvivors.engine.KnoxIsoPlayerShell;
import java.lang.reflect.*;
import java.util.Map;

public class StrengthFixture {
    static int checks;
    static void check(boolean condition,String message){checks++;if(!condition)throw new AssertionError("strength: "+message);}
    static void bits(float got,float expected,String message){check(Float.floatToRawIntBits(got)==Float.floatToRawIntBits(expected),message+" got="+got+" expected="+expected);}
    static Field field(Class<?> c,String n)throws Exception{Field f=c.getDeclaredField(n);f.setAccessible(true);return f;}
    static Object runtime(String id,Object body)throws Exception{
        Class<?> npc=Class.forName("com.knoxsurvivors.npc.KnoxNpc");
        Constructor<?> nc=npc.getDeclaredConstructor(String.class,Object.class,int.class,int.class,int.class); nc.setAccessible(true);
        Object instance=nc.newInstance(id,body,0,0,0);
        Class<?> rt=Class.forName("com.knoxsurvivors.npc.KnoxNpcRuntime"); Constructor<?> rc=rt.getDeclaredConstructor(npc);rc.setAccessible(true);return rc.newInstance(instance);
    }
    @SuppressWarnings("unchecked") public static void run(boolean buddy)throws Exception{
        Class<?> agent=Class.forName("com.knoxsurvivors.agent.KnoxAgent");
        Class<?> boot=Class.forName("com.knoxsurvivors.bridge.KnoxBridgeBootstrap");
        Object bridge=boot.getMethod("getBridge").invoke(null);
        Object registry=field(bridge.getClass(),"npcRegistry").get(bridge);
        Map<String,Object> active=(Map<String,Object>)field(registry.getClass(),"activeNpcs").get(registry);
        KnoxIsoPlayerShell attacker=new KnoxIsoPlayerShell(), other=new KnoxIsoPlayerShell();
        IsoZombie victim=new IsoZombie(); HandWeapon weapon=new HandWeapon();
        active.put("a",runtime("a",attacker)); active.put("b",runtime("b",other));
        LuaManager.Table env=new LuaManager.Table(), sandbox=new LuaManager.Table(), opts=new LuaManager.Table();
        LuaManager.env=env; env.rawset("KnoxJavaBridge",bridge); env.rawset("SandboxVars",sandbox);
        sandbox.rawset("KnoxSurvivors",opts); opts.rawset("Enabled",true); opts.rawset("SurvivorStrength",4.0);
        bits(victim.Hit(weapon,attacker,8,false,1),10,"inactive adapter returns native damage");
        if(buddy) agent.getMethod("startFromZombieBuddy").invoke(null);
        else {field(agent,"runtimeSource").set(null,"knoxbridge");field(agent,"runtimeStarted").setBoolean(null,true);}
        int beforeN=victim.nativeCalls,beforeA=victim.applications;
        for(int tier=1;tier<=4;tier++){
            opts.rawset("SurvivorStrength",(double)tier);
            float expected=tier==1?10*.9f:tier==3?10*1.1f:tier==4?20:10;
            bits(victim.Hit(weapon,attacker,8,false,1),expected,"tier "+tier+" after native modifier");
        }
        check(victim.nativeCalls-beforeN==4 && victim.applications-beforeA==4,"native computation and downstream application once per hit");
        opts.rawset("SurvivorStrength",2.0);
        float unusual=Float.intBitsToFloat(0x3f812345);
        bits(victim.Hit(weapon,attacker,unusual,false,1),unusual*1.25f,"Normal preserves non-round native float bits");
        opts.rawset("SurvivorStrength",4.0);
        for(float input:new float[]{-0.0f,-1.0f,Float.POSITIVE_INFINITY,Float.NEGATIVE_INFINITY,Float.NaN})
            bits(victim.Hit(weapon,attacker,input,false,1),input*1.25f,"nonpositive and nonfinite native result unchanged");
        float large=Float.MAX_VALUE/2;
        bits(victim.Hit(weapon,attacker,large,false,1),large*1.25f,"scaled overflow preserves finite native result");
        bits(victim.Hit(null,attacker,8,false,1),10,"missing weapon");
        env.rawset("SandboxVars",null);bits(victim.Hit(weapon,attacker,8,false,1),10,"missing sandbox");
        env.rawset("SandboxVars",new Object());bits(victim.Hit(weapon,attacker,8,false,1),10,"malformed sandbox");
        env.rawset("SandboxVars",sandbox);sandbox.rawset("KnoxSurvivors",null);
        bits(victim.Hit(weapon,attacker,8,false,1),10,"missing settings table");
        sandbox.rawset("KnoxSurvivors",new Object());bits(victim.Hit(weapon,attacker,8,false,1),10,"malformed settings table");
        sandbox.rawset("KnoxSurvivors",opts);env.rawset("KnoxJavaBridge",new Object());
        bits(victim.Hit(weapon,attacker,8,false,1),10,"foreign bridge refused");env.rawset("KnoxJavaBridge",bridge);
        opts.rawset("SurvivorStrength",4.0);
        beforeN=victim.nativeCalls;beforeA=victim.applications;
        bits(victim.Hit(weapon,attacker,8,false,1,true),8,"already processed bypass");
        check(victim.nativeCalls==beforeN && victim.applications==beforeA+1,"bypass skips native damage and applies once");
        bits(victim.outside(weapon,attacker,8),10,"direct damage call remains native");
        bits(other.Hit(weapon,attacker,8,false,1),20,"registered survivor victim admitted");
        bits(new IsoPlayer().Hit(weapon,attacker,8,false,1),10,"human victim excluded");
        bits(victim.Hit(weapon,new IsoPlayer(),8,false,1),10,"human attacker excluded");
        bits(attacker.Hit(weapon,attacker,8,false,1),10,"self excluded");
        for(Object v:new Object[]{null,0.0,5.0,1.5,"4",Double.NaN,Double.POSITIVE_INFINITY}){
            opts.rawset("SurvivorStrength",v);bits(victim.Hit(weapon,attacker,8,false,1),10,"missing or invalid tier");
        }
        opts.rawset("SurvivorStrength",4.0);opts.rawset("Enabled",false);
        bits(victim.Hit(weapon,attacker,8,false,1),10,"disabled mod");opts.rawset("Enabled",true);
        weapon.melee=false;bits(victim.Hit(weapon,attacker,8,false,1),10,"non-melee");weapon.melee=true;
        weapon.bare=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"bare hands");weapon.bare=false;
        weapon.ranged=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"ranged");weapon.ranged=false;
        weapon.explosive=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"explosive");weapon.explosive=false;
        attacker.shove=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"shove");attacker.shove=false;
        attacker.anim=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"shove stomp animation");attacker.anim=false;
        attacker.shoveAnim=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"shove animation");attacker.shoveAnim=false;
        attacker.stompAnim=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"stomp animation");attacker.stompAnim=false;
        attacker.dead=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"dead attacker");attacker.dead=false;
        victim.dead=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"dead victim");victim.dead=false;
        attacker.square=null;bits(victim.Hit(weapon,attacker,8,false,1),10,"detached attacker");attacker.square=new Object();
        victim.square=null;bits(victim.Hit(weapon,attacker,8,false,1),10,"detached victim");victim.square=new Object();
        zombie.network.GameClient.client=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"client");zombie.network.GameClient.client=false;
        zombie.network.GameServer.server=true;bits(victim.Hit(weapon,attacker,8,false,1),10,"server");zombie.network.GameServer.server=false;
        active.remove("a");bits(victim.Hit(weapon,attacker,8,false,1),10,"unregistered attacker");
        KnoxIsoPlayerShell replacement=new KnoxIsoPlayerShell();active.put("a",runtime("a",replacement));
        bits(victim.Hit(weapon,attacker,8,false,1),10,"replaced body rejected");
        bits(victim.Hit(weapon,replacement,8,false,1),20,"replacement admitted");
        active.remove("b");bits(other.Hit(weapon,replacement,8,false,1),10,"unregistered shell victim");
        LuaManager.env=new LuaManager.Table();bits(victim.Hit(weapon,replacement,8,false,1),10,"new unexposed environment");
        check(active.size()==1,"hit guard must not clear registry on environment change"); LuaManager.env=env;
        victim.throwNative=true;try{victim.Hit(weapon,replacement,8,false,1);throw new AssertionError("native exception lost");}
        catch(IllegalArgumentException expected){check("native failure".equals(expected.getMessage()),"native exception propagated");}
        System.out.println("strength transformed fixture PASS adapter="+(buddy?"zombiebuddy":"bridge")+" checks="+checks);
    }
}
