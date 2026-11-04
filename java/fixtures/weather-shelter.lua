-- The idle spot chooser already had an indoor/yard preference. It now asks the
-- weather first, because a person being rained on does not choose the yard. This
-- drives the production reading the chooser consumes.
local N = assert(rawget(_G, "codecWeatherNeeds"), "the needs rule is loaded")

local rain = 0.0
local previousClimate = rawget(_G, "getClimateManager")
getClimateManager = function()
    return { getRainIntensity = function() return rain end }
end

local function body(core, hasThermo, wet)
    local damage = { getThermoregulator = function() return nil end }
    if hasThermo ~= false then
        damage.getThermoregulator = function()
            return { getCoreTemperature = function() return core end }
        end
    end
    return {
        getBodyDamage = function() return damage end,
        getClothingWetness = function() return wet end,
    }
end

-- Dry and warm: no reason to move, so the existing preference stands.
rain = 0.0
assert(N.shelterReason(body(36.8)) == nil, "clear weather and a warm body stay put")
assert(N.rainIntensity() == 0.0, "the sky is readable")

-- Rain answers first, and only from the band the rule states.
rain = 0.14
assert(N.shelterReason(body(36.8)) == nil, "a trace of rain is not weather")
rain = 0.15
assert(N.shelterReason(body(36.8)) == "rain", "noticed rain sends a person inside")
rain = 0.60
assert(N.shelterReason(body(34.0)) == "rain", "rain is answered before cold")

-- Cold is the body's own answer, at the stated core.
rain = 0.0
assert(N.coreTemperature(body(35.5)) == 35.5, "the cold core is readable")
assert(N.shelterReason(body(35.5)) == "cold", "the cold threshold is where it says")
assert(N.shelterReason(body(35.6)) == nil, "a hair above it is not cold")
assert(N.shelterReason(body(34.2)) == "cold", "a cold body goes inside in the dry")

-- Rain soaks clothing and the soaking outlasts the rain: a person still wet
-- through does not choose the yard because the sky happens to be clear.
rain = 0.0
assert(N.clothingWetness(body(36.8, true, 44)) == 44, "wetness is readable")
assert(N.shelterReason(body(36.8, true, 44)) == nil, "damp clothes are not a reason")
assert(N.shelterReason(body(36.8, true, 45)) == "wet", "soaked clothes send a person in")
rain = 0.30
assert(N.shelterReason(body(36.8, true, 90)) == "rain", "the rain is named while it falls")
rain = 0.0
assert(N.shelterReason(body(34.0, true, 90)) == "cold", "cold is named before wet")
assert(N.shelterReason(body(36.8, false, 90)) == "wet", "wetness needs no core read")
assert(N.clothingWetness(nil) == nil, "no body has no wetness")
local noWetness = { getBodyDamage = function()
    return { getThermoregulator = function() return nil end }
end }
assert(N.clothingWetness(noWetness) == nil, "a body without the accessor is unknown")
assert(N.shelterReason(noWetness) == nil, "an unread body is not sent inside")

-- One reason, one bank. An unknown reason must not borrow the rain's words.
assert(N.shelterBank("rain") == "weather_rain", "rain has its own bank")
assert(N.shelterBank("cold") == "weather_cold", "cold has its own bank")
assert(N.shelterBank("wet") == "weather_wet", "wet has its own bank")
assert(N.shelterBank("fog") == nil, "an unknown reason has no bank")
assert(N.shelterBank(nil) == nil, "no reason says nothing")

-- A body without a thermoregulator, and no character at all, are silence.
assert(N.shelterReason(body(34.0, false)) == nil, "an unread body is not cold")
assert(N.shelterReason(nil) == nil, "no body is not cold")
assert(N.coreTemperature(nil) == nil, "no body has no temperature")

-- A sky we cannot read must not move anybody, even a cold person is still
-- answered by their own body.
getClimateManager = function() error("no climate here") end
assert(N.rainIntensity() == nil, "a failing sky read is unknown, not dry")
assert(N.shelterReason(body(36.8)) == nil, "unknown weather moves nobody")
assert(N.shelterReason(body(34.5)) == "cold", "a cold body is still cold")

-- An older build simply has no climate accessor.
getClimateManager = nil
assert(N.rainIntensity() == nil, "a missing climate accessor is unknown")
assert(N.shelterReason(body(36.8)) == nil, "a missing sky moves nobody")

getClimateManager = previousClimate
print("Weather shelter PASS rain=true cold=true wet=true threshold=true unknown=true")
