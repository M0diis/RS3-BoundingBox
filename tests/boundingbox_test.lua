package.path = PLUGIN_ROOT .. "/?.lua;" .. package.path
local total = 0
local function test(name, run)
    local ok, problem = pcall(run)
    if not ok then error(name .. ": " .. tostring(problem), 0) end
    total = total + 1
    print("PASS " .. name)
end
local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = clone(v) end
    return copy
end
local function database(initial)
    return {
        stored = initial, writes = 0,
        GetStructuredData = function(self) return clone(self.stored) end,
        SetStructuredData = function(self, _, value)
            self.stored = clone(value); self.writes = self.writes + 1; return true
        end,
    }
end

Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
ShapeData = { new = function() return {} end }
local calls = {}
ShapeList = { Draw = function(options) calls[#calls + 1] = options end }
EntityType = { NPC = 1, PLAYER = 2, OBJSTACK = 3 }
local function coord(x, z, level)
    return { x = x, z = z, level = level or 0,
        ToCoordFine = function(self, centred)
            local offset = centred and 256 or 0
            return { position = Vector3.new(self.x * 512 + offset, 0, self.z * 512 + offset) }
        end }
end
local function entity(x, z, level)
    return {
        isValid = true, uid = 10, configID = 42, displayName = "Goblin",
        coordGrid = coord(x or 1, z or 1, level), width = 2, length = 3,
        aabb = { minimum = Vector3.new(500, 30, 700), dimensions = Vector3.new(200, 500, 300),
            width = 200, height = 500, length = 300 },
    }
end
local player = entity(0, 0)
player.uid = 99
local available = true
Player = { GetEntity = function() return player end, IsAvailable = function() return available end }
World = { GetGroundHeight = function(_, x, z) return 100 + x / 512 + z / 512, true end }
local locations = {}
LocList = { ByDistance = function() return locations end }
local Settings = require("src/settings")
local Renderer = require("src/renderer")
local settings, renderer
local function reset()
    settings = Settings.new(database())
    renderer = Renderer.new(settings)
    calls, locations = {}, {}
    available = true
end

test("corrupt persisted values use defaults and numeric bounds", function()
    local s = Settings.new(database({ enabled = "false", distance = 1000, lineWidth = -2,
        nameFilter = {}, hiddenNPCs = "nope", categories = { npcs = { enabled = false, colour = 0/0 } } }))
    eq(s.values.enabled, true); eq(s.values.distance, 64); eq(s.values.lineWidth, 1)
    eq(s.values.hiddenNPCs, ""); eq(s.values.nameFilter, "")
    eq(s.values.categories.npcs.enabled, false); eq(s.values.categories.npcs.colour, 0xFFCB66FF)
end)
test("saved preferences survive loading and reset", function()
    local db = database()
    local s = Settings.new(db)
    s.values.categories.objects.colour = 0x44556677
    s.values.hiddenNPCs = "42, 005"
    s.values.enabled = false
    s:Save()
    local loaded = Settings.new(db)
    eq(loaded.values.categories.objects.colour, 0x44556677)
    eq(loaded.hiddenNPCs["5"], true); eq(loaded.values.enabled, false)
    loaded:Reset()
    eq(loaded.values.enabled, true); eq(next(loaded.hiddenNPCs), nil)
end)
test("ID lists validate complete tokens", function()
    eq(Settings.ParseIDs(" 42,005 ")["5"], true)
    eq(next(Settings.ParseIDs("  ")), nil)
    for _, invalid in ipairs({ "42,", "1,,2", "-1", "1.5", "1e3", "a", "2147483648" }) do
        eq(Settings.ParseIDs(invalid), nil)
    end
end)
test("names use a literal case-insensitive substring", function()
    local s = Settings.new(database())
    s.values.nameFilter = "GOB["; s:Compile()
    eq(s:MatchesName("Gob[lin"), true)
    eq(s:MatchesName("Goblin"), false)
    eq(s:MatchesName(nil), false)
end)
test("NPC bounds draw at API world minimum without extra translation", function()
    reset()
    local npc = entity()
    eq(renderer:DrawEntity({ entityType = EntityType.NPC, npcEntity = npc }), true)
    eq(#calls, 1); eq(calls[1].translation, npc.aabb.minimum)
    eq(calls[1].scale, npc.aabb.dimensions); eq(#calls[1].shapeData.lines, 24)
    eq(calls[1].ignoreDepth, false)
end)
test("category colours, alpha and line width reach drawing", function()
    reset()
    settings.values.categories.npcs.colour = 0xABCDEF44
    settings.values.lineWidth = 7
    renderer:DrawEntity({ entityType = EntityType.NPC, npcEntity = entity() })
    eq(calls[1].colour, 0xABCDEF44); eq(calls[1].lineWidth, 7)
end)
test("invalid, distant and different-floor NPCs do not draw", function()
    reset()
    local invalid = entity(); invalid.isValid = false
    for _, npc in ipairs({ invalid, entity(30, 0), entity(1, 1, 1) }) do
        eq(renderer:DrawEntity({ entityType = EntityType.NPC, npcEntity = npc }), true)
    end
    eq(#calls, 0)
end)
test("master toggle, category toggle and per-ID exclusions work", function()
    reset()
    local event = { entityType = EntityType.NPC, npcEntity = entity() }
    settings.values.enabled = false; renderer:DrawEntity(event)
    settings.values.enabled = true; settings.values.categories.npcs.enabled = false; renderer:DrawEntity(event)
    settings.values.categories.npcs.enabled = true; settings.values.hiddenNPCs = "42"; settings:Compile()
    renderer:DrawEntity(event)
    eq(#calls, 0)
end)
test("self and other-player toggles are independent", function()
    reset()
    settings.values.categories.self.enabled = true
    renderer:DrawEntity({ entityType = EntityType.PLAYER, playerEntity = player })
    renderer:DrawEntity({ entityType = EntityType.PLAYER, playerEntity = entity() })
    eq(#calls, 1)
    settings.values.categories.self.enabled = false; settings.values.categories.players.enabled = true
    renderer:DrawEntity({ entityType = EntityType.PLAYER, playerEntity = player })
    renderer:DrawEntity({ entityType = EntityType.PLAYER, playerEntity = entity() })
    eq(#calls, 2)
end)
test("ground stack filter matches any item in the stack", function()
    reset()
    settings.values.nameFilter = "logs"; settings:Compile()
    local stack = entity()
    stack.stackSize = 2
    stack.GetEntry = function(_, index) return { config = { name = index == 2 and "Oak logs" or "Coins" } } end
    renderer:DrawEntity({ entityType = EntityType.OBJSTACK, objStackEntity = stack })
    eq(#calls, 1)
    settings.values.nameFilter = "sword"; settings:Compile()
    renderer:DrawEntity({ entityType = EntityType.OBJSTACK, objStackEntity = stack })
    eq(#calls, 1)
end)
test("unknown event types, absent entities and missing bounds are safe", function()
    reset()
    eq(renderer:DrawEntity({ entityType = 999 }), true)
    eq(renderer:DrawEntity({ entityType = EntityType.NPC }), true)
    local npc = entity(); npc.aabb = nil
    eq(renderer:DrawEntity({ entityType = EntityType.NPC, npcEntity = npc }), true)
    eq(#calls, 0)
end)
test("object footprint uses rotated dimensions once and follows slopes", function()
    reset()
    local loc = entity(2, 3)
    loc.width, loc.length, loc.rotationType = 3, 2, 1
    locations = { loc }
    renderer:RefreshObjects(); renderer:DrawObjects()
    eq(#calls, 1)
    local points = calls[1].shapePositions
    eq(points[1].x, 1024); eq(points[1].z, 1536)
    eq(points[2].x - points[1].x, 1536)
    eq(points[3].z - points[2].z, 1024)
    eq(points[1].y, 113); eq(points[3].y, 118)
end)
test("removed, roof-hidden and invalid cached objects stop drawing immediately", function()
    reset()
    local a, b, c = entity(), entity(), entity()
    locations = { a, b, c }; renderer:RefreshObjects()
    a.isHidden = true; b.isRoofRemoved = true; c.isValid = false
    renderer:DrawObjects(); eq(#calls, 0)
end)
test("object ID, name and floor filters are applied before caching", function()
    reset()
    settings.values.hiddenObjects = "42"; settings:Compile()
    locations = { entity() }; renderer:RefreshObjects(); eq(#renderer.objects, 0)
    settings.values.hiddenObjects = ""; settings.values.nameFilter = "bank"; settings:Compile()
    renderer:RefreshObjects(); eq(#renderer.objects, 0)
    settings.values.nameFilter = ""; settings:Compile()
    locations = { entity(1, 1, 2) }; renderer:RefreshObjects(); eq(#renderer.objects, 0)
end)
test("unavailable ground does not fabricate a footprint", function()
    reset()
    local original = World.GetGroundHeight
    World.GetGroundHeight = function() return -1, false end
    locations = { entity() }; renderer:RefreshObjects(); eq(#renderer.objects, 0)
    World.GetGroundHeight = original
end)
test("frame budget bounds drawing and resets next frame", function()
    reset()
    for _ = 1, 301 do locations[#locations + 1] = entity() end
    renderer:RefreshObjects(); renderer:DrawObjects()
    renderer:DrawEntity({ entityType = EntityType.NPC, npcEntity = entity() })
    eq(#calls, 300)
    settings.values.categories.objects.enabled = false
    renderer:DrawObjects()
    renderer:DrawEntity({ entityType = EntityType.NPC, npcEntity = entity() })
    eq(#calls, 301)
end)

-- API-shaped PrettyUI doubles: signatures match upstream 1.2.1. These exercise
-- user callbacks and cross-panel state, not rendering or native layout.
local createdViews = {}
local function view()
    local v = { controls = {}, texts = {}, buttons = {} }
    function v:AddTitle(text) self.texts[#self.texts + 1] = text end
    function v:AddText(text)
        local label = { content = text }; self.texts[#self.texts + 1] = label; return label
    end
    function v:AddCheckboxButton(choices, options)
        local c = { selected = choices[1].selected, key = choices[1].value, options = options }
        function c:SetSelected(_, selected) self.selected = selected end
        function c:Change(selected) self.options.onChange(self, {}, self.key, selected) end
        self.controls[#self.controls + 1] = c; return c
    end
    function v:AddColourPicker(options)
        local c = { value = options.value, options = options }
        function c:SetValue(value) self.value = value end
        self.controls[#self.controls + 1] = c; return c
    end
    v.AddSlider = v.AddColourPicker
    function v:AddTextField(options)
        local c = { text = options.text, options = options }
        function c:GetText() return self.text end
        function c:SetText(text) self.text = text end
        function c:Submit(text) self.text = text; self.options.onSubmit(self, text) end
        function c:Change(text) self.text = text; self.options.onChange(self, "change", text) end
        self.controls[#self.controls + 1] = c; return c
    end
    function v:AddSimpleButton(label, action) self.buttons[label] = action end
    function v:SetSize(width, height) self.width, self.height = width, height end
    function v:Destroy() self.destroyed = true end
    createdViews[#createdViews + 1] = v
    return v
end
prettyui = { SimpleView = { new = function() return view() end }, ColourPicker = {} }
local SettingsUI = require("src/settings_ui")
test("PrettyUI callbacks persist and synchronize both panels", function()
    local db = database()
    local s = Settings.new(db)
    local changed = 0
    local gui = SettingsUI.new(s, function() changed = changed + 1 end)
    local a = gui:Mount("settings", { width = 420, height = 600 })
    local b = gui:Mount("content", { width = 320, height = 400 })
    a.categories.npcs.toggle:Change(false)
    eq(s.values.categories.npcs.enabled, false); eq(b.categories.npcs.toggle.selected, false)
    a.categories.npcs.colour.options.onChange(nil, 0x12345677)
    eq(b.categories.npcs.colour.value, 0x12345677)
    a.width.options.onChange(nil, 6); eq(b.width.value, 6)
    a.filter:Change("Gob["); eq(b.filter:GetText(), "Gob[")
    a.npcIDs:Submit("42, 5"); eq(s.hiddenNPCs["42"], true)
    eq(b.npcIDs:GetText(), "42, 5"); eq(db.writes, 5); eq(changed, 5)
    a.npcIDs:Submit("42, wrong")
    eq(db.writes, 5); assert(a.message.content:find("numeric"))
    a.view.buttons["Reset settings"]()
    eq(b.categories.npcs.toggle.selected, true); eq(b.npcIDs:GetText(), "")
    gui:Destroy(); eq(a.view.destroyed, true); eq(b.view.destroyed, true)
end)
test("remount replaces the previous view and resize relayouts", function()
    local gui = SettingsUI.new(Settings.new(database()), function() end)
    local parent = { width = 400, height = 500 }
    local a = gui:Mount("settings", parent)
    local b = gui:Mount("settings", parent)
    eq(a.view.destroyed, true)
    parent.width = 300; gui:Resize(); eq(b.view.width, 300)
    parent.height = 200; gui:Resize(); eq(b.view.height, 200)
    gui:Destroy()
end)
test("persistence failure is visible", function()
    local db = database(); db.SetStructuredData = function() return false end
    local gui = SettingsUI.new(Settings.new(db), function() end)
    local a = gui:Mount("settings", { width = 400, height = 500 })
    a.enabled:Change(false)
    assert(a.message.content:find("Could not save"))
    a.view.buttons["Reset settings"]()
    assert(a.message.content:find("Could not save"))
    eq(a.enabled.selected, true)
    gui:Destroy()
end)

test("entrypoint draws, survives failures, and removes every subscription", function()
    local handlers = {}
    Event = setmetatable({}, { __index = function(self, name)
        local event = {
            Subscribe = function(key, callback) handlers[name .. key] = callback end,
            Unsubscribe = function(key) handlers[name .. key] = nil end,
        }
        rawset(self, name, event); return event
    end })
    PersistentDB = database()
    available, locations, calls = true, { entity() }, {}
    dofile(PLUGIN_ROOT .. "/main.lua")
    local parent = { width = 400, height = 500 }
    handlers["SettingsLayerReadyboundingbox.settings"]({ component = parent })
    local settingsView = createdViews[#createdViews]
    handlers["ContentLayerReadyboundingbox.content"]({ component = { width = 350, height = 400 } })
    handlers["Logicboundingbox.logic"]({ logicTick = 10 })
    handlers["Drawboundingbox.draw"]({})
    eq(#calls, 1)
    local callback = handlers["EntityDrawboundingbox.entity"]
    eq(callback({ entityType = EntityType.NPC, npcEntity = entity() }), true)
    eq(#calls, 2)
    local original = ShapeList.Draw
    ShapeList.Draw = function() error("synthetic draw failure") end
    eq(callback({ entityType = EntityType.NPC, npcEntity = entity() }), true)
    ShapeList.Draw = original
    available = false
    parent.width = 250
    handlers["Logicboundingbox.logic"]({ logicTick = 20 })
    eq(settingsView.width, 250)
    handlers["Drawboundingbox.draw"]({})
    eq(#calls, 2)
    available = true
    handlers["GameStateChangedboundingbox.state"]({})
    PluginShutdown()
    eq(next(handlers), nil)
    eq(createdViews[#createdViews].destroyed, true)
end)
print(string.format("%d behavioral checks passed", total))
