local Settings = require("src/settings")
local Renderer = require("src/renderer")
local SettingsUI = require("src/settings_ui")

assert(prettyui and prettyui.SimpleView and prettyui.ColourPicker,
    "BoundingBox requires PrettyUI with SimpleView and ColourPicker support.")

local settings = Settings.new(PersistentDB)
local renderer = Renderer.new(settings)
local refreshNeeded = true
local settingsUI = SettingsUI.new(settings, function()
    renderer:Clear()
    refreshNeeded = true
end)
local lastError

local function reportError(problem)
    local message = tostring(problem)
    if message ~= lastError then
        print("BoundingBox: " .. message)
        lastError = message
    end
end

Event.SettingsLayerReady.Subscribe("boundingbox.settings", function(event)
    settingsUI:Mount("settings", event.component)
end)
Event.ContentLayerReady.Subscribe("boundingbox.content", function(event)
    settingsUI:Mount("content", event.component)
end)
Event.Logic.Subscribe("boundingbox.logic", function(event)
    if event.logicTick % 10 == 0 then settingsUI:Resize() end
    if not Player.IsAvailable() then renderer:Clear(); return end
    if refreshNeeded or event.logicTick % 10 == 0 then
        refreshNeeded = false
        local ok, problem = pcall(function() renderer:RefreshObjects() end)
        if not ok then renderer:Clear(); reportError(problem) end
    end
end)
Event.Draw.Subscribe("boundingbox.draw", function()
    if not Player.IsAvailable() then renderer:Clear(); return end
    local ok, problem = pcall(function() renderer:DrawObjects() end)
    if not ok then reportError(problem) end
end)
Event.EntityDraw.Subscribe("boundingbox.entity", function(event)
    if Player.IsAvailable() then
        local ok, problem = pcall(function() renderer:DrawEntity(event) end)
        if not ok then reportError(problem) end
    end
    return true
end)
Event.GameStateChanged.Subscribe("boundingbox.state", function()
    renderer:Clear()
    refreshNeeded = true
end)

function PluginShutdown()
    Event.SettingsLayerReady.Unsubscribe("boundingbox.settings")
    Event.ContentLayerReady.Unsubscribe("boundingbox.content")
    Event.Logic.Unsubscribe("boundingbox.logic")
    Event.Draw.Unsubscribe("boundingbox.draw")
    Event.EntityDraw.Unsubscribe("boundingbox.entity")
    Event.GameStateChanged.Unsubscribe("boundingbox.state")
    settingsUI:Destroy()
    renderer:Clear()
end
