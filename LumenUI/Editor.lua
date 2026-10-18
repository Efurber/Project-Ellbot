local _, addon = ...
local unpack = unpack or table.unpack

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function percent(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end
local function pixels(value) return string.format("%d px", math.floor(value + 0.5)) end
local function integer(value) return tostring(math.floor(value + 0.5)) end

function addon:CreateEditor()
    if self.editorFrame then return self.editorFrame end
    local owner, refreshing = self, false
    local refresh, feedback = nil, nil
    local controls, labels, surfaces, tabs, pages = {}, {}, {}, {}, {}
    local activeTab, profilePage, layoutPage, selectedProfile = "Appearance", 1, 1, nil
    local lastStyleKey
    local function palette()
        return owner:GetPalette()
    end
    local function label(parent, text, x, y, size, kind, width)
        local result = owner:CreateLabel(parent, text, size or 12, kind or "text")
        result:SetPoint("TOPLEFT", x, y)
        result:SetJustifyH("LEFT")
        if width then result:SetWidth(width); result:SetWordWrap(true) end
        labels[#labels + 1] = { object = result, kind = kind or "text" }
        return result
    end
    local function style(frame, variant)
        owner:StyleFrame(frame, variant)
        surfaces[#surfaces + 1] = { frame = frame, variant = variant }
    end
    local function button(parent, text, x, y, width, height, callback)
        local result = CreateFrame("Button", nil, parent, "BackdropTemplate")
        result:SetPoint("TOPLEFT", x, y)
        result:SetSize(width, height or 30)
        style(result, "tile")
        result.caption = owner:CreateLabel(result, text, 12, "text")
        result.caption:SetPoint("CENTER")
        labels[#labels + 1] = { object = result.caption, kind = "text" }
        result.selection = result:CreateTexture(nil, "OVERLAY")
        result.selection:SetPoint("LEFT", 5, 0)
        result.selection:SetSize(2, math.max(10, (height or 30) - 14))
        result.selection:Hide()
        result:SetScript("OnClick", callback)
        result:SetScript("OnEnter", function(self)
            self.hover = true
            self.selection:SetColorTexture(unpack(palette().accent))
            self.selection:Show()
        end)
        result:SetScript("OnLeave", function(self)
            self.hover = false
            self.selection:SetShown(self.selected and true or false)
        end)
        return result
    end
    local function selectButton(control, selected)
        local colors = palette()
        local color = selected and colors.accent or colors.muted
        control.selected = selected
        control.caption:SetTextColor(unpack(color))
        control.selection:SetColorTexture(unpack(colors.accent))
        control.selection:SetShown(selected or control.hover)
    end
    local function section(parent, text, x, y)
        return label(parent, text, x, y, 11, "accent")
    end
    local window = CreateFrame("Frame", "LumenUIEditor", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetSize(800, 720)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    style(window, "panel")
    self.editorFrame = window
    label(window, "LumenUI", 26, -24, 25, "text")
    label(window, "A calmer space for your adventures.", 26, -58, 12, "muted")
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -64, -1)
    header:SetHeight(82)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    button(window, "x", 746, -22, 30, 28, function() window:Hide() end).command = "close-editor"

    local function showTab(name)
        activeTab, feedback = name, nil
        for pageName, page in pairs(pages) do page:SetShown(pageName == name) end
        if refresh then refresh() end
    end
    for index, name in ipairs({ "Appearance", "Dock", "Layout", "Profiles" }) do
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 210, -105)
        page:SetSize(564, 574)
        page:Hide()
        pages[name] = page
        local tab = button(window, name, 20, -105 - (index - 1) * 44, 164, 36, function() showTab(name) end)
        tab.tabName = name
        tabs[name] = tab
    end
    local sidebarNote = label(window, "Your changes save\nautomatically.", 28, -316, 11, "muted", 148)
    sidebarNote:SetSpacing(5)
    local reset = button(window, "Reset everything", 20, -641, 164, 30, function()
        owner:ResetSettings()
        feedback = "Default settings restored."
        refresh()
    end)
    reset.command = "reset-all"
    local status = label(window, "", 210, -688, 11, "muted", 560)

    local function getElement()
        return owner:GetElementSettings(window.selectedElementId) or {}
    end
    local function checkbox(parent, text, x, y, width, key, elementKey)
        local control = CreateFrame("CheckButton", nil, parent)
        control:SetPoint("TOPLEFT", x, y)
        control:SetSize(width, 25)
        local square = CreateFrame("Frame", nil, control, "BackdropTemplate")
        square:SetPoint("TOPLEFT", 0, -2)
        square:SetSize(18, 18)
        style(square, "tile")
        local tick = square:CreateTexture(nil, "ARTWORK")
        tick:SetPoint("CENTER")
        tick:SetSize(9, 9)
        control.tick = tick
        control.title = label(control, text, 27, -4, 12, "text", width - 28)
        control.key, control.elementKey = key, elementKey
        control.isCheckbox = true
        control:SetScript("OnClick", function(self)
            if refreshing then return end
            if elementKey then
                owner:SetElementSetting(window.selectedElementId, elementKey, self:GetChecked() and true or false)
            else
                owner:SetSetting(key, self:GetChecked() and true or false)
            end
            feedback = nil
            refresh()
        end)
        controls[#controls + 1] = control
        return control
    end
    local function slider(parent, text, x, y, width, key, low, high, step, format, colorKey, elementKey)
        local control = CreateFrame("Slider", nil, parent)
        control:SetPoint("TOPLEFT", x, y - 24)
        control:SetSize(width, 12)
        control:SetOrientation("HORIZONTAL")
        control:SetMinMaxValues(low, high)
        control:SetValueStep(step)
        control:SetObeyStepOnDrag(true)
        control:SetHitRectInsets(0, 0, -7, -7)
        control:EnableMouseWheel(true)
        local track = control:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(3)
        control.track = track
        control:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        control:GetThumbTexture():SetSize(8, 14)
        control.title = label(parent, text, x, y, 11, "text")
        control.valueText = label(parent, "", x + width - 80, y, 11, "muted", 80)
        control.valueText:SetJustifyH("RIGHT")
        control.key, control.colorKey, control.elementKey = key, colorKey, elementKey
        control.minimum, control.format = low, format or integer
        control:SetScript("OnValueChanged", function(self, value)
            self.valueText:SetText(self.format(value))
            if refreshing then return end
            value = clamp(value, low, high)
            if colorKey then
                local color = owner:GetSettings().accent
                owner:SetAccent(colorKey == "r" and value or color.r, colorKey == "g" and value or color.g, colorKey == "b" and value or color.b)
            elseif elementKey then
                owner:SetElementSetting(window.selectedElementId, elementKey, value)
            else
                owner:SetSetting(key, value)
            end
            feedback = nil
            refresh()
        end)
        control:SetScript("OnMouseWheel", function(self, delta)
            self:SetValue(clamp(self:GetValue() + delta * step, low, high))
        end)
        controls[#controls + 1] = control
        return control
    end

    local appearance = pages.Appearance
    section(appearance, "COLOR THEME", 0, 0)
    local themeButtons = {}
    for index, theme in ipairs({ "dark", "light" }) do
        local control = button(appearance, theme == "dark" and "Dark" or "Light", (index - 1) * 137, -27, 124, 34, function()
            owner:SetSetting("theme", theme)
            refresh()
        end)
        control.theme = theme
        themeButtons[theme] = control
    end
    section(appearance, "ACCENT COLOR", 0, -95)
    slider(appearance, "Red", 0, -124, 260, "accent", 0, 1, 1 / 255, function(v) return integer(v * 255) end, "r")
    slider(appearance, "Green", 0, -178, 260, "accent", 0, 1, 1 / 255, function(v) return integer(v * 255) end, "g")
    slider(appearance, "Blue", 0, -232, 260, "accent", 0, 1, 1 / 255, function(v) return integer(v * 255) end, "b")
    section(appearance, "SURFACES", 0, -302)
    slider(appearance, "Window opacity", 0, -332, 260, "opacity", 0.35, 1, 0.01, percent)
    slider(appearance, "Corner radius", 0, -386, 260, "radius", 4, 32, 1, pixels)
    slider(appearance, "Editor scale", 0, -440, 260, "scale", 0.65, 1.5, 0.05, percent)
    section(appearance, "PERSONALIZE", 300, 0)
    checkbox(appearance, "Reduce motion", 300, -30, 264, "reducedMotion")
    checkbox(appearance, "Style game windows", 300, -78, 264, "skinWindows")
    checkbox(appearance, "Style action bars", 300, -119, 264, "skinActionBars")
    checkbox(appearance, "Style unit frames", 300, -160, 264, "skinUnitFrames")
    local appearanceNote = label(appearance, "A single accent ties your dock and windows together. Changes appear as you make them.", 300, -234, 12, "muted", 245)
    appearanceNote:SetSpacing(5)

    local dock = pages.Dock
    section(dock, "BEHAVIOR", 0, 0)
    checkbox(dock, "Auto-hide dock", 0, -28, 260, "dockHidden")
    checkbox(dock, "Keep dock pinned", 0, -58, 260, "dockPinned")
    checkbox(dock, "Show clock", 0, -88, 260, "dockClock")
    checkbox(dock, "Show status", 0, -118, 260, "dockStatus")
    section(dock, "SIZE & MOVEMENT", 0, -170)
    slider(dock, "Width", 0, -198, 260, "dockWidth", 360, 1200, 10, pixels)
    slider(dock, "Height", 0, -252, 260, "dockHeight", 56, 140, 2, pixels)
    slider(dock, "Scale", 0, -306, 260, "dockScale", 0.65, 1.5, 0.05, percent)
    slider(dock, "Hide delay", 0, -360, 260, "dockHideDelay", 0.1, 3, 0.05, function(v) return string.format("%.2f s", v) end)
    slider(dock, "Icon spacing", 0, -414, 260, "dockSpacing", 2, 24, 1, pixels)
    label(dock, "Drag the dock while this editor is open to place it.", 0, -488, 11, "muted", 260)
    section(dock, "DOCK ITEMS", 300, 0)
    label(dock, "Show an item, then arrange its order.", 300, -25, 11, "muted", 264)
    local dockRows = {}
    for index = 1, 12 do
        local row = CreateFrame("Frame", nil, dock)
        row:SetPoint("TOPLEFT", 300, -53 - (index - 1) * 30)
        row:SetSize(264, 27)
        local check = CreateFrame("CheckButton", nil, row)
        check:SetPoint("LEFT", 0, 0)
        check:SetSize(20, 20)
        local box = CreateFrame("Frame", nil, check, "BackdropTemplate")
        box:SetAllPoints()
        style(box, "tile")
        local tick = box:CreateTexture(nil, "ARTWORK")
        tick:SetPoint("CENTER")
        tick:SetSize(9, 9)
        check.tick = tick
        check:SetScript("OnClick", function(self)
            if row.actionId then owner:SetDockEnabled(row.actionId, self:GetChecked() and true or false); refresh() end
        end)
        row.check = check
        row.caption = label(row, "", 29, -7, 11, "text", 171)
        for direction, delta in pairs({ up = -1, down = 1 }) do
            local control = button(row, direction == "up" and "^" or "v", direction == "up" and 207 or 237, -1, 25, 25, function()
                if row.actionId then owner:MoveDockItem(row.actionId, delta); refresh() end
            end)
            control.command = "move-" .. direction
            row[direction] = control
        end
        dockRows[index] = row
    end
    window.dockRows = dockRows
    section(dock, "REVEAL AREA", 300, -428)
    slider(dock, "Hotspot width", 300, -455, 264, "dockTriggerWidth", 40, 600, 10, pixels)
    slider(dock, "Hotspot height", 300, -509, 264, "dockTriggerHeight", 4, 48, 1, pixels)

    local layout, catalog = pages.Layout, owner.layoutCatalog or {}
    section(layout, "GAME ELEMENTS", 0, 0)
    local elementButtons = {}
    window.selectedElementId = catalog[1] and catalog[1].id
    for index = 1, 14 do
        local control
        control = button(layout, "", 0, -29 - (index - 1) * 34, 164, 29, function()
            window.selectedElementId, feedback = control.elementId, nil
            refresh()
        end)
        control.caption:SetWidth(148)
        control.caption:SetWordWrap(false)
        elementButtons[index] = control
    end
    local layoutPageText = label(layout, "", 0, -506, 11, "muted", 164)
    layoutPageText:SetJustifyH("CENTER")
    local previousLayout = button(layout, "Previous", 0, -530, 77, 29, function() layoutPage = math.max(1, layoutPage - 1); refresh() end)
    local nextLayout = button(layout, "Next", 87, -530, 77, 29, function() layoutPage = layoutPage + 1; refresh() end)
    previousLayout.command, nextLayout.command = "previous-elements", "next-elements"
    local selectedElementLabel = section(layout, "", 190, 0)
    checkbox(layout, "Apply custom layout", 190, -30, 374, nil, "enabled")
    checkbox(layout, "Show element", 190, -62, 374, nil, "visible")
    slider(layout, "Horizontal position", 190, -109, 374, nil, -1920, 1920, 1, pixels, nil, "x")
    slider(layout, "Vertical position", 190, -163, 374, nil, -1080, 1080, 1, pixels, nil, "y")
    slider(layout, "Scale", 190, -217, 374, nil, 0.5, 2, 0.05, percent, nil, "scale")
    slider(layout, "Opacity", 190, -271, 374, nil, 0.1, 1, 0.01, percent, nil, "opacity")
    slider(layout, "Width", 190, -325, 374, nil, 40, 1600, 1, pixels, nil, "width").resizableOnly = true
    slider(layout, "Height", 190, -379, 374, nil, 20, 700, 1, pixels, nil, "height").resizableOnly = true
    local resetElement = button(layout, "Reset this element", 190, -434, 178, 30, function()
        owner:ResetElement(window.selectedElementId)
        feedback = "Element reset."
        refresh()
    end)
    resetElement.command = "reset-element"
    local editLayout = button(layout, "Unlock layout", 190, -484, 178, 32, function()
        if not owner.layoutEditing and InCombatLockdown and InCombatLockdown() then
            feedback = "Unlock the layout after combat."
            refresh()
            return
        end
        owner:SetLayoutEditing(not owner.layoutEditing)
        feedback = nil
        refresh()
    end)
    editLayout.command = "toggle-layout"
    button(layout, "Game Edit Mode", 386, -484, 178, 32, function() owner:RunAction("editmode") end).command = "edit-mode"
    label(layout, "Unlock to drag supported elements. Locking finishes your layout.", 190, -536, 11, "muted", 374)

    local profiles = pages.Profiles
    section(profiles, "SAVE YOUR SPACE", 0, 0)
    label(profiles, "Keep different looks for different characters or activities.", 0, -27, 12, "muted", 550)
    local nameInput = CreateFrame("EditBox", nil, profiles, "BackdropTemplate")
    nameInput:SetPoint("TOPLEFT", 0, -71)
    nameInput:SetSize(350, 34)
    style(nameInput, "tile")
    nameInput:SetFontObject("GameFontHighlight")
    nameInput:SetTextInsets(10, 10, 0, 0)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(24)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    window.profileNameInput = nameInput
    local saveProfile = button(profiles, "Save current", 370, -71, 194, 34, function()
        local name = trim(nameInput:GetText())
        if name == "" then feedback = "Enter a profile name first."; refresh(); return end
        local ok, message = owner:SaveProfile(name)
        if ok then selectedProfile = name end
        feedback = message or (ok and "Profile saved." or "Unable to save this profile.")
        refresh()
    end)
    saveProfile.command = "save-profile"
    section(profiles, "YOUR PROFILES", 0, -145)
    local profileButtons = {}
    for index = 1, 8 do
        local control
        control = button(profiles, "", 0, -174 - (index - 1) * 34, 564, 29, function()
            if control.profileName then selectedProfile = control.profileName; nameInput:SetText(selectedProfile); feedback = nil; refresh() end
        end)
        profileButtons[index] = control
    end
    local loadProfile = button(profiles, "Load selected", 0, -465, 175, 32, function()
        if not selectedProfile then return end
        local ok, message = owner:LoadProfile(selectedProfile)
        feedback = message or (ok and "Profile loaded." or "Unable to load this profile.")
        refresh()
    end)
    loadProfile.command = "load-profile"
    local deleteProfile = button(profiles, "Delete selected", 190, -465, 175, 32, function()
        if not selectedProfile then return end
        local ok, message = owner:DeleteProfile(selectedProfile)
        feedback = message or (ok and "Profile deleted." or "Unable to delete this profile.")
        selectedProfile = nil
        refresh()
    end)
    deleteProfile.command = "delete-profile"
    local pageText = label(profiles, "", 200, -525, 11, "muted", 164)
    pageText:SetJustifyH("CENTER")
    local previous = button(profiles, "Previous", 0, -515, 150, 30, function() profilePage = math.max(1, profilePage - 1); refresh() end)
    local nextPage = button(profiles, "Next", 414, -515, 150, 30, function() profilePage = profilePage + 1; refresh() end)
    previous.command, nextPage.command = "previous-profiles", "next-profiles"

    refresh = function()
        if refreshing then return end
        refreshing = true
        local settings, colors = owner:GetSettings(), palette()
        local styleKey = tostring(settings.theme) .. ":" .. tostring(settings.radius) .. ":" .. tostring(settings.opacity)
        if styleKey ~= lastStyleKey then
            for _, entry in ipairs(surfaces) do owner:StyleFrame(entry.frame, entry.variant) end
            lastStyleKey = styleKey
        end
        local availableScale = math.min((UIParent:GetWidth() - 24) / 800, (UIParent:GetHeight() - 24) / 720)
        window:SetScale(math.min(settings.scale, math.max(0.35, availableScale)))
        nameInput:SetTextColor(unpack(colors.text))
        local selectedElement
        for _, element in ipairs(catalog) do if element.id == window.selectedElementId then selectedElement = element end end
        for _, entry in ipairs(labels) do entry.object:SetTextColor(unpack(colors[entry.kind] or colors.text)) end
        for name, tab in pairs(tabs) do selectButton(tab, activeTab == name) end
        for theme, control in pairs(themeButtons) do selectButton(control, settings.theme == theme) end
        for _, control in ipairs(controls) do
            local value
            if control.elementKey then value = getElement()[control.elementKey]
            elseif control.colorKey then value = settings.accent[control.colorKey]
            else value = settings[control.key] end
            local enabled = not control.elementKey or selectedElement ~= nil
            if control.resizableOnly then enabled = enabled and selectedElement.resizable and true or false end
            control:SetEnabled(enabled)
            control:SetAlpha(enabled and 1 or 0.35)
            if control.isCheckbox then
                control:SetChecked(value and true or false)
                control.tick:SetColorTexture(unpack(colors.accent))
                control.tick:SetShown(value and true or false)
            else
                value = type(value) == "number" and value or control.minimum
                control:SetValue(value)
                control.valueText:SetText(control.format(value))
                control.track:SetColorTexture(unpack(colors.panel))
                control:GetThumbTexture():SetVertexColor(unpack(colors.accent))
                control.title:SetAlpha(enabled and 1 or 0.35)
                control.valueText:SetAlpha(enabled and 1 or 0.35)
                control:EnableMouseWheel(enabled)
            end
        end
        local available, ordered, seen = owner:GetDockActions(true) or {}, {}, {}
        local actionMap = {}
        for _, action in ipairs(available) do actionMap[action.id] = action end
        for _, id in ipairs(settings.dockOrder or {}) do
            if actionMap[id] and not seen[id] then ordered[#ordered + 1], seen[id] = actionMap[id], true end
        end
        for _, action in ipairs(available) do if not seen[action.id] then ordered[#ordered + 1], seen[action.id] = action, true end end
        for index, row in ipairs(dockRows) do
            local action = ordered[index]
            row:SetShown(action ~= nil)
            if action then
                row.actionId, row.check.actionId = action.id, action.id
                row.up.actionId, row.down.actionId = action.id, action.id
                row.caption:SetText(action.label or action.id)
                local enabled = not settings.dockEnabled or settings.dockEnabled[action.id] ~= false
                row.check:SetChecked(enabled)
                row.check.tick:SetColorTexture(unpack(colors.accent))
                row.check.tick:SetShown(enabled)
                row.up:SetEnabled(index > 1)
                row.down:SetEnabled(index < #ordered)
            end
        end
        local layoutPages = math.max(1, math.ceil(#catalog / 14))
        layoutPage = clamp(layoutPage, 1, layoutPages)
        for index, control in ipairs(elementButtons) do
            local element = catalog[(layoutPage - 1) * 14 + index]
            control.elementId = element and element.id or nil
            control:SetShown(element ~= nil)
            if element then
                control.caption:SetText(element.label)
                selectButton(control, element.id == window.selectedElementId)
            end
        end
        layoutPageText:SetText(string.format("%d / %d", layoutPage, layoutPages))
        previousLayout:SetEnabled(layoutPage > 1)
        nextLayout:SetEnabled(layoutPage < layoutPages)
        selectedElementLabel:SetText(selectedElement and selectedElement.label or "NO ELEMENTS AVAILABLE")
        editLayout.caption:SetText(owner.layoutEditing and "Lock layout" or "Unlock layout")
        selectButton(editLayout, owner.layoutEditing and true or false)
        local names = owner:GetProfileNames() or {}
        local profileExists = false
        for _, name in ipairs(names) do if selectedProfile == name then profileExists = true end end
        if not profileExists then selectedProfile = names[1] end
        local totalPages = math.max(1, math.ceil(#names / 8))
        profilePage = clamp(profilePage, 1, totalPages)
        for index, control in ipairs(profileButtons) do
            local name = names[(profilePage - 1) * 8 + index]
            control.profileName = name
            control:SetShown(name ~= nil)
            if name then control.caption:SetText(name); selectButton(control, name == selectedProfile) end
        end
        pageText:SetText(#names == 0 and "No saved profiles" or string.format("%d / %d", profilePage, totalPages))
        previous:SetEnabled(profilePage > 1)
        nextPage:SetEnabled(profilePage < totalPages)
        loadProfile:SetEnabled(selectedProfile ~= nil)
        deleteProfile:SetEnabled(selectedProfile ~= nil and selectedProfile ~= "Default")
        local statusText = feedback or "Changes save automatically."
        if not feedback and (owner.layoutPending or owner.skinPending) then
            statusText = "Some changes will apply after combat."
        elseif not feedback and activeTab == "Layout" then
            if selectedElement and type(selectedElement.frames) == "table" and #selectedElement.frames > 0 then
                local found = false
                for _, frame in ipairs(selectedElement.frames) do if type(frame) ~= "string" or _G[frame] then found = true end end
                if not found then statusText = "This element becomes available when its game window opens." end
            end
        end
        status:SetText(statusText)
        refreshing = false
    end
    window.Refresh = refresh
    window:SetScript("OnShow", function()
        if owner.SetDockEditing then owner:SetDockEditing(true) end
        refresh()
    end)
    window:SetScript("OnHide", function()
        window:StopMovingOrSizing()
        nameInput:ClearFocus()
        owner:SetLayoutEditing(false)
        if owner.SetDockEditing then owner:SetDockEditing(false) end
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "LumenUIEditor") end
    showTab("Appearance")
    refresh()
    return window
end

function addon:ToggleEditor()
    local window = self:CreateEditor()
    window:SetShown(not window:IsShown())
end

function addon:RefreshEditor()
    if self.editorFrame and self.editorFrame.Refresh then self.editorFrame.Refresh() end
end
