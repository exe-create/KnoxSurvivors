package zombie.characters;

/** Offline native-shaped human health fixture; never included in the mod jar. */
public class IsoPlayer {
    public final BodyDamage damage = new BodyDamage();
    public boolean dead;
    public float getHealth() { return 1.0f; }
    public BodyDamage getBodyDamage() { return damage; }
    public boolean isDead() { return dead; }

    public static final class BodyDamage {
        public float health = 100.0f;
        public float getHealth() { return health; }
    }
}
