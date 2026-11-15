local factory = assert(scheduleReadableFactory)
local function run(font, width)
    local timeline = factory(font, width)
    local blocks = {}
    local hours = { "12am-4am", "4am-8am", "8am-12pm", "12pm-4pm", "4pm-8pm", "8pm-12am" }
    local labels = { "Sleep", "Work", "Patrol", "Guard Duty", "Leisure", "Anything" }
    for i = 1, 6 do blocks[i] = { hours = hours[i], label = labels[i] } end
    timeline:setBlocks(blocks)
    assert(timeline.height == timeline.cells.height + 4, "panel reserves all timeline rows")
    assert(#timeline.cells.cells == 6, "all six schedule blocks are present")
    if width == 380 then assert(timeline.cells.rows > 1, "narrow timeline wraps into rows") end
    local draws, current = {}, 0
    function timeline:drawRect() current = current + 1; draws[current] = {} end
    function timeline:drawText(text, x, y)
        local cell = self.cells.cells[current]
        assert(x >= 1 + cell.x and x + #text * font * 0.55 <= 1 + cell.x + cell.width,
            "rendered text stays inside the cell horizontally")
        assert(y >= 2 + cell.y and y + font <= 2 + cell.y + cell.height,
            "rendered text stays inside the cell vertically")
        draws[current][#draws[current] + 1] = text
    end
    timeline.enabled = true
    timeline:render()
    for index, cell in ipairs(timeline.cells.cells) do
        local rendered = table.concat(draws[index], ""):gsub("%s+", "")
        assert(rendered == (hours[index] .. labels[index]):gsub("%s+", ""),
            "the full time range and assignment render for block " .. index)
        local selected = nil
        timeline.owner = { paintScheduleBlock = function(self, value) selected = value.knoxBlock end }
        assert(timeline:onMouseDown(1 + cell.x + cell.width / 2, 2 + cell.y + cell.height / 2),
            "a cell accepts a click")
        assert(selected == index, "a click chooses the row's own block")
    end
    local selected = nil
    timeline.owner = { paintScheduleBlock = function(self, value) selected = value.knoxBlock end }
    timeline.enabled = false
    local first = timeline.cells.cells[1]
    assert(not timeline:onMouseDown(1 + first.x + 1, 2 + first.y + 1) and selected == nil,
        "disabled schedule cannot change a block")
    if timeline.cells.rows > 1 then
        local first = timeline.cells.cells[1]
        local selected = nil
        timeline.owner = { paintScheduleBlock = function(self, value) selected = value.knoxBlock end }
        assert(not timeline:onMouseDown(1 + first.x + 1, 2 + first.y + first.height + 1),
            "vertical row gap is not a block")
        assert(selected == nil, "gap leaves the draft unchanged")
    end
end
run(14, 380)
run(24, 380)
run(14, 1000)
run(24, 65)
print("Schedule readable layout PASS text=true rows=true hit=true narrow=true")
