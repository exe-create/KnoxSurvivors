local R = assert(KnoxBugReport)
local oldVersion=KnoxSurvivors
KnoxSurvivors={VERSION="fixture-0.3.1"}
assert(R.diagnostics({}):find("Knox Survivors: fixture-0.3.1",1,true),"diagnostics use the loaded mod's version owner")
KnoxSurvivors=oldVersion
local input = { summary = "Survivor cannot open door", steps = "Order survivor to open the locked door", expected = "Survivor reports it is locked", actual = "Survivor stands still" }
local valid = assert(R.validate(input, true, 100000, nil))
assert(not R.validate(input, false, 100000, nil), "public acknowledgement is required")
assert(not R.validate({summary="x", steps=input.steps, expected=input.expected, actual=input.actual}, true, 100000, nil), "short summary is rejected")
assert(not R.validate(input, true, 129999, 100000), "cooldown prevents immediate repeated draft")
assert(R.validate(input, true, 130000, 100000), "cooldown expires at boundary")
assert(not R.validate(input, true, 99999, 100000), "clock reversal fails closed")
local diag = R.diagnostics({ gameVersion="42.21.0", adapter="ZombieBuddy", active=2, living=5, maxActive=32, player="SECRET_PLAYER", path="SECRET_PATH", ip="SECRET_IP" })
assert(not diag:find("SECRET"), "diagnostics ignore unapproved values")
assert(diag:find("Active survivors: 2", 1, true), "active count is exported")
assert(not R.diagnostics({gameVersion="secret/path"}):find("secret", 1, true), "version rejects unsafe values")
local url = assert(R.url(valid, diag))
assert(url:find("Survivor%%20cannot%%20open%%20door"), "draft title is URL encoded")
assert(url:find("%%0A"), "draft line breaks are encoded")
local controlled = assert(R.validate({summary="Summary with\1 control", steps=input.steps, expected=input.expected, actual=input.actual}, true, 1, nil))
assert(not controlled.summary:find("\1", 1, true), "control characters are removed")
local giant = { summary=valid.summary, steps=string.rep("#", 3000), expected=valid.expected, actual=valid.actual }
assert(not R.url(giant, diag), "oversized encoded URL is rejected")
local x, y = R.place(400, 200, 100, 25, {{x=288,y=12,w=100,h=25}})
assert(x and not (x == 288 and y == 12), "placement avoids a visible control")
assert(not R.place(100, 30, 100, 25, {}), "placement fails when screen is too small")
assert(not R.place(400, 200, 100, 25, {{x=0,y=0,w=400,h=200}}), "placement hides when covered")
for _, font in ipairs({ 14, 20, 30 }) do
    local g = assert(R.layout(1920, 1080, font, font + 5, 600))
    assert(g.notice >= g.title + font + 5, "notice follows measured title")
    assert(g.labels[1] >= g.notice + 2 * font, "fields follow both notice lines")
    for i = 1, 4 do
        assert(g.entries[i].y >= g.labels[i] + font, "entry clears its label")
        if i < 4 then assert(g.labels[i + 1] >= g.entries[i].y + g.entries[i].h, "rows do not overlap") end
    end
    assert(g.ack >= g.entries[4].y + g.entries[4].h, "acknowledgement clears fields")
    assert(g.message >= g.ack + g.row and g.buttons >= g.message + font, "feedback and buttons do not overlap")
    assert(g.buttons + g.row <= g.height, "buttons fit in the window")
end
assert(not R.layout(320, 240, 30, 35, 600), "form hides if measured content cannot fit")
