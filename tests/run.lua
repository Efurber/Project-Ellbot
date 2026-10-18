-- Run from the repository root: lua5.1 tests/run.lua
-- These stateful API tests do not validate actual client rendering or protected execution.
local root = (arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]+$")) or "."
local Mock = assert(loadfile(root .. "/tests/wow_mock.lua"))()
local tests, passed = {}, 0

local function test(name, callback) tests[#tests + 1] = { name, callback } end
local function equal(actual, expected, context)
    assert(actual == expected, (context or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, context)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.00001,
        (context or "number") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(values, expected)
    for _, value in ipairs(values) do if value == expected then return true end end
    return false
end
local function find(state, predicate)
    for _, object in ipairs(state.objects) do if predicate(object) then return object end end
    error("requested UI control was not created")
end
local function control(state, field, value)
    return find(state, function(object) return object[field] == value end)
end
local function advance(state, seconds)
    local count = math.ceil(seconds / 0.05)
    for _ = 1, count do state:tick(seconds / count) end
end
local function loadAddon(saved, overrides)
    local state = Mock.install(overrides)
    _G.LumenUIDB = saved
    local addon, files, interfaces = {}, {}, {}
    local toc = assert(io.open(root .. "/LumenUI/LumenUI.toc", "r"))
    for line in toc:lines() do
        local values = line:match("^##%s*Interface:%s*(.-)%s*$")
        if values then for version in values:gmatch("%d+") do interfaces[tonumber(version)] = true end end
        local filename = line:match("^%s*(.-%.lua)%s*$")
        if filename and not filename:match("^#") then files[#files + 1] = filename end
    end
    toc:close()
    assert(interfaces[state.interfaceVersion], "TOC does not declare interface " .. state.interfaceVersion)
    for _, filename in ipairs(files) do
        assert(loadfile(root .. "/LumenUI/" .. filename))("LumenUI", addon)
    end
    state:fire("ADDON_LOADED", "LumenUI")
    state:fire("PLAYER_LOGIN")
    assert(addon.dock and addon.dockTrigger and addon:GetSettings(), "addon did not initialize")
    return addon, state
end
local function anchors(frame)
    local result = {}
    for index = 1, frame:GetNumPoints() do result[index] = { frame:GetPoint(index) } end
    return result
end
local function sameAnchors(frame, original)
    equal(frame:GetNumPoints(), #original, "anchor count")
    for index, point in ipairs(original) do
        local actual = { frame:GetPoint(index) }
        for slot, value in ipairs(point) do equal(actual[slot], value, "anchor field " .. slot) end
    end
end

-- Metadata validation runs before Lua chunks, catching client packaging mistakes.
test("manifest boots mocked Forever and Retail clients with an invisible idle dock", function()
    for _, client in ipairs({ { 16001, "1.60.1", 18 }, { 120100, "12.1.0", 1 }, { 120105, "12.1.5", 1 } }) do
        local addon = loadAddon(nil, { interfaceVersion = client[1] })
        local version, _, _, interface = GetBuildInfo()
        equal(version, client[2]); equal(interface, client[1]); equal(WOW_PROJECT_ID, client[3])
        equal(addon:GetSettings().dockHidden, true)
        assert(not addon.dock:IsShown(), "idle auto-hidden dock must be invisible")
        assert(not addon.dock:GetScript("OnUpdate"), "hidden idle dock must not poll every frame")
        assert(addon.dockTrigger:IsShown() and addon.dockTrigger:IsMouseEnabled())
        equal(#{ addon.dockTrigger:GetRegions() }, 0, "idle reveal area must have no visible artwork")
        equal(SLASH_LUMENUI1, "/lumen")
    end
    local ok, failure = pcall(loadAddon, nil, { interfaceVersion = 120001 })
    assert(not ok and tostring(failure):find("TOC does not declare interface 120001", 1, true))
end)

test("dock hover animates open, bridges child hover, and closes after its delay", function()
    local addon, state = loadAddon()
    state:call(addon.dockTrigger, "OnEnter")
    advance(state, 0.3)
    assert(addon.dock:IsShown() and addon.dockState.expanded)
    near(addon.dockState.progress, 1)
    local button = assert(addon.dockButtons[1])
    state:call(button, "OnEnter")
    state:call(addon.dockTrigger, "OnLeave")
    advance(state, addon:GetSettings().dockHideDelay + 0.5)
    assert(addon.dockState.target, "hovering a child button must keep the dock open")
    assert(GameTooltip:IsShown(), "dock shortcut should explain its action")
    state:call(button, "OnLeave")
    state.cursorX, state.cursorY = 0, 0
    advance(state, addon:GetSettings().dockHideDelay / 2)
    assert(addon.dock:IsShown(), "leaving should respect the configured grace period")
    advance(state, addon:GetSettings().dockHideDelay + 0.5)
    assert(not addon.dock:IsShown())
    assert(not addon.dock:GetScript("OnUpdate"), "closed dock must release its update handler")
    assert(not GameTooltip:IsShown())
end)

test("dock hover corridor covers pointer travel between the screen edge and open buttons", function()
    local addon, state = loadAddon()
    state:call(addon.dockTrigger, "OnEnter")
    advance(state, 0.3)
    state:call(addon.dockTrigger, "OnLeave")
    local scale = addon.dock:GetEffectiveScale()
    local centerX = addon.dock:GetCenter()
    state.cursorX = centerX * scale
    state.cursorY = (addon.dock:GetTop() * scale + addon.dockTrigger:GetBottom() * addon.dockTrigger:GetEffectiveScale()) / 2
    advance(state, addon:GetSettings().dockHideDelay + 0.3)
    assert(addon.dockState.target, "pointer travel through the hover corridor must not collapse the dock")
end)

test("pinning, editing, compact mode, and reduced motion control dock visibility", function()
    local addon, state = loadAddon()
    addon:SetSetting("reducedMotion", true)
    addon:SetDockExpanded(true)
    near(addon.dockState.progress, 1, "reduced motion should open immediately")
    addon:SetDockExpanded(false)
    near(addon.dockState.progress, 0)
    assert(not addon.dock:IsShown())
    addon:SetSetting("dockPinned", true)
    advance(state, 2)
    assert(addon.dock:IsShown() and addon.dockState.target)
    addon:SetSetting("dockPinned", false)
    state.cursorX, state.cursorY = 0, 0
    advance(state, addon:GetSettings().dockHideDelay + 0.3)
    assert(not addon.dock:IsShown())
    addon:SetSetting("dockHidden", false)
    assert(addon.dock:IsShown() and addon.dock.compactLabel:IsShown(), "compact mode should retain a small pill")
    addon:SetDockEditing(true)
    assert(addon.dockState.target and addon.dock:IsMovable())
    addon:SetDockEditing(false)
    advance(state, addon:GetSettings().dockHideDelay + 0.3)
    assert(not addon.dock:IsMovable())
end)

test("scaled dock dragging saves stable UIParent coordinates independently of editor scale", function()
    local addon, state = loadAddon(nil, { uiScale = 0.85 })
    addon:SetSetting("dockScale", 1.2)
    addon:SetSetting("reducedMotion", true)
    addon:SetDockEditing(true)
    state:call(addon.dock, "OnDragStart", "LeftButton")
    assert(addon.dock.moving)
    addon.dock:ClearAllPoints()
    addon.dock:SetPoint("TOP", UIParent, "TOP", 100, -50)
    state:call(addon.dock, "OnDragStop")
    assert(not addon.dock.moving)
    near(addon:GetSettings().dockX, 120, "horizontal position should be stored in UIParent units")
    near(addon:GetSettings().dockY, -60)
    local x = addon.dock:GetCenter()
    local top = addon.dock:GetTop()
    local conversion = addon.dock:GetEffectiveScale() / UIParent:GetEffectiveScale()
    near(x * conversion - UIParent:GetWidth() / 2, 120)
    near(top * conversion - UIParent:GetHeight(), -60)
    addon:SetSetting("scale", 1.3)
    near(addon.dock:GetScale(), 1.2, "editor scaling must not change dock scale")
    local reloaded = loadAddon(LumenUIDB, { uiScale = 0.85 })
    near(reloaded:GetSettings().dockX, 120)
    near(reloaded:GetSettings().dockY, -60)
end)

test("selected dock actions can be disabled, reordered, restored, and routed to native UI", function()
    local addon, state = loadAddon()
    local original = addon:GetDockActions()
    assert(#original >= 2)
    local first, second = original[1].id, original[2].id
    assert(addon:SetDockEnabled(first, false))
    for _, action in ipairs(addon:GetDockActions()) do assert(action.id ~= first) end
    assert(addon:SetDockEnabled(first, true))
    assert(addon:MoveDockItem(second, -1))
    equal(addon:GetDockActions()[1].id, second)
    equal(addon.dockButtons[1].actionId, second, "visible shortcuts should follow saved order")
    local character = find(state, function(object) return object.actionId == "character" and object.action end)
    state:call(character, "OnClick", "LeftButton")
    assert(CharacterFrame:IsShown())
    equal(state.calls[#state.calls][1], "ToggleCharacter")
    addon:SetSetting("dockClock", false)
    addon:SetSetting("dockStatus", false)
    assert(not addon.dock.clockLabel:IsShown() and not addon.dock.fpsLabel:IsShown())
end)

test("native action routing guards combat and handles unavailable APIs safely", function()
    local addon, state = loadAddon()
    state.inCombat = true
    local count = #state.calls
    assert(not addon:RunAction("character"))
    equal(#state.calls, count, "combat-blocked actions must not invoke native toggles")
    assert(addon:RunAction("editor"), "cosmetic editor should remain accessible in combat")
    assert(addon.editorFrame:IsShown())
    addon:ToggleEditor()
    state.inCombat = false
    _G.ToggleSpellBook, _G.PlayerSpellsUtil = nil, nil
    _G.PlayerSpellsFrame, _G.SpellBookFrame = nil, nil
    local ok, result = pcall(function() return addon:RunAction("spells") end)
    assert(ok and not result, "missing client panels should return an unavailable result rather than error")
    assert(not addon:RunAction("unknown-action"))
end)

test("settings sanitize malformed saved data and persist independent profile snapshots", function()
    local addon = loadAddon({ settings = {
        theme = "bad", dockHidden = "bad", opacity = -10, radius = math.huge, scale = 0 / 0,
        dockWidth = -100, dockHeight = 9999, dockHideDelay = "bad",
        accent = { r = -1, g = 3, b = "bad" },
        dockOrder = { "map", "map", "missing" }, dockEnabled = { map = false },
    }, profiles = "bad", activeProfile = "missing" })
    local settings = addon:GetSettings()
    equal(settings.theme, "dark")
    equal(settings.dockHidden, true)
    assert(settings.opacity >= 0.35 and settings.opacity <= 1)
    assert(settings.radius >= 4 and settings.radius <= 32)
    assert(settings.scale >= 0.65 and settings.scale <= 1.5)
    assert(settings.dockWidth >= 360 and settings.dockWidth <= 1200)
    assert(settings.dockHeight >= 56 and settings.dockHeight <= 140)
    near(settings.accent.r, 0); near(settings.accent.g, 1)
    equal(settings.dockOrder[1], "map")
    local seen = {}
    for _, id in ipairs(settings.dockOrder) do assert(not seen[id]); seen[id] = true; assert(id ~= "missing") end
    addon:SetSetting("theme", "light")
    addon:SetSetting("dockWidth", 860)
    addon:SetAccent(0.2, 0.4, 0.6)
    assert(addon:SaveProfile("Raiding"))
    addon:SetAccent(0.8, 0.7, 0.1)
    addon:SetSetting("dockWidth", 600)
    assert(addon:LoadProfile("Raiding"))
    equal(addon:GetSettings().theme, "light")
    equal(addon:GetSettings().dockWidth, 860)
    near(addon:GetSettings().accent.r, 0.2)
    local reloaded = loadAddon(LumenUIDB)
    equal(reloaded:GetSettings().dockWidth, 860)
    assert(contains(reloaded:GetProfileNames(), "Raiding"))
    assert(not reloaded:SaveProfile("Default"))
    assert(not reloaded:DeleteProfile("Default"))
    assert(reloaded:DeleteProfile("Raiding"))
    assert(not contains(reloaded:GetProfileNames(), "Raiding"))
    reloaded:ResetSettings()
    equal(reloaded:GetSettings().theme, "dark")
    equal(reloaded:GetSettings().dockHidden, true)
    near(reloaded:GetSettings().accent.r, reloaded.defaults.accent.r)
end)

test("layout overrides move, scale, fade, and reset native frames without altering defaults", function()
    local addon, state = loadAddon()
    local frame = state.PlayerFrame
    local original = anchors(frame)
    local alpha, scale, width, height = frame:GetAlpha(), frame:GetScale(), frame:GetWidth(), frame:GetHeight()
    assert(not addon:GetElementSettings("player").enabled)
    sameAnchors(frame, original)
    addon:SetElementSetting("player", "x", 120)
    addon:SetElementSetting("player", "y", -80)
    addon:SetElementSetting("player", "scale", 1.25)
    addon:SetElementSetting("player", "opacity", 0.55)
    local _, relative = frame:GetPoint()
    local centerX, centerY = frame:GetCenter()
    local uiX, uiY = UIParent:GetCenter()
    local conversion = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    equal(relative, UIParent)
    near(centerX * conversion - uiX, 120, "scaled frame horizontal position in UIParent coordinates")
    near(centerY * conversion - uiY, -80, "scaled frame vertical position in UIParent coordinates")
    near(frame:GetScale(), 1.25); near(frame:GetAlpha(), 0.55)
    addon:ResetElement("player")
    sameAnchors(frame, original)
    near(frame:GetAlpha(), alpha); near(frame:GetScale(), scale)
    near(frame:GetWidth(), width); near(frame:GetHeight(), height)
end)

test("layout resizes supported panels and preserves native dynamic visibility", function()
    local addon, state = loadAddon()
    addon:SetElementSetting("chat", "width", 620)
    addon:SetElementSetting("chat", "height", 260)
    near(state.ChatFrame1:GetWidth(), 620); near(state.ChatFrame1:GetHeight(), 260)
    addon:ResetElement("chat")
    near(state.ChatFrame1:GetWidth(), 400); near(state.ChatFrame1:GetHeight(), 180)
    assert(not state.TargetFrame:IsShown())
    addon:SetElementSetting("target", "visible", true)
    assert(not state.TargetFrame:IsShown(), "visible override must not invent a selected target")
    addon:SetElementSetting("target", "visible", false)
    state.TargetFrame:Show()
    assert(not state.TargetFrame:IsShown(), "native show attempts should respect an explicit hidden override")
    addon:ResetElement("target")
end)

test("protected layout changes defer during combat and late frames initialize on addon events", function()
    local addon, state = loadAddon()
    local original = anchors(state.PlayerFrame)
    state.inCombat = true
    addon:SetElementSetting("player", "x", 180)
    assert(addon.layoutPending)
    sameAnchors(state.PlayerFrame, original)
    state.inCombat = false
    state:fire("PLAYER_REGEN_ENABLED")
    assert(not addon.layoutPending)
    local _, _, _, x = state.PlayerFrame:GetPoint()
    near(x, 180)
    local late, lateState = loadAddon(nil, { createNativeFrames = false })
    late:SetElementSetting("player", "x", 90)
    lateState:createNativeUI()
    lateState:fire("ADDON_LOADED", "Blizzard_UnitFrame")
    local _, _, _, lateX = lateState.PlayerFrame:GetPoint()
    near(lateX, 90, "late native frames should receive saved overrides")
end)

test("layout handles drag hidden elements and lock safely through combat transitions", function()
    local addon, state = loadAddon()
    addon:SetLayoutEditing(true)
    local handle = find(state, function(object)
        if object:GetParent() ~= addon.layoutHandleRoot then return false end
        for _, region in ipairs({ object:GetRegions() }) do
            if region.kind == "FontString" and region:GetText():find("Target", 1, true) then return true end
        end
        return false
    end)
    assert(handle:IsShown() and not state.TargetFrame:IsShown(), "hidden native elements need visible independent handles")
    state:call(handle, "OnDragStart", "LeftButton")
    handle:ClearAllPoints(); handle:SetPoint("CENTER", UIParent, "CENTER", 200, -150)
    state:call(handle, "OnDragStop")
    near(addon:GetElementSettings("target").x, 200)
    near(addon:GetElementSettings("target").y, -150)
    assert(not state.TargetFrame:IsShown(), "moving a target handle must not invent a selected target")
    state.inCombat = true
    state:fire("PLAYER_REGEN_DISABLED")
    assert(not addon.layoutEditing and not addon.layoutHandleRoot:IsShown())
    state.inCombat = false
    state:fire("PLAYER_REGEN_ENABLED")
    assert(addon.layoutEditing and addon.layoutHandleRoot:IsShown())
    addon.layoutHandleRoot:Hide()
    assert(not addon.layoutEditing, "closing the handle layer should finish layout editing")
end)

test("skins restore original artwork, typography, icons, and native button handlers", function()
    local addon, state = loadAddon()
    local button, window = ActionButton1, CharacterFrame
    near(window.Bg:GetAlpha(), 0)
    near(window.NineSlice:GetAlpha(), 0)
    near(button.NormalTexture:GetAlpha(), 0)
    local left, right = button.icon:GetTexCoord()
    near(left, 0.08); near(right, 0.92)
    equal(button:GetScript("OnClick"), button.originalOnClick, "styling must preserve secure action callbacks")
    equal(PlayerFrameHealthBar:GetStatusBarTexture():GetTexture(), "Interface\\Buttons\\WHITE8X8")
    addon:SetSetting("skinWindows", false)
    addon:SetSetting("skinActionBars", false)
    addon:SetSetting("skinUnitFrames", false)
    near(window.Bg:GetAlpha(), 0.7); near(window.NineSlice:GetAlpha(), 0.8)
    near(button.NormalTexture:GetAlpha(), 0.75)
    left, right = button.icon:GetTexCoord()
    near(left, 0); near(right, 1)
    local font, size, flags = button.HotKey:GetFont()
    equal(font, STANDARD_TEXT_FONT); equal(size, 12); equal(flags, "OUTLINE")
    equal(PlayerFrameHealthBar:GetStatusBarTexture():GetTexture(), "OriginalHealthTexture")
    equal(button:GetScript("OnClick"), button.originalOnClick)
    state:call(button, "OnClick")
    equal(state.actionClicks, 1)
    assert(not window.lumenSurface.shown and not button.lumenSurface.shown)
end)

test("skin toggles defer in combat and apply after regeneration", function()
    local addon, state = loadAddon()
    state.inCombat = true
    addon:SetSetting("skinWindows", false)
    assert(addon.skinPending)
    near(CharacterFrame.Bg:GetAlpha(), 0)
    state.inCombat = false
    state:fire("PLAYER_REGEN_ENABLED")
    assert(not addon.skinPending)
    near(CharacterFrame.Bg:GetAlpha(), 0.7)
end)

test("editor controls update settings, keep disabled shortcuts available, and manage profiles", function()
    local addon, state = loadAddon()
    addon:ToggleEditor()
    local editor = addon.editorFrame
    assert(editor:IsShown() and addon.dockEditing)
    assert(not addon.layoutEditing, "opening settings must not unlock the game layout")
    control(state, "key", "dockWidth"):SetValue(880)
    equal(addon:GetSettings().dockWidth, 880)
    control(state, "colorKey", "r"):SetValue(0.45)
    near(addon:GetSettings().accent.r, 0.45)
    local actionCheck = find(state, function(object) return object.kind == "CheckButton" and object.actionId == "character" end)
    actionCheck:SetChecked(false); state:call(actionCheck, "OnClick")
    equal(addon:GetSettings().dockEnabled.character, false)
    actionCheck = find(state, function(object) return object.kind == "CheckButton" and object.actionId == "character" and object:IsShown() end)
    actionCheck:SetChecked(true); state:call(actionCheck, "OnClick")
    equal(addon:GetSettings().dockEnabled.character, true, "disabled items must remain available to re-enable")
    editor.profileNameInput:SetText("Exploration")
    state:call(control(state, "command", "save-profile"), "OnClick")
    assert(contains(addon:GetProfileNames(), "Exploration"))
    addon:SetSetting("dockWidth", 600)
    state:call(control(state, "command", "load-profile"), "OnClick")
    equal(addon:GetSettings().dockWidth, 880)
    addon:ToggleEditor()
    assert(not editor:IsShown() and not addon.dockEditing and not addon.layoutEditing)
end)

for _, item in ipairs(tests) do
    local ok, failure = pcall(item[2])
    if ok then passed = passed + 1; io.write("PASS " .. item[1] .. "\n")
    else io.write("FAIL " .. item[1] .. "\n  " .. tostring(failure) .. "\n") end
end
io.write(string.format("%d/%d functional tests passed\n", passed, #tests))
if passed ~= #tests then error("functional tests failed", 0) end
