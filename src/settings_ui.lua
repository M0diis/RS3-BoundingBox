local Settings = require("src/settings")
local SettingsUI = {}
SettingsUI.__index = SettingsUI

function SettingsUI.new(settings, changed)
    return setmetatable({ settings = settings, changed = changed, surfaces = {} }, SettingsUI)
end

function SettingsUI:Save()
    self:ApplyResult(self.settings:Save())
end

function SettingsUI:ApplyResult(saved)
    self:Sync()
    self.changed()
    if saved == false then
        for _, surface in pairs(self.surfaces) do surface.message.content = "Could not save settings. Changes apply for this session." end
    end
end

function SettingsUI:Sync()
    local values = self.settings.values
    for _, surface in pairs(self.surfaces) do
        surface.enabled:SetSelected("enabled", values.enabled, false)
        surface.width:SetValue(values.lineWidth, false)
        surface.distance:SetValue(values.distance, false)
        if surface.filter:GetText() ~= values.nameFilter then surface.filter:SetText(values.nameFilter) end
        if surface.npcIDs:GetText() ~= values.hiddenNPCs then surface.npcIDs:SetText(values.hiddenNPCs) end
        if surface.objectIDs:GetText() ~= values.hiddenObjects then surface.objectIDs:SetText(values.hiddenObjects) end
        for _, category in ipairs(Settings.categories) do
            local value, controls = values.categories[category.key], surface.categories[category.key]
            controls.toggle:SetSelected(category.key, value.enabled, false)
            controls.colour:SetValue(value.colour, false)
        end
        surface.message.content = "Changes are saved automatically."
    end
end

function SettingsUI:Mount(key, parent)
    if self.surfaces[key] then self.surfaces[key].view:Destroy() end
    local view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
    local surface = { view = view, parent = parent, categories = {} }
    self.surfaces[key] = surface
    view:AddTitle("BoundingBox")
    view:AddText("Outline entity bounds and object footprints.")
    surface.message = view:AddText("Changes are saved automatically.")
    surface.enabled = view:AddCheckboxButton({ { text = "Enable outlines", value = "enabled", selected = self.settings.values.enabled } }, {
        onChange = function(_, _, _, selected)
            self.settings.values.enabled = selected
            self:Save()
        end,
    })
    view:AddTitle("Entity types")
    for _, definition in ipairs(Settings.categories) do
        local category = definition.key
        local value = self.settings.values.categories[category]
        local toggle = view:AddCheckboxButton({ { text = definition.label, value = category, selected = value.enabled } }, {
            width = 240,
            onChange = function(_, _, _, selected)
                self.settings.values.categories[category].enabled = selected
                self:Save()
            end,
        })
        local colour = view:AddColourPicker({
            inline = true, alphaSlider = true, value = value.colour,
            windowTitle = definition.label .. " colour", tooltip = "Change colour and opacity: " .. definition.label,
            onChange = function(_, selected)
                self.settings.values.categories[category].colour = selected
                self:Save()
            end,
        })
        surface.categories[category] = { toggle = toggle, colour = colour }
    end
    view:AddTitle("Display")
    view:AddText("Line width (1–10)")
    surface.width = view:AddSlider({ min = 1, max = 10, step = 1, value = self.settings.values.lineWidth,
        onChange = function(_, value) self.settings.values.lineWidth = value; self:Save() end })
    view:AddText("Draw distance in tiles (1–64)")
    surface.distance = view:AddSlider({ min = 1, max = 64, step = 1, value = self.settings.values.distance,
        onChange = function(_, value) self.settings.values.distance = value; self:Save() end })
    view:AddText("Only names containing (leave blank for all)")
    surface.filter = view:AddTextField({ text = self.settings.values.nameFilter, maxLength = 80,
        placeholder = "For example: goblin",
        tooltip = "One case-insensitive substring. Punctuation is treated literally.",
        onChange = function(_, _, text) self.settings.values.nameFilter = text; self:Save() end })
    view:AddTitle("Hide specific types")
    view:AddText("Comma-separated config IDs. Every instance of each listed type is excluded.")
    local function idsField(label, keyName)
        view:AddText(label)
        return view:AddTextField({ text = self.settings.values[keyName], maxLength = 1000,
            placeholder = "IDs separated by commas; blank hides none",
            onSubmit = function(_, text)
                local ids, problem = Settings.ParseIDs(text)
                if not ids then surface.message.content = problem; return end
                self.settings.values[keyName] = text
                self:Save()
            end,
        })
    end
    surface.npcIDs = idsField("Hide NPC IDs (press Enter to apply)", "hiddenNPCs")
    surface.objectIDs = idsField("Hide object IDs (press Enter to apply)", "hiddenObjects")
    view:AddSimpleButton("Reset settings", function()
        self:ApplyResult(self.settings:Reset())
    end)
    view:AddText("Objects use tile footprints; other categories use API bounding boxes. These are not exact model clickboxes. Hidden objects and removed roofs are skipped; outlines respect world depth.")
    return surface
end

function SettingsUI:Resize()
    for _, surface in pairs(self.surfaces) do
        local width, height = surface.parent.width, surface.parent.height
        if surface.widthAvailable ~= width or surface.heightAvailable ~= height then
            surface.view:SetSize(width, height)
            surface.widthAvailable, surface.heightAvailable = width, height
        end
    end
end

function SettingsUI:Destroy()
    for _, surface in pairs(self.surfaces) do surface.view:Destroy() end
    self.surfaces = {}
end

return SettingsUI
