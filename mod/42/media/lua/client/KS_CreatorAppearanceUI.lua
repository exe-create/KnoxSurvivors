-- Native appearance controls for the existing creator window. The roster model
-- owns the data, the window owns selection and saving, and these callbacks only
-- edit that selected record. No player descriptor or world body is borrowed.
local AppearanceUI = {}
_G.KnoxCreatorAppearanceUI = AppearanceUI

function AppearanceUI.install(Panel, Window, Creator, UILayout)
    -- All mutations land on the selected roster record; no MainScreen descriptor is
    -- borrowed. Refreshing a dropdown never calls its selection callback.
    function Panel.fieldOptions(kind, person, defs)
        local options = {}
        if kind == "sex" then return {{id=false,label="Male"},{id=true,label="Female"}} end
        if kind == "hair" or kind == "beard" then
            local values = kind == "hair" and Panel.hairOptions(person.female) or Panel.beardOptions(person.female)
            for _, value in ipairs(values) do
                local label = value == "" and "None" or value
                if value ~= "" and getTextOrNull then
                    label = getTextOrNull((kind == "hair" and "IGUI_Hair_" or "IGUI_Beard_") .. value) or label
                end
                options[#options + 1] = {id=value,label=label}
            end
            return options
        end
        if kind == "faction" then
            options[1] = {id="solo",label="Independent survivor"}
            local current = person and person.faction
            local found = current == "solo"
            for _, entry in ipairs(defs or {}) do
                options[#options + 1] = entry
                if entry.id == current then found = true end
            end
            if current and not found then
                options[#options + 1] = {id=current,label=Creator.factionLabel(current,defs) .. " (saved group)"}
            end
            return options
        end
        local lists = {look=Creator.LOOKS,profession=Creator.PROFESSIONS,kit=Creator.KITS,pack=Creator.PACKS}
        return lists[kind] or {}
    end

    function Window:onFieldSelected(combo)
        local person = self:selected()
        if not person or self.templateRoster or self.refreshingFields or self.group.readOnly then return end
        local value = combo:getOptionData(combo.selected)
        local kind = combo.knoxKind
        if kind == "sex" then
            person.female = value == true
            local valid = false
            for _, hair in ipairs(Panel.hairOptions(person.female)) do if hair == person.hair then valid = true end end
            if not valid then person.hair = "" end
            if person.female then person.beard = "" end
        elseif kind == "profession" then
            person.profession = value
            local capabilities = rawget(_G, "KnoxSurvivorCapabilities")
            if person.traits ~= nil and capabilities and capabilities.creatorTraitChoices then
                person.traits = capabilities.creatorTraitChoices(value, person.traits) or person.traits
            end
        elseif kind == "faction" then
            person.faction = value; self.selectedFactionId = value
        else person[kind] = value end
        self.dirty = true
        self:refresh()
    end

    function Window:refreshFields(person)
        self.refreshingFields = true
        self.styleChoices = self.styleChoices or {}
        for _, combo in ipairs(self.fieldCombos or {}) do
            local kind = combo.knoxKind
            local value = person and person[kind]
            if kind == "sex" and person then value = person.female == true end
            if kind == "faction" and person then value = Creator.personFactionId(person, self.group) end
            local choices = {{id="",label="Choose a person"}}
            if person then
                if kind == "hair" or kind == "beard" then
                    -- Installed styles stay fixed while this editor is open. Keep
                    -- separate male/female choices; unrelated edits need no API scan.
                    local key = kind .. (person.female and ":female" or ":male")
                    choices = self.styleChoices[key]
                    if not choices then
                        choices = Panel.fieldOptions(kind, person, self.group.defs)
                        self.styleChoices[key] = choices
                    end
                else choices = Panel.fieldOptions(kind, person, self.group.defs) end
            end
            local selected
            for index, entry in ipairs(choices) do if entry.id == value then selected = index end end
            local extra = person and value ~= nil and selected == nil
                and {id=value,label=tostring(value) .. " (unavailable)"} or nil
            local count = #choices + (extra and 1 or 0)
            local previous = combo.knoxChoices
            local changed = previous == nil or #previous ~= count
            for index = 1, count do
                local entry = choices[index] or extra
                local old = previous and previous[index]
                if not old or old.id ~= entry.id or old.label ~= (entry.label or "Unnamed choice") then changed = true end
            end
            if changed then
                combo:clear()
                combo.knoxChoices = {}
                for index = 1, count do
                    local entry = choices[index] or extra
                    local label = entry.label or "Unnamed choice"
                    combo:addOptionWithData(label, entry.id)
                    combo.knoxChoices[index] = {id=entry.id,label=label}
                end
            end
            combo.selected = selected or (extra and count or 1)
            combo.disabled = person == nil or self.templateRoster ~= nil or self.group.readOnly == true or (kind == "beard" and person.female)
        end
        self.refreshingFields = false
    end

    function Window:closeColourPicker()
        if self.colourPicker then
            self.colourPicker:setVisible(false)
            self.colourPicker:removeFromUIManager()
            self.colourPicker = nil
        end
    end

    function Window:openColourPicker(kind, person, button)
        self:closeColourPicker()
        local colors = {}
        if kind == "skin" then colors = Creator.SKIN_COLOURS
        else
            for _, entry in ipairs(Creator.HAIR_COLOURS) do
                local rgb = Creator.colourOf(entry.id)
                colors[#colors + 1] = {r=rgb[1],g=rgb[2],b=rgb[3]}
            end
        end
        local picker = ISColorPicker:new(0, 0, nil)
        picker:initialise()
        picker.keepOnScreen = true
        picker.pickedTarget = self
        picker:setColors(colors, #colors, 1)
        picker.index = kind == "skin" and ((Creator.skinIndex(person.skin) or 0) + 1)
            or Creator.colourIndexOf(person.hairColour)
        local screenW, screenH = UILayout.screenSize()
        picker:setX(math.max(0, math.min(button:getAbsoluteX(), screenW - picker.width)))
        picker:setY(math.max(0, math.min(button:getAbsoluteY() + button.height, screenH - picker.height)))
        picker:setPickedFunc(function(owner, color, mouseUp)
            if owner:selected() ~= person or owner.templateRoster then owner:closeColourPicker(); return end
            if kind == "skin" then person.skin = picker.index - 1
            else person.hairColour = Creator.HAIR_COLOURS[picker.index].id end
            owner.dirty = true; owner:refresh()
            if mouseUp then owner:closeColourPicker() end
        end)
        self.colourPicker = picker
        picker:addToUIManager(); picker:setCapture(true); picker:bringToTop()
    end

end

return AppearanceUI
