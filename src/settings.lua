local Settings = {}
Settings.__index = Settings

Settings.categories = {
    { key = "objects", label = "Objects (tile footprints)", colour = 0x4FC3F7FF, enabled = true },
    { key = "npcs", label = "NPCs", colour = 0xFFCB66FF, enabled = true },
    { key = "items", label = "Ground-item stacks", colour = 0x75DB9AFF, enabled = true },
    { key = "players", label = "Other players", colour = 0xC49CFFFF, enabled = false },
    { key = "self", label = "Your character", colour = 0xFFFFFFFF, enabled = false },
}

local function integer(value, fallback, minimum, maximum)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

local function boolean(value, fallback)
    if type(value) == "boolean" then return value end
    return fallback
end

-- Deliberately plain text, never a Lua pattern supplied by a user.
function Settings.ParseIDs(text)
    local ids = {}
    if type(text) ~= "string" then return nil, "Enter comma-separated numeric IDs." end
    if #text > 1000 then return nil, "Use at most 1,000 characters." end
    if text:match("^%s*$") then return ids end
    for token in (text .. ","):gmatch("(.-),") do
        token = token:match("^%s*(.-)%s*$")
        if not token:match("^%d+$") or tonumber(token) > 2147483647 then
            return nil, "Use numeric IDs separated by commas, for example 1, 2, 3."
        end
        ids[tostring(math.floor(tonumber(token)))] = true
    end
    return ids
end

function Settings.Defaults()
    local values = {
        enabled = true, lineWidth = 2, distance = 20,
        nameFilter = "", hiddenNPCs = "", hiddenObjects = "", categories = {},
    }
    for _, category in ipairs(Settings.categories) do
        values.categories[category.key] = { enabled = category.enabled, colour = category.colour }
    end
    return values
end

function Settings.new(db)
    local self = setmetatable({ db = db, values = Settings.Defaults() }, Settings)
    local stored = db:GetStructuredData("boundingbox.settings.v1")
    if type(stored) == "table" then
        local values = self.values
        values.enabled = boolean(stored.enabled, values.enabled)
        values.lineWidth = integer(stored.lineWidth, values.lineWidth, 1, 10)
        values.distance = integer(stored.distance, values.distance, 1, 64)
        if type(stored.nameFilter) == "string" then values.nameFilter = stored.nameFilter:sub(1, 80) end
        for _, key in ipairs({ "hiddenNPCs", "hiddenObjects" }) do
            if Settings.ParseIDs(stored[key]) then values[key] = stored[key] end
        end
        if type(stored.categories) == "table" then
            for key, category in pairs(values.categories) do
                local saved = stored.categories[key]
                if type(saved) == "table" then
                    category.enabled = boolean(saved.enabled, category.enabled)
                    category.colour = integer(saved.colour, category.colour, 0, 0xFFFFFFFF)
                end
            end
        end
    end
    self:Compile()
    return self
end

function Settings:Compile()
    self.filter = self.values.nameFilter:lower()
    self.hiddenNPCs = Settings.ParseIDs(self.values.hiddenNPCs)
    self.hiddenObjects = Settings.ParseIDs(self.values.hiddenObjects)
end

function Settings:Save()
    self:Compile()
    return self.db:SetStructuredData("boundingbox.settings.v1", self.values)
end

function Settings:Reset()
    self.values = Settings.Defaults()
    return self:Save()
end

function Settings:MatchesName(name)
    return self.filter == "" or (name or ""):lower():find(self.filter, 1, true) ~= nil
end

return Settings
