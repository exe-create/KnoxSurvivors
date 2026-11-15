local size=assert(talkViewportSize)
for _,font in ipairs({14,21,28,42}) do
    for _,screen in ipairs({{1280,720},{1920,1080},{640,480}}) do
        local w,h,scale=size(font,screen[1],screen[2])
        assert(w>0 and h>0 and w<=screen[1]-20 and h<=screen[2]-20,
            "talk window fits the actual player viewport at every tested font")
        assert(scale>=1,"window fit does not silently shrink the player's interface font")
    end
end
local w,h=size(14,1280,720)
assert(w==500 and h==300,"ordinary talk geometry remains unchanged")
local largeW,largeH=size(42,1280,720)
assert(largeW==1260 and largeH==700,"oversized talk uses viewport bounds rather than hiding actions offscreen")
print("Talk viewport PASS fonts=true normalPreserved=true bounded=true nativeRendering=false")
