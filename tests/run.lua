-- Run from the repository root: lua5.1 tests/run.lua
-- WoW rendering, texture clipping, and real client API changes need an in-game check.
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
local function different(left, right)
    if #left ~= #right then return true end
    for index, value in ipairs(left) do
        if type(value) == "number" and math.abs(value - right[index]) > 0.00001 then return true end
    end
    return false
end

local function loadAddon(saved, overrides)
    local state = Mock.install(overrides)
    _G.ForeverXPDB = saved
    local addon = {}
    local toc = assert(io.open(root .. "/ForeverXP/ForeverXP.toc", "r"))
    local files, supportedInterfaces = {}, {}
    for line in toc:lines() do
        local interfaces = line:match("^##%s*Interface:%s*(.-)%s*$")
        if interfaces then
            for interface in interfaces:gmatch("%d+") do supportedInterfaces[tonumber(interface)] = true end
        end
        local file = line:match("^%s*(.-%.lua)%s*$")
        if file and not file:match("^#") then
            files[#files + 1] = file
        end
    end
    toc:close()
    assert(supportedInterfaces[state.interfaceVersion], "TOC does not declare interface " .. state.interfaceVersion)
    for _, file in ipairs(files) do
        assert(loadfile(root .. "/ForeverXP/" .. file))("ForeverXP", addon)
    end
    state:fire("ADDON_LOADED", "ForeverXP")
    state:fire("PLAYER_LOGIN")
    assert(addon.bar and addon.fill and addon.state, "addon did not initialize its XP bar")
    return addon, state
end

local function find(state, predicate)
    for _, object in ipairs(state.objects) do
        if predicate(object) then return object end
    end
    error("requested UI control was not created")
end

local function findCaption(state, caption)
    return find(state, function(object)
        return object.caption and object.caption:GetText() == caption
    end)
end

local function rainbowColors(addon)
    local colors = {}
    for _, texture in ipairs(addon.rainbowSegments) do
        local r, g, b = texture.gradient[2]:GetRGB()
        colors[#colors + 1], colors[#colors + 2], colors[#colors + 3] = r, g, b
    end
    return colors
end

local function particleState(addon)
    local values = {}
    for _, texture in ipairs(addon.classEffects.particles) do
        if texture:IsShown() then
            local _, _, _, x, y = texture:GetPoint()
            for _, value in ipairs({ x, y, texture:GetWidth(), texture:GetHeight(), texture:GetAlpha(), texture:GetRotation() }) do
                values[#values + 1] = value
            end
        end
    end
    return values
end

test("manifest admits mocked Forever 1.60.1 and Retail clients for XP and settings", function()
    for _, client in ipairs({ { 16001, "1.60.1", 60 }, { 120100, "12.1.0", 90 }, { 120105, "12.1.5", 90 } }) do
        local addon, state = loadAddon(nil, { interfaceVersion = client[1] })
        local version, _, _, interface = GetBuildInfo()
        equal(version, client[2], "mock client version")
        equal(interface, client[1], "mock client interface")
        equal(state.maxLevel, client[3], "mock client maximum level")
        equal(WOW_PROJECT_ID, client[1] == 16001 and WOW_PROJECT_CAMELOT or WOW_PROJECT_MAINLINE,
            "mock client project family")
        equal(addon.fill:GetValue(), 250)
        state.xp = 400
        state:fire("PLAYER_XP_UPDATE", "player")
        equal(addon.fill:GetValue(), 400)
        addon:ToggleOptions()
        assert(addon.optionsFrame:IsShown(), "settings should open under each declared mock client")
        state:call(findCaption(state, "Solid color"), "OnClick")
        equal(addon:GetSettings().mode, "solid")
        addon:ToggleOptions()
        equal(addon.fill:GetValue(), 400, "settings should restore live XP")
    end
    local ok, failure = pcall(loadAddon, nil, { interfaceVersion = 120001 })
    assert(not ok and tostring(failure):find("TOC does not declare interface 120001", 1, true),
        "the loader must reject interfaces omitted by the manifest")
end)

test("XP and rested XP follow player events", function()
    local addon, state = loadAddon()
    local minimum, maximum = addon.fill:GetMinMaxValues()
    equal(minimum, 0)
    equal(maximum, 1000)
    equal(addon.fill:GetValue(), 250)
    equal(addon.rested:GetValue(), 600, "rested endpoint")
    near(addon.rainbowLayer:GetWidth(), addon.trackWidth * 0.25, "rainbow clips to earned XP")
    assert(addon.bar:IsShown(), "leveling XP bar should be visible")
    assert(addon.text:GetText():find("25", 1, true), "XP label should include progress")

    state.xp, state.rested = 900, 500
    state:fire("PLAYER_XP_UPDATE", "player")
    equal(addon.fill:GetValue(), 900)
    equal(addon.rested:GetValue(), 1000, "rested endpoint caps at level requirement")
    near(addon.state.ratio, 0.9)
    near(addon.rainbowLayer:GetWidth(), addon.trackWidth * 0.9)

    state.xp = 500
    state:fire("PLAYER_XP_UPDATE", "party1")
    equal(addon.fill:GetValue(), 900, "other units must not change player XP")
    state:fire("PLAYER_XP_UPDATE", "player")
    equal(addon.fill:GetValue(), 500)

    state.rested = nil
    state:fire("UPDATE_EXHAUSTION")
    assert(not addon.rested:IsShown(), "missing rested XP should hide the overlay")
    addon:SetSetting("showText", false)
    assert(not addon.text:IsShown(), "text preference should update the live bar")
    state.xp = 0
    state:fire("PLAYER_XP_UPDATE", "player")
    assert(not addon.rainbowLayer:IsShown(), "empty XP must not display a colored fill")
    assert(not addon.leadingGlow:IsShown(), "empty XP must not display a progress endpoint")
end)

test("rainbow, breathing, and reduced motion affect live animation", function()
    local addon, state = loadAddon()
    assert(#addon.rainbowSegments >= 8, "rainbow should have enough segments for a smooth gradient")
    local before = rainbowColors(addon)
    state:tick(0.4)
    assert(different(before, rainbowColors(addon)), "rainbow colors should move over time")

    addon:SetSetting("reducedMotion", true)
    before = rainbowColors(addon)
    local phase = addon.state.phase
    state:tick(0.4)
    equal(addon.state.phase, phase, "reduced motion freezes phase")
    assert(not different(before, rainbowColors(addon)), "reduced motion freezes rainbow colors")

    addon:SetSetting("mode", "pulse")
    addon:SetSetting("reducedMotion", false)
    before = { addon.fill:GetStatusBarColor() }
    state:tick(0.4)
    assert(different(before, { addon.fill:GetStatusBarColor() }), "breathing mode should modulate base color")
    addon:SetSetting("mode", "solid")
    before = { addon.fill:GetStatusBarColor() }
    state:tick(0.4)
    assert(not different(before, { addon.fill:GetStatusBarColor() }), "solid mode should retain its base color")
end)

test("settings persist dimensions, appearance, and colors", function()
    local addon = loadAddon()
    addon:SetSetting("displayMode", "custom")
    addon:SetSetting("width", 840)
    addon:SetSetting("height", 30)
    addon:SetSetting("scale", 1.3)
    addon:SetSetting("mode", "solid")
    addon:SetSetting("showRested", false)
    addon:SetColor(0.25, 0.5, 0.75)
    near(addon.bar:GetWidth(), 840)
    near(addon.bar:GetHeight(), 30)
    near(addon.bar:GetScale(), 1.3)
    assert(not addon.rested:IsShown())

    local reloaded = loadAddon(ForeverXPDB)
    local settings = reloaded:GetSettings()
    equal(settings.mode, "solid")
    equal(settings.showRested, false)
    equal(settings.width, 840)
    near(settings.color.r, 0.25)
    near(settings.color.g, 0.5)
    near(settings.color.b, 0.75)
    near(reloaded.bar:GetScale(), 1.3)
end)

test("invalid saved settings are sanitized and resets are independent", function()
    local addon = loadAddon({
        mode = "unknown", displayMode = "unknown", width = -100, height = 10000, scale = "broken",
        speed = -1, brightness = 9, glow = -3, showText = "yes",
        color = { r = -1, g = 2, b = "broken" },
        position = { point = "INVALID", relativePoint = {}, x = 0 / 0, y = "broken" },
    })
    local settings = addon:GetSettings()
    equal(settings.mode, "rainbow")
    equal(settings.displayMode, "native")
    assert(settings.width >= 240 and settings.width <= 1200)
    assert(settings.height >= 12 and settings.height <= 48)
    assert(type(settings.scale) == "number")
    assert(settings.speed >= 0.05 and settings.speed <= 2)
    assert(settings.brightness >= 0.15 and settings.brightness <= 1)
    assert(settings.glow >= 0 and settings.glow <= 1)
    assert(type(settings.showText) == "boolean")
    for _, component in pairs(settings.color) do
        assert(type(component) == "number" and component >= 0 and component <= 1)
    end
    assert(settings.position.x == settings.position.x, "NaN coordinates must not reach frame layout")

    addon:SetColor(1, 0, 0)
    addon:SetSetting("width", 900)
    addon:ResetSettings()
    equal(addon:GetSettings().width, 620)
    near(addon:GetSettings().color.r, 0.1)
    addon:SetColor(0, 1, 0)
    addon:ResetSettings()
    near(addon:GetSettings().color.r, 0.1, "reset must not share mutated color defaults")
    near(addon:GetSettings().color.g, 0.75)
end)

test("max level hiding and preview restore actual XP", function()
    local addon, state = loadAddon({ displayMode = "custom" }, { interfaceVersion = 120100, playerLevel = 90, xp = 0, xpMax = 0 })
    assert(not addon.bar:IsShown(), "maximum-level bar should hide by default")
    addon:SetPreview(true)
    assert(addon.bar:IsShown(), "preview should remain usable at maximum level")
    assert(addon.state.ratio > 0 and addon.state.ratio < 1, "preview should contain sample XP")
    addon:SetPreview(false)
    assert(not addon.bar:IsShown(), "closing preview restores maximum-level behavior")
    addon:SetSetting("hideAtMax", false)
    assert(addon.bar:IsShown(), "maximum-level visibility preference should take effect")

    state.playerLevel, state.xp, state.xpMax = 25, 400, 2000
    state:fire("PLAYER_LEVEL_UP", 25)
    state:fire("PLAYER_XP_UPDATE", "player")
    equal(addon.fill:GetValue(), 400)
    near(addon.state.ratio, 0.2)
end)

test("Forever level 60 hides XP while minimap settings and preview remain accessible", function()
    local addon, state = loadAddon(nil, { playerLevel = 59, xp = 800, xpMax = 1000 })
    equal(select(4, GetBuildInfo()), 16001)
    equal(WOW_PROJECT_ID, 18, "Forever uses the Camelot project family")
    equal(state.maxLevel, 60)
    assert(not GameRulesUtil.IsPlayerAtEffectiveMaxLevel())
    assert(addon.bar:IsShown(), "Forever leveling XP should remain visible below level 60")
    state.xp = 950
    state:fire("PLAYER_XP_UPDATE", "player")
    equal(addon.fill:GetValue(), 950)
    near(addon.state.ratio, 0.95)
    state.playerLevel, state.xp, state.xpMax = 60, 0, 0
    state:fire("PLAYER_LEVEL_UP", 60)
    assert(GameRulesUtil.IsPlayerAtEffectiveMaxLevel())
    assert(not addon.bar:IsShown(), "Forever level 60 should hide the XP bar")
    assert(addon.minimapButton:IsShown(), "Forever max-level settings must remain accessible")
    state:call(addon.minimapButton, "OnClick", "LeftButton")
    assert(addon.optionsFrame:IsShown())
    assert(addon.previewEnabled and addon.bar:IsShown(), "Forever max-level settings should show sample XP")
    assert(addon.state.ratio > 0 and addon.state.ratio < 1)
    state:call(addon.minimapButton, "OnClick", "LeftButton")
    assert(not addon.optionsFrame:IsShown())
    assert(not addon.bar:IsShown(), "closing Forever preview should restore max-level hiding")
    assert(addon.minimapButton:IsShown())
end)

test("restricted XP hides safely and recovers when public data returns", function()
    local addon, state = loadAddon(nil, { interfaceVersion = 120100 })
    local restricted = setmetatable({}, {
        __add = function() error("restricted XP must never be added") end,
        __lt = function() error("restricted XP must never be compared") end,
        __tostring = function() error("restricted XP must never be formatted") end,
    })
    state.secretValue, state.xp = restricted, restricted
    state:fire("PLAYER_XP_UPDATE", "player")
    assert(addon.state.secret)
    assert(not addon.bar:IsShown(), "restricted XP should hide instead of error")
    addon:SetPreview(true)
    assert(addon.bar:IsShown(), "sample preview remains usable without public XP")
    addon:SetPreview(false)
    assert(not addon.bar:IsShown())
    state.xp = 300
    state:fire("PLAYER_XP_UPDATE", "player")
    assert(not addon.state.secret)
    assert(addon.bar:IsShown())
    equal(addon.fill:GetValue(), 300)
end)

test("dragging requires unlock and saves the resulting position", function()
    local addon, state = loadAddon()
    addon:SetSetting("displayMode", "custom")
    state:call(addon.bar, "OnDragStart", "LeftButton")
    assert(not addon.bar.moving, "locked XP bar must not move")
    addon:SetSetting("locked", false)
    state:call(addon.bar, "OnDragStart", "LeftButton")
    assert(addon.bar.moving, "unlocked XP bar should move")
    addon.bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 140, 210)
    state:call(addon.bar, "OnDragStop")
    assert(not addon.bar.moving)
    local position = addon:GetSettings().position
    equal(position.point, "BOTTOMLEFT")
    equal(position.relativePoint, "BOTTOMLEFT")
    near(position.x, 140)
    near(position.y, 210)
    local reloaded = loadAddon(ForeverXPDB)
    local point, _, relativePoint, x, y = reloaded.bar:GetPoint()
    equal(point, "BOTTOMLEFT")
    equal(relativePoint, "BOTTOMLEFT")
    near(x, 140)
    near(y, 210)
end)

test("options controls change the live bar and preview closes cleanly", function()
    local addon, state = loadAddon()
    addon:ToggleOptions()
    local window = addon.optionsFrame
    assert(window:IsShown())
    assert(addon.previewEnabled, "opening settings should display a sample preview")
    state:call(findCaption(state, "Custom replacement"), "OnClick")
    state:call(findCaption(state, "Breathing"), "OnClick")
    equal(addon:GetSettings().mode, "pulse")
    local width = find(state, function(object) return object.kind == "Slider" and object.key == "width" end)
    width:SetValue(780)
    equal(addon:GetSettings().width, 780)
    near(addon.bar:GetWidth(), 780)
    local red = find(state, function(object) return object.kind == "Slider" and object.colorKey == "r" end)
    red:SetValue(0.6)
    near(addon:GetSettings().color.r, 0.6)
    local reducedMotion = find(state, function(object) return object.kind == "CheckButton" and object.key == "reducedMotion" end)
    reducedMotion:SetChecked(true)
    state:call(reducedMotion, "OnClick")
    equal(addon:GetSettings().reducedMotion, true)
    assert(reducedMotion.tick:IsShown(), "checked setting should have a visible tick")
    state:call(findCaption(state, "Reset"), "OnClick")
    equal(addon:GetSettings().mode, "rainbow")
    equal(addon:GetSettings().width, 620)
    assert(not reducedMotion.tick:IsShown(), "reset should clear the reduced-motion tick")
    addon:ToggleOptions()
    assert(not window:IsShown())
    assert(not addon.previewEnabled)
    equal(addon.fill:GetValue(), 250, "closing sample preview restores live XP")
end)

test("slash commands control appearance and refresh an open settings window", function()
    local addon, state = loadAddon()
    equal(SLASH_FOREVERXP1, "/fxp")
    equal(SLASH_FOREVERXP2, "/foreverxp")
    local command = assert(SlashCmdList.FOREVERXP)
    command("")
    assert(addon.optionsFrame:IsShown())
    command("  SOLID  ")
    equal(addon:GetSettings().mode, "solid")
    assert(findCaption(state, "Solid color").selected, "slash changes should update settings selection")
    command("lock")
    equal(addon:GetSettings().locked, false)
    command("reset")
    equal(addon:GetSettings().locked, true)
    assert(findCaption(state, "Rainbow").selected)
    command("options")
    assert(not addon.optionsFrame:IsShown())
    command("preview")
    assert(addon.previewEnabled)
    command("preview")
    assert(not addon.previewEnabled)
    local count = #state.messages
    command("help")
    assert(#state.messages > count, "unknown commands should explain supported commands")
end)

test("minimap launcher opens settings, toggles lock, and remains available at max level", function()
    local addon, state = loadAddon(nil, { interfaceVersion = 120100, playerLevel = 90, xp = 0, xpMax = 0 })
    local launcher = assert(addon.minimapButton, "minimap launcher should be created at login")
    equal(launcher:GetParent(), Minimap)
    assert(not addon.bar:IsShown(), "maximum-level XP bar should remain hidden")
    assert(launcher:IsShown(), "launcher should stay accessible when the XP bar is hidden")
    assert(not launcher:GetScript("OnUpdate"), "launcher should not update while idle")

    state:call(launcher, "OnClick", "LeftButton")
    assert(addon.optionsFrame:IsShown(), "left click should open settings")
    local locked = find(state, function(object) return object.kind == "CheckButton" and object.key == "locked" end)
    assert(locked:GetChecked())
    state:call(launcher, "OnClick", "RightButton")
    equal(addon:GetSettings().locked, false, "right click should unlock the XP bar")
    assert(not locked:GetChecked(), "right click should refresh the open settings checkbox")
    state:call(launcher, "OnClick", "RightButton")
    equal(addon:GetSettings().locked, true)
    state:call(launcher, "OnClick", "LeftButton")
    assert(not addon.optionsFrame:IsShown(), "left click should also close settings")

    state:call(launcher, "OnEnter")
    assert(GameTooltip:IsShown())
    local tooltip = table.concat(GameTooltip.lines or {}, " "):lower()
    assert(tooltip:find("left", 1, true) and tooltip:find("right", 1, true) and tooltip:find("drag", 1, true),
        "launcher tooltip should explain both clicks and dragging")
    state:call(launcher, "OnLeave")
    assert(not GameTooltip:IsShown())
end)

test("minimap visibility migrates, persists, and resets through supported controls", function()
    local addon, state = loadAddon({ mode = "solid", width = 720 })
    equal(addon:GetSettings().showMinimap, true, "old saved settings should enable the new launcher")
    near(addon:GetSettings().minimapAngle, 225, "old saved settings should receive the default angle")
    assert(addon.minimapButton:IsShown())
    addon:ToggleOptions()
    local control = find(state, function(object) return object.kind == "CheckButton" and object.key == "showMinimap" end)
    control:SetChecked(false)
    state:call(control, "OnClick")
    assert(not addon.minimapButton:IsShown(), "settings checkbox should hide the launcher")
    equal(addon:GetSettings().showMinimap, false)
    local reloaded = loadAddon(ForeverXPDB)
    equal(reloaded:GetSettings().showMinimap, false)
    assert(not reloaded.minimapButton:IsShown(), "launcher visibility should survive reload")
    SlashCmdList.FOREVERXP("minimap")
    assert(reloaded.minimapButton:IsShown(), "slash command should restore a hidden launcher")
    reloaded:SetSetting("showMinimap", false)
    reloaded:SetSetting("minimapAngle", 90)
    reloaded:ResetSettings()
    equal(reloaded:GetSettings().showMinimap, true)
    near(reloaded:GetSettings().minimapAngle, 225)
    assert(reloaded.minimapButton:IsShown(), "reset should restore launcher visibility")
end)

test("minimap dragging accounts for scale, saves angle, and cleans up update handlers", function()
    local geometry = { minimapCenterX = 600, minimapCenterY = 500, minimapScale = 0.8, uiScale = 1.1 }
    local addon, state = loadAddon(nil, geometry)
    local launcher = addon.minimapButton
    local scale = Minimap:GetEffectiveScale()
    state.cursorX, state.cursorY = 700 * scale, 500 * scale
    state:call(launcher, "OnDragStart", "LeftButton")
    assert(launcher:GetScript("OnUpdate"), "dragging should enable cursor tracking")
    state:tick(0.05)
    near(addon:GetSettings().minimapAngle, 0, "cursor directly right of the scaled minimap")
    state.cursorX, state.cursorY = 600 * scale, 600 * scale
    state:tick(0.05)
    near(addon:GetSettings().minimapAngle, 90, "cursor directly above the scaled minimap")
    local point, relative, relativePoint, x, y = launcher:GetPoint()
    equal(point, "CENTER")
    equal(relative, Minimap)
    equal(relativePoint, "CENTER")
    near(x, 0)
    near(y, Minimap:GetHeight() / 2 + 5)
    state:call(launcher, "OnDragStop")
    assert(not launcher:GetScript("OnUpdate"), "stopping drag should remove cursor tracking")
    state:call(launcher, "OnClick", "LeftButton")
    assert(not addon.optionsFrame or not addon.optionsFrame:IsShown(), "drag release must not open settings")
    state:tick(1)
    state:call(launcher, "OnClick", "LeftButton")
    assert(addon.optionsFrame:IsShown(), "click should work again after drag release")
    addon:ToggleOptions()

    local reloaded, reloadedState = loadAddon(ForeverXPDB, geometry)
    near(reloaded:GetSettings().minimapAngle, 90)
    local _, _, _, savedX, savedY = reloaded.minimapButton:GetPoint()
    near(savedX, 0)
    near(savedY, Minimap:GetHeight() / 2 + 5, "reloaded launcher should retain its position")
    reloadedState:call(reloaded.minimapButton, "OnDragStart", "LeftButton")
    reloaded:SetSetting("showMinimap", false)
    assert(not reloaded.minimapButton:GetScript("OnUpdate"), "hiding during drag should stop cursor tracking")
end)

test("minimap launcher follows square and round edges after resizing", function()
    local addon, state = loadAddon(nil, { minimapShape = "SQUARE" })
    local _, _, _, x, y = addon.minimapButton:GetPoint()
    near(x, -75, "square minimap lower-left corner")
    near(y, -75)
    Minimap:SetSize(180, 100)
    _, _, _, x, y = addon.minimapButton:GetPoint()
    near(x, -95, "resizing should refresh the icon without another setting change")
    near(y, -55)
    state.minimapShape = "ROUND"
    addon:RefreshMinimapButton()
    _, _, _, x, y = addon.minimapButton:GetPoint()
    near(x, -95 / math.sqrt(2), "round shape should follow the ellipse instead of the corner")
    near(y, -55 / math.sqrt(2))
end)

test("native mode mounts one skin on Blizzard XP and preserves reputation and honor", function()
    local addon, state = loadAddon()
    equal(addon:GetSettings().displayMode, "native", "the default should skin Blizzard XP")
    assert(addon.nativeActive)
    equal(addon.nativeTarget, state.nativeXP)
    equal(addon.bar:GetParent(), state.nativeXP)
    local _, anchor = addon.bar:GetPoint()
    equal(anchor, state.nativeStatusBar, "skin should follow the real XP status bar")
    near(addon.bar:GetWidth(), 1000)
    near(addon.bar:GetHeight(), 14)
    near(state.nativeXP:GetAlpha(), 1, "native XP frame should remain available")
    assert(state.nativeXP:IsMouseEnabled())
    near(state.nativeXP.OverlayFrame:GetAlpha(), 0, "native text should not duplicate skin text")
    near(state.nativeXP.ExhaustionTick:GetAlpha(), 0)
    near(state.nativeXP.ExhaustionLevelFillBar:GetAlpha(), 0)
    assert(not state.nativeXP.OverlayFrame:IsMouseEnabled())
    assert(not state.nativeXP.ExhaustionTick:IsMouseEnabled(), "native rested tooltip must not intercept skin clicks")
    equal(state.nativeXP.ExhaustionTick:GetScript("OnEnter"), state.nativeXP.originalTickOnEnter,
        "skinning should preserve Blizzard's rested callback")
    local r, g, b = state.nativeStatusBar:GetStatusBarColor()
    local skinR, skinG, skinB = addon.fill:GetStatusBarColor()
    near(r, skinR); near(g, skinG); near(b, skinB)
    for _, neighbor in ipairs({ state.nativeManager, state.nativeContainer, state.nativeReputation, state.nativeHonor }) do
        near(neighbor:GetAlpha(), 1, "non-XP tracking visuals must remain untouched")
        assert(neighbor:IsShown())
    end
    assert(state.nativeReputation:IsMouseEnabled() and state.nativeHonor:IsMouseEnabled())
    local skinCount = 0
    for _, object in ipairs(state.objects) do
        if object.name == "ForeverXPBar" then skinCount = skinCount + 1 end
    end
    equal(skinCount, 1, "there must be one skin, without a floating duplicate")
    addon:SetSetting("locked", false)
    addon:SetSetting("width", 840)
    near(addon.bar:GetWidth(), 1000, "native width should follow Blizzard rather than custom dimensions")
    state:call(addon.bar, "OnDragStart", "LeftButton")
    assert(not addon.bar.moving, "native XP should follow Blizzard layout instead of dragging")
end)

test("custom and preview suppress only native XP and restore native skin on return", function()
    local addon, state = loadAddon()
    addon:SetSetting("displayMode", "custom")
    assert(not addon.nativeActive)
    equal(addon.bar:GetParent(), UIParent)
    near(addon.bar:GetWidth(), addon:GetSettings().width)
    for _, xp in ipairs({ state.nativeXP, state.secondaryNativeXP }) do
        near(xp:GetAlpha(), 0, "custom replacement must suppress every native XP copy")
        assert(not xp:IsMouseEnabled())
        assert(not xp.StatusBar:IsMouseEnabled())
        assert(not xp.OverlayFrame:IsMouseEnabled())
        assert(not xp.ExhaustionTick:IsMouseEnabled(), "suppressed XP must not leave an invisible rested mouse target")
        equal(xp.ExhaustionTick:GetScript("OnEnter"), xp.originalTickOnEnter)
        assert(xp:IsShown(), "replacement should preserve Blizzard's visibility bookkeeping")
        near(xp.OverlayFrame:GetAlpha(), 1, "native subregion settings should restore when the whole XP frame is suppressed")
        local r, g, b = xp.StatusBar:GetStatusBarColor()
        near(r, 0.58); near(g, 0); near(b, 0.55)
    end
    near(state.nativeReputation:GetAlpha(), 1)
    near(state.nativeHonor:GetAlpha(), 1)
    assert(state.nativeReputation:IsMouseEnabled() and state.nativeHonor:IsMouseEnabled())
    addon:SetSetting("displayMode", "native")
    assert(addon.nativeActive)
    equal(addon.bar:GetParent(), state.nativeXP)
    near(state.nativeXP:GetAlpha(), 1)
    assert(state.nativeXP:IsMouseEnabled())
    addon:ToggleOptions()
    assert(addon.previewEnabled)
    equal(addon.bar:GetParent(), UIParent, "settings sample should use the movable preview")
    near(state.nativeXP:GetAlpha(), 0, "sample preview should avoid a second visible XP bar")
    near(state.nativeReputation:GetAlpha(), 1)
    addon:ToggleOptions()
    assert(not addon.previewEnabled and addon.nativeActive)
    equal(addon.bar:GetParent(), state.nativeXP)
    near(state.nativeXP:GetAlpha(), 1)
    equal(addon.fill:GetValue(), state.xp)
end)

test("native skin follows XP resize, visibility, manager refresh, and container changes", function()
    local addon, state = loadAddon()
    state.nativeStatusBar:SetSize(780, 18)
    near(addon.bar:GetWidth(), 780, "native status bar resize should update the skin")
    near(addon.bar:GetHeight(), 18)
    state.nativeXP:Hide()
    assert(not addon.bar:IsVisible(), "hidden native XP must not leave a floating duplicate")
    state.nativeXP:Show()
    assert(addon.bar:IsVisible())
    state.nativeStatusBar:SetStatusBarColor(1, 0, 0)
    state.nativeManager:UpdateBarVisuals()
    local r, g, b = state.nativeStatusBar:GetStatusBarColor()
    local skinR, skinG, skinB = addon.fill:GetStatusBarColor()
    near(r, skinR); near(g, skinG); near(b, skinB)
    state.nativeContainer:Hide()
    state.secondaryNativeContainer:Show()
    state.nativeManager:UpdateBarsShown()
    equal(addon.nativeTarget, state.secondaryNativeXP, "skin should move to Blizzard's visible XP container")
    equal(addon.bar:GetParent(), state.secondaryNativeXP)
    assert(addon.bar:IsVisible())
end)

test("native mode discovers XP bars initialized after login", function()
    local addon, state = loadAddon(nil, { createNativeBars = false })
    assert(not addon.nativeActive)
    equal(addon.bar:GetParent(), UIParent)
    assert(addon.bar:IsVisible(), "missing native XP should provide the supported custom fallback")
    state:createNativeXPBars()
    state:fire("PLAYER_ENTERING_WORLD")
    assert(addon.nativeActive)
    equal(addon.nativeTarget, state.nativeXP)
    equal(addon.bar:GetParent(), state.nativeXP)
    assert(addon.bar:IsVisible())
end)

test("custom replacement hides XP chrome and restores it for reputation, honor, and native preview return", function()
    local addon, state = loadAddon()
    local containers = { state.nativeContainer, state.secondaryNativeContainer }
    local original = {}
    for _, container in ipairs(containers) do
        original[container.BarFrameTexture] = container.BarFrameTexture:GetAlpha()
        for divider in container.HorizontalDividersPool:EnumerateActive() do original[divider] = divider:GetAlpha() end
    end
    local function chrome(container, hidden)
        near(container.BarFrameTexture:GetAlpha(), hidden and 0 or original[container.BarFrameTexture], "container border")
        for divider in container.HorizontalDividersPool:EnumerateActive() do
            near(divider:GetAlpha(), hidden and 0 or original[divider], "container divider")
        end
        near(container:GetAlpha(), 1, "suppressing XP chrome must preserve the shared container")
    end
    addon:SetSetting("displayMode", "custom")
    chrome(state.nativeContainer, true)
    chrome(state.secondaryNativeContainer, true)
    local pool = state.nativeContainer.HorizontalDividersPool
    local released = next(pool.activeObjects)
    pool.activeObjects[released] = nil
    state.nativeManager:UpdateBarsShown()
    near(released:GetAlpha(), original[released], "released pooled dividers must regain their original alpha")
    pool.activeObjects[released] = true
    state.nativeManager:UpdateBarVisuals()
    near(released:GetAlpha(), 0, "reacquired XP dividers should be suppressed again")
    state.nativeContainer.pendingBarToShowIndex = StatusTrackingBarInfo.BarsEnum.Reputation
    state.nativeContainer:ApplyPendingBarToShow()
    state.secondaryNativeContainer.pendingBarToShowIndex = StatusTrackingBarInfo.BarsEnum.Honor
    state.secondaryNativeContainer:ApplyPendingBarToShow()
    chrome(state.nativeContainer, false)
    chrome(state.secondaryNativeContainer, false)
    state.nativeContainer.pendingBarToShowIndex = StatusTrackingBarInfo.BarsEnum.Experience
    state.nativeContainer:ApplyPendingBarToShow()
    chrome(state.nativeContainer, true)
    chrome(state.secondaryNativeContainer, false)
    addon:SetSetting("displayMode", "native")
    chrome(state.nativeContainer, false)
    addon:ToggleOptions()
    chrome(state.nativeContainer, true)
    chrome(state.secondaryNativeContainer, false)
    addon:ToggleOptions()
    chrome(state.nativeContainer, false)
    chrome(state.secondaryNativeContainer, false)
end)

test("native placement defers protected changes during combat and resumes afterwards", function()
    local addon, state = loadAddon(nil, { nativeProtected = true })
    state.inCombat = true
    addon:SetSetting("displayMode", "custom")
    assert(addon.nativePlacementDeferred)
    equal(addon.bar:GetParent(), state.nativeXP, "combat should preserve the active protected placement")
    near(state.nativeXP:GetAlpha(), 1)
    state.inCombat = false
    state:fire("PLAYER_REGEN_ENABLED")
    assert(not addon.nativePlacementDeferred)
    equal(addon.bar:GetParent(), UIParent)
    near(state.nativeXP:GetAlpha(), 0)

    local startup, startupState = loadAddon(nil, { inCombat = true, nativeProtected = true })
    assert(startup.nativePlacementDeferred)
    assert(not startup.bar:IsShown(), "startup should not draw before protected placement is available")
    startupState.inCombat = false
    startupState:fire("PLAYER_REGEN_ENABLED")
    assert(startup.nativeActive)
    equal(startup.bar:GetParent(), startupState.nativeXP)
    assert(startup.bar:IsVisible())
end)

test("ordinary unprotected native XP keeps updating and animating during combat", function()
    local addon, state = loadAddon(nil, { inCombat = true })
    assert(addon.nativeActive and not addon.nativePlacementDeferred)
    state.xp = 550
    state:fire("PLAYER_XP_UPDATE", "player")
    equal(addon.fill:GetValue(), 550)
    equal(addon.bar:GetParent(), state.nativeXP)
    local colors = rainbowColors(addon)
    state:tick(0.2)
    assert(different(colors, rainbowColors(addon)), "unprotected native effects should animate in normal combat")
end)

test("class themes have distinct particles, animated gradients, and heavy void smoke", function()
    local addon, state = loadAddon()
    local expectedKinds = {
        flame = { flame = true, ember = true },
        frost = { frostspark = true, frostshard = true },
        arcane = { arcanerune = true, arcaneorb = true },
        void = { voidsmoke = true, voidrim = true },
    }
    local signatures = {}
    for _, mode in ipairs({ "flame", "frost", "arcane", "void" }) do
        addon:SetSetting("mode", mode)
        equal(addon.classEffects.mode, mode)
        assert(addon.classEffects.frame:IsShown(), "themed particles should be visible with earned XP")
        assert(not addon.sweep:IsShown(), "themed particles should replace the generic highlight")
        local seen, visible = {}, 0
        for _, texture in ipairs(addon.classEffects.particles) do
            if texture:IsShown() then
                visible = visible + 1
                assert(expectedKinds[mode][texture.effectKind], "theme should use its own particle shapes")
                seen[texture.effectKind] = true
                local _, _, _, x = texture:GetPoint()
                assert(x >= 0 and x <= addon.trackWidth * addon.state.ratio, "particles must follow earned XP horizontally")
                if texture.effectKind == "voidsmoke" then
                    equal(texture:GetBlendMode(), "BLEND", "heavy smoke needs dark centers")
                    local r, g, b = texture:GetVertexColor()
                    assert(r < 0.08 and g < 0.08 and b < 0.08, "void smoke should be dark rather than a bright purple glow")
                elseif texture.effectKind == "voidrim" then
                    equal(texture:GetBlendMode(), "ADD", "void should have separate luminous smoke rims")
                end
            end
        end
        for kind in pairs(expectedKinds[mode]) do assert(seen[kind], "missing themed particle " .. kind) end
        assert(visible > 0 and visible <= 20, "effects should reuse a bounded particle pool")
        local colors, positions = rainbowColors(addon), particleState(addon)
        signatures[mode] = colors
        state:tick(0.2)
        assert(different(colors, rainbowColors(addon)), "theme gradients should animate")
        assert(different(positions, particleState(addon)), "theme particles should move")
    end
    assert(different(signatures.flame, signatures.frost))
    assert(different(signatures.frost, signatures.arcane))
    assert(different(signatures.arcane, signatures.void))
end)

test("class themes respect reduced motion, empty XP, glow, and standard-mode cleanup", function()
    local addon, state = loadAddon()
    for _, mode in ipairs({ "flame", "frost", "arcane", "void" }) do
        addon:SetSetting("mode", mode)
        addon:SetSetting("reducedMotion", true)
        local colors, phase = rainbowColors(addon), addon.state.phase
        assert(not addon.classEffects.frame:IsShown())
        for _, texture in ipairs(addon.classEffects.particles) do assert(not texture:IsShown()) end
        state:tick(0.2)
        equal(addon.state.phase, phase)
        assert(not different(colors, rainbowColors(addon)), "reduced motion should freeze themed gradients")
        addon:SetSetting("reducedMotion", false)
        assert(addon.classEffects.frame:IsShown())
    end
    addon:SetSetting("glow", 0)
    assert(not addon.classEffects.frame:IsShown())
    addon:SetSetting("glow", 0.7)
    state.xp = 0
    state:fire("PLAYER_XP_UPDATE", "player")
    assert(not addon.classEffects.frame:IsShown(), "empty XP must not display free-floating class particles")
    state.xp = 250
    state:fire("PLAYER_XP_UPDATE", "player")
    assert(addon.classEffects.frame:IsShown())
    addon:SetSetting("mode", "rainbow")
    equal(addon.classEffects.mode, nil)
    assert(not addon.classEffects.frame:IsShown())
    for _, texture in ipairs(addon.classEffects.particles) do assert(not texture:IsShown()) end
    addon:SetSetting("mode", "solid")
    for _, texture in ipairs(addon.rainbowSegments) do assert(not texture:IsShown()) end
end)

test("class mode resolves player class and theme choices persist without random particle jumps", function()
    local addon, state = loadAddon()
    addon:SetSetting("mode", "class")
    for class, mode in pairs({ MAGE = "arcane", DEATHKNIGHT = "frost", WARLOCK = "void", PRIEST = "void", WARRIOR = "flame" }) do
        state.playerClass = class
        state:fire("PLAYER_ENTERING_WORLD")
        equal(addon:ResolveClassEffectMode(), mode, "automatic effect for " .. class)
        equal(addon.classEffects.mode, mode)
    end
    addon:SetSetting("mode", "flame")
    local initial = particleState(addon)
    state:tick(0.2)
    assert(different(initial, particleState(addon)))
    local reloaded = loadAddon(ForeverXPDB)
    equal(reloaded:GetSettings().mode, "flame")
    assert(not different(initial, particleState(reloaded)), "particle placement should be deterministic after reload")
    reloaded:ResetSettings()
    equal(reloaded:GetSettings().displayMode, "native")
    equal(reloaded:GetSettings().mode, "rainbow")
    assert(not reloaded.classEffects.frame:IsShown())
end)

test("theme and display selectors work through settings and slash commands", function()
    local addon, state = loadAddon()
    addon:ToggleOptions()
    local width = find(state, function(object) return object.kind == "Slider" and object.key == "width" end)
    local hideAtMax = find(state, function(object) return object.kind == "CheckButton" and object.key == "hideAtMax" end)
    assert(not width:IsEnabled() and not hideAtMax:IsEnabled(), "native controls should leave geometry and visibility to Blizzard")
    for mode, caption in pairs({ flame = "Flame", frost = "Frost", arcane = "Arcane", void = "Shadow / Void", class = "By class" }) do
        state:call(findCaption(state, caption), "OnClick")
        equal(addon:GetSettings().mode, mode)
    end
    for _, mode in ipairs({ "flame", "frost", "arcane", "void", "class" }) do
        SlashCmdList.FOREVERXP(mode)
        equal(addon:GetSettings().mode, mode)
        local selected = find(state, function(object) return object.mode == mode end)
        assert(selected.selected, "slash changes should refresh the selected effect")
    end
    SlashCmdList.FOREVERXP("custom")
    equal(addon:GetSettings().displayMode, "custom")
    assert(width:IsEnabled() and hideAtMax:IsEnabled(), "custom placement should enable custom geometry and visibility")
    state:call(findCaption(state, "Blizzard bar"), "OnClick")
    equal(addon:GetSettings().displayMode, "native")
    addon:ToggleOptions()
    assert(addon.nativeActive)
    SlashCmdList.FOREVERXP("custom")
    equal(addon.bar:GetParent(), UIParent)
    SlashCmdList.FOREVERXP("native")
    equal(addon.bar:GetParent(), state.nativeXP)
end)

for _, item in ipairs(tests) do
    local ok, failure = pcall(item[2])
    if ok then
        passed = passed + 1
        io.write("PASS " .. item[1] .. "\n")
    else
        io.write("FAIL " .. item[1] .. "\n  " .. tostring(failure) .. "\n")
    end
end
io.write(string.format("%d/%d functional tests passed\n", passed, #tests))
if passed ~= #tests then error("functional tests failed", 0) end
