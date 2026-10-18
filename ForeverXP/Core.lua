local addonName, addon = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ASSETS = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
local SEGMENTS = 48
local UPDATE_INTERVAL = 1 / 30
local floor, min, max, sin = math.floor, math.min, math.max, math.sin
local validPoints = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

addon.defaults = {
    mode = "rainbow",
    color = { r = 0.1, g = 0.75, b = 1 },
    speed = 0.35,
    brightness = 0.85,
    glow = 0.7,
    width = 620,
    height = 22,
    scale = 1,
    showText = true,
    showRested = true,
    locked = true,
    reducedMotion = false,
    hideAtMax = true,
    showMinimap = true,
    minimapAngle = 225,
    position = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 180 },
}

local ranges = {
    speed = { 0.05, 2 }, brightness = { 0.15, 1 }, glow = { 0, 1 },
    width = { 240, 1200 }, height = { 12, 48 }, scale = { 0.5, 2 },
    minimapAngle = { 0, 360 },
}
local booleanKeys = {
    showText = true, showRested = true, locked = true,
    reducedMotion = true, hideAtMax = true, showMinimap = true,
}

local function isNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function clamp(value, low, high, fallback)
    if not isNumber(value) then return fallback end
    return min(high, max(low, value))
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function sanitize(saved)
    local result = copy(addon.defaults)
    if type(saved) ~= "table" then return result end
    for key, limits in pairs(ranges) do
        result[key] = clamp(saved[key], limits[1], limits[2], result[key])
    end
    for key in pairs(booleanKeys) do
        if type(saved[key]) == "boolean" then result[key] = saved[key] end
    end
    if saved.mode == "solid" or saved.mode == "rainbow" or saved.mode == "pulse" then
        result.mode = saved.mode
    end
    if type(saved.color) == "table" then
        for _, key in ipairs({ "r", "g", "b" }) do
            result.color[key] = clamp(saved.color[key], 0, 1, result.color[key])
        end
    end
    if type(saved.position) == "table" then
        local position = saved.position
        if validPoints[position.point] then result.position.point = position.point end
        if validPoints[position.relativePoint] then result.position.relativePoint = position.relativePoint end
        result.position.x = clamp(position.x, -20000, 20000, result.position.x)
        result.position.y = clamp(position.y, -20000, 20000, result.position.y)
    end
    result.version = 1
    return result
end

local function hsv(hue, saturation, value)
    local sector = (hue % 1) * 6
    local index = floor(sector)
    local fraction = sector - index
    local p = value * (1 - saturation)
    local q = value * (1 - fraction * saturation)
    local t = value * (1 - (1 - fraction) * saturation)
    if index == 0 then return value, t, p end
    if index == 1 then return q, value, p end
    if index == 2 then return p, value, t end
    if index == 3 then return p, q, value end
    if index == 4 then return t, p, value end
    return value, p, q
end

local function secret(value)
    return issecretvalue and issecretvalue(value)
end

local function atMaxLevel(level, maxXP)
    if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
        return GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
    end
    local maximum = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
    if not maximum and GetMaxPlayerLevel then maximum = GetMaxPlayerLevel() end
    return (isNumber(maximum) and level >= maximum) or maxXP <= 0
end

function addon:GetSettings()
    return self.db
end

function addon:SetSetting(key, value)
    if not self.db then return end
    if ranges[key] then
        local limits = ranges[key]
        self.db[key] = clamp(value, limits[1], limits[2], self.db[key])
    elseif booleanKeys[key] and type(value) == "boolean" then
        self.db[key] = value
    elseif key == "mode" and (value == "solid" or value == "rainbow" or value == "pulse") then
        self.db.mode = value
    else
        return
    end
    if key == "minimapAngle" or key == "showMinimap" then
        if self.RefreshMinimapButton then self:RefreshMinimapButton() end
    else
        self:Refresh()
    end
end

function addon:SetColor(red, green, blue)
    self.db.color.r = clamp(red, 0, 1, self.db.color.r)
    self.db.color.g = clamp(green, 0, 1, self.db.color.g)
    self.db.color.b = clamp(blue, 0, 1, self.db.color.b)
    self:Refresh()
end

function addon:ResetSettings()
    ForeverXPDB = sanitize(nil)
    self.db = ForeverXPDB
    self.state.phase = 0
    self:Refresh()
end

function addon:SetPreview(enabled)
    self.previewEnabled = enabled and true or false
    self:Refresh()
end

function addon:ApplyLayout()
    local settings, bar = self.db, self.bar
    bar:SetSize(settings.width, settings.height)
    bar:SetScale(settings.scale)
    if not self.dragging then
        local position = settings.position
        bar:ClearAllPoints()
        bar:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    end
    bar:SetMovable(not settings.locked)
    local width, height = settings.width - 10, settings.height - 8
    self.trackWidth, self.trackHeight = width, height
    self.track:SetSize(width, height)
    self.effectCanvas:SetWidth(width)
    for index, segment in ipairs(self.rainbowSegments) do
        segment:ClearAllPoints()
        segment:SetPoint("TOPLEFT", self.effectCanvas, "TOPLEFT", (index - 1) * width / SEGMENTS, 0)
        segment:SetSize(width / SEGMENTS, height)
    end
    self.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", min(14, max(10, height - 1)), "OUTLINE")
    self.text:SetWidth(width - 12)
end

function addon:UpdateXP()
    local state, settings = self.state, self.db
    local xp, maxXP, rested, level
    if self.previewEnabled then
        xp, maxXP, rested, level = 6500, 10000, 2200, 42
    else
        xp, maxXP, rested, level = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion(), UnitLevel("player")
    end
    state.secret = secret(xp) or secret(maxXP) or secret(rested) or secret(level)
    -- XP is public in current Retail. Hide gracefully if a future client restricts it.
    if state.secret then self.bar:Hide(); return end
    xp = isNumber(xp) and max(0, xp) or 0
    maxXP = isNumber(maxXP) and max(0, maxXP) or 0
    rested = isNumber(rested) and max(0, rested) or 0
    level = isNumber(level) and level or 1
    state.xp, state.maxXP, state.rested, state.level = xp, maxXP, rested, level
    state.atMax = not self.previewEnabled and atMaxLevel(level, maxXP)
    state.xpLocked = not self.previewEnabled and IsXPUserDisabled and IsXPUserDisabled() or false
    state.ratio = maxXP > 0 and min(1, xp / maxXP) or 0
    self.fill:SetMinMaxValues(0, max(1, maxXP))
    self.fill:SetValue(min(xp, maxXP))
    self.rested:SetMinMaxValues(0, max(1, maxXP))
    self.rested:SetValue(min(maxXP, xp + rested))
    self.rested:SetShown(settings.showRested and rested > 0)
    local fillWidth = self.trackWidth * state.ratio
    self.rainbowLayer:SetWidth(max(0.001, fillWidth))
    self.rainbowLayer:SetShown(state.ratio > 0)
    self.leadingGlow:ClearAllPoints()
    self.leadingGlow:SetPoint("CENTER", self.track, "LEFT", fillWidth, 0)
    self.leadingGlow:SetSize(40, max(28, self.trackHeight * 3))
    self.leadingGlow:SetShown(state.ratio > 0)
    local prefix = self.previewEnabled and "PREVIEW  |  " or ""
    if state.atMax then
        self.text:SetText(prefix .. "Level " .. level .. "  |  Maximum level")
    else
        local percentage = floor(state.ratio * 1000 + 0.5) / 10
        local suffix = state.xpLocked and "  |  XP locked" or ""
        self.text:SetText(string.format("%sLv %d  |  %s / %s XP  |  %.1f%%%s", prefix, level, BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp), BreakUpLargeNumbers and BreakUpLargeNumbers(maxXP) or tostring(maxXP), percentage, suffix))
    end
    self.text:SetShown(settings.showText)
    self.bar:SetShown(self.previewEnabled or not (settings.hideAtMax and state.atMax))
end

function addon:Paint()
    local settings, state = self.db, self.state
    local phase = settings.reducedMotion and 0 or state.phase
    local red, green, blue = settings.color.r, settings.color.g, settings.color.b
    local intensity = settings.brightness
    if settings.mode == "pulse" and not settings.reducedMotion then
        intensity = intensity * (0.65 + 0.35 * (sin(phase * math.pi * 2) + 1) / 2)
    end
    if settings.mode == "rainbow" then
        for index, segment in ipairs(self.rainbowSegments) do
            local r1, g1, b1 = hsv(phase + (index - 1) / (SEGMENTS * 1.2), 0.85, intensity)
            local r2, g2, b2 = hsv(phase + index / (SEGMENTS * 1.2), 0.85, intensity)
            segment:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
            segment:Show()
        end
        red, green, blue = hsv(phase + state.ratio / 1.2, 0.85, intensity)
    else
        red, green, blue = red * intensity, green * intensity, blue * intensity
        for _, segment in ipairs(self.rainbowSegments) do segment:Hide() end
    end
    self.fill:SetStatusBarColor(red, green, blue, 1)
    local breathing = (settings.reducedMotion or settings.mode == "solid") and 0.8 or (0.7 + 0.3 * (sin(phase * math.pi * 4) + 1) / 2)
    self.leadingGlow:SetVertexColor(red, green, blue)
    self.leadingGlow:SetAlpha(settings.glow * 0.65 * breathing)
    self.edgeTop:SetColorTexture(red, green, blue, settings.glow * 0.65)
    self.edgeBottom:SetColorTexture(red, green, blue, settings.glow * 0.3)
    self.sweep:SetShown(not settings.reducedMotion and settings.mode ~= "solid" and settings.glow > 0)
    self.sweep:SetAlpha(settings.glow * 0.4)
    local sweepWidth = max(40, self.trackWidth * 0.12)
    local sweepX = ((phase * 3) % 1) * (self.trackWidth * state.ratio + sweepWidth) - sweepWidth / 2
    self.sweep:ClearAllPoints()
    self.sweep:SetPoint("CENTER", self.rainbowLayer, "LEFT", sweepX, 0)
    self.sweep:SetSize(sweepWidth, self.trackHeight * 2)
end

function addon:Refresh()
    if not self.bar or not self.db then return end
    self:ApplyLayout()
    self:UpdateXP()
    self:Paint()
    if self.RefreshMinimapButton then self:RefreshMinimapButton() end
end

function addon:ShowTooltip()
    local state = self.state
    if state.secret then return end
    GameTooltip:SetOwner(self.bar, "ANCHOR_TOP")
    GameTooltip:AddLine("ForeverXP", 0.35, 0.85, 1)
    if self.previewEnabled then
        GameTooltip:AddLine("Sample XP preview — your real XP is unchanged.", 1, 0.8, 0.4)
    elseif state.atMax then
        GameTooltip:AddLine("You have reached your current maximum level.", 1, 1, 1)
    else
        local formatNumber = BreakUpLargeNumbers or tostring
        GameTooltip:AddDoubleLine("Level", tostring(state.level), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("XP to next level", formatNumber(max(0, state.maxXP - state.xp)), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Rested bonus XP", formatNumber(state.rested), 0.45, 0.7, 1, 0.6, 0.8, 1)
        if state.xpLocked then GameTooltip:AddLine("Experience gain is disabled.", 1, 0.7, 0.3) end
    end
    GameTooltip:AddLine("Right-click for appearance settings.", 0.65, 0.65, 0.65)
    if not self.db.locked then GameTooltip:AddLine("Drag to move the bar.", 0.65, 0.65, 0.65) end
    GameTooltip:Show()
end

function addon:CreateBar()
    local bar = CreateFrame("Frame", "ForeverXPBar", UIParent, "BackdropTemplate")
    self.bar = bar
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bar:SetBackdropColor(0.025, 0.03, 0.055, 0.95)
    bar:SetBackdropBorderColor(0.2, 0.24, 0.32, 0.95)

    local track = CreateFrame("Frame", nil, bar)
    self.track = track
    track:SetPoint("CENTER")
    local background = track:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.045, 0.055, 0.085, 1)

    local rested = CreateFrame("StatusBar", nil, track)
    self.rested = rested
    rested:SetAllPoints()
    rested:SetStatusBarTexture(WHITE)
    rested:SetStatusBarColor(0.18, 0.38, 0.7, 0.55)
    local fill = CreateFrame("StatusBar", nil, track)
    self.fill = fill
    fill:SetAllPoints()
    fill:SetFrameLevel(rested:GetFrameLevel() + 1)
    fill:SetStatusBarTexture(WHITE)

    local layer = CreateFrame("Frame", nil, fill)
    self.rainbowLayer = layer
    layer:SetPoint("TOPLEFT")
    layer:SetPoint("BOTTOMLEFT")
    layer:SetClipsChildren(true)
    -- Frame clipping applies to child frames; textures live on an unclipped-width child.
    local canvas = CreateFrame("Frame", nil, layer)
    self.effectCanvas = canvas
    canvas:SetPoint("TOPLEFT")
    canvas:SetPoint("BOTTOMLEFT")
    self.rainbowSegments = {}
    for index = 1, SEGMENTS do
        local segment = canvas:CreateTexture(nil, "ARTWORK")
        segment:SetColorTexture(1, 1, 1, 1)
        self.rainbowSegments[index] = segment
    end
    local sweep = canvas:CreateTexture(nil, "OVERLAY")
    self.sweep = sweep
    sweep:SetTexture(ASSETS .. "Shine.tga")
    sweep:SetBlendMode("ADD")

    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(layer:GetFrameLevel() + 2)
    local leadingGlow = overlay:CreateTexture(nil, "ARTWORK")
    self.leadingGlow = leadingGlow
    leadingGlow:SetTexture(ASSETS .. "Glow.tga")
    leadingGlow:SetBlendMode("ADD")
    local top = overlay:CreateTexture(nil, "OVERLAY")
    self.edgeTop = top
    top:SetPoint("TOPLEFT", track, "TOPLEFT")
    top:SetPoint("TOPRIGHT", track, "TOPRIGHT")
    top:SetHeight(1)
    local bottom = overlay:CreateTexture(nil, "OVERLAY")
    self.edgeBottom = bottom
    bottom:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT")
    bottom:SetHeight(1)
    self.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.text:SetPoint("CENTER")
    self.text:SetTextColor(0.95, 0.97, 1)
    self.text:SetShadowOffset(1, -1)
    self.text:SetWordWrap(false)

    bar:SetScript("OnEnter", function() addon:ShowTooltip() end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then addon:ToggleOptions() end
    end)
    bar:SetScript("OnDragStart", function(frame)
        if addon.db.locked then return end
        addon.dragging = true
        frame:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(frame)
        if not addon.dragging then return end
        frame:StopMovingOrSizing()
        addon.dragging = false
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        addon.db.position = {
            point = validPoints[point] and point or "CENTER",
            relativePoint = validPoints[relativePoint] and relativePoint or "CENTER",
            x = floor((x or 0) + 0.5), y = floor((y or 0) + 0.5),
        }
    end)
    bar:SetScript("OnUpdate", function(_, elapsed)
        if addon.db.reducedMotion or addon.db.mode == "solid" then return end
        addon.elapsed = addon.elapsed + min(elapsed, 0.25)
        if addon.elapsed < UPDATE_INTERVAL then return end
        addon.state.phase = (addon.state.phase + addon.elapsed * addon.db.speed * 0.25) % 1
        addon.elapsed = 0
        addon:Paint()
    end)
end

local function say(message)
    print("|cff59d9ffForeverXP:|r " .. message)
end

local function slashCommand(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    if command == "lock" then
        addon:SetSetting("locked", not addon.db.locked)
        if addon.RefreshOptions then addon:RefreshOptions() end
        say(addon.db.locked and "Bar locked." or "Bar unlocked. Drag it to move.")
    elseif command == "reset" then
        addon:ResetSettings()
        if addon.RefreshOptions then addon:RefreshOptions() end
        say("Appearance and position reset.")
    elseif command == "preview" then
        addon:SetPreview(not addon.previewEnabled)
        say(addon.previewEnabled and "Sample XP preview enabled." or "Sample XP preview disabled.")
    elseif command == "minimap" then
        addon:SetSetting("showMinimap", not addon.db.showMinimap)
        if addon.RefreshOptions then addon:RefreshOptions() end
        say(addon.db.showMinimap and "Minimap button shown." or "Minimap button hidden. Use /fxp minimap to show it again.")
    elseif command == "solid" or command == "rainbow" or command == "pulse" then
        addon:SetSetting("mode", command)
        if addon.RefreshOptions then addon:RefreshOptions() end
    elseif command == "" or command == "options" then
        addon:ToggleOptions()
    else
        say("/fxp opens settings. Commands: rainbow, solid, pulse, lock, preview, minimap, reset.")
    end
end

addon.state = { phase = 0, xp = 0, maxXP = 1, rested = 0, level = 1, ratio = 0 }
addon.elapsed = 0
addon.events = CreateFrame("Frame")
addon.events:RegisterEvent("ADDON_LOADED")
addon.events:RegisterEvent("PLAYER_LOGIN")
addon.events:SetScript("OnEvent", function(frame, event, unit)
    if event == "ADDON_LOADED" then
        if unit ~= addonName then return end
        ForeverXPDB = sanitize(ForeverXPDB)
        addon.db = ForeverXPDB
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if not addon.db then ForeverXPDB = sanitize(ForeverXPDB); addon.db = ForeverXPDB end
        addon:CreateBar()
        if addon.CreateMinimapButton then addon:CreateMinimapButton() end
        for _, name in ipairs({
            "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP",
            "PLAYER_UPDATE_RESTING", "PLAYER_MAX_LEVEL_UPDATE", "UPDATE_EXPANSION_LEVEL",
            "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "UNIT_LEVEL",
        }) do frame:RegisterEvent(name) end
        SLASH_FOREVERXP1, SLASH_FOREVERXP2 = "/fxp", "/foreverxp"
        SlashCmdList.FOREVERXP = slashCommand
        addon:Refresh()
        say("Ready. Type /fxp for appearance settings.")
    elseif (event == "PLAYER_XP_UPDATE" or event == "UNIT_LEVEL") and unit and unit ~= "player" then
        return
    else
        addon:Refresh()
    end
end)
