-- The camera state every perspective adapter reads, and the one question that
-- matters: is the crosshair the pointer? ViewpointUI's isActive() means the mod
-- is loaded, which is true in the isometric view as well, so it cannot answer
-- this; the companion mod's cursor state does, because that is what it uses to
-- lock the mouse to camera look.
local L = assert(rawget(_G, "KnoxSurvivorUILayout"), "the layout module is loaded")

-- Nothing loaded: no camera, so the isometric layout is right.
Viewpoint, ViewpointUI, VPUI, ViewpointQOL = nil, nil, nil, nil
assert(L.isPerspective() == false, "no camera means no perspective")

-- The camera is driving: the cursor is not free, so the crosshair is the pointer.
ViewpointQOL = { isCursorMode = function() return false end }
assert(L.isPerspective() == true, "a locked cursor is the perspective camera")

-- The cursor is free (isometric, or a window is open): not perspective.
ViewpointQOL = { isCursorMode = function() return true end }
assert(L.isPerspective() == false, "a free cursor is not the perspective camera")

-- A query that throws must not be read as perspective.
ViewpointQOL = { isCursorMode = function() error("no bridge") end }
assert(L.isPerspective() == false, "a failing cursor query is not perspective")

-- A companion without the query is not evidence of any camera.
ViewpointQOL = {}
assert(L.isPerspective() == false, "a cursor mode we cannot read is not perspective")

-- A loaded ViewpointUI is not a camera: this is the mistake that put the hint
-- and the talk key into first and third person.
ViewpointUI = { isActive = function() return true end }
assert(L.isPerspective() == false, "the mod being active is not the camera")

-- The legacy global still answers when it can name the mode.
Viewpoint = { View = { next = function() return "first" end } }
assert(L.isPerspective() == false, "a legacy first-person answer stays isometric")
Viewpoint = { View = { next = function() return "third" end } }
assert(L.isPerspective() == true, "a legacy third-person answer is perspective")

-- Leave the globals as they were found: later fixtures must not inherit a camera.
Viewpoint, ViewpointUI, VPUI, ViewpointQOL = nil, nil, nil, nil
assert(L.isPerspective() == false, "the camera is gone again for later fixtures")
print("Viewpoint perspective PASS cursor_state=true legacy_global=true mod_active_is_not_camera=true")
