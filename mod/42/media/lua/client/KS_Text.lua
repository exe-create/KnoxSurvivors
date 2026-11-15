-- Translation access for Knox Survivors UI text. Build 42 loads JSON tables from
-- media/lua/shared/Translate/<LANG>/, and getText returns the key itself when a
-- language lacks it. Every call here therefore takes the English wording as the
-- fallback, so a half-translated or unknown language never shows a raw key.
--
-- Convention: keys are IGUI_KS_<Surface><Meaning>, and the English text lives in
-- media/lua/shared/Translate/EN/IG_UI.json.
local Text = {}

function Text.get(key, english, ...)
    local fallback = english ~= nil and english or key
    if key == nil then return fallback end
    local ok, value = pcall(getText, key, ...)
    if not ok or value == nil or value == "" or value == key then
        return fallback
    end
    return value
end

-- For a key that carries one substitution, e.g. "Have %1 saw logs".
function Text.format(key, english, ...)
    local template = Text.get(key, english)
    local packed = { ... }
    return (string.gsub(template, "%%(%d)", function(index)
        local value = packed[tonumber(index)]
        return value ~= nil and tostring(value) or ""
    end))
end

KnoxText = Text
