local _, addon = ...

-- All gameplay buttons, unit bindings, cooldowns, and window content stay native.
-- Each module owns only cosmetic changes and can restore its original styling.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local unpack = unpack or table.unpack
local groups = {}
local hooked = setmetatable({}, { __mode = "k" })
local applying = false

local windowNames = {
    "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame",
    "ClassTalentFrame", "PlayerTalentFrame", "QuestLogFrame", "QuestMapFrame",
    "FriendsFrame", "GameMenuFrame", "MerchantFrame", "BankFrame", "MailFrame",
    "GossipFrame", "QuestFrame", "LootFrame",
}

local actionPrefixes = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton",
}

local function usable(object)
    return object and not (object.IsForbidden and object:IsForbidden())
end

local function path(object, ...)
    for index = 1, select("#", ...) do
        if not object then return nil end
        object = object[select(index, ...)]
    end
    return object
end

local function group(name)
    if not groups[name] then
        groups[name] = { alpha = {}, fonts = {}, coords = {}, bars = {}, surfaces = {} }
    end
    return groups[name]
end

local function hideArt(state, object)
    if not usable(object) or not object.SetAlpha or not object.GetAlpha then return end
    if state.alpha[object] == nil then state.alpha[object] = object:GetAlpha() end
    object:SetAlpha(0)
end

local function hideTexture(state, object)
    -- A field called Background may also be a content frame. Touch textures only.
    if usable(object) and object.GetTexture then hideArt(state, object) end
end

local function hidePanelBackground(state, object)
    if not usable(object) then return end
    if object.GetTexture then
        hideTexture(state, object)
    else
        -- FlatPanelBackgroundTemplate uses four textures in a frame, not a Bg texture.
        for _, key in ipairs({ "BottomLeft", "BottomRight", "BottomEdge", "TopSection" }) do
            hideTexture(state, object[key])
        end
    end
end

local characterBackgroundAtlases = {
    ["UI-Character-Info-General-BG"] = true,
    ["UI-Character-Info-Stat-BG"] = true,
    ["UI-Character-Info-Stat-StoneBG3"] = true,
}

local function hideCharacterBackgrounds(state, object)
    if not usable(object) or not object.GetRegions then return end
    -- Forever's character panes have anonymous background regions. Match only
    -- their documented art atlases; never indiscriminately hide their contents.
    for _, region in ipairs({ object:GetRegions() }) do
        if region.GetAtlas and characterBackgroundAtlases[region:GetAtlas()] then
            hideTexture(state, region)
        end
    end
end

local function font(state, object, kind, size)
    if not usable(object) or not object.GetFont or not object.SetFont then return end
    if not state.fonts[object] then
        state.fonts[object] = {
            font = { object:GetFont() },
            color = object.GetTextColor and { object:GetTextColor() },
            shadow = object.GetShadowColor and { object:GetShadowColor() },
            offset = object.GetShadowOffset and { object:GetShadowOffset() },
        }
    end
    addon:StyleText(object, kind, size)
end

local function surface(state, object, variant)
    if not usable(object) or not object.CreateTexture then return end
    addon:StyleFrame(object, variant)
    addon:SetSurfaceShown(object, true)
    state.surfaces[object] = true
end

local function cropIcon(state, object)
    if not usable(object) or not object.GetTexCoord or not object.SetTexCoord then return end
    if not state.coords[object] then state.coords[object] = { object:GetTexCoord() } end
    object:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local function flatBar(state, bar)
    if not usable(bar) or not bar.SetStatusBarTexture or not bar.GetStatusBarTexture then return end
    if not state.bars[bar] then
        local texture = bar:GetStatusBarTexture()
        state.bars[bar] = {
            texture = texture and texture.GetTexture and texture:GetTexture(),
            atlas = texture and texture.GetAtlas and texture:GetAtlas(),
            coords = texture and texture.GetTexCoord and { texture:GetTexCoord() },
        }
    end
    -- The native health/power value, colors, prediction overlays, and events remain intact.
    bar:SetStatusBarTexture(WHITE)
end

local function restore(name)
    local state = groups[name]
    if not state then return end
    for object, alpha in pairs(state.alpha) do
        if usable(object) then object:SetAlpha(alpha) end
    end
    for object, original in pairs(state.fonts) do
        if usable(object) then
            if original.font[1] then object:SetFont(unpack(original.font)) end
            if original.color and object.SetTextColor then object:SetTextColor(unpack(original.color)) end
            if original.shadow and object.SetShadowColor then object:SetShadowColor(unpack(original.shadow)) end
            if original.offset and object.SetShadowOffset then object:SetShadowOffset(unpack(original.offset)) end
        end
    end
    for object, coords in pairs(state.coords) do
        if usable(object) then object:SetTexCoord(unpack(coords)) end
    end
    for bar, original in pairs(state.bars) do
        if usable(bar) then
            bar:SetStatusBarTexture(original.texture)
            local texture = bar:GetStatusBarTexture()
            if texture then
                if original.atlas and texture.SetAtlas then texture:SetAtlas(original.atlas) end
                if original.coords and texture.SetTexCoord then texture:SetTexCoord(unpack(original.coords)) end
            end
        end
    end
    for object in pairs(state.surfaces) do
        if usable(object) then addon:SetSurfaceShown(object, false) end
    end
    groups[name] = nil
end

local function onShow(frame)
    if hooked[frame] or not frame.HookScript then return end
    hooked[frame] = true
    frame:HookScript("OnShow", function()
        if not applying then addon:ApplySkins() end
    end)
end

local function skinWindow(state, frame, name)
    surface(state, frame, "panel")
    -- NineSlice is an ornamental border frame; controls and portrait remain separate.
    hideArt(state, frame.NineSlice)
    for _, key in ipairs({ "Bg", "Background", "TitleBg", "TitleBackground", "TopTileStreaks", "InsetBg" }) do
        hideTexture(state, frame[key])
    end
    hidePanelBackground(state, frame.Bg)
    hidePanelBackground(state, path(frame, "Inset", "Bg"))
    hideArt(state, path(frame, "Inset", "NineSlice"))
    hideTexture(state, path(frame, "PortraitContainer", "FrameTexture"))
    if name == "CharacterFrame" then
        hideCharacterBackgrounds(state, frame.LeftPaneHost)
        hideCharacterBackgrounds(state, frame.RightPaneHost)
        hideTexture(state, path(frame, "RightPaneHost", "StoneBg"))
    end
    font(state, frame.TitleText, "title", 16)
    font(state, path(frame, "TitleContainer", "TitleText"), "title", 16)
    font(state, path(frame, "TitleContainer", "Text"), "title", 16)
    font(state, _G[name .. "TitleText"], "title", 16)
    onShow(frame)
end

local function skinActionButton(state, button, name)
    surface(state, button, "tile")
    cropIcon(state, button.icon or button.Icon or _G[name .. "Icon"])
    hideTexture(state, button.NormalTexture or _G[name .. "NormalTexture"])
    if button.GetNormalTexture then hideTexture(state, button:GetNormalTexture()) end
    hideTexture(state, button.SlotArt)
    hideTexture(state, button.SlotBackground)
    -- Quality/equipped borders, spell alerts, checked state, cooldowns, and key labels stay visible.
    font(state, button.HotKey or _G[name .. "HotKey"], "muted", 10)
    font(state, button.Count or _G[name .. "Count"], "body", 11)
end

local function skinActionArt(state)
    local main = _G.MainActionBar or _G.MainMenuBar
    if main then
        hideTexture(state, main.BorderArt)
        hideTexture(state, path(main, "EndCaps", "LeftEndCap", "Texture"))
        hideTexture(state, path(main, "EndCaps", "RightEndCap", "Texture"))
    end
    hideTexture(state, _G.MainMenuBarLeftEndCap)
    hideTexture(state, _G.MainMenuBarRightEndCap)
end

local function skinUnit(state, frame, name)
    surface(state, frame, "tile")
    local container = frame.PlayerFrameContainer or frame.TargetFrameContainer
    hideTexture(state, path(container, "FrameTexture"))
    hideTexture(state, path(frame, "TextureFrame", "Texture"))
    hideTexture(state, _G[name .. "Texture"])
    hideTexture(state, _G[name .. "TextureFrameTexture"])
    local content = frame.PlayerFrameContent or frame.TargetFrameContent
    local main = content and (content.PlayerFrameContentMain or content.TargetFrameContentMain)
    flatBar(state, path(main, "HealthBarsContainer", "HealthBar"))
    flatBar(state, path(main, "HealthBarContainer", "HealthBar"))
    flatBar(state, path(main, "ManaBarArea", "ManaBar"))
    flatBar(state, main and main.ManaBar)
    flatBar(state, frame.healthbar or frame.HealthBar or _G[name .. "HealthBar"])
    flatBar(state, frame.manabar or frame.ManaBar or _G[name .. "ManaBar"])
    onShow(frame)
end

function addon:ApplySkins()
    if applying then return false end
    if InCombatLockdown and InCombatLockdown() then
        self.skinPending = true
        return false
    end
    applying = true
    local settings = self:GetSettings()
    local stats = { windows = 0, actionButtons = 0, unitFrames = 0 }

    if settings.skinWindows then
        local state = group("windows")
        for _, name in ipairs(windowNames) do
            local frame = _G[name]
            if usable(frame) then
                skinWindow(state, frame, name)
                stats.windows = stats.windows + 1
            end
        end
    else
        restore("windows")
    end

    if settings.skinActionBars then
        local state = group("actions")
        for _, prefix in ipairs(actionPrefixes) do
            for index = 1, 12 do
                local name = prefix .. index
                local button = _G[name]
                if usable(button) then
                    skinActionButton(state, button, name)
                    stats.actionButtons = stats.actionButtons + 1
                end
            end
        end
        skinActionArt(state)
    else
        restore("actions")
    end

    if settings.skinUnitFrames then
        local state = group("units")
        for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame" }) do
            local frame = _G[name]
            if usable(frame) then
                skinUnit(state, frame, name)
                stats.unitFrames = stats.unitFrames + 1
            end
        end
    else
        restore("units")
    end

    self.skinStats = stats
    self.skinPending = false
    applying = false
    return true
end
