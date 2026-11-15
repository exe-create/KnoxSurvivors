package zombie.characters;
import zombie.iso.IsoGridSquare;
public class IsoZombie {
    public float x=10.5f,y=20,z=0;
    public boolean dead,onFloor;
    public IsoGridSquare square=new IsoGridSquare(10,20,0);
    public float getX(){return x;} public float getY(){return y;} public float getZ(){return z;}
    public float getHealth(){return 100;} public boolean isDead(){return dead;}
    public boolean isOnFloor(){return onFloor;} public IsoGridSquare getCurrentSquare(){return square;}
}
