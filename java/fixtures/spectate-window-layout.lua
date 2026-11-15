local old=UILayout
local layout={scaled=function(value) return value end,tintWindow=function(window) window.tint="module" end}
UILayout=nil
local small=spectateWindowFactory(layout,320,200)
assert(small.width==280 and small.height==160 and small.tint=="module", "browser uses imported layout on small screen")
assert(small.title=="Knox Survivor Spectator" and small.resizable==false, "browser retains title and fixed size")
UILayout={scaled=function() error("global layout must not be read") end,tintWindow=function() error("global tint") end}
local large=spectateWindowFactory(layout,1920,1080)
assert(large.width==620 and large.height==500 and large.tint=="module", "browser ignores poisoned global layout")
local tiny=spectateWindowFactory(layout,30,30)
assert(tiny.width==1 and tiny.height==1, "browser dimensions never fall below one")
UILayout=old
print("Spectator window imported layout PASS nativeGameplay=false")
