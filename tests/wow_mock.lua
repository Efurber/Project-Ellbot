-- A small stateful WoW API mock. This exercises addon behavior, not rendering.
local Mock = {}
local unpack = unpack or table.unpack

local Object = {}
Object.__index = Object

function Object:SetSize(width, height)
    local changed = self.width ~= width or self.height ~= height
    self.width, self.height = width, height
    if changed and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, width, height) end
end
function Object:SetWidth(value) self:SetSize(value, self:GetHeight()) end
function Object:SetHeight(value) self:SetSize(self:GetWidth(), value) end
function Object:GetWidth() return self.width or 0 end
function Object:GetHeight() return self.height or 0 end
function Object:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point end
    if type(relativePoint) == "number" then x, y, relativePoint = relativePoint, x, point end
    relative, relativePoint = relative or self.parent, relativePoint or point
    self.centerX, self.centerY = nil, nil
    local anchor = { point, relative, relativePoint, x or 0, y or 0 }
    self.points = self.points or {}
    for index, previous in ipairs(self.points) do
        if previous[1] == point then self.points[index] = anchor; return end
    end
    self.points[#self.points + 1] = anchor
end
function Object:GetPoint(index) return unpack((self.points or {})[index or 1] or {}) end
function Object:GetNumPoints() return #(self.points or {}) end
function Object:ClearAllPoints() self.points = {} end
function Object:SetAllPoints(target)
    self.allPoints = target or self.parent
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", self.allPoints, "TOPLEFT")
    self:SetPoint("BOTTOMRIGHT", self.allPoints, "BOTTOMRIGHT")
end
function Object:SetParent(parent)
    if self.parent == parent then return end
    if self.parent then
        for index = #self.parent.children, 1, -1 do
            if self.parent.children[index] == self then table.remove(self.parent.children, index) end
        end
    end
    self.parent = parent
    if parent then parent.children[#parent.children + 1] = self end
end
function Object:GetParent() return self.parent end
function Object:IsProtected() return self.protected or false end
function Object:GetChildren()
    local children = {}
    for _, child in ipairs(self.children) do
        if child.kind ~= "Texture" and child.kind ~= "FontString" then children[#children + 1] = child end
    end
    return unpack(children)
end
function Object:GetRegions()
    local regions = {}
    for _, child in ipairs(self.children) do
        if child.kind == "Texture" or child.kind == "FontString" then regions[#regions + 1] = child end
    end
    return unpack(regions)
end
function Object:SetScale(scale) self.scale = scale end
function Object:GetScale() return self.scale or 1 end
function Object:GetEffectiveScale()
    return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function Object:GetCenter()
    if self.centerX then return self.centerX, self.centerY end
    local point, relative, relativePoint, x, y = self:GetPoint()
    local centerX, centerY = 0, 0
    if relative and relative ~= self then centerX, centerY = relative:GetCenter() end
    local conversion = relative and relative:GetEffectiveScale() / self:GetEffectiveScale() or 1
    local anchors = {
        TOPLEFT = { -0.5, 0.5 }, TOP = { 0, 0.5 }, TOPRIGHT = { 0.5, 0.5 },
        LEFT = { -0.5, 0 }, CENTER = { 0, 0 }, RIGHT = { 0.5, 0 },
        BOTTOMLEFT = { -0.5, -0.5 }, BOTTOM = { 0, -0.5 }, BOTTOMRIGHT = { 0.5, -0.5 },
    }
    local own, target = anchors[point] or anchors.CENTER, anchors[relativePoint] or anchors.CENTER
    return (centerX + target[1] * (relative and relative:GetWidth() or 0)) * conversion - own[1] * self:GetWidth() + (x or 0),
        (centerY + target[2] * (relative and relative:GetHeight() or 0)) * conversion - own[2] * self:GetHeight() + (y or 0)
end
function Object:GetLeft() local x = self:GetCenter(); return x - self:GetWidth() / 2 end
function Object:GetRight() local x = self:GetCenter(); return x + self:GetWidth() / 2 end
function Object:GetTop() local _, y = self:GetCenter(); return y + self:GetHeight() / 2 end
function Object:GetBottom() local _, y = self:GetCenter(); return y - self:GetHeight() / 2 end
function Object:IsMouseOver() return self.state.mouseOver[self] or false end
function Object:SetAlpha(alpha) self.alpha = alpha end
function Object:GetAlpha() return self.alpha or 1 end
function Object:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Object:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Object:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Object:IsShown() return self.shown end
function Object:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Object:SetScript(name, handler) self.scripts[name] = handler end
function Object:GetScript(name) return self.scripts[name] end
function Object:HookScript(name, handler)
    local previous = self.scripts[name]
    self.scripts[name] = function(...)
        if previous then previous(...) end
        return handler(...)
    end
end
function Object:RegisterEvent(event) self.events[event] = true end
function Object:UnregisterEvent(event) self.events[event] = nil end
function Object:UnregisterAllEvents() self.events = {} end
function Object:IsEventRegistered(event) return self.events[event] or false end
function Object:SetMovable(movable) self.movable = movable end
function Object:IsMovable() return self.movable end
function Object:EnableMouse(enabled) self.mouseEnabled = enabled end
function Object:IsMouseEnabled() return self.mouseEnabled end
function Object:RegisterForDrag(...) self.dragButtons = { ... } end
function Object:RegisterForClicks(...) self.clickButtons = { ... } end
function Object:StartMoving() self.moving = true end
function Object:StopMovingOrSizing() self.moving = false end
function Object:SetClampedToScreen(value) self.clamped = value end
function Object:SetClipsChildren(value) self.clipsChildren = value end
function Object:SetFrameStrata(value) self.strata = value end
function Object:GetFrameStrata() return self.strata or "MEDIUM" end
function Object:SetFrameLevel(value) self.level = value end
function Object:GetFrameLevel() return self.level or 1 end
function Object:SetBackdrop(value) self.backdrop = value end
function Object:SetBackdropColor(...) self.backdropColor = { ... } end
function Object:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function Object:Enable() self.enabled = true end
function Object:Disable() self.enabled = false end
function Object:SetEnabled(enabled) self.enabled = enabled end
function Object:IsEnabled() return self.enabled ~= false end
function Object:SetText(text) self.text = tostring(text or "") end
function Object:GetText() return self.text or "" end
function Object:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end
function Object:SetTextColor(...) self.textColor = { ... } end
function Object:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
function Object:SetFont(...) self.font = { ... } end
function Object:GetFont() return unpack(self.font or { "Fonts\\FRIZQT__.TTF", 12, "" }) end
function Object:SetFontObject(font) self.fontObject = font end
function Object:SetJustifyH(value) self.justifyH = value end
function Object:SetJustifyV(value) self.justifyV = value end
function Object:SetShadowColor(...) self.shadowColor = { ... } end
function Object:GetShadowColor() return unpack(self.shadowColor or { 0, 0, 0, 1 }) end
function Object:SetShadowOffset(...) self.shadowOffset = { ... } end
function Object:GetShadowOffset() return unpack(self.shadowOffset or { 0, 0 }) end
function Object:SetWordWrap(value) self.wordWrap = value end
function Object:SetSpacing(value) self.spacing = value end
function Object:GetStringWidth() return #self:GetText() * 7 end
function Object:SetTexture(texture) self.texture, self.atlas = texture, nil end
function Object:GetTexture() return self.texture end
function Object:SetAtlas(atlas) self.atlas = atlas end
function Object:GetAtlas() return self.atlas end
function Object:SetColorTexture(...) self.color = { ... } end
function Object:SetVertexColor(...) self.vertexColor = { ... } end
function Object:GetVertexColor() return unpack(self.vertexColor or { 1, 1, 1, 1 }) end
function Object:SetBlendMode(value) self.blendMode = value end
function Object:GetBlendMode() return self.blendMode or "BLEND" end
function Object:SetDrawLayer(...) self.drawLayer = { ... } end
function Object:SetTexCoord(...) self.texCoord = { ... } end
function Object:GetTexCoord() return unpack(self.texCoord or { 0, 1, 0, 1 }) end
function Object:SetGradient(...) self.gradient = { ... } end
function Object:SetGradientAlpha(...) self.gradient = { ... } end
function Object:SetRotation(value) self.rotation = value end
function Object:GetRotation() return self.rotation or 0 end
function Object:SetHorizTile(value) self.horizTile = value end
function Object:SetVertTile(value) self.vertTile = value end
function Object:SetDesaturated(value) self.desaturated = value end
function Object:SetStatusBarTexture(texture)
    if type(texture) == "string" then
        self.statusTexture = self.statusTexture or self:CreateTexture(nil, "ARTWORK")
        self.statusTexture:SetTexture(texture)
    else
        self.statusTexture = texture
    end
end
function Object:GetStatusBarTexture() return self.statusTexture end
function Object:SetStatusBarColor(...) self.statusBarColor = { ... } end
function Object:GetStatusBarColor() return unpack(self.statusBarColor or { 1, 1, 1, 1 }) end
function Object:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function Object:GetMinMaxValues() return self.minimum or 0, self.maximum or 1 end
function Object:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function Object:GetValue() return self.value or 0 end
function Object:SetOrientation(value) self.orientation = value end
function Object:SetReverseFill(value) self.reverseFill = value end
function Object:SetValueStep(value) self.step = value end
function Object:SetObeyStepOnDrag(value) self.obeyStep = value end
function Object:SetThumbTexture(texture)
    self.thumbTexture = self:CreateTexture(nil, "OVERLAY")
    self.thumbTexture:SetTexture(texture)
end
function Object:GetThumbTexture() return self.thumbTexture end
function Object:SetChecked(value) self.checked = value end
function Object:GetChecked() return self.checked or false end
function Object:SetCheckedTexture(texture) self.checkedTexture = texture end
function Object:EnableMouseWheel(enabled) self.mouseWheel = enabled end
function Object:SetHitRectInsets(...) self.hitRectInsets = { ... } end
function Object:SetAutoFocus(value) self.autoFocus = value end
function Object:SetNumeric(value) self.numeric = value end
function Object:SetMaxLetters(value) self.maxLetters = value end
function Object:SetTextInsets(...) self.textInsets = { ... } end
function Object:ClearFocus() self.focused = false end
function Object:SetFocus() self.focused = true end
function Object:HighlightText() self.highlighted = true end
function Object:SetNormalTexture(texture) self.normalTexture = texture end
function Object:SetPushedTexture(texture) self.pushedTexture = texture end
function Object:SetHighlightTexture(texture) self.highlightTexture = texture end
function Object:SetDisabledTexture(texture) self.disabledTexture = texture end
function Object:SetNormalFontObject(font) self.normalFont = font end
function Object:SetHighlightFontObject(font) self.highlightFont = font end
function Object:SetScrollChild(child) self.scrollChild = child end
function Object:SetVerticalScroll(offset) self.verticalScroll = offset end
function Object:GetVerticalScroll() return self.verticalScroll or 0 end
function Object:GetName() return self.name end
function Object:IsObjectType(kind) return self.kind == kind or kind == "Frame" end

local function newObject(state, kind, name, parent)
    local object = setmetatable({
        state = state, kind = kind, name = name, parent = parent,
        shown = true, scripts = {}, events = {}, children = {},
    }, Object)
    state.objects[#state.objects + 1] = object
    if parent then parent.children[#parent.children + 1] = object end
    if name then _G[name] = object end
    return object
end

function Object:CreateTexture(name, layer, template, sublevel)
    local object = newObject(self.state, "Texture", name, self)
    object.layer, object.template, object.sublevel = layer, template, sublevel
    return object
end
function Object:CreateFontString(name, layer, template)
    local object = newObject(self.state, "FontString", name, self)
    object.layer, object.template = layer, template
    return object
end

function Mock.install(overrides)
    local state = {
        objects = {}, time = 0, messages = {}, calls = {}, timers = {},
        interfaceVersion = 16001, uiScale = 1, inCombat = false,
        cursorX = 960, cursorY = 540, mouseOver = {}, createNativeFrames = true,
        playerClass = "MAGE", playerName = "TestPlayer", frameRate = 120,
    }
    for key, value in pairs(overrides or {}) do state[key] = value end
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CAMELOT = 1, 18
    _G.WOW_PROJECT_ID = state.interfaceVersion == 16001 and WOW_PROJECT_CAMELOT or WOW_PROJECT_MAINLINE
    _G.UIParent = newObject(state, "Frame", "UIParent")
    UIParent:SetSize(1920, 1080)
    UIParent:SetScale(state.uiScale)
    UIParent.centerX, UIParent.centerY = 960, 540
    _G.CreateFrame = function(kind, name, parent, template)
        local frame = newObject(state, kind, name, parent or UIParent)
        frame.template = template
        return frame
    end
    _G.GetTime = function() return state.time end
    _G.GetCursorPosition = function() return state.cursorX, state.cursorY end
    _G.MouseIsOver = function(frame) return state.mouseOver[frame] or false end
    _G.InCombatLockdown = function() return state.inCombat end
    _G.GetBuildInfo = function()
        local interface = state.interfaceVersion
        local version = string.format("%d.%d.%d", math.floor(interface / 10000), math.floor(interface / 100) % 100, interface % 100)
        return version, "00000", "Oct 18 2026", interface
    end
    _G.UnitClass = function() return state.playerClass, state.playerClass, 8 end
    _G.UnitName = function() return state.playerName end
    _G.GetLocale = function() return "enUS" end
    _G.GetGameTime = function() return 13, 37 end
    _G.GetFramerate = function() return state.frameRate end
    _G.GetNetStats = function() return 0, 0, 32, 48 end
    _G.GetCVar = function() return "0" end
    _G.IsShiftKeyDown = function() return state.shiftDown or false end
    _G.SlashCmdList, _G.UISpecialFrames = {}, {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, value) state.messages[#state.messages + 1] = value end }
    _G.print = function(...) state.messages[#state.messages + 1] = table.concat({ ... }, " ") end
    _G.CreateColor = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a or 1,
            GetRGBA = function(self) return self.r, self.g, self.b, self.a end,
            GetRGB = function(self) return self.r, self.g, self.b end }
    end
    _G.hooksecurefunc = function(owner, method, callback)
        if type(owner) == "string" then owner, method, callback = _G, owner, method end
        local original = assert(owner[method], "cannot hook missing function " .. tostring(method))
        owner[method] = function(...)
            local results = { original(...) }
            callback(...)
            return unpack(results)
        end
    end
    _G.C_Timer = {}
    local function schedule(delay, callback, interval)
        local timer = { at = state.time + delay, callback = callback, interval = interval }
        function timer:Cancel() self.canceled = true end
        state.timers[#state.timers + 1] = timer
        return timer
    end
    function C_Timer.After(delay, callback) schedule(delay, callback) end
    function C_Timer.NewTimer(delay, callback) return schedule(delay, callback) end
    function C_Timer.NewTicker(interval, callback) return schedule(interval, callback, interval) end
    _G.GameTooltip = CreateFrame("Frame", "GameTooltip", UIParent)
    function GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
    function GameTooltip:AddLine(line) self.lines = self.lines or {}; self.lines[#self.lines + 1] = line end
    function GameTooltip:AddDoubleLine(left, right) self:AddLine(left .. " " .. right) end
    function GameTooltip:ClearLines() self.lines = {} end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    for _, name in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalLarge" }) do _G[name] = name end
    _G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
    _G.PlaySound = function() end
    _G.wipe = function(value) for key in pairs(value) do value[key] = nil end; return value end
    _G.strtrim = function(value) return value:match("^%s*(.-)%s*$") end
    _G.Settings = {
        OpenToCategory = function(category) state.calls[#state.calls + 1] = { "Settings.OpenToCategory", category } end,
    }
    _G.C_AddOns = {
        LoadAddOn = function(name) state.calls[#state.calls + 1] = { "C_AddOns.LoadAddOn", name }; return true end,
        IsAddOnLoaded = function() return true end,
    }
    _G.UIParentLoadAddOn = function(name) return C_AddOns.LoadAddOn(name) end
    _G.C_SpellBook = nil
    _G.C_PlayerInfo = nil
    _G.PlayerSpellsUtil = nil

    local nativeNames = {
        "PlayerFrame", "TargetFrame", "FocusFrame", "MinimapCluster", "Minimap", "ChatFrame1",
        "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
        "MultiBar5", "MultiBar6", "MultiBar7", "PlayerCastingBarFrame", "CastingBarFrame", "BuffFrame", "ObjectiveTrackerFrame",
        "MicroMenu", "BagsBar", "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "FriendsFrame", "PVEFrame",
        "QuestLogFrame", "WorldMapFrame", "AchievementFrame", "CollectionsJournal", "EncounterJournal", "GameMenuFrame",
        "GuildFrame", "CalendarFrame", "HelpFrame", "MerchantFrame", "GossipFrame", "QuestFrame", "BankFrame", "MailFrame",
    }
    for _, name in ipairs(nativeNames) do _G[name] = nil end
    for index = 1, 12 do _G["ActionButton" .. index] = nil end
    _G.PlayerFrameHealthBar, _G.PlayerFrameManaBar, _G.TargetFrameHealthBar = nil, nil, nil

    function state:createNativeUI()
        if self.nativeCreated then return end
        self.nativeCreated = true
        for index, name in ipairs(nativeNames) do
            local frame = CreateFrame("Frame", name, UIParent)
            frame:SetSize(260, 100)
            frame:SetPoint("CENTER", UIParent, "CENTER", -500 + index * 17, 200 - index * 4)
            frame.centerX, frame.centerY = 960 - 500 + index * 17, 540 + 200 - index * 4
            frame:EnableMouse(true)
            frame:SetAlpha(0.9)
            self[name] = frame
        end
        PlayerFrame.protected, TargetFrame.protected, MainActionBar.protected = true, true, true
        TargetFrame:Hide(); FocusFrame:Hide(); PlayerCastingBarFrame:Hide(); CastingBarFrame:Hide()
        MinimapCluster:SetSize(180, 180)
        MinimapCluster.centerX, MinimapCluster.centerY = 1780, 920
        Minimap:SetParent(MinimapCluster); Minimap:SetSize(160, 160)
        ChatFrame1:SetSize(400, 180); ObjectiveTrackerFrame:SetSize(250, 450)
        for _, name in ipairs({ "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "FriendsFrame", "PVEFrame", "QuestLogFrame", "WorldMapFrame", "AchievementFrame", "CollectionsJournal", "EncounterJournal", "GameMenuFrame", "GuildFrame", "CalendarFrame", "HelpFrame", "MerchantFrame", "GossipFrame", "QuestFrame", "BankFrame", "MailFrame" }) do
            local frame = _G[name]
            frame.Bg = frame:CreateTexture(nil, "BACKGROUND"); frame.Bg:SetTexture("OriginalWindowBackground"); frame.Bg:SetAlpha(0.7)
            frame.NineSlice = CreateFrame("Frame", nil, frame); frame.NineSlice:SetAlpha(0.8)
            frame.TitleText = frame:CreateFontString(nil, "OVERLAY"); frame.TitleText:SetText(name); frame.TitleText:SetTextColor(0.9, 0.8, 0.6, 1)
            frame:Hide()
        end
        for index = 1, 12 do
            local button = CreateFrame("CheckButton", "ActionButton" .. index, MainActionBar)
            button:SetSize(36, 36)
            button.icon = button:CreateTexture(nil, "ARTWORK"); button.icon:SetTexture("OriginalActionIcon"); button.icon:SetTexCoord(0, 1, 0, 1)
            button.NormalTexture = button:CreateTexture(nil, "OVERLAY"); button.NormalTexture:SetAlpha(0.75)
            button.SlotArt = button:CreateTexture(nil, "BACKGROUND"); button.SlotArt:SetAlpha(0.65)
            button.SlotBackground = button:CreateTexture(nil, "BACKGROUND"); button.SlotBackground:SetAlpha(0.55)
            button.HotKey = button:CreateFontString(nil, "OVERLAY"); button.HotKey:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
            button.Count = button:CreateFontString(nil, "OVERLAY")
            local callback = function() self.actionClicks = (self.actionClicks or 0) + 1 end
            button:SetScript("OnClick", callback); button.originalOnClick = callback
        end
        MainActionBar.BorderArt = MainActionBar:CreateTexture(nil, "OVERLAY")
        MainActionBar.EndCaps = { LeftEndCap = { Texture = MainActionBar:CreateTexture(nil, "OVERLAY") }, RightEndCap = { Texture = MainActionBar:CreateTexture(nil, "OVERLAY") } }
        local function unitVisuals(frame, key)
            frame[key .. "FrameContainer"] = { FrameTexture = frame:CreateTexture(nil, "OVERLAY") }
            local health = CreateFrame("StatusBar", nil, frame); health:SetStatusBarTexture("OriginalHealthTexture"); health:SetStatusBarColor(0.2, 0.7, 0.3, 1)
            local mana = CreateFrame("StatusBar", nil, frame); mana:SetStatusBarTexture("OriginalManaTexture")
            frame[key .. "FrameContent"] = { [key .. "FrameContentMain"] = { HealthBarsContainer = { HealthBar = health }, ManaBarArea = { ManaBar = mana }, ManaBar = mana } }
            return health, mana
        end
        _G.PlayerFrameHealthBar, _G.PlayerFrameManaBar = unitVisuals(PlayerFrame, "Player")
        _G.TargetFrameHealthBar = unitVisuals(TargetFrame, "Target")
    end
    if state.createNativeFrames then state:createNativeUI() end

    local routes = {
        ToggleCharacter = "CharacterFrame", ToggleSpellBook = "SpellBookFrame", ToggleAllBags = "BagsBar",
        ToggleWorldMap = "WorldMapFrame", ToggleFriendsFrame = "FriendsFrame", ToggleGuildFrame = "GuildFrame",
        ToggleAchievementFrame = "AchievementFrame", ToggleCollectionsJournal = "CollectionsJournal",
        ToggleEncounterJournal = "EncounterJournal", ToggleTalentFrame = "PlayerSpellsFrame",
        PVEFrame_ToggleFrame = "PVEFrame", ToggleGameMenu = "GameMenuFrame", ToggleCalendar = "CalendarFrame",
        ToggleQuestLog = "QuestLogFrame", ToggleHelpFrame = "HelpFrame",
    }
    for method, frameName in pairs(routes) do
        _G[method] = function(...)
            state.calls[#state.calls + 1] = { method, ... }
            local frame = _G[frameName]
            if frame then frame:SetShown(not frame:IsShown()) end
        end
    end

    function state:fire(event, ...)
        local frames = {}
        for _, frame in ipairs(self.objects) do if frame.events[event] then frames[#frames + 1] = frame end end
        for _, frame in ipairs(frames) do if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end end
    end
    function state:tick(elapsed)
        self.time = self.time + elapsed
        local frames = {}
        for _, frame in ipairs(self.objects) do if frame:IsVisible() and frame.scripts.OnUpdate then frames[#frames + 1] = frame end end
        for _, frame in ipairs(frames) do if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed) end end
        local due = {}
        for _, timer in ipairs(self.timers) do if not timer.canceled and timer.at <= self.time then due[#due + 1] = timer end end
        for _, timer in ipairs(due) do
            if timer.interval then timer.at = self.time + timer.interval else timer.canceled = true end
            timer.callback(timer)
        end
    end
    function state:call(frame, script, ...)
        assert(frame and frame.scripts[script], "missing " .. script .. " handler")
        return frame.scripts[script](frame, ...)
    end
    return state
end

return Mock
