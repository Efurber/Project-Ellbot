local addonName, addon = ...
local ICONS = "Interface\\AddOns\\" .. addonName .. "\\Textures\\Icons\\"

addon.actions = {
    { id = "character", label = "Character", icon = ICONS .. "Character.tga", description = "Character equipment and stats" },
    { id = "bags", label = "Bags", icon = ICONS .. "Bags.tga", description = "Open or close your bags" },
    { id = "spells", label = "Spells", icon = ICONS .. "Spells.tga", description = "Your spellbook" },
    { id = "talents", label = "Talents", icon = ICONS .. "Talents.tga", description = "Class talents and specializations" },
    { id = "quests", label = "Quests", icon = ICONS .. "Quests.tga", description = "Your quest journal" },
    { id = "map", label = "Map", icon = ICONS .. "Map.tga", description = "World map" },
    { id = "social", label = "Friends", icon = ICONS .. "Social.tga", description = "Friends and social panels" },
    { id = "guild", label = "Guild", icon = ICONS .. "Guild.tga", description = "Your guild" },
    { id = "calendar", label = "Calendar", icon = ICONS .. "Calendar.tga", description = "Calendar and events" },
    { id = "menu", label = "Menu", icon = ICONS .. "Menu.tga", description = "Game menu" },
    { id = "editmode", label = "Game layout", icon = ICONS .. "Layout.tga", description = "Blizzard's Edit Mode" },
    { id = "editor", label = "Customize", icon = ICONS .. "Settings.tga", description = "Edit LumenUI appearance, dock, and layout", combatAllowed = true },
}

local byId = {}
for _, action in ipairs(addon.actions) do byId[action.id] = action end

function addon:GetDockActions(includeDisabled)
    local settings, actions = self:GetSettings(), {}
    for _, id in ipairs(settings.dockOrder) do
        if (includeDisabled or settings.dockEnabled[id]) and byId[id] then actions[#actions + 1] = byId[id] end
    end
    return actions
end

local function toggleFrame(frame)
    if not frame then return false end
    if frame:IsShown() then
        if HideUIPanel then HideUIPanel(frame) else frame:Hide() end
    else
        if ShowUIPanel then ShowUIPanel(frame) else frame:Show() end
    end
    return true
end

local function loadBlizzard(name)
    if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn(name)
    elseif LoadAddOn then LoadAddOn(name) end
end

local routes = {
    character = function()
        if ToggleCharacter then ToggleCharacter("PaperDollFrame"); return true end
        return toggleFrame(CharacterFrame)
    end,
    bags = function() if ToggleAllBags then ToggleAllBags(); return true end; return false end,
    spells = function()
        if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then PlayerSpellsUtil.ToggleSpellBookFrame(); return true end
        if ToggleSpellBook then ToggleSpellBook(BOOKTYPE_SPELL or "spell"); return true end
        loadBlizzard("Blizzard_PlayerSpells")
        return toggleFrame(PlayerSpellsFrame or SpellBookFrame)
    end,
    talents = function()
        if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentOrSpecFrame then PlayerSpellsUtil.ToggleClassTalentOrSpecFrame(); return true end
        if ToggleTalentFrame then ToggleTalentFrame(); return true end
        loadBlizzard("Blizzard_PlayerSpells")
        return toggleFrame(PlayerSpellsFrame or PlayerTalentFrame or ClassTalentFrame)
    end,
    quests = function()
        if ToggleQuestLog then ToggleQuestLog(); return true end
        return toggleFrame(QuestMapFrame or QuestLogFrame)
    end,
    map = function()
        if ToggleWorldMap then ToggleWorldMap(); return true end
        return toggleFrame(WorldMapFrame)
    end,
    social = function()
        if ToggleFriendsFrame then ToggleFriendsFrame(1); return true end
        return toggleFrame(FriendsFrame)
    end,
    guild = function()
        if ToggleGuildFrame then ToggleGuildFrame(); return true end
        loadBlizzard("Blizzard_Communities")
        return toggleFrame(CommunitiesFrame or GuildFrame)
    end,
    calendar = function()
        if ToggleCalendar then ToggleCalendar(); return true end
        loadBlizzard("Blizzard_Calendar")
        return toggleFrame(CalendarFrame)
    end,
    menu = function()
        if ToggleGameMenu then ToggleGameMenu(); return true end
        return toggleFrame(GameMenuFrame)
    end,
    editmode = function()
        if not EditModeManagerFrame then return false end
        return toggleFrame(EditModeManagerFrame)
    end,
    editor = function() addon:ToggleEditor(); return true end,
}

function addon:RunAction(id)
    local action = byId[id]
    if not action then return false, "Unknown dock action." end
    if InCombatLockdown and InCombatLockdown() and not action.combatAllowed then
        self:Say("Open " .. action.label .. " after combat.")
        return false, "Available after combat."
    end
    local ok, result = pcall(routes[id])
    if not ok or not result then
        local message = action.label .. " is unavailable in this client or character state."
        self:Say(message)
        return false, message
    end
    return true
end
