local Renderer = {}
Renderer.__index = Renderer

local TILE = 512
local MAX_OUTLINES = 300

function Renderer.new(settings)
    local self = setmetatable({ settings = settings, objects = {}, drawn = 0 }, Renderer)
    self.box = ShapeData.new()
    self.box.positions = {
        Vector3.new(0, 0, 0), Vector3.new(1, 0, 0),
        Vector3.new(1, 0, 1), Vector3.new(0, 0, 1),
        Vector3.new(0, 1, 0), Vector3.new(1, 1, 0),
        Vector3.new(1, 1, 1), Vector3.new(0, 1, 1),
    }
    self.box.lines = { 0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7 }
    self.quadLines = { 0, 1, 1, 2, 2, 3, 3, 0 }
    return self
end

function Renderer:Clear()
    self.objects = {}
    self.drawn = 0
end

function Renderer:InRange(entity, player)
    if not entity or not entity.isValid or not player or not player.isValid then return false end
    local a, b = entity.coordGrid, player.coordGrid
    if a.level ~= b.level then return false end
    local dx, dz = a.x - b.x, a.z - b.z
    return dx * dx + dz * dz <= self.settings.values.distance ^ 2
end

-- Locations have no exposed model AABB. Use already-rotated tile dimensions,
-- anchored at the SW corner, and sample all corners to follow sloped ground.
function Renderer:Footprint(entity)
    local origin = entity.coordGrid:ToCoordFine(false).position
    local width, length = entity.width * TILE, entity.length * TILE
    if width <= 0 or length <= 0 then return nil end
    local positions = {}
    for _, point in ipairs({ { 0, 0 }, { width, 0 }, { width, length }, { 0, length } }) do
        local x, z = origin.x + point[1], origin.z + point[2]
        local height, available = World.GetGroundHeight(entity.coordGrid.level, x, z)
        if not available or height < 0 then return nil end
        positions[#positions + 1] = Vector3.new(x, height + 8, z)
    end
    return positions
end

function Renderer:RefreshObjects()
    self.objects = {}
    local values = self.settings.values
    local player = Player.GetEntity()
    if not values.enabled or not values.categories.objects.enabled or not player or not player.isValid then return end
    local candidates = LocList.ByDistance(player.coordGrid, values.distance, true)
    local nearby = {}
    for _, entity in ipairs(candidates) do
        if self:InRange(entity, player) and not entity.isHidden and not entity.isRoofRemoved
            and not self.settings.hiddenObjects[tostring(entity.configID)]
            and self.settings:MatchesName(entity.displayName) then
            local coord = entity.coordGrid
            local dx, dz = coord.x - player.coordGrid.x, coord.z - player.coordGrid.z
            nearby[#nearby + 1] = { entity = entity, distance = dx * dx + dz * dz }
        end
    end
    table.sort(nearby, function(a, b) return a.distance < b.distance end)
    for index = 1, math.min(#nearby, MAX_OUTLINES) do
        local entity = nearby[index].entity
        local positions = self:Footprint(entity)
        if positions then self.objects[#self.objects + 1] = { entity = entity, positions = positions } end
    end
end

function Renderer:DrawObjects()
    self.drawn = 0
    local values = self.settings.values
    if not values.enabled or not values.categories.objects.enabled then return end
    local player = Player.GetEntity()
    for _, object in ipairs(self.objects) do
        local entity = object.entity
        if self.drawn >= MAX_OUTLINES then break end
        if self:InRange(entity, player) and not entity.isHidden and not entity.isRoofRemoved then
            ShapeList.Draw{
                shapePositions = object.positions, shapeLines = self.quadLines,
                colour = values.categories.objects.colour,
                lineWidth = values.lineWidth, ignoreDepth = false,
            }
            self.drawn = self.drawn + 1
        end
    end
end

function Renderer:DrawEntity(event)
    local values = self.settings.values
    if not values.enabled or self.drawn >= MAX_OUTLINES then return true end
    local player = Player.GetEntity()
    local category, entity
    if event.entityType == EntityType.NPC then
        category, entity = "npcs", event.npcEntity
    elseif event.entityType == EntityType.OBJSTACK then
        category, entity = "items", event.objStackEntity
    elseif event.entityType == EntityType.PLAYER then
        entity = event.playerEntity
        if not entity or not entity.isValid or not player or not player.isValid then return true end
        category = entity.uid == player.uid and "self" or "players"
    else
        return true
    end
    if not values.categories[category].enabled or not self:InRange(entity, player) then return true end
    if category == "npcs" and self.settings.hiddenNPCs[tostring(entity.configID)] then return true end
    if category == "items" then
        local matches = self.settings.filter == ""
        for i = 1, entity.stackSize do
            local entry = entity:GetEntry(i)
            if entry and self.settings:MatchesName(entry.config.name) then matches = true; break end
        end
        if not matches then return true end
    elseif not self.settings:MatchesName(entity.displayName) then
        return true
    end
    local bounds = entity.aabb
    if not bounds or bounds.width <= 0 or bounds.height <= 0 or bounds.length <= 0 then return true end
    ShapeList.Draw{
        shapeData = self.box, translation = bounds.minimum, scale = bounds.dimensions,
        colour = values.categories[category].colour,
        lineWidth = values.lineWidth, ignoreDepth = false,
    }
    self.drawn = self.drawn + 1
    -- Never hide the entity or change the game's click zones.
    return true
end

return Renderer
