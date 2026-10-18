local _, addon = ...

local C = {
    background = { 0.035, 0.045, 0.075, 0.98 },
    panel = { 0.065, 0.08, 0.12, 1 },
    border = { 0.15, 0.2, 0.29, 1 },
    accent = { 0.30, 0.88, 0.93, 1 },
    text = { 0.91, 0.94, 1, 1 },
    muted = { 0.56, 0.64, 0.75, 1 },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function label(parent, text, x, y, font, color)
    local result = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    result:SetPoint("TOPLEFT", x, y)
    result:SetText(text)
    result:SetJustifyH("LEFT")
    result:SetTextColor(unpack(color or C.text))
    return result
end

local function backdrop(frame, background, border)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(background or C.panel))
    frame:SetBackdropBorderColor(unpack(border or C.border))
end

local function button(parent, text, width, height)
    local result = CreateFrame("Button", nil, parent, "BackdropTemplate")
    result:SetSize(width, height)
    backdrop(result)
    result.caption = result:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    result.caption:SetPoint("CENTER")
    result.caption:SetText(text)
    result.caption:SetTextColor(unpack(C.text))
    result:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(C.accent))
    end)
    result:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(self.selected and C.accent or C.border))
    end)
    return result
end

local function selectButton(control, selected)
    control.selected = selected
    if selected then
        control:SetBackdropColor(0.08, 0.20, 0.25, 1)
        control:SetBackdropBorderColor(unpack(C.accent))
        control.caption:SetTextColor(unpack(C.accent))
    else
        control:SetBackdropColor(unpack(C.panel))
        control:SetBackdropBorderColor(unpack(C.border))
        control.caption:SetTextColor(unpack(C.muted))
    end
end

local function section(parent, text, y)
    label(parent, text, 0, y, "GameFontNormal", C.accent)
end

function addon:CreateOptions()
    if self.optionsFrame then
        return self.optionsFrame
    end

    local owner = self
    local window = CreateFrame("Frame", "ForeverXPOptions", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetSize(500, 690)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    backdrop(window, C.background)
    self.optionsFrame = window

    local stripe = window:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("TOPRIGHT", -1, -1)
    stripe:SetHeight(3)
    stripe:SetColorTexture(unpack(C.accent))

    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 1, -4)
    header:SetPoint("TOPRIGHT", -45, -4)
    header:SetHeight(74)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    label(header, "ForeverXP", 25, -19, "GameFontNormalLarge", C.text)
    label(header, "A little more color for the journey.", 25, -44, "GameFontHighlightSmall", C.muted)

    local close = button(window, "x", 26, 26)
    close:SetPoint("TOPRIGHT", -15, -17)
    close:SetScript("OnClick", function() window:Hide() end)

    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", 28, -135)
    content:SetPoint("BOTTOMRIGHT", -28, 57)

    local appearance = CreateFrame("Frame", nil, content)
    appearance:SetAllPoints()
    local layout = CreateFrame("Frame", nil, content)
    layout:SetAllPoints()
    layout:Hide()

    local tabs = {}
    local pages = { appearance, layout }
    local function showTab(index)
        for i, page in ipairs(pages) do
            page:SetShown(i == index)
            selectButton(tabs[i], i == index)
        end
    end
    for index, name in ipairs({ "Appearance", "Layout & behavior" }) do
        local tab = button(window, name, 216, 32)
        tab:SetPoint("TOPLEFT", 28 + (index - 1) * 228, -88)
        tab:SetScript("OnClick", function() showTab(index) end)
        tabs[index] = tab
    end

    local controls = {}
    local modes = {}
    local refreshing = false
    local refresh

    local function slider(parent, title, key, y, minimum, maximum, step, format, tint, colorKey)
        local control = CreateFrame("Slider", nil, parent)
        control:SetPoint("TOPLEFT", 0, y - 22)
        control:SetSize(444, 12)
        control:SetOrientation("HORIZONTAL")
        control:SetMinMaxValues(minimum, maximum)
        control:SetValueStep(step)
        control:SetObeyStepOnDrag(true)
        control:EnableMouseWheel(true)
        control:SetHitRectInsets(0, 0, -7, -7)

        local track = control:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(4)
        track:SetColorTexture(0.13, 0.17, 0.24, 1)
        control:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = control:GetThumbTexture()
        thumb:SetSize(9, 15)
        thumb:SetVertexColor(unpack(tint or C.accent))

        label(parent, title, 0, y, "GameFontHighlightSmall", tint or C.text)
        local valueText = label(parent, "", 0, y, "GameFontHighlightSmall", C.muted)
        valueText:ClearAllPoints()
        valueText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
        control.key = key
        control.colorKey = colorKey
        control.valueText = valueText
        control.format = format
        control:SetScript("OnValueChanged", function(_, value)
            valueText:SetText(format(value))
            if refreshing then return end
            value = clamp(value, minimum, maximum)
            if colorKey then
                local color = owner:GetSettings().color
                local values = { r = color.r, g = color.g, b = color.b }
                values[colorKey] = value
                owner:SetColor(values.r, values.g, values.b)
            else
                owner:SetSetting(key, value)
            end
            refresh()
        end)
        control:SetScript("OnMouseWheel", function(self, delta)
            self:SetValue(clamp(self:GetValue() + step * delta, minimum, maximum))
        end)
        controls[#controls + 1] = control
        return control
    end

    local function checkbox(parent, title, key, y)
        local control = CreateFrame("CheckButton", nil, parent)
        control:SetPoint("TOPLEFT", 0, y)
        control:SetSize(444, 25)
        local square = CreateFrame("Frame", nil, control, "BackdropTemplate")
        square:SetSize(18, 18)
        square:SetPoint("TOPLEFT", 0, -2)
        backdrop(square)
        local tick = square:CreateTexture(nil, "ARTWORK")
        tick:SetSize(10, 10)
        tick:SetPoint("CENTER", square, "CENTER")
        tick:SetColorTexture(unpack(C.accent))
        control.tick = tick
        label(control, title, 28, -4, "GameFontHighlight", C.text)
        control:SetScript("OnEnter", function() square:SetBackdropBorderColor(unpack(C.accent)) end)
        control:SetScript("OnLeave", function() square:SetBackdropBorderColor(unpack(C.border)) end)
        control.key = key
        control.isCheckbox = true
        control:SetScript("OnClick", function(self)
            owner:SetSetting(key, self:GetChecked() and true or false)
            refresh()
        end)
        controls[#controls + 1] = control
        return control
    end

    local function percent(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end
    local function integer(value) return string.format("%d px", math.floor(value + 0.5)) end
    local function rgb(value) return tostring(math.floor(value * 255 + 0.5)) end

    section(appearance, "LIGHT EFFECT", 0)
    for index, definition in ipairs({
        { "rainbow", "Rainbow" }, { "solid", "Solid color" }, { "pulse", "Breathing" },
    }) do
        local mode = definition[1]
        local control = button(appearance, definition[2], 140, 31)
        control:SetPoint("TOPLEFT", (index - 1) * 152, -23)
        control:SetScript("OnClick", function()
            owner:SetSetting("mode", mode)
            refresh()
        end)
        modes[mode] = control
    end
    local modeDescription = label(appearance, "", 0, -64, "GameFontHighlightSmall", C.muted)
    modeDescription:SetWidth(444)
    modeDescription:SetWordWrap(true)

    section(appearance, "BASE COLOR", -103)
    local swatch = appearance:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(18, 12)
    swatch:SetPoint("TOPRIGHT", 0, -103)
    slider(appearance, "Red", "color", -128, 0, 1, 1 / 255, rgb, { 1, 0.42, 0.45, 1 }, "r")
    slider(appearance, "Green", "color", -171, 0, 1, 1 / 255, rgb, { 0.41, 0.91, 0.64, 1 }, "g")
    slider(appearance, "Blue", "color", -214, 0, 1, 1 / 255, rgb, { 0.42, 0.67, 1, 1 }, "b")

    section(appearance, "FINISH", -269)
    slider(appearance, "Brightness", "brightness", -295, 0.15, 1, 0.05, percent)
    slider(appearance, "Glow intensity", "glow", -338, 0, 1, 0.05, percent)
    slider(appearance, "Animation speed", "speed", -381, 0.05, 2, 0.05, function(value)
        return string.format("%.2fx", value)
    end)
    checkbox(appearance, "Reduce motion (keep colors still)", "reducedMotion", -442)

    section(layout, "BAR DIMENSIONS", 0)
    slider(layout, "Width", "width", -29, 240, 1200, 10, integer)
    slider(layout, "Height", "height", -80, 12, 48, 1, integer)
    slider(layout, "Scale", "scale", -131, 0.5, 2, 0.05, percent)

    section(layout, "BEHAVIOR", -195)
    checkbox(layout, "Show XP and level text", "showText", -224)
    checkbox(layout, "Show rested XP", "showRested", -260)
    checkbox(layout, "Lock bar position", "locked", -296)
    checkbox(layout, "Hide at maximum level", "hideAtMax", -332)
    local dragNote = label(layout, "Unlock the bar, then drag it to your preferred position.\nYour position and appearance are saved automatically.", 0, -381, "GameFontHighlightSmall", C.muted)
    dragNote:SetWidth(444)
    dragNote:SetSpacing(5)
    local maxNote = label(layout, "The sample preview remains visible here, including at maximum level.", 0, -435, "GameFontHighlightSmall", C.muted)
    maxNote:SetWidth(444)
    maxNote:SetWordWrap(true)

    local footerLine = window:CreateTexture(nil, "ARTWORK")
    footerLine:SetPoint("BOTTOMLEFT", 28, 49)
    footerLine:SetPoint("BOTTOMRIGHT", -28, 49)
    footerLine:SetHeight(1)
    footerLine:SetColorTexture(unpack(C.border))
    label(window, "SAMPLE XP PREVIEW  |  Changes save instantly", 28, -657, "GameFontHighlightSmall", C.muted)
    local reset = button(window, "Reset", 70, 25)
    reset:SetPoint("BOTTOMRIGHT", -28, 13)
    reset:SetScript("OnClick", function()
        owner:ResetSettings()
        refresh()
    end)

    refresh = function()
        if refreshing then return end
        refreshing = true
        local settings = owner:GetSettings()
        for _, control in ipairs(controls) do
            if control.isCheckbox then
                control:SetChecked(settings[control.key])
                control.tick:SetShown(settings[control.key])
            else
                local value = control.colorKey and settings.color[control.colorKey] or settings[control.key]
                control:SetValue(value)
                control.valueText:SetText(control.format(value))
            end
        end
        for mode, control in pairs(modes) do
            selectButton(control, settings.mode == mode)
        end
        swatch:SetColorTexture(settings.color.r, settings.color.g, settings.color.b, 1)
        if settings.mode == "rainbow" then
            modeDescription:SetText("A flowing rainbow across your XP. Base color is used by the other effects.")
        elseif settings.mode == "pulse" then
            modeDescription:SetText("A soft breathing light in your chosen base color.")
        else
            modeDescription:SetText("Your chosen base color with a soft glow at the end of your XP.")
        end
        refreshing = false
    end
    window.Refresh = refresh
    window:SetScript("OnShow", function()
        owner:SetPreview(true)
        refresh()
    end)
    window:SetScript("OnHide", function()
        window:StopMovingOrSizing()
        owner:SetPreview(false)
    end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ForeverXPOptions")
    end
    showTab(1)
    refresh()
    return window
end

function addon:ToggleOptions()
    local window = self:CreateOptions()
    window:SetShown(not window:IsShown())
end

function addon:RefreshOptions()
    if self.optionsFrame and self.optionsFrame.Refresh then
        self.optionsFrame.Refresh()
    end
end
