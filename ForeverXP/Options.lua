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

    local effects = CreateFrame("Frame", nil, content)
    effects:SetAllPoints()
    local appearance = CreateFrame("Frame", nil, content)
    appearance:SetAllPoints()
    appearance:Hide()
    local layout = CreateFrame("Frame", nil, content)
    layout:SetAllPoints()
    layout:Hide()

    local tabs = {}
    local pages = { effects, appearance, layout }
    local function showTab(index)
        for i, page in ipairs(pages) do
            page:SetShown(i == index)
            selectButton(tabs[i], i == index)
        end
    end
    for index, name in ipairs({ "Effects", "Color & light", "Bar & behavior" }) do
        local tab = button(window, name, 140, 32)
        tab:SetPoint("TOPLEFT", 28 + (index - 1) * 152, -88)
        tab:SetScript("OnClick", function() showTab(index) end)
        tabs[index] = tab
    end

    local controls = {}
    local modes = {}
    local displayModes = {}
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

        control.title = label(parent, title, 0, y, "GameFontHighlightSmall", tint or C.text)
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
        control.title = label(control, title, 28, -4, "GameFontHighlight", C.text)
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

    section(effects, "CHOOSE YOUR EFFECT", 0)
    for index, definition in ipairs({
        { "class", "By class" }, { "flame", "Flame" },
        { "frost", "Frost" }, { "arcane", "Arcane" },
        { "void", "Shadow / Void" }, { "rainbow", "Rainbow" },
        { "solid", "Solid color" }, { "pulse", "Breathing" },
    }) do
        local mode = definition[1]
        local control = button(effects, definition[2], 216, 35)
        control:SetPoint("TOPLEFT", ((index - 1) % 2) * 228, -26 - math.floor((index - 1) / 2) * 44)
        control.mode = mode
        control:SetScript("OnClick", function()
            owner:SetSetting("mode", mode)
            refresh()
        end)
        modes[mode] = control
    end
    local modeDescription = label(effects, "", 0, -214, "GameFontHighlight", C.text)
    modeDescription:SetWidth(444)
    modeDescription:SetWordWrap(true)
    modeDescription:SetSpacing(5)

    section(effects, "MAKE THE LIGHT YOUR OWN", -304)
    local effectsNote = label(effects, "Use Color & light to tune brightness, glow and animation speed. Solid color and Breathing also use your chosen RGB color.", 0, -330, "GameFontHighlightSmall", C.muted)
    effectsNote:SetWidth(444)
    effectsNote:SetWordWrap(true)
    effectsNote:SetSpacing(5)
    local sampleNote = label(effects, "The sample XP bar stays visible while these settings are open, so you can try every effect at any level.", 0, -412, "GameFontHighlightSmall", C.muted)
    sampleNote:SetWidth(444)
    sampleNote:SetWordWrap(true)
    sampleNote:SetSpacing(5)

    section(appearance, "BASE COLOR", 0)
    local swatch = appearance:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(18, 12)
    swatch:SetPoint("TOPRIGHT", 0, 0)
    local colorNote = label(appearance, "", 0, -25, "GameFontHighlightSmall", C.muted)
    colorNote:SetWidth(444)
    colorNote:SetWordWrap(true)
    slider(appearance, "Red", "color", -73, 0, 1, 1 / 255, rgb, { 1, 0.42, 0.45, 1 }, "r")
    slider(appearance, "Green", "color", -118, 0, 1, 1 / 255, rgb, { 0.41, 0.91, 0.64, 1 }, "g")
    slider(appearance, "Blue", "color", -163, 0, 1, 1 / 255, rgb, { 0.42, 0.67, 1, 1 }, "b")

    section(appearance, "FINISH", -218)
    slider(appearance, "Brightness", "brightness", -244, 0.15, 1, 0.05, percent)
    slider(appearance, "Glow intensity", "glow", -289, 0, 1, 0.05, percent)
    slider(appearance, "Animation speed", "speed", -334, 0.05, 2, 0.05, function(value)
        return string.format("%.2fx", value)
    end)
    checkbox(appearance, "Reduce motion (keep colors still)", "reducedMotion", -392)
    local motionNote = label(appearance, "Reduced motion keeps your effect's colors without moving lights or pulsing.", 0, -438, "GameFontHighlightSmall", C.muted)
    motionNote:SetWidth(444)
    motionNote:SetWordWrap(true)
    motionNote:SetSpacing(5)

    section(layout, "APPLY EFFECTS TO", 0)
    for index, definition in ipairs({ { "native", "Blizzard bar" }, { "custom", "Custom replacement" } }) do
        local displayMode = definition[1]
        local control = button(layout, definition[2], 216, 32)
        control:SetPoint("TOPLEFT", (index - 1) * 228, -25)
        control.displayMode = displayMode
        control:SetScript("OnClick", function()
            owner:SetSetting("displayMode", displayMode)
            refresh()
        end)
        displayModes[displayMode] = control
    end
    local placementNote = label(layout, "", 0, -72, "GameFontHighlightSmall", C.muted)
    placementNote:SetWidth(444)
    placementNote:SetWordWrap(true)
    placementNote:SetSpacing(4)
    local nativeStatus = label(layout, "", 0, -112, "GameFontHighlightSmall", C.accent)
    nativeStatus:SetWidth(444)
    nativeStatus:SetWordWrap(true)

    section(layout, "CUSTOM BAR DIMENSIONS", -148)
    slider(layout, "Width", "width", -174, 240, 1200, 10, integer).customOnly = true
    slider(layout, "Height", "height", -216, 12, 48, 1, integer).customOnly = true
    slider(layout, "Scale", "scale", -258, 0.5, 2, 0.05, percent).customOnly = true

    section(layout, "BEHAVIOR", -310)
    checkbox(layout, "Show XP and level text", "showText", -335)
    checkbox(layout, "Show rested XP", "showRested", -365)
    checkbox(layout, "Lock custom bar position", "locked", -395).customOnly = true
    checkbox(layout, "Hide custom bar at maximum level", "hideAtMax", -425).customOnly = true
    checkbox(layout, "Show minimap button", "showMinimap", -455)

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
        local customBar = settings.displayMode == "custom"
        local customColor = settings.mode == "solid" or settings.mode == "pulse"
        for _, control in ipairs(controls) do
            if control.isCheckbox then
                control:SetChecked(settings[control.key])
                control.tick:SetShown(settings[control.key])
            else
                local value = control.colorKey and settings.color[control.colorKey] or settings[control.key]
                control:SetValue(value)
                control.valueText:SetText(control.format(value))
            end
            local enabled = (not control.customOnly or customBar) and (not control.colorKey or customColor)
            control:SetEnabled(enabled)
            control:SetAlpha(enabled and 1 or 0.35)
            if not control.isCheckbox then
                control:EnableMouseWheel(enabled)
                control.title:SetAlpha(enabled and 1 or 0.35)
                control.valueText:SetAlpha(enabled and 1 or 0.35)
            end
        end
        for mode, control in pairs(modes) do
            selectButton(control, settings.mode == mode)
        end
        for displayMode, control in pairs(displayModes) do
            selectButton(control, (settings.displayMode or "native") == displayMode)
        end
        swatch:SetColorTexture(settings.color.r, settings.color.g, settings.color.b, 1)
        local descriptions = {
            class = "Your class chooses the magic. The effect follows your character automatically.",
            flame = "Warm flames and glowing embers dance along your XP bar.",
            frost = "Icy blues and bright frost shimmer across your progress.",
            arcane = "Violet arcane light and magical sparks flow along the bar.",
            void = "Deep shadow, heavy violet glow and restless void energy.",
            rainbow = "A flowing rainbow brings a full spectrum of color to your XP.",
            pulse = "A soft breathing light in your chosen RGB color.",
            solid = "Your chosen RGB color with a soft glow at the end of your XP.",
        }
        modeDescription:SetText(descriptions[settings.mode] or descriptions.rainbow)
        if customColor then
            colorNote:SetText("Choose the RGB color for Solid color and Breathing.")
        else
            colorNote:SetText("This effect uses its own colors. Choose Solid color or Breathing to use the RGB sliders.")
        end
        swatch:SetAlpha(customColor and 1 or 0.35)
        placementNote:SetText(customBar
            and "Replaces Blizzard's XP bar. Unlock the custom bar below, then drag it to your preferred position."
            or "Use Blizzard's Edit Mode for position and size. The game controls when its XP bar is visible.")
        nativeStatus:SetText(type(owner.nativeStatus) == "string" and owner.nativeStatus or "")
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
