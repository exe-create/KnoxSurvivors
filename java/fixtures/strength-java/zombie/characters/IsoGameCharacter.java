package zombie.characters;
import zombie.inventory.types.HandWeapon;
public class IsoGameCharacter {
    public int nativeCalls, applications;
    public float applied;
    public boolean dead, shove, anim, shoveAnim, stompAnim, throwNative;
    public Object square = new Object();
    public boolean isDead(){return dead;}
    public Object getCurrentSquare(){return square;}
    public boolean isDoShove(){return shove;}
    public boolean isShoveStompAnim(){return anim;}
    public boolean isPerformingShoveAnimation(){return shoveAnim;}
    public boolean isPerformingStompAnimation(){return stompAnim;}
    public float processHitDamage(HandWeapon w,IsoGameCharacter attacker,float damage,boolean flag,float dot){
        nativeCalls++; if(throwNative) throw new IllegalArgumentException("native failure"); return damage * 1.25f;
    }
    public float Hit(HandWeapon w,IsoGameCharacter a,float d,boolean f,float dot){return Hit(w,a,d,f,dot,false);}
    public float Hit(HandWeapon w,IsoGameCharacter a,float d,boolean f,float dot,boolean processed){
        float result = processed ? d : processHitDamage(w,a,d,f,dot);
        applications++; applied=result; return result;
    }
    public float outside(HandWeapon w,IsoGameCharacter a,float d){return processHitDamage(w,a,d,false,1);}
}
