-- Live play 2026-11-10 (42.22.2, f:5401/f:8701) showed the exposed
-- character:applyTraits call raise on return inside applyIdentity
-- (ReturnValues.put:61 via LuaJavaInvoker.call:185), aborting a survivor's
-- activation mid-identity. The owner is fail closed: a raise is a named
-- refusal and never a silent half-identity, and a clean identity is returned
-- unchanged. The real production function is loaded by identity_apply_source
-- (section extraction, same idiom as the controller TUNE windows).
local identity = assert(rawget(_G, "knoxIdentityFunctions"), "identity owner missing")
assert(type(identity.applyIdentity) == "function", "applyIdentity missing")

local saved = {
    CharacterProfessionDefinition = rawget(_G, "CharacterProfessionDefinition"),
    CharacterTraitDefinition = rawget(_G, "CharacterTraitDefinition"),
}
local professionDefinition = { getType = function() return "unemployed" end }
local traitDefinition = { getType = function() return "TestTrait" end }
local professions = { size = function() return 1 end, get = function(_, index)
    return index == 0 and professionDefinition or nil
end }
local traits = { size = function() return 1 end, get = function(_, index)
    return index == 0 and traitDefinition or nil
end }
CharacterProfessionDefinition = { getProfessions = function() return professions end }
CharacterTraitDefinition = { getTraits = function() return traits end }

local profile = { professionId = "unemployed", traitIds = { "TestTrait" } }
local known = { clear = function() end, add = function() end }
local function baseCharacter(applyTraits)
    return {
        getDescriptor = function()
            return { setCharacterProfession = function() end,
                setProfessionSkills = function() end }
        end,
        getCharacterTraits = function()
            return { getKnownTraits = function() return known end }
        end,
        applyTraits = applyTraits,
    }
end

-- Scenario 1: the exposed applyTraits raises on return -> named refusal.
local raising = baseCharacter(function() error("kahlua_invoker_return_path_npe") end)
local ok, evidence = identity.applyIdentity(raising, profile, false)
assert(ok == false, "a raise at the traits boundary must refuse, not apply")
assert(type(evidence) == "string"
        and string.find(evidence, "apply_traits_runtime_error=", 1, true) ~= nil,
    "named receipt expected, got " .. tostring(evidence))
assert(string.find(evidence, "kahlua_invoker_return_path_npe", 1, true) ~= nil,
    "the raise text must survive in the receipt, got " .. tostring(evidence))

-- Scenario 2: a clean identity is unchanged -> applied, definition returned.
local clean = baseCharacter(function() end)
clean.applyProfessionRecipes = function() end
clean.applyCharacterTraitsRecipes = function() end
local applied, definition = identity.applyIdentity(clean, profile, false)
assert(applied == true, "a clean identity must apply, got " .. tostring(applied))
assert(definition == professionDefinition,
    "the returned profession must be the matched definition object")

CharacterProfessionDefinition = saved.CharacterProfessionDefinition
CharacterTraitDefinition = saved.CharacterTraitDefinition
