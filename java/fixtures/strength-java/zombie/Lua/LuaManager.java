package zombie.Lua;
import java.util.HashMap;
public class LuaManager {
    public static Table env;
    public static class Table {
        private final HashMap<Object,Object> data=new HashMap<>();
        public Object rawget(Object k){return data.get(k);} public void rawset(Object k,Object v){data.put(k,v);}
    }
}
