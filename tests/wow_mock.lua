-- A small stateful WoW API mock. This exercises addon behavior, not rendering.
local Mock = {}
local unpack = unpack or table.unpack

local Object = {}
Object.__index = Object

function Object:SetSize(width, height) self.width, self.height = width, height end
function Object:SetWidth(value) self.width = value end
function Object:SetHeight(value) self.height = value end
function Object:GetWidth() return self.width or 0 end
function Object:GetHeight() return self.height or 0 end
function Object:SetPoint(...) self.point = { ... } end
function Object:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 }) end
function Object:ClearAllPoints() self.point = nil end
function Object:SetAllPoints(target) self.allPoints = target or self.parent end
function Object:SetParent(parent) self.parent = parent end
function Object:GetParent() return self.parent end
function Object:SetScale(scale) self.scale = scale end
function Object:GetScale() return self.scale or 1 end
function Object:GetEffectiveScale() return self:GetScale() end
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
function Object:SetFont(...) self.font = { ... } end
function Object:SetFontObject(font) self.fontObject = font end
function Object:SetJustifyH(value) self.justifyH = value end
function Object:SetJustifyV(value) self.justifyV = value end
function Object:SetShadowColor(...) self.shadowColor = { ... } end
function Object:SetShadowOffset(...) self.shadowOffset = { ... } end
function Object:SetWordWrap(value) self.wordWrap = value end
function Object:SetSpacing(value) self.spacing = value end
function Object:GetStringWidth() return #self:GetText() * 7 end
function Object:SetTexture(texture) self.texture = texture end
function Object:GetTexture() return self.texture end
function Object:SetColorTexture(...) self.color = { ... } end
function Object:SetVertexColor(...) self.vertexColor = { ... } end
function Object:GetVertexColor() return unpack(self.vertexColor or { 1, 1, 1, 1 }) end
function Object:SetBlendMode(value) self.blendMode = value end
function Object:SetDrawLayer(...) self.drawLayer = { ... } end
function Object:SetTexCoord(...) self.texCoord = { ... } end
function Object:SetGradient(...) self.gradient = { ... } end
function Object:SetGradientAlpha(...) self.gradient = { ... } end
function Object:SetRotation(value) self.rotation = value end
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
        objects = {}, time = 0, xp = 250, xpMax = 1000, rested = 350,
        playerLevel = 20, maxLevel = 90, messages = {}, openedSettings = nil,
        interfaceVersion = 120100,
    }
    for key, value in pairs(overrides or {}) do state[key] = value end

    _G.UIParent = newObject(state, "Frame", "UIParent")
    UIParent:SetSize(1920, 1080)
    _G.CreateFrame = function(kind, name, parent, template)
        local frame = newObject(state, kind, name, parent or UIParent)
        frame.template = template
        return frame
    end
    _G.GetTime = function() return state.time end
    _G.UnitXP = function(unit) assert(unit == "player"); return state.xp end
    _G.UnitXPMax = function(unit) assert(unit == "player"); return state.xpMax end
    _G.GetXPExhaustion = function() return state.rested end
    _G.UnitLevel = function(unit) assert(unit == "player"); return state.playerLevel end
    _G.GetMaxPlayerLevel = function() return state.maxLevel end
    _G.GetMaxLevelForPlayerExpansion = function() return state.maxLevel end
    _G.GetAccountExpansionLevel = function() return 11 end
    _G.GetExpansionLevel = function() return 11 end
    _G.GetBuildInfo = function()
        local interface = state.interfaceVersion
        local version = string.format("%d.%d.%d", math.floor(interface / 10000), math.floor(interface / 100) % 100, interface % 100)
        return version, "00000", "Oct 18 2026", interface
    end
    _G.IsXPUserDisabled = function() return state.xpDisabled or false end
    _G.InCombatLockdown = function() return state.inCombat or false end
    _G.issecretvalue = function(value) return state.secretValue ~= nil and value == state.secretValue end
    _G.UnitName = function() return "TestPlayer" end
    _G.IsShiftKeyDown = function() return state.shiftDown or false end
    _G.GetCursorPosition = function() return 960, 540 end
    _G.GetLocale = function() return "enUS" end
    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, value) state.messages[#state.messages + 1] = value end }
    _G.print = function(...) state.messages[#state.messages + 1] = table.concat({ ... }, " ") end
    _G.CreateColor = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a or 1,
            GetRGBA = function(self) return self.r, self.g, self.b, self.a end,
            GetRGB = function(self) return self.r, self.g, self.b end }
    end
    _G.C_Timer = {
        After = function(_, callback) callback() end,
        NewTicker = function(_, callback) return { Cancel = function() end, callback = callback } end,
    }
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name)
            return { panel = panel, name = name, GetID = function() return name end }
        end,
        RegisterAddOnCategory = function(category) state.settingsCategory = category end,
        OpenToCategory = function(category) state.openedSettings = category end,
    }
    _G.InterfaceOptions_AddCategory = function(panel) state.legacyPanel = panel end
    _G.InterfaceOptionsFrame_OpenToCategory = function(panel) state.openedSettings = panel end
    _G.ColorPickerFrame = newObject(state, "Frame", "ColorPickerFrame", UIParent)
    function ColorPickerFrame:SetupColorPickerAndShow(info)
        self.info, self.rgb = info, { info.r, info.g, info.b }
        self:Show()
    end
    function ColorPickerFrame:GetColorRGB() return unpack(self.rgb or { 1, 1, 1 }) end
    _G.GameTooltip = newObject(state, "Frame", "GameTooltip", UIParent)
    function GameTooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function GameTooltip:AddLine(line) self.lines = self.lines or {}; self.lines[#self.lines + 1] = line end
    function GameTooltip:AddDoubleLine(left, right) self:AddLine(left .. " " .. right) end
    function GameTooltip:ClearLines() self.lines = {} end
    _G.GameFontNormal = "GameFontNormal"
    _G.GameFontNormalSmall = "GameFontNormalSmall"
    _G.GameFontHighlight = "GameFontHighlight"
    _G.GameFontHighlightSmall = "GameFontHighlightSmall"
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.BACKDROP_TOOLTIP_16_16_5555 = {}
    _G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1 }
    _G.PlaySound = function() end
    _G.wipe = function(value) for key in pairs(value) do value[key] = nil end; return value end
    _G.strtrim = function(value) return value:match("^%s*(.-)%s*$") end

    function state:fire(event, ...)
        local frames = {}
        for _, frame in ipairs(self.objects) do
            if frame.events[event] then frames[#frames + 1] = frame end
        end
        for _, frame in ipairs(frames) do
            if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
        end
    end
    function state:tick(elapsed)
        self.time = self.time + elapsed
        for _, frame in ipairs(self.objects) do
            if frame:IsVisible() and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed) end
        end
    end
    function state:call(frame, script, ...)
        assert(frame and frame.scripts[script], "missing " .. script .. " handler")
        return frame.scripts[script](frame, ...)
    end
    return state
end

return Mock
