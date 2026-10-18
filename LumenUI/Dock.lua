local _, addon = ...

local min, max, floor = math.min, math.max, math.floor
local ANIMATION_TIME = 0.24
local UPDATE_INTERVAL = 1 / 30

local function clamp(value, low, high)
    return max(low, min(high, value))
end

local function smooth(value)
    return value * value * (3 - 2 * value)
end

local function bounds(frame)
    if not frame or not frame:IsShown() then return end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left or not right or not top or not bottom then return end
    local scale = frame:GetEffectiveScale()
    return left * scale, right * scale, top * scale, bottom * scale
end

local function hideTooltip(button)
    if button.tooltipShown and GameTooltip then GameTooltip:Hide() end
    button.tooltipShown = nil
end

local function showTooltip(button)
    if not GameTooltip or not button.action then return end
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:AddLine(button.action.label or button.action.id, 0.96, 0.97, 1)
    if button.action.description then
        GameTooltip:AddLine(button.action.description, 0.65, 0.70, 0.78, true)
    end
    GameTooltip:AddLine("Right-click to edit the dock.", 0.52, 0.59, 0.69)
    GameTooltip:Show()
    button.tooltipShown = true
end

function addon:CreateDock()
    if self.dock then return self.dock end

    local owner = self
    local dock = CreateFrame("Frame", "LumenUIDock", UIParent)
    dock:Hide()
    dock:SetPoint("TOP", UIParent, "TOP", 0, -10)
    dock:SetSize(180, 18)
    dock:SetFrameStrata("HIGH")
    dock:SetClampedToScreen(true)
    dock:SetMovable(true)
    dock:EnableMouse(false)
    dock:RegisterForDrag("LeftButton")
    dock:SetClipsChildren(true)
    self.dock = dock
    self.dockButtons = {}
    self.dockState = {
        progress = 0, target = false, expanded = false, elapsed = 0,
        telemetryElapsed = 0, width = 720, height = 76,
    }

    -- The trigger owns no textures. It is the only interactive region at idle
    -- when the hidden-dock preference is enabled.
    local trigger = CreateFrame("Frame", "LumenUIDockTrigger", UIParent)
    trigger:SetFrameStrata("HIGH")
    trigger:EnableMouse(true)
    self.dockTrigger = trigger

    local content = CreateFrame("Frame", nil, dock)
    content:SetPoint("CENTER")
    dock.content = content
    local grid = CreateFrame("Frame", nil, content)
    dock.grid = grid
    local empty = owner:CreateLabel(grid, "Add shortcuts in the editor", 12, "muted")
    empty:SetPoint("CENTER")
    dock.emptyLabel = empty
    local compact = owner:CreateLabel(dock, "Lumen", 12, "muted")
    compact:SetPoint("CENTER")
    dock.compactLabel = compact

    local telemetry = CreateFrame("Frame", nil, content)
    telemetry:SetPoint("RIGHT", -18, 0)
    dock.telemetry = telemetry
    dock.clockLabel = owner:CreateLabel(telemetry, "00:00", 16, "text")
    dock.clockHint = owner:CreateLabel(telemetry, "SERVER TIME", 8, "muted")
    dock.fpsLabel = owner:CreateLabel(telemetry, "-- FPS", 11, "text")
    dock.latencyLabel = owner:CreateLabel(telemetry, "-- ms", 10, "muted")
    dock.divider = content:CreateTexture(nil, "ARTWORK")
    dock.divider:SetWidth(1)

    local update
    local function startUpdating()
        dock:SetScript("OnUpdate", update)
    end

    local function forcedOpen()
        local settings = owner:GetSettings()
        return settings.dockPinned or owner.dockEditing or owner.layoutEditing or dock.dragging
    end

    local function hovered()
        if trigger.hovered or dock.hovered then return true end
        for _, button in ipairs(owner.dockButtons) do
            if button:IsShown() and button.hovered then return true end
        end
        local tl, tr, tt, tb = bounds(trigger)
        local dl, dr, dt, db = bounds(dock)
        if not tl or not dl then return false end
        local x, y = GetCursorPosition()
        -- The union includes the gap between trigger and pill. It keeps the
        -- dock open during pointer travel without adding a mouse-blocking frame.
        return x >= min(tl, dl) - 4 and x <= max(tr, dr) + 4
            and y >= min(tb, db) - 4 and y <= max(tt, dt) + 4
    end

    local function refreshTelemetry()
        if GetGameTime then
            local hour, minute = GetGameTime()
            dock.clockLabel:SetText(string.format("%02d:%02d", hour or 0, minute or 0))
        else
            dock.clockLabel:SetText("--:--")
        end
        local fps = GetFramerate and GetFramerate()
        dock.fpsLabel:SetText(fps and string.format("%d FPS", floor(fps + 0.5)) or "-- FPS")
        local latency
        if GetNetStats then
            local _, _, home, world = GetNetStats()
            latency = world or home
        end
        dock.latencyLabel:SetText(latency and string.format("%d ms", floor(latency + 0.5)) or "-- ms")
    end
    dock.RefreshTelemetry = refreshTelemetry

    local function render()
        local state, settings = owner.dockState, owner:GetSettings()
        local progress = smooth(state.progress)
        local compactWidth = settings.dockHidden and min(180, state.width) or 128
        local compactHeight = settings.dockHidden and 18 or 32
        dock:SetSize(compactWidth + (state.width - compactWidth) * progress,
            compactHeight + (state.height - compactHeight) * progress)
        dock:SetAlpha(settings.dockHidden and progress or 1)
        dock.content:SetAlpha(smooth(clamp((state.progress - 0.18) / 0.82, 0, 1)))
        dock.content:SetShown(state.progress > 0)
        dock.compactLabel:SetShown(not settings.dockHidden and state.progress < 0.8)
        dock.compactLabel:SetAlpha(1 - progress)
        dock:EnableMouse(state.progress > 0 or not settings.dockHidden)
        state.expanded = state.progress >= 1
        if state.progress == 0 and not state.target then
            if settings.dockHidden then dock:Hide() else dock:Show() end
            dock:SetScript("OnUpdate", nil)
        else
            dock:Show()
        end
    end
    dock.Render = render

    update = function(_, elapsed)
        local state, settings = owner.dockState, owner:GetSettings()
        state.elapsed = state.elapsed + min(elapsed, 0.25)
        if state.elapsed < UPDATE_INTERVAL then return end
        local delta = state.elapsed
        state.elapsed = 0

        if state.target then
            if forcedOpen() or hovered() then
                state.leaveSince = nil
            else
                state.leaveSince = state.leaveSince or GetTime()
                if GetTime() - state.leaveSince >= settings.dockHideDelay then
                    state.target = false
                    state.leaveSince = nil
                end
            end
        end

        local target = state.target and 1 or 0
        if settings.reducedMotion then
            state.progress = target
        elseif state.progress < target then
            state.progress = min(1, state.progress + delta / ANIMATION_TIME)
        elseif state.progress > target then
            state.progress = max(0, state.progress - delta / (ANIMATION_TIME * 0.8))
        end
        render()

        if state.progress > 0 then
            state.telemetryElapsed = state.telemetryElapsed + delta
            if state.telemetryElapsed >= 1 then
                state.telemetryElapsed = 0
                refreshTelemetry()
            end
            for _, button in ipairs(owner.dockButtons) do
                if button:IsShown() then
                    local desired = button.hovered and 1 or 0
                    button.hoverProgress = settings.reducedMotion and desired
                        or button.hoverProgress + (desired - button.hoverProgress) * min(1, delta * 15)
                    button:SetScale(1 + button.hoverProgress * 0.07)
                    local text, accent = state.palette.text, state.palette.accent
                    local amount = button.hoverProgress
                    button.icon:SetVertexColor(text[1] + (accent[1] - text[1]) * amount,
                        text[2] + (accent[2] - text[2]) * amount, text[3] + (accent[3] - text[3]) * amount, 1)
                end
            end
        end
    end

    local function beginDrag()
        if not (owner.layoutEditing or owner.dockEditing) then return end
        owner:SetDockExpanded(true)
        dock.dragging = true
        dock:StartMoving()
    end

    local function finishDrag()
        if not dock.dragging then return end
        dock:StopMovingOrSizing()
        local centerX = dock:GetCenter()
        local top = dock:GetTop()
        local conversion = dock:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if centerX and top then
            owner:SetSetting("dockX", centerX * conversion - UIParent:GetWidth() / 2)
            owner:SetSetting("dockY", top * conversion - UIParent:GetHeight())
        end
        dock.dragging = nil
        dock.suppressClickUntil = GetTime() + 0.25
        owner:RefreshDock()
    end
    dock.BeginDrag, dock.FinishDrag = beginDrag, finishDrag

    trigger:SetScript("OnEnter", function()
        trigger.hovered = true
        owner:SetDockExpanded(true)
    end)
    trigger:SetScript("OnLeave", function()
        trigger.hovered = nil
        if owner.dockState.target then startUpdating() end
    end)
    trigger:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" then owner:ToggleEditor() end
    end)
    dock:SetScript("OnEnter", function()
        dock.hovered = true
        owner:SetDockExpanded(true)
    end)
    dock:SetScript("OnLeave", function()
        dock.hovered = nil
        if owner.dockState.target then startUpdating() end
    end)
    dock:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" and not (dock.suppressClickUntil and GetTime() < dock.suppressClickUntil) then
            owner:ToggleEditor()
        end
    end)
    dock:SetScript("OnDragStart", beginDrag)
    dock:SetScript("OnDragStop", finishDrag)
    dock:SetScript("OnHide", function()
        dock.hovered = nil
        if dock.dragging then dock:StopMovingOrSizing(); dock.dragging = nil end
        for _, button in ipairs(owner.dockButtons) do
            button.hovered = nil
            hideTooltip(button)
        end
    end)
    dock.StartUpdating = startUpdating
    self:RefreshDock()
    return dock
end

function addon:SetDockExpanded(expanded)
    if not self.dock then self:CreateDock() end
    local settings, state = self:GetSettings(), self.dockState
    state.target = expanded or settings.dockPinned or self.dockEditing or self.layoutEditing or false
    state.leaveSince = nil
    if settings.reducedMotion then state.progress = state.target and 1 or 0 end
    if state.target then
        self.dock:Show()
        self.dock.RefreshTelemetry()
    end
    self.dock.Render()
    if state.target or state.progress > 0 then self.dock.StartUpdating() end
end

function addon:SetDockEditing(enabled)
    self.dockEditing = enabled and true or false
    if not self.dock then self:CreateDock() end
    self:RefreshDock()
    if self.dockEditing then self:SetDockExpanded(true) end
end

function addon:RefreshDock()
    if not self.dock then return end
    local dock, trigger, state, settings = self.dock, self.dockTrigger, self.dockState, self:GetSettings()
    local palette = self:GetPalette()
    local scale = settings.dockScale
    local available = max(120, (UIParent:GetWidth() - 24) / scale)
    local width = min(settings.dockWidth, available)
    local actions = self:GetDockActions() or {}
    local count, spacing, rows = #actions, settings.dockSpacing, 1
    local showClock, showStatus = settings.dockClock, settings.dockStatus
    local function telemetrySize()
        local size = (showClock and 65 or 0) + (showStatus and 70 or 0)
        return size > 0 and size + 16 or 0
    end
    local minimumColumns = max(1, math.ceil(count / 3))
    local minimumGrid = minimumColumns * 24 + (minimumColumns - 1) * spacing
    if width - 40 - telemetrySize() < minimumGrid then showStatus = false end
    if width - 40 - telemetrySize() < minimumGrid then showClock = false end
    local telemetryWidth = telemetrySize()
    local gridWidth = max(40, width - 40 - telemetryWidth)
    if minimumColumns > 1 then
        spacing = min(spacing, max(0, (gridWidth - minimumColumns * 18) / (minimumColumns - 1)))
    end
    local columns, tile = max(1, count), 44
    repeat
        columns = max(1, math.ceil(count / rows))
        tile = min(44, (gridWidth - spacing * (columns - 1)) / columns)
        if tile >= 30 or rows >= 3 then break end
        rows = rows + 1
    until false
    tile = max(18, tile)
    local gridHeight = rows * tile + (rows - 1) * spacing
    state.width = width
    state.height = max(settings.dockHeight, gridHeight + 12)
    state.palette = palette
    dock:SetScale(scale)
    dock:SetMovable(self.layoutEditing or self.dockEditing or false)
    if not dock.dragging then
        local horizontal = max(0, (UIParent:GetWidth() - width * scale) / 2 - 8)
        local x = clamp(settings.dockX, -horizontal, horizontal)
        local y = clamp(settings.dockY, -max(0, UIParent:GetHeight() - state.height * scale - 8), 0)
        dock:ClearAllPoints()
        dock:SetPoint("TOP", UIParent, "TOP", x / scale, y / scale)
        trigger:ClearAllPoints()
        trigger:SetPoint("TOP", UIParent, "TOP", x, 0)
    end
    trigger:SetSize(min(settings.dockTriggerWidth, UIParent:GetWidth()), settings.dockTriggerHeight)
    trigger:Show()
    dock.content:SetSize(width, state.height)
    dock.grid:ClearAllPoints()
    dock.grid:SetPoint("LEFT", dock.content, "LEFT", 20, 0)
    dock.grid:SetSize(gridWidth, gridHeight)
    dock.emptyLabel:SetShown(count == 0)
    dock.compactLabel:SetTextColor(unpack(palette.muted))
    dock.emptyLabel:SetTextColor(unpack(palette.muted))
    self:StyleFrame(dock, "dock")

    for index, action in ipairs(actions) do
        local button = self.dockButtons[index]
        if not button then
            button = CreateFrame("Button", nil, dock.grid)
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetPoint("CENTER")
            button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button.hoverProgress = 0
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button:RegisterForDrag("LeftButton")
            button:SetScript("OnEnter", function(self)
                self.hovered = true
                addon:SetDockExpanded(true)
                showTooltip(self)
            end)
            button:SetScript("OnLeave", function(self)
                self.hovered = nil
                hideTooltip(self)
            end)
            button:SetScript("OnHide", function(self)
                self.hovered = nil
                hideTooltip(self)
            end)
            button:SetScript("OnClick", function(self, mouseButton)
                if dock.dragging or (dock.suppressClickUntil and GetTime() < dock.suppressClickUntil) then return end
                if mouseButton == "RightButton" then addon:ToggleEditor()
                elseif self.action then addon:RunAction(self.action.id) end
            end)
            button:SetScript("OnDragStart", dock.BeginDrag)
            button:SetScript("OnDragStop", dock.FinishDrag)
            self.dockButtons[index] = button
        end
        button.action, button.actionId = action, action.id
        button:SetSize(tile, tile)
        local column, row = (index - 1) % columns, floor((index - 1) / columns)
        local rowCount = min(columns, count - row * columns)
        local rowWidth = rowCount * tile + (rowCount - 1) * spacing
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", dock.grid, "TOPLEFT", (gridWidth - rowWidth) / 2 + column * (tile + spacing), -row * (tile + spacing))
        button.icon:SetSize(max(14, tile - 13), max(14, tile - 13))
        button.icon:SetTexture(action.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        button.icon:SetVertexColor(unpack(palette.text))
        self:StyleFrame(button, "tile")
        button:Show()
    end
    for index = count + 1, #self.dockButtons do self.dockButtons[index]:Hide() end

    dock.telemetry:SetSize(max(1, telemetryWidth - 16), max(40, state.height - 24))
    dock.clockLabel:ClearAllPoints()
    dock.clockHint:ClearAllPoints()
    dock.fpsLabel:ClearAllPoints()
    dock.latencyLabel:ClearAllPoints()
    dock.clockLabel:SetPoint("LEFT", dock.telemetry, "LEFT", 0, 7)
    dock.clockHint:SetPoint("LEFT", dock.telemetry, "LEFT", 0, -11)
    local statusX = showClock and 70 or 0
    dock.fpsLabel:SetPoint("LEFT", dock.telemetry, "LEFT", statusX, 7)
    dock.latencyLabel:SetPoint("LEFT", dock.telemetry, "LEFT", statusX, -10)
    dock.clockLabel:SetShown(showClock)
    dock.clockHint:SetShown(showClock)
    dock.fpsLabel:SetShown(showStatus)
    dock.latencyLabel:SetShown(showStatus)
    dock.clockLabel:SetTextColor(unpack(palette.text))
    dock.fpsLabel:SetTextColor(unpack(palette.text))
    dock.clockHint:SetTextColor(unpack(palette.muted))
    dock.latencyLabel:SetTextColor(unpack(palette.muted))
    dock.divider:ClearAllPoints()
    dock.divider:SetPoint("LEFT", dock.content, "LEFT", width - telemetryWidth - 9, 0)
    dock.divider:SetHeight(min(30, state.height - 24))
    dock.divider:SetColorTexture(palette.muted[1], palette.muted[2], palette.muted[3], 0.18)
    dock.divider:SetShown(telemetryWidth > 0)
    dock.RefreshTelemetry()
    if settings.dockPinned or self.dockEditing or self.layoutEditing then state.target = true end
    if settings.reducedMotion then state.progress = state.target and 1 or 0 end
    dock.Render()
    if state.target or state.progress > 0 then dock.StartUpdating() end
end
