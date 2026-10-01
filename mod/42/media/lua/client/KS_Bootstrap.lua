local KnoxSurvivors = rawget(_G, "KnoxSurvivors") or {}
_G.KnoxSurvivors = KnoxSurvivors

KnoxSurvivors.VERSION = "0.3.0-rc1"

local function onGameStart()
    print("[KnoxSurvivors] Lua bootstrap loaded version=" .. KnoxSurvivors.VERSION)
end

Events.OnGameStart.Add(onGameStart)
