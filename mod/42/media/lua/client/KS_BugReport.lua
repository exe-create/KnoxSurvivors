-- Offline-safe report construction. Only explicitly named diagnostics are exported.
KnoxBugReport = {}
local R = KnoxBugReport
R.maxUrl = 7500
R.cooldownMs = 30000

local function clean(value)
    value = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    return (value:gsub("[%z\1-\8\11\12\14-\31\127]", ""))
end

function R.validate(fields, acknowledged, now, last)
    fields = type(fields) == "table" and fields or {}
    if not acknowledged then return nil, "Please acknowledge the public report notice." end
    if last and (not now or now < last or now - last < R.cooldownMs) then
        return nil, "Please wait 30 seconds before opening another draft."
    end
    local out = {}
    for _, spec in ipairs({ {"summary", 10, 120}, {"steps", 15, 1000}, {"expected", 10, 500}, {"actual", 10, 500} }) do
        local value = clean(fields[spec[1]]):match("^%s*(.-)%s*$")
        if #value < spec[2] or #value > spec[3] then
            return nil, spec[1] .. " must be " .. spec[2] .. "-" .. spec[3] .. " characters."
        end
        out[spec[1]] = value
    end
    out.summary = out.summary:gsub("\n", " ")
    return out
end

local function safe(value)
    if type(value) == "number" then return tostring(math.max(0, math.floor(value))) end
    return "Unavailable"
end

function R.diagnostics(d)
    d = d or {}
    local mod = rawget(_G, "KnoxSurvivors")
    local version = tostring(type(mod) == "table" and mod.VERSION or "Unavailable")
    if not version:match("^[%w%.%- ]+$") or #version > 40 then version = "Unavailable" end
    local game = tostring(d.gameVersion or "Unavailable")
    if not game:match("^[%w%.%- ]+$") or #game > 40 then game = "Unavailable" end
    local adapter = d.adapter
    if adapter ~= "ZombieBuddy" and adapter ~= "KnoxBridgeRuntime" then adapter = "Unavailable" end
    return "Knox Survivors: " .. version .. "\nGame version: " .. game .. "\nRuntime adapter: " .. adapter
        .. "\nActive survivors: " .. safe(d.active) .. "\nLiving survivors: " .. safe(d.living)
        .. "\nMaximum active survivors: " .. safe(d.maxActive) .. "\n"
end

function R.body(fields, diagnostics)
    return "## Reproduction steps\n" .. fields.steps .. "\n\n## Expected\n" .. fields.expected
        .. "\n\n## Actual\n" .. fields.actual .. "\n\n## Diagnostics\n```\n" .. diagnostics .. "```\n"
end

local function encode(value)
    return (value:gsub("([^%w%-%._~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

function R.url(fields, diagnostics)
    local url = "https://github.com/exe-create/KnoxSurvivors/issues/new?title=" .. encode(fields.summary)
        .. "&body=" .. encode(R.body(fields, diagnostics))
    if #url > R.maxUrl then return nil, "Report is too long for a browser link; shorten the text." end
    return url
end

function R.place(width, height, buttonWidth, buttonHeight, obstacles)
    local gap = 12
    for y = gap, height - buttonHeight - gap, buttonHeight + gap do
        for x = width - buttonWidth - gap, gap, -(buttonWidth + gap) do
            local free = true
            for _, b in ipairs(obstacles or {}) do
                if x < b.x + b.w and x + buttonWidth > b.x and y < b.y + b.h and y + buttonHeight > b.y then free = false; break end
            end
            if free then return x, y end
        end
    end
    return nil
end

-- Inputs come from the active UI fonts; nil means the form cannot fit safely.
function R.layout(screenWidth, screenHeight, small, medium, minimumWidth)
    local gap = 8
    local width = math.max(460, math.ceil(minimumWidth or 460))
    local row = math.max(26, math.ceil(small + 8))
    local labels, entries = {}, {}
    local y = 12 + medium + gap + small * 2 + gap
    for i = 1, 4 do
        labels[i] = y
        y = y + small + 3
        local h = i == 2 and row * 2 or row
        entries[i] = { y = y, h = h }
        y = y + h + gap
    end
    local ack = y
    y = y + row + gap
    local message = y
    y = y + small + gap
    local buttons = y
    local height = buttons + row + 12
    if width + 24 > screenWidth or height + 24 > screenHeight then return nil end
    return { width = width, height = height, row = row, labels = labels, entries = entries,
        ack = ack, message = message, buttons = buttons, title = 12, notice = 12 + medium + gap }
end
