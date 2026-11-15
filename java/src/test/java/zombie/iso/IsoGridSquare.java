package zombie.iso;

/** Test-only signature stub for reflection-based combat cleanup verification. */
public final class IsoGridSquare {
    private int x, y, z;
    public final java.util.ArrayList<Object> moving = new java.util.ArrayList<>();
    public IsoGridSquare neighbor;
    public Object window;
    public boolean blocked, stairs, free=true, floor=true;
    public Object room, hoppable;
    public IsoGridSquare() { }
    public IsoGridSquare(int x, int y, int z) { this.x=x; this.y=y; this.z=z; }
    public int getX() { return x; }
    public int getY() { return y; }
    public int getZ() { return z; }
    public java.util.ArrayList<Object> getMovingObjects() { return moving; }
    public IsoGridSquare getAdjacentSquare(IsoDirections direction) { return neighbor; }
    public boolean isBlockedTo(IsoGridSquare next) { return blocked; }
    public boolean HasStairs() { return stairs; }
    public boolean isFree(boolean ignore) { return free; }
    public boolean TreatAsSolidFloor() { return floor; }
    public Object getRoom() { return room; }
    public Object getWindowFrameTo(IsoGridSquare next) { return null; }
    public Object getWindowThumpableTo(IsoGridSquare next) { return null; }
    public boolean isHoppableTo(IsoGridSquare next) { return hoppable != null; }
    public Object getHoppableTo(IsoGridSquare next) { return hoppable; }
    public Object getWallHoppableTo(IsoGridSquare next) { return hoppable; }
    public Object getDoorTo(IsoGridSquare next) { return null; }
    public Object getWindowTo(IsoGridSquare next) { return window; }
}
