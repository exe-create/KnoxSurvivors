package zombie.iso;

/** Test-only signature stub for reflection-based combat cleanup verification. */
public final class IsoGridSquare {
    private int x, y, z;
    public final java.util.ArrayList<Object> moving = new java.util.ArrayList<>();
    public IsoGridSquare neighbor;
    public IsoGridSquare() { }
    public IsoGridSquare(int x, int y, int z) { this.x=x; this.y=y; this.z=z; }
    public int getX() { return x; }
    public int getY() { return y; }
    public int getZ() { return z; }
    public java.util.ArrayList<Object> getMovingObjects() { return moving; }
    public IsoGridSquare getAdjacentSquare(IsoDirections direction) { return neighbor; }
}
