local S = assert(KnoxSettings, "settings owner is loaded")
local previous = SandboxVars
SandboxVars = nil
assert(S.survivorStrength() == 2, "missing sandbox defaults to Normal")
SandboxVars = { KnoxSurvivors = {} }
assert(S.survivorStrength() == 2, "missing key defaults to Normal")
for tier = 1, 4 do
    SandboxVars.KnoxSurvivors.SurvivorStrength = tier
    assert(S.survivorStrength() == tier, "each strength setting is read from the current world")
end
for _, invalid in ipairs({0, 5, 1.5, "3", false}) do
    SandboxVars.KnoxSurvivors.SurvivorStrength = invalid
    assert(S.survivorStrength() == 2, "invalid setting defaults to Normal")
end
SandboxVars = previous
