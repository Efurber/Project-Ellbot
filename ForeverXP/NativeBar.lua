local _, addon = ...

-- Keep Blizzard's XP frame and its manager in control of positioning, visibility,
-- and XP updates. Only the XP frame's appearance is changed by this module.
local records = {}
local chromeRecords = {}
local managerHooks = {}
local containerHooks = {}
local frameHooks = {}
local applying = false
local refreshing = false

local function protectedInCombat(frame)
    return InCombatLockdown and InCombatLockdown() and frame and frame.IsProtected and frame:IsProtected()
end

local function protectedXP(frame)
    if not frame then return false end
    return protectedInCombat(frame) or protectedInCombat(frame.StatusBar)
        or protectedInCombat(frame.OverlayFrame) or protectedInCombat(frame.ExhaustionTick)
end

local function refreshFromNative()
    if applying or refreshing or not addon.bar or not addon.db then return end
    refreshing = true
    addon:Refresh()
    refreshing = false
end

local function hookFrame(frame)
    if not frame or frameHooks[frame] or not frame.HookScript then return end
    frameHooks[frame] = true
    frame:HookScript("OnShow", refreshFromNative)
    frame:HookScript("OnHide", refreshFromNative)
    frame:HookScript("OnSizeChanged", refreshFromNative)
end

local function hookManager(manager)
    if not manager or managerHooks[manager] or not hooksecurefunc then return end
    managerHooks[manager] = true
    for _, method in ipairs({ "UpdateBarsShown", "UpdateBarVisuals", "CheckForLayoutChange" }) do
        if type(manager[method]) == "function" then
            hooksecurefunc(manager, method, refreshFromNative)
        end
    end
end

local function hookContainer(container)
    if containerHooks[container] or not hooksecurefunc then return end
    containerHooks[container] = true
    -- Fade callbacks apply a pending bar after the manager's update has already
    -- returned. Refresh after the new shownBarIndex is committed as well.
    for _, method in ipairs({ "ApplyPendingBarToShow", "UpdateShownState" }) do
        if type(container[method]) == "function" then
            hooksecurefunc(container, method, refreshFromNative)
        end
    end
end

local function discover()
    local bars, seen, containers = {}, {}, {}
    local experience = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
        and StatusTrackingBarInfo.BarsEnum.Experience or 4

    local function add(frame)
        if not frame or seen[frame] or not frame.GetWidth or not frame.SetAlpha then return end
        seen[frame] = true
        bars[#bars + 1] = frame
        if not records[frame] then records[frame] = { frame = frame } end
        hookFrame(frame)
        if frame.StatusBar then hookFrame(frame.StatusBar) end
    end

    local function addContainer(container)
        if not container then return end
        hookContainer(container)
        hookFrame(container)
        if container.bars and container.bars[experience] then
            local frame = container.bars[experience]
            containers[container] = frame
            add(frame)
        end
    end

    local manager = StatusTrackingBarManager
    hookManager(manager)
    if manager then
        if manager.barContainers then
            for _, container in pairs(manager.barContainers) do addContainer(container) end
        end
        addContainer(manager.MainStatusTrackingBarContainer)
        addContainer(manager.SecondaryStatusTrackingBarContainer)
    end
    addContainer(MainStatusTrackingBarContainer)
    addContainer(SecondaryStatusTrackingBarContainer)

    -- This fallback is restricted to the legacy player XP bar, never pet XP,
    -- reputation, honor, or the shared status-tracking containers.
    if MainMenuExpBar and MainMenuExpBar.SetMinMaxValues then add(MainMenuExpBar) end
    return bars, seen, containers, experience
end

local function setContainerChrome(containers, experience, suppress)
    local wanted = {}
    local function add(region, container)
        if region and region.GetAlpha and region.SetAlpha then wanted[region] = container end
    end
    if suppress then
        for container, xp in pairs(containers) do
            local shown = container.GetShownBar and container:GetShownBar()
            local selected = shown and shown == xp or (not shown and container.shownBarIndex == experience)
            if selected then
                add(container.BarFrameTexture, container)
                local pool = container.HorizontalDividersPool
                if pool and pool.EnumerateActive then
                    for divider in pool:EnumerateActive() do add(divider, container) end
                end
            end
        end
    end
    -- A container can switch to reputation or honor without changing frames.
    -- Restore its chrome immediately, including any dividers released by its pool.
    for region, original in pairs(chromeRecords) do
        if not wanted[region] then
            region:SetAlpha(original.alpha)
            if original.mouse ~= nil and region.EnableMouse then region:EnableMouse(original.mouse) end
            chromeRecords[region] = nil
        end
    end
    for region, container in pairs(wanted) do
        if not chromeRecords[region] then
            chromeRecords[region] = {
                alpha = region:GetAlpha(), mouse = region.IsMouseEnabled and region:IsMouseEnabled(),
                container = container,
            }
        end
        region:SetAlpha(0)
        if chromeRecords[region].mouse ~= nil and region.EnableMouse then region:EnableMouse(false) end
    end
end

local function setSuppressed(record, suppressed)
    local frame = record.frame
    if suppressed and not record.suppressed then
        record.alpha = frame:GetAlpha()
        record.mouse = frame.IsMouseEnabled and frame:IsMouseEnabled()
        record.childMouse = {}
        for _, key in ipairs({ "StatusBar", "OverlayFrame", "ExhaustionTick" }) do
            local child = frame[key]
            if child and child.IsMouseEnabled and child.EnableMouse then
                record.childMouse[#record.childMouse + 1] = { frame = child, enabled = child:IsMouseEnabled() }
            end
        end
        record.suppressed = true
    end
    if suppressed then
        frame:SetAlpha(0)
        if frame.EnableMouse then frame:EnableMouse(false) end
        for _, child in ipairs(record.childMouse) do child.frame:EnableMouse(false) end
    elseif record.suppressed then
        frame:SetAlpha(record.alpha)
        if record.mouse ~= nil and frame.EnableMouse then frame:EnableMouse(record.mouse) end
        for _, child in ipairs(record.childMouse) do child.frame:EnableMouse(child.enabled) end
        record.suppressed = nil
        record.alpha, record.mouse, record.childMouse = nil, nil, nil
    end
end

local function setSkinVisuals(record, skinned)
    if skinned then
        if not record.visuals then
            record.visuals = {}
            local frame = record.frame
            for _, key in ipairs({ "OverlayFrame", "ExhaustionTick", "ExhaustionLevelFillBar" }) do
                local region = frame[key]
                if region and region.GetAlpha and region.SetAlpha then
                    record.visuals[#record.visuals + 1] = {
                        region = region, alpha = region:GetAlpha(),
                        mouse = region.IsMouseEnabled and region:IsMouseEnabled(),
                    }
                end
            end
        end
        for _, visual in ipairs(record.visuals) do
            visual.region:SetAlpha(0)
            if visual.mouse ~= nil and visual.region.EnableMouse then visual.region:EnableMouse(false) end
        end
    elseif record.visuals then
        for _, visual in ipairs(record.visuals) do
            visual.region:SetAlpha(visual.alpha)
            if visual.mouse ~= nil and visual.region.EnableMouse then visual.region:EnableMouse(visual.mouse) end
        end
        record.visuals = nil
    end
end

local function restoreColor(record)
    if not record.color then return end
    record.statusBar:SetStatusBarColor(unpack(record.color))
    record.color, record.statusBar = nil, nil
end

local function chooseTarget(bars)
    -- Both containers own an XP instance. Only one normally displays it; keep
    -- the overlay attached to the instance Blizzard currently shows.
    for _, frame in ipairs(bars) do
        if frame.IsVisible and frame:IsVisible() then return frame end
    end
    for _, frame in ipairs(bars) do
        if frame.IsShown and frame:IsShown() then return frame end
    end
    for _, frame in ipairs(bars) do
        if frame == addon.nativeTarget then return frame end
    end
    return bars[1]
end

local function dimensions(frame, fallbackWidth, fallbackHeight)
    local width, height = frame:GetWidth(), frame:GetHeight()
    if type(width) ~= "number" or width <= 0 then width = fallbackWidth end
    if type(height) ~= "number" or height <= 0 then height = fallbackHeight end
    return width, height
end

function addon:ApplyBarPlacement()
    local bar, settings = self.bar, self.db
    if not bar or not settings then return false, 620, 22 end
    if applying then
        local placement = self.nativePlacement
        return self.nativeActive or false, placement and placement.width or settings.width,
            placement and placement.height or settings.height
    end
    applying = true
    local bars, present, containers, experience = discover()
    self.nativeBars = bars
    local nativeRequested = settings.displayMode ~= "custom" and not self.previewEnabled
    local target = nativeRequested and chooseTarget(bars) or nil
    local anchor = target and (target.StatusBar or target)

    -- Do not modify protected frames or their placement during combat. The
    -- core retries this method on PLAYER_REGEN_ENABLED.
    local blocked = protectedInCombat(bar) or protectedXP(target) or protectedInCombat(anchor)
    for frame, record in pairs(records) do
        if (present[frame] or record.suppressed or record.visuals or record.color)
            and protectedXP(frame) then
            blocked = true
        end
    end
    for container in pairs(containers) do
        if protectedInCombat(container) then blocked = true end
    end
    for region, original in pairs(chromeRecords) do
        if protectedInCombat(region) or protectedInCombat(original.container) then blocked = true end
    end
    if blocked then
        self.nativePlacementDeferred = true
        self.nativeStatus = "The display change will apply after combat."
        applying = false
        local placement = self.nativePlacement
        return self.nativeActive or false, placement and placement.width or settings.width,
            placement and placement.height or settings.height
    end

    self.nativePlacementDeferred = false
    local width, height
    if target then
        width, height = dimensions(anchor, target:GetWidth(), target:GetHeight())
        width, height = math.max(1, width), math.max(1, height)
        if bar:GetParent() ~= target then bar:SetParent(target) end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
        bar:SetScale(1)
        bar:SetSize(width, height)
        bar:SetFrameStrata(target.GetFrameStrata and target:GetFrameStrata() or "MEDIUM")
        bar:SetFrameLevel((anchor.GetFrameLevel and anchor:GetFrameLevel() or 1) + 10)
        if bar.SetClampedToScreen then bar:SetClampedToScreen(false) end
        self.nativeActive, self.nativeTarget = true, target
        self.nativeStatus = "Skinning Blizzard's XP bar in its original position."
    else
        width, height = settings.width, settings.height
        if bar:GetParent() ~= UIParent then bar:SetParent(UIParent) end
        bar:SetFrameStrata("MEDIUM")
        bar:SetFrameLevel((UIParent.GetFrameLevel and UIParent:GetFrameLevel() or 0) + 10)
        bar:SetScale(settings.scale)
        bar:SetSize(width, height)
        if bar.SetClampedToScreen then bar:SetClampedToScreen(true) end
        if not self.dragging then
            local position = settings.position
            bar:ClearAllPoints()
            bar:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
        end
        self.nativeActive, self.nativeTarget = false, nil
        if self.previewEnabled then
            self.nativeStatus = "Showing sample XP; your selected display returns when settings close."
        elseif settings.displayMode == "custom" then
            self.nativeStatus = "The custom XP bar replaces Blizzard's XP bar."
        else
            self.nativeStatus = "Blizzard's XP bar is unavailable; using custom placement."
        end
    end

    -- Restore the native parent before drawing a mounted skin. In custom or
    -- sample mode suppress only player-XP instances, including hidden ones
    -- which Blizzard may show later while switching its shared containers.
    for frame, record in pairs(records) do
        if self.nativeActive then
            setSuppressed(record, false)
            setSkinVisuals(record, frame == target)
        else
            setSkinVisuals(record, false)
            setSuppressed(record, present[frame])
        end
        if not self.nativeActive or not present[frame] then restoreColor(record) end
    end
    setContainerChrome(containers, experience, not self.nativeActive)
    self.nativePlacement = { width = width, height = height }
    self.nativePlacementReady = true
    applying = false
    return self.nativeActive, width, height
end

function addon:PaintNativeBar(red, green, blue)
    if not self.nativeActive or self.nativePlacementDeferred or self.previewEnabled then return end
    for _, frame in ipairs(self.nativeBars or {}) do
        local statusBar = frame.StatusBar or frame
        if statusBar.SetStatusBarColor and statusBar.GetStatusBarColor and not protectedInCombat(statusBar) then
            local record = records[frame]
            if not record.color then
                record.color = { statusBar:GetStatusBarColor() }
                record.statusBar = statusBar
            end
            statusBar:SetStatusBarColor(red, green, blue, 1)
        end
    end
end
