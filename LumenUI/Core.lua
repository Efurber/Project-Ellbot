local addonName, addon = ...

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function number(value, low, high, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return math.max(low, math.min(high, value))
end

local actionOrder = { "character", "bags", "spells", "talents", "quests", "map", "social", "guild", "calendar", "menu", "editmode", "editor" }
local actionIds = {}
for _, id in ipairs(actionOrder) do actionIds[id] = true end

addon.defaults = {
    theme = "dark", accent = { r = 0.28, g = 0.58, b = 1 },
    opacity = 0.94, radius = 18, scale = 1, reducedMotion = false,
    skinWindows = true, skinActionBars = true, skinUnitFrames = true,
    dockWidth = 720, dockHeight = 76, dockScale = 1, dockX = 0, dockY = -10,
    dockTriggerWidth = 180, dockTriggerHeight = 18, dockHideDelay = 0.65,
    dockHidden = true, dockPinned = false, dockSpacing = 10, dockClock = true, dockStatus = true,
    dockOrder = copy(actionOrder),
    dockEnabled = {
        character = true, bags = true, spells = true, talents = true, quests = true, map = true,
        social = true, guild = false, calendar = false, menu = true, editmode = false, editor = true,
    },
    layout = {},
}

local ranges = {
    opacity = { 0.35, 1 }, radius = { 4, 32 }, scale = { 0.65, 1.5 },
    dockWidth = { 360, 1200 }, dockHeight = { 56, 140 }, dockScale = { 0.65, 1.5 },
    dockX = { -3000, 3000 }, dockY = { -2000, 0 }, dockTriggerWidth = { 40, 600 },
    dockTriggerHeight = { 4, 48 }, dockHideDelay = { 0.1, 3 }, dockSpacing = { 2, 24 },
}
local booleans = {
    reducedMotion = true, skinWindows = true, skinActionBars = true, skinUnitFrames = true,
    dockHidden = true, dockPinned = true, dockClock = true, dockStatus = true,
}
local points = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function sanitize(saved)
    local result = copy(addon.defaults)
    if type(saved) ~= "table" then return result end
    if saved.theme == "light" or saved.theme == "dark" then result.theme = saved.theme end
    for key, limits in pairs(ranges) do result[key] = number(saved[key], limits[1], limits[2], result[key]) end
    for key in pairs(booleans) do if type(saved[key]) == "boolean" then result[key] = saved[key] end end
    if type(saved.accent) == "table" then
        for _, channel in ipairs({ "r", "g", "b" }) do result.accent[channel] = number(saved.accent[channel], 0, 1, result.accent[channel]) end
    end
    if type(saved.dockOrder) == "table" then
        local order, seen = {}, {}
        for _, id in ipairs(saved.dockOrder) do
            if actionIds[id] and not seen[id] then order[#order + 1] = id; seen[id] = true end
        end
        for _, id in ipairs(actionOrder) do if not seen[id] then order[#order + 1] = id end end
        result.dockOrder = order
    end
    if type(saved.dockEnabled) == "table" then
        for id in pairs(actionIds) do
            if type(saved.dockEnabled[id]) == "boolean" then result.dockEnabled[id] = saved.dockEnabled[id] end
        end
    end
    if type(saved.layout) == "table" then
        for _, entry in ipairs(addon.layoutCatalog or {}) do
            local value = saved.layout[entry.id]
            if type(value) == "table" then
                result.layout[entry.id] = {
                    enabled = value.enabled == true,
                    point = points[value.point] and value.point or "CENTER",
                    x = number(value.x, -5000, 5000, 0), y = number(value.y, -5000, 5000, 0),
                    scale = number(value.scale, 0.5, 2, 1), opacity = number(value.opacity, 0.1, 1, 1),
                    visible = value.visible ~= false,
                    width = entry.resizable and number(value.width, 0, 1600, 0) or 0,
                    height = entry.resizable and number(value.height, 0, 1400, 0) or 0,
                }
            end
        end
    end
    return result
end

local function profileName(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("%c", ""):match("^%s*(.-)%s*$")
    if value == "" or #value > 24 then return nil end
    return value
end

function addon:Say(message)
    print("|cff70aaffLumenUI:|r " .. tostring(message))
end

function addon:GetSettings() return self.db end

function addon:Refresh()
    if not self.db or self.refreshing then return end
    self.refreshing = true
    if self.ApplyLayout then self:ApplyLayout() end
    if self.ApplySkins then self:ApplySkins() end
    if self.RefreshDock then self:RefreshDock() end
    if self.RefreshEditor then self:RefreshEditor() end
    self.refreshing = false
end

function addon:SetSetting(key, value)
    if not self.db then return false end
    if ranges[key] then
        local limits = ranges[key]
        self.db[key] = number(value, limits[1], limits[2], self.db[key])
    elseif booleans[key] and type(value) == "boolean" then self.db[key] = value
    elseif key == "theme" and (value == "dark" or value == "light") then self.db.theme = value
    else return false end
    self:Refresh()
    return true
end

function addon:SetAccent(red, green, blue)
    if not self.db then return end
    self.db.accent.r = number(red, 0, 1, self.db.accent.r)
    self.db.accent.g = number(green, 0, 1, self.db.accent.g)
    self.db.accent.b = number(blue, 0, 1, self.db.accent.b)
    self:Refresh()
end

function addon:SetDockEnabled(id, enabled)
    if not actionIds[id] or type(enabled) ~= "boolean" then return false end
    self.db.dockEnabled[id] = enabled
    self:Refresh()
    return true
end

function addon:MoveDockItem(id, delta)
    if not actionIds[id] or not (delta == 1 or delta == -1) then return false end
    local order = self.db.dockOrder
    for index, item in ipairs(order) do
        if item == id then
            local target = math.max(1, math.min(#order, index + delta))
            order[index], order[target] = order[target], order[index]
            self:Refresh()
            return true
        end
    end
    return false
end

function addon:GetProfileNames()
    local names = {}
    for name in pairs(self.saved.profiles) do names[#names + 1] = name end
    table.sort(names)
    table.insert(names, 1, "Default")
    return names
end

function addon:SaveProfile(name)
    name = profileName(name)
    if not name then return false, "Use a profile name between 1 and 24 characters." end
    if string.lower(name) == "default" then return false, "Default is a built-in preset. Choose another name." end
    local count = 0
    for _ in pairs(self.saved.profiles) do count = count + 1 end
    if not self.saved.profiles[name] and count >= 12 then return false, "You can save up to 12 custom profiles." end
    self.saved.profiles[name] = sanitize(self.db)
    self.saved.activeProfile = name
    if self.RefreshEditor then self:RefreshEditor() end
    return true, "Saved " .. name .. "."
end

function addon:LoadProfile(name)
    local source = name == "Default" and self.defaults or self.saved.profiles[name]
    if not source then return false, "That profile does not exist." end
    if self.SetLayoutEditing then self:SetLayoutEditing(false) end
    self.db = sanitize(source)
    self.saved.settings, self.saved.activeProfile = self.db, name
    self:Refresh()
    return true, "Loaded " .. name .. "."
end

function addon:DeleteProfile(name)
    if not name or name == "Default" then return false, "The Default preset is kept for resetting your UI." end
    if not self.saved.profiles[name] then return false, "That profile does not exist." end
    self.saved.profiles[name] = nil
    if self.saved.activeProfile == name then self.saved.activeProfile = "Custom" end
    if self.RefreshEditor then self:RefreshEditor() end
    return true, "Deleted " .. name .. "."
end

function addon:ResetSettings()
    return self:LoadProfile("Default")
end

local function initialize()
    local saved = type(LumenUIDB) == "table" and LumenUIDB or {}
    local profiles, count = {}, 0
    if type(saved.profiles) == "table" then
        for name, settings in pairs(saved.profiles) do
            local cleanName = profileName(name)
            if cleanName and string.lower(cleanName) ~= "default" and type(settings) == "table" and count < 12 then
                profiles[cleanName] = sanitize(settings)
                count = count + 1
            end
        end
    end
    local active = profileName(saved.activeProfile) or "Default"
    if active ~= "Default" and active ~= "Custom" and not profiles[active] then active = "Custom" end
    LumenUIDB = { version = 1, settings = sanitize(saved.settings), profiles = profiles, activeProfile = active }
    addon.saved, addon.db = LumenUIDB, LumenUIDB.settings
end

local function slash(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    if command == "unlock" then
        if InCombatLockdown and InCombatLockdown() then addon:Say("Unlock the layout after combat."); return end
        addon:SetLayoutEditing(true)
        if addon.SetDockEditing then addon:SetDockEditing(true) end
    elseif command == "lock" then
        addon:SetLayoutEditing(false)
        if addon.SetDockEditing then addon:SetDockEditing(false) end
    elseif command == "dock" then addon:SetSetting("dockPinned", not addon.db.dockPinned)
    elseif command == "reset" then addon:ResetSettings(); addon:Say("Default appearance and layout restored.")
    elseif command == "" or command == "options" then addon:ToggleEditor()
    else addon:Say("/lumen opens the editor. Commands: unlock, lock, dock, reset.") end
end

addon.events = CreateFrame("Frame")
addon.events:RegisterEvent("ADDON_LOADED")
addon.events:RegisterEvent("PLAYER_LOGIN")
addon.events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == addonName then initialize()
        elseif addon.loggedIn then addon:Refresh() end
    elseif event == "PLAYER_LOGIN" then
        if not addon.db then initialize() end
        addon.loggedIn = true
        addon:CreateDock()
        for _, value in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
            addon.events:RegisterEvent(value)
        end
        SLASH_LUMENUI1, SLASH_LUMENUI2 = "/lumen", "/lumenui"
        SlashCmdList.LUMENUI = slash
        addon:Refresh()
        addon:Say("Ready. Hover at the top center of the screen, or type /lumen to edit.")
    elseif event == "PLAYER_REGEN_DISABLED" then
        if addon.layoutEditing then
            addon.resumeLayoutEditing = true
            addon:SetLayoutEditing(false)
        end
    else
        addon:Refresh()
        if event == "PLAYER_REGEN_ENABLED" and addon.resumeLayoutEditing then
            addon.resumeLayoutEditing = nil
            addon:SetLayoutEditing(true)
        end
    end
end)
