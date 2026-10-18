local _, addon = ...

-- These globals are present in the Forever 1.60.1 Blizzard UI. Alternatives
-- cover the older names still used by some Blizzard modules.
addon.layoutCatalog = {
    { id = "player", label = "Player", frames = { "PlayerFrame" } },
    { id = "target", label = "Target", frames = { "TargetFrame" }, dynamic = true },
    { id = "focus", label = "Focus", frames = { "FocusFrame" }, dynamic = true },
    { id = "party", label = "Party", frames = { "PartyFrame", "CompactPartyFrame" }, dynamic = true },
    { id = "raid", label = "Raid", frames = { "CompactRaidFrameContainer" }, dynamic = true },
    { id = "minimap", label = "Minimap", frames = { "MinimapCluster", "Minimap" } },
    { id = "chat", label = "Chat", frames = { "ChatFrame1" }, resizable = true },
    { id = "primary", label = "Primary action bar", frames = { "MainActionBar", "MainMenuBar" } },
    { id = "bottomLeft", label = "Bottom left action bar", frames = { "MultiBarBottomLeft" } },
    { id = "bottomRight", label = "Bottom right action bar", frames = { "MultiBarBottomRight" } },
    { id = "sideRight", label = "Right action bar", frames = { "MultiBarRight" } },
    { id = "sideLeft", label = "Left action bar", frames = { "MultiBarLeft" } },
    { id = "extra5", label = "Action bar 5", frames = { "MultiBar5" } },
    { id = "extra6", label = "Action bar 6", frames = { "MultiBar6" } },
    { id = "extra7", label = "Action bar 7", frames = { "MultiBar7" } },
    { id = "cast", label = "Cast bar", frames = { "PlayerCastingBarFrame", "CastingBarFrame" }, dynamic = true },
    { id = "buffs", label = "Buffs", frames = { "BuffFrame" } },
    { id = "objectives", label = "Objectives", frames = { "ObjectiveTrackerFrame" }, resizable = true, dynamic = true },
    { id = "micro", label = "Micro menu", frames = { "MicroMenu" } },
    { id = "bags", label = "Bag buttons", frames = { "BagsBar" } },
}

addon.layoutRanges = {
    x = { -5000, 5000 }, y = { -5000, 5000 }, scale = { 0.5, 2 }, opacity = { 0.1, 1 },
    width = { 100, 1600 }, height = { 50, 1400 },
}

local points = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local catalog, records, hooked, generated = {}, {}, {}, {}
local applying, updatingHandles, changingEditing = false, false, false
local finishDrag, attachDrag
for _, entry in ipairs(addon.layoutCatalog) do catalog[entry.id] = entry end

local function number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

local function clamp(value, low, high, fallback)
    if not number(value) then return fallback end
    return math.max(low, math.min(high, value))
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function blocked(frame)
    return inCombat() and frame.IsProtected and frame:IsProtected()
end

local function scaleOf(frame)
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    return number(scale) and scale > 0 and scale or 1
end

local function centerOffset(frame)
    local x, y = frame:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    if not number(x) or not number(y) or not number(centerX) or not number(centerY) then return 0, 0 end
    local frameScale, uiScale = scaleOf(frame), scaleOf(UIParent)
    return (x * frameScale - centerX * uiScale) / uiScale,
        (y * frameScale - centerY * uiScale) / uiScale
end

function addon:GetLayoutElement(id)
    return catalog[id]
end

function addon:FindLayoutFrame(id)
    local entry = catalog[id]
    if not entry then return end
    for _, name in ipairs(entry.frames) do
        local frame = _G[name]
        if frame and frame.GetPoint and frame.GetCenter and frame.SetPoint
            and not (frame.IsForbidden and frame:IsForbidden()) then return frame, entry end
    end
end

local function defaults(frame)
    local x, y = 0, 0
    if frame then x, y = centerOffset(frame) end
    return {
        enabled = false, point = "CENTER", x = x, y = y,
        scale = frame and clamp(frame:GetScale(), 0.5, 2, 1) or 1,
        opacity = frame and clamp(frame:GetAlpha(), 0.1, 1, 1) or 1,
        visible = true, width = 0, height = 0,
    }
end

function addon:GetElementSettings(id)
    local entry = catalog[id]
    if not entry then return end
    local settings = self:GetSettings()
    if type(settings.layout) ~= "table" then settings.layout = {} end
    local value = settings.layout[id]
    if type(value) ~= "table" then
        value = defaults(self:FindLayoutFrame(id))
        settings.layout[id] = value
        generated[value] = true
    end
    local base = defaults()
    value.enabled = value.enabled == true
    value.point = points[value.point] and value.point or "CENTER"
    value.visible = value.visible ~= false
    for key, limits in pairs(self.layoutRanges) do
        if (key == "width" or key == "height") and (not entry.resizable or value[key] == 0 or value[key] == nil) then
            value[key] = 0
        else
            value[key] = clamp(value[key], limits[1], limits[2], base[key])
        end
    end
    return value
end

local function snapshot(frame)
    local original = {
        anchors = {}, scale = frame:GetScale(), alpha = frame:GetAlpha(),
        mouse = frame.IsMouseEnabled and frame:IsMouseEnabled(), shown = frame:IsShown(),
        width = frame:GetWidth(), height = frame:GetHeight(),
    }
    local count = frame.GetNumPoints and frame:GetNumPoints() or 1
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        if point then
            original.anchors[#original.anchors + 1] = {
                point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y,
            }
        end
    end
    return original
end

local function releaseVisibility(record)
    if not record.manualHidden then return end
    local frame, entry = record.frame, record.entry
    record.manualHidden = nil
    -- A unit can disappear while its frame is manually hidden. Ask Blizzard's
    -- unit updater for current visibility instead of reviving an empty target.
    if (entry.id == "target" or entry.id == "focus" or entry.id == "objectives")
        and type(frame.Update) == "function" then
        frame:Update()
    elseif entry.id == "party" and type(frame.UpdateVisibility) == "function" then
        frame:UpdateVisibility()
    elseif entry.id == "raid" and type(frame.TryUpdate) == "function" then
        frame:TryUpdate()
        if record.engineWantedShown then frame:Show() end
    elseif entry.id == "party" and frame == PartyFrame and record.engineWantedShown then
        -- PartyFrame is a container: its OnShow refreshes member visibility.
        -- Showing that previously shown container does not invent party units.
        frame:Show()
    elseif not entry.dynamic and record.engineWantedShown then
        frame:Show()
    end
    record.engineWantedShown = nil
end

local function restore(record)
    if not record.original then return true end
    local frame, original = record.frame, record.original
    if blocked(frame) or (record.manualHidden and inCombat()) then return false end
    frame:SetScale(original.scale)
    frame:ClearAllPoints()
    for _, anchor in ipairs(original.anchors) do
        frame:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint, anchor.x, anchor.y)
    end
    frame:SetAlpha(original.alpha)
    if original.mouse ~= nil and frame.EnableMouse then frame:EnableMouse(original.mouse) end
    if record.widthTouched then frame:SetWidth(original.width) end
    if record.heightTouched then frame:SetHeight(original.height) end
    releaseVisibility(record)
    record.original, record.applied, record.widthTouched, record.heightTouched = nil, nil, nil, nil
    return true
end

local function nativeChanged(record, visibility)
    if applying then return end
    if visibility ~= nil and record.manualHidden then record.engineWantedShown = visibility end
    if record.dragging then
        if attachDrag then attachDrag(record) end
        return
    end
    local settings = addon:GetSettings()
    local override = settings.layout and settings.layout[record.entry.id]
    if override and override.enabled then
        addon:ApplyLayout()
    elseif addon.layoutEditing then
        addon:UpdateLayoutHandles()
    end
end

local function hook(record)
    local frame = record.frame
    if hooked[frame] then return end
    hooked[frame] = true
    local id = record.entry.id
    local function changed(visibility)
        local current = records[id]
        if current and current.frame == frame then nativeChanged(current, visibility) end
    end
    if hooksecurefunc then
        for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetScale", "SetAlpha", "SetSize", "SetWidth", "SetHeight" }) do
            if type(frame[method]) == "function" then
                hooksecurefunc(frame, method, function() changed() end)
            end
        end
        if type(frame.Show) == "function" then
            hooksecurefunc(frame, "Show", function() changed(true) end)
        end
        if type(frame.Hide) == "function" then
            hooksecurefunc(frame, "Hide", function() changed(false) end)
        end
    end
    if frame.HookScript then
        frame:HookScript("OnShow", function() changed(true) end)
        frame:HookScript("OnHide", function() changed(false) end)
        frame:HookScript("OnSizeChanged", function() changed() end)
    end
end

local function recordFor(entry, frame)
    local record = records[entry.id]
    if record and record.frame ~= frame then
        if not restore(record) then return nil, true end
        if record.handle then record.handle:Hide() end
        if addon.layoutHandles then addon.layoutHandles[entry.id] = nil end
        records[entry.id] = nil
        record = nil
    end
    if not record and frame then
        record = { entry = entry, frame = frame }
        records[entry.id] = record
    end
    return record
end

local function apply(record, settings)
    local frame = record.frame
    if blocked(frame) or (inCombat() and (settings.visible == false or record.manualHidden)) then return false end
    if record.dragging then return true end
    if not record.original then record.original = snapshot(frame) end
    frame:SetScale(settings.scale)
    local factor = scaleOf(UIParent) / scaleOf(frame)
    frame:ClearAllPoints()
    frame:SetPoint(settings.point, UIParent, "CENTER", settings.x * factor, settings.y * factor)
    frame:SetAlpha(settings.opacity)
    if record.entry.resizable then
        if settings.width > 0 then
            frame:SetWidth(settings.width)
            record.widthTouched = true
        elseif record.widthTouched then
            frame:SetWidth(record.original.width)
            record.widthTouched = nil
        end
        if settings.height > 0 then
            frame:SetHeight(settings.height)
            record.heightTouched = true
        elseif record.heightTouched then
            frame:SetHeight(record.original.height)
            record.heightTouched = nil
        end
    end
    if settings.visible == false then
        if not record.manualHidden then
            record.engineWantedShown = frame:IsShown()
            record.manualHidden = true
        end
        frame:Hide()
    else
        releaseVisibility(record)
    end
    record.applied = true
    return true
end

function addon:ApplyLayout()
    if applying then return end
    applying = true
    local pending, unavailable = false, false
    self.layoutAvailability = self.layoutAvailability or {}
    local layout = self:GetSettings().layout or {}
    for _, entry in ipairs(self.layoutCatalog) do
        local frame = self:FindLayoutFrame(entry.id)
        self.layoutAvailability[entry.id] = frame ~= nil
        local value = layout[entry.id]
        local record, waiting = recordFor(entry, frame)
        if waiting then
            pending = true
        elseif frame and record then
            if (value and value.enabled) or self.layoutEditing then hook(record) end
            if value and value.enabled then
                if not apply(record, self:GetElementSettings(entry.id)) then pending = true end
            elseif record.original and not restore(record) then
                pending = true
            end
        elseif value and value.enabled then
            unavailable = true
        end
    end
    self.layoutPending = pending
    self.layoutStatus = pending and "Protected or visibility changes will apply after combat."
        or unavailable and "Some elements will appear when their Blizzard module loads."
        or "Layout is up to date."
    applying = false
    self:UpdateLayoutHandles()
end

local function seedFirstEdit(id, settings)
    if settings.enabled or not generated[settings] then return end
    local frame = addon:FindLayoutFrame(id)
    if not frame then return end
    local base = defaults(frame)
    settings.point, settings.x, settings.y = base.point, base.x, base.y
    settings.scale, settings.opacity = base.scale, base.opacity
    generated[settings] = nil
end

function addon:SetElementSetting(id, key, value)
    local entry = catalog[id]
    if not entry then return false end
    if key == "enabled" or key == "visible" then
        if type(value) ~= "boolean" then return false end
    elseif key == "point" then
        if not points[value] then return false end
    elseif self.layoutRanges[key] then
        if not number(value) or ((key == "width" or key == "height") and not entry.resizable) then return false end
        local limits = self.layoutRanges[key]
        if not ((key == "width" or key == "height") and value == 0) then
            value = clamp(value, limits[1], limits[2], limits[1])
        end
    else
        return false
    end
    local settings = self:GetElementSettings(id)
    seedFirstEdit(id, settings)
    settings[key] = value
    if key ~= "enabled" then settings.enabled = true end
    self:ApplyLayout()
    if self.RefreshEditor then self:RefreshEditor() end
    return true
end

function addon:ResetElement(id)
    if not catalog[id] then return false end
    local settings = self:GetSettings()
    if settings.layout then settings.layout[id] = nil end
    self:ApplyLayout()
    if self.RefreshEditor then self:RefreshEditor() end
    return true
end

local function ensureHandleRoot()
    if addon.layoutHandleRoot then return addon.layoutHandleRoot end
    local root = CreateFrame("Frame", "LumenUILayoutHandles", UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("DIALOG")
    root:SetFrameLevel(20)
    root:Hide()
    root:SetScript("OnHide", function()
        if addon.layoutEditing and not changingEditing then addon:SetLayoutEditing(false) end
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "LumenUILayoutHandles") end
    addon.layoutHandleRoot = root
    return root
end

attachDrag = function(record)
    if applying or blocked(record.frame) then return end
    applying = true
    record.frame:ClearAllPoints()
    record.frame:SetPoint("CENTER", record.handle, "CENTER", 0, 0)
    applying = false
end

finishDrag = function(record)
    if not record.dragging then return end
    record.handle:StopMovingOrSizing()
    record.dragging = nil
    local x, y = centerOffset(record.handle)
    local settings = addon:GetElementSettings(record.entry.id)
    settings.enabled, settings.point = true, "CENTER"
    settings.x, settings.y = clamp(x, -5000, 5000, 0), clamp(y, -5000, 5000, 0)
    generated[settings] = nil
    addon:ApplyLayout()
    if addon.RefreshEditor then addon:RefreshEditor() end
end

local function createHandle(record)
    local handle = CreateFrame("Frame", nil, ensureHandleRoot(), "BackdropTemplate")
    record.handle = handle
    addon.layoutHandles = addon.layoutHandles or {}
    addon.layoutHandles[record.entry.id] = handle
    handle.lumenElementId = record.entry.id
    handle:SetMovable(true)
    handle:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    addon:StyleFrame(handle, "tile")
    local label = addon:CreateLabel(handle, record.entry.label, 12, "accent")
    label:SetPoint("CENTER")
    record.label = label
    handle:SetScript("OnDragStart", function()
        if not addon.layoutEditing then return end
        local settings = addon:GetElementSettings(record.entry.id)
        seedFirstEdit(record.entry.id, settings)
        settings.enabled = true
        if not record.original and not blocked(record.frame) then record.original = snapshot(record.frame) end
        record.dragging = true
        handle:StartMoving()
        attachDrag(record)
    end)
    handle:SetScript("OnDragStop", function() finishDrag(record) end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not record.dragging then addon:ResetElement(record.entry.id) end
    end)
    handle:SetScript("OnHide", function() finishDrag(record) end)
    return handle
end

function addon:UpdateLayoutHandles()
    if updatingHandles or applying then return end
    updatingHandles = true
    for _, entry in ipairs(self.layoutCatalog) do
        local record = records[entry.id]
        if record then
            if self.layoutEditing and record.frame then
                local handle = record.handle or createHandle(record)
                if not record.dragging then
                    local frame, uiScale = record.frame, scaleOf(UIParent)
                    local x, y = centerOffset(frame)
                    local settings = self:GetSettings().layout and self:GetSettings().layout[entry.id]
                    if settings and settings.enabled and blocked(frame) and settings.point == "CENTER" then
                        x, y = settings.x, settings.y
                    end
                    handle:ClearAllPoints()
                    handle:SetPoint("CENTER", UIParent, "CENTER", x, y)
                    handle:SetSize(math.max(100, frame:GetWidth() * scaleOf(frame) / uiScale),
                        math.max(30, frame:GetHeight() * scaleOf(frame) / uiScale))
                    local visible
                    if frame.IsVisible then visible = frame:IsVisible() else visible = frame:IsShown() end
                    record.label:SetText(entry.label .. (visible and "" or " (hidden)"))
                    handle:SetAlpha(visible and 0.9 or 0.65)
                    self:StyleFrame(handle, "tile")
                end
                handle:Show()
            elseif record.handle then
                record.handle:Hide()
            end
        end
    end
    updatingHandles = false
end

function addon:SetLayoutEditing(enabled)
    enabled = enabled == true
    if changingEditing then return end
    changingEditing = true
    if not enabled then
        for _, record in pairs(records) do finishDrag(record) end
    end
    self.layoutEditing = enabled
    if enabled then ensureHandleRoot():Show()
    elseif self.layoutHandleRoot then self.layoutHandleRoot:Hide() end
    self:ApplyLayout()
    changingEditing = false
    if self.RefreshEditor then self:RefreshEditor() end
end
