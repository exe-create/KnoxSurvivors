-- One yard, one name. The save keeps whatever label it was given; only the
-- default the base layout itself wrote before the rename is translated, and the
-- translation lives beside the zone record rather than in each panel.
local P = assert(rawget(_G, "KnoxPersistence"), "the persistence module is loaded")
assert(type(P.zoneDisplayLabel) == "function", "the zone record owner names a zone")

-- A label that is already the current name, or the player's own, is shown as written.
-- Superseded 2026-11-06: the yard's current name is "Drop Point"; "Log Yard" is
-- now a legacy name translated below, like "Log Processing".
assert(P.zoneDisplayLabel({ type = "log_processing", label = "Drop Point" }, "x") == "Drop Point",
    "the current name reads unchanged")
assert(P.zoneDisplayLabel({ type = "log_processing", label = "Back Yard" }, "x") == "Back Yard",
    "a name the player chose is never translated")

-- The old names are the only strings that change.
assert(P.zoneDisplayLabel({ type = "log_processing", label = "Log Processing" }, "x") == "Drop Point",
    "the pre-rename default reads as the current name")
assert(P.zoneDisplayLabel({ type = "log_processing", label = "Log Yard" }, "x") == "Drop Point",
    "the earlier yard name reads as the current name")

-- Another kind of area keeps its words even when they match.
assert(P.zoneDisplayLabel({ type = "woodcutting", label = "Log Processing" }, "x") == "Log Processing",
    "only the log area is renamed")

-- No label at all falls back rather than inventing one.
assert(P.zoneDisplayLabel({ type = "log_processing" }, "Log yard") == "Log yard",
    "a zone without a label uses the caller's fallback")
assert(P.zoneDisplayLabel({ type = "log_processing", label = "" }, "Log yard") == "Log yard",
    "an empty label uses the caller's fallback")
assert(P.zoneDisplayLabel(nil, "Log yard") == "Log yard", "no zone uses the caller's fallback")

-- Reading a name never rewrites the record.
local zone = { type = "log_processing", label = "Log Processing" }
P.zoneDisplayLabel(zone, "x")
assert(zone.label == "Log Processing", "the save keeps the label it stored")
