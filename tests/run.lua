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

test("manifest admits mocked 12.1.0 and 12.1.5 clients for XP and settings", function()
    for _, client in ipairs({ { 120100, "12.1.0" }, { 120105, "12.1.5" } }) do
        local addon, state = loadAddon(nil, { interfaceVersion = client[1] })
        local version, _, _, interface = GetBuildInfo()
        equal(version, client[2], "mock client version")
        equal(interface, client[1], "mock client interface")
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
        mode = "unknown", width = -100, height = 10000, scale = "broken",
        speed = -1, brightness = 9, glow = -3, showText = "yes",
        color = { r = -1, g = 2, b = "broken" },
        position = { point = "INVALID", relativePoint = {}, x = 0 / 0, y = "broken" },
    })
    local settings = addon:GetSettings()
    equal(settings.mode, "rainbow")
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
    local addon, state = loadAddon(nil, { playerLevel = 90, xp = 0, xpMax = 0 })
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

test("restricted XP hides safely and recovers when public data returns", function()
    local addon, state = loadAddon()
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
