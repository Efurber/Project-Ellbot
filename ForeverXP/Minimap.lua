local _, addon = ...

local sin, cos, rad, deg = math.sin, math.cos, math.rad, math.deg
local min, max, sqrt = math.min, math.max, math.sqrt

-- Quadrants: bottom-right, bottom-left, top-right, top-left. A true entry
-- follows the round edge; a false entry follows the square edge.
local shapes = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

local function showTooltip(button)
    if not GameTooltip then return end
    local settings = addon:GetSettings()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("ForeverXP", 0.35, 0.85, 1)
    GameTooltip:AddLine("Left-click to customize your XP bar.", 1, 1, 1)
    GameTooltip:AddLine(settings.locked and "Right-click to unlock the custom XP bar." or "Right-click to lock the custom XP bar.", 0.8, 0.85, 0.95)
    GameTooltip:AddLine("Drag to move this icon around the minimap.", 0.65, 0.7, 0.8)
    GameTooltip:Show()
    button.tooltipShown = true
end

local function hideTooltip(button)
    if button.tooltipShown and GameTooltip then GameTooltip:Hide() end
    button.tooltipShown = nil
end

local function stopDragging(button)
    if button.dragging then
        button.dragging = nil
        -- A mouse release after dragging must not also open settings.
        button.suppressClickUntil = GetTime() + 0.25
    end
    button:SetScript("OnUpdate", nil)
end

local function updateDrag(button)
    local minimap = button:GetParent()
    local centerX, centerY = minimap:GetCenter()
    if not centerX or not centerY then return end
    local scale = minimap:GetEffectiveScale()
    if not scale or scale <= 0 then return end
    local cursorX, cursorY = GetCursorPosition()
    local x, y = cursorX / scale - centerX, cursorY / scale - centerY
    if x == 0 and y == 0 then return end
    local angle = deg(atan2(y, x)) % 360
    addon:SetSetting("minimapAngle", angle)
end

function addon:RefreshMinimapButton()
    local button = self.minimapButton
    local settings = self:GetSettings()
    if not button or not settings then return end
    local minimap = button:GetParent()
    local radiusX = max(1, minimap:GetWidth() / 2) + 5
    local radiusY = max(1, minimap:GetHeight() / 2) + 5
    local angle = rad(settings.minimapAngle or 225)
    local x, y = cos(angle), sin(angle)
    local quadrant = 1
    if x < 0 then quadrant = quadrant + 1 end
    if y > 0 then quadrant = quadrant + 2 end
    local shape = shapes[GetMinimapShape and GetMinimapShape() or "ROUND"] or shapes.ROUND
    if shape[quadrant] then
        x, y = x * radiusX, y * radiusY
    else
        x = max(-radiusX, min(radiusX, x * radiusX * sqrt(2)))
        y = max(-radiusY, min(radiusY, y * radiusY * sqrt(2)))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", minimap, "CENTER", x, y)
    button:SetShown(settings.showMinimap ~= false)
end

function addon:CreateMinimapButton()
    if self.minimapButton then
        self:RefreshMinimapButton()
        return self.minimapButton
    end
    if not Minimap then return end

    local button = CreateFrame("Button", "ForeverXPMinimapButton", Minimap)
    self.minimapButton = button
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_ArcaneTorrent")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnEnter", function(self)
        if not self.dragging then showTooltip(self) end
    end)
    button:SetScript("OnLeave", hideTooltip)
    button:SetScript("OnClick", function(self, mouseButton)
        if self.dragging or (self.suppressClickUntil and GetTime() < self.suppressClickUntil) then return end
        if mouseButton == "LeftButton" then
            addon:ToggleOptions()
        elseif mouseButton == "RightButton" then
            addon:SetSetting("locked", not addon:GetSettings().locked)
            if addon.RefreshOptions then addon:RefreshOptions() end
            if self.tooltipShown then showTooltip(self) end
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        hideTooltip(self)
        self:SetScript("OnUpdate", updateDrag)
        updateDrag(self)
    end)
    button:SetScript("OnDragStop", stopDragging)
    button:SetScript("OnHide", function(self)
        stopDragging(self)
        hideTooltip(self)
    end)
    if Minimap.HookScript then
        Minimap:HookScript("OnSizeChanged", function() addon:RefreshMinimapButton() end)
    end
    self:RefreshMinimapButton()
    return button
end
