local addonName, addon = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TEXTURES = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
local FONT = "Fonts\\ARIALN.TTF"
local min, max = math.min, math.max

local function number(value, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function clamp(value, low, high, fallback)
    return min(high, max(low, number(value, fallback)))
end

function addon:GetPalette()
    local settings = self:GetSettings()
    local opacity = clamp(settings.opacity, 0, 1, 0.94)
    local accent = type(settings.accent) == "table" and settings.accent or {}
    local palette
    if settings.theme == "light" then
        palette = {
            bg = { 0.94, 0.95, 0.97, opacity },
            panel = { 0.985, 0.989, 0.997, opacity },
            text = { 0.12, 0.14, 0.18, 1 },
            muted = { 0.39, 0.43, 0.49, 1 },
            border = { 1, 1, 1, 0.88 * opacity },
        }
    else
        palette = {
            bg = { 0.055, 0.067, 0.088, opacity },
            panel = { 0.095, 0.110, 0.138, opacity },
            text = { 0.95, 0.965, 0.985, 1 },
            muted = { 0.61, 0.65, 0.71, 1 },
            border = { 1, 1, 1, 0.16 * opacity },
        }
    end
    palette.accent = {
        clamp(accent.r or accent[1], 0, 1, 0.32),
        clamp(accent.g or accent[2], 0, 1, 0.65),
        clamp(accent.b or accent[3], 0, 1, 1),
        1,
    }
    return palette
end

-- The four corners sample a circular mask; the intervening rectangles keep
-- every edge straight, including while the dock changes its aspect ratio.
local slices = {
    { "topLeft", 0, 0.5, 0, 0.5 },
    { "top", 0.5, 0.5, 0, 0.5 },
    { "topRight", 0.5, 1, 0, 0.5 },
    { "left", 0, 0.5, 0.5, 0.5 },
    { "center", 0.5, 0.5, 0.5, 0.5 },
    { "right", 0.5, 1, 0.5, 0.5 },
    { "bottomLeft", 0, 0.5, 0.5, 1 },
    { "bottom", 0.5, 0.5, 0.5, 1 },
    { "bottomRight", 0.5, 1, 0.5, 1 },
}

local function createLayer(frame, surface, sublevel, soft)
    local layer = {}
    for index, slice in ipairs(slices) do
        local texture = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
        local corner = index == 1 or index == 3 or index == 7 or index == 9
        if corner or (soft and index ~= 5) then
            texture:SetTexture(TEXTURES .. (soft and "Shadow.tga" or "Circle.tga"))
            texture:SetTexCoord(slice[2], slice[3], slice[4], slice[5])
        else
            texture:SetTexture(WHITE)
        end
        texture:SetBlendMode("BLEND")
        layer[slice[1]] = texture
        layer[#layer + 1] = texture
        surface.textures[#surface.textures + 1] = texture
    end
    return layer
end

local function colorLayer(layer, color)
    for _, texture in ipairs(layer) do
        texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function place(surface, texture, x, y, width, height)
    texture.lumenActive = width > 0 and height > 0
    if texture.lumenActive then
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", surface.frame, "TOPLEFT", x, y)
        texture:SetSize(width, height)
    end
    if texture.lumenActive and surface.shown then texture:Show() else texture:Hide() end
end

local function layoutLayer(surface, layer, x, y, width, height, radius)
    radius = max(0, min(radius, width / 2, height / 2))
    local middleWidth, middleHeight = max(0, width - radius * 2), max(0, height - radius * 2)
    place(surface, layer.topLeft, x, y, radius, radius)
    place(surface, layer.top, x + radius, y, middleWidth, radius)
    place(surface, layer.topRight, x + width - radius, y, radius, radius)
    place(surface, layer.left, x, y - radius, radius, middleHeight)
    place(surface, layer.center, x + radius, y - radius, middleWidth, middleHeight)
    place(surface, layer.right, x + width - radius, y - radius, radius, middleHeight)
    place(surface, layer.bottomLeft, x, y - height + radius, radius, radius)
    place(surface, layer.bottom, x + radius, y - height + radius, middleWidth, radius)
    place(surface, layer.bottomRight, x + width - radius, y - height + radius, radius, radius)
end

local function layoutSurface(surface)
    if surface.updating then return end
    surface.updating = true
    local width = max(0, number(surface.frame:GetWidth(), 0))
    local height = max(0, number(surface.frame:GetHeight(), 0))
    if width == 0 or height == 0 then
        for _, texture in ipairs(surface.textures) do
            texture.lumenActive = false
            texture:Hide()
        end
    else
        local radius = min(surface.radius, width / 2, height / 2)
        local inset = min(0.75, width / 4, height / 4)
        layoutLayer(surface, surface.shadowOuter, -6, 2, width + 12, height + 12, radius + 6)
        layoutLayer(surface, surface.shadowInner, -2, 0, width + 4, height + 4, radius + 2)
        layoutLayer(surface, surface.outline, 0, 0, width, height, radius)
        layoutLayer(surface, surface.body, inset, -inset, width - inset * 2, height - inset * 2,
            max(0, radius - inset))
    end
    surface.updating = false
end

function addon:StyleFrame(frame, variant)
    local surface = frame.lumenSurface
    if not surface then
        surface = { frame = frame, textures = {}, shown = true }
        frame.lumenSurface = surface
        surface.shadowOuter = createLayer(frame, surface, -8, true)
        surface.shadowInner = createLayer(frame, surface, -7, true)
        surface.outline = createLayer(frame, surface, -6, false)
        surface.body = createLayer(frame, surface, -5, false)
        frame:HookScript("OnSizeChanged", function() layoutSurface(surface) end)
    end
    surface.variant = variant == "dock" and "dock" or (variant == "tile" and "tile" or "panel")
    local settings = self:GetSettings()
    surface.radius = clamp(settings.radius, 0, 64, 18)
    local palette = self:GetPalette()
    local opacity = palette.panel[4]
    colorLayer(surface.shadowOuter, { 0, 0, 0, 0.075 * opacity })
    colorLayer(surface.shadowInner, { 0, 0, 0, 0.16 * opacity })
    colorLayer(surface.outline, palette.border)
    colorLayer(surface.body, surface.variant == "dock" and palette.bg or palette.panel)
    layoutSurface(surface)
    return surface
end

function addon:SetSurfaceShown(frame, shown)
    local surface = frame.lumenSurface
    if not surface then return end
    surface.shown = not not shown
    for _, texture in ipairs(surface.textures) do
        if surface.shown and texture.lumenActive then texture:Show() else texture:Hide() end
    end
end

function addon:StyleText(fontString, kind, size)
    if not fontString then return end
    if size == nil and fontString.GetFont then
        local _, currentSize = fontString:GetFont()
        size = currentSize
    end
    size = clamp(size, 8, 48, fontString.lumenFontSize or 12)
    fontString.lumenFontSize = size
    local palette = self:GetPalette()
    local color = palette[kind == "muted" and "muted" or (kind == "accent" and "accent" or "text")]
    fontString:SetFont(FONT, size, "")
    fontString:SetTextColor(color[1], color[2], color[3], color[4])
    fontString:SetShadowColor(0, 0, 0, 0)
    fontString:SetShadowOffset(0, 0)
    return fontString
end

function addon:CreateLabel(parent, text, size, kind)
    local label = parent:CreateFontString(nil, "OVERLAY")
    self:StyleText(label, kind, size or 12)
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    return label
end
