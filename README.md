# LumenUI

A minimal, Apple-inspired interface addon for **WoW Forever 1.60.1 (Interface 16001)**. Rounded glass surfaces, original monoline icons, clean typography, and a top-center dock that is **completely invisible until you hover over its activation area**. Retail 12.1.0 and 12.1.5 are also declared targets.

## Install

1. **Remove or disable the old ForeverXP addon** before installing this replacement. Its XP code and download package have been removed from this project; LumenUI is a separate addon.
2. Extract `dist/LumenUI.zip` into the `Interface/AddOns/` directory used by your Forever client, alongside your other working addons.
3. Confirm the path ends in `Interface/AddOns/LumenUI/LumenUI.toc`, without an extra nested folder.
4. Restart WoW, enable **LumenUI**, and log in.
5. Move your pointer to the **top center edge of the screen** to reveal the dock. Type **`/lumen`** or **`/lumenui`** to open the editor directly.

All assets are included. There are no external libraries or network services to configure. Preferences and profiles save per account when WoW logs out or reloads its UI.

## Your hover dock

The default invisible trigger occupies a small area at the top center. Hovering expands a rounded dock; leaving it collapses the dock after a short delay. Crossing from the trigger to its shortcuts keeps it open. The collapsed, invisible dock runs no update loop and does not cover the screen with an interactive panel.

Choose and reorder shortcuts for **Character, Bags, Spells, Talents, Quests, Map, Friends, Guild, Calendar, Menu, Game layout, and Customize**. Optional server time, FPS, and latency sit beside your selected shortcuts. The layout adapts to narrower screens and larger item selections.

In the **Dock** editor tab you can change width, height, scale, spacing, position, trigger size, and collapse delay. Turn off invisible idle mode for a small persistent pill, or pin the full dock open. Right-click a shortcut to open the editor. While editing, you can also drag the dock to reposition it. **Reduced motion** makes expansion immediate.

## A consistent UI

Three independently switchable appearance modules restyle native gameplay UI:

- **Game windows:** rounded translucent backgrounds and clean headings for supported character, spellbook/talent, quest, social, menu, vendor, bank, mail, gossip, and loot panels.
- **Action bars:** flat backplates, cropped icons, quieter key labels, and reduced ornamental artwork. Native action buttons, bindings, cooldowns, counts, and spell alerts remain functional.
- **Unit frames:** clean backgrounds and flat health/power textures for supported player, target, and focus frames. Native resource values, portraits, interactions, and events stay in control.

The **Appearance** tab provides light/dark themes, RGB accent controls, surface opacity, corner radius, editor scale, reduced motion, and module toggles. Disabling a styling module restores the appearance values it captured. The editor fits smaller displays automatically.

This is a configurable skin and layout system for the supported native elements; individual game-window content and third-party addon windows keep their own controls. It does not replace gameplay actions with custom secure buttons.

## Edit your layout

The **Layout** tab lists supported HUD elements, including player, target, focus, minimap, chat, action bars, cast bar, buffs, objectives, micro menu, and bag buttons. Available party and raid elements are included where supported by the client. The list has pages so every supported element remains accessible.

Select an element to change its position, scale, opacity, and visibility. Chat and objective panels also expose width/height controls. **Unlock layout** shows labeled drag handles; lock it again or close the editor to finish. You can also use `/lumen unlock` and `/lumen lock`.

Native positions are preserved until you edit them. An element reset restores its captured anchors, scale, opacity, and applicable dimensions. Dynamic target/focus/cast frames retain native visibility rules. The **Game layout** shortcut opens Blizzard's Edit Mode for the game's own detailed layout options.

Protected layout changes wait until combat ends, and layout drag handles close during combat. Some native panels load only when opened; saved edits apply when those frames become available. The editor reports pending changes. Third-party UI addons that also move or skin the same elements can override each other; choose one owner for those elements.

## Profiles and recovery

The **Profiles** tab saves, loads, and deletes named configurations, including dock contents/order, appearance, and HUD layout. Up to 12 custom profiles can be stored. The built-in **Default** preset stays available for recovery.

| Command | Action |
| --- | --- |
| `/lumen` or `/lumenui` | Open or close the editor |
| `/lumen unlock` | Show layout drag handles and reveal the dock |
| `/lumen lock` | Finish layout editing |
| `/lumen dock` | Toggle a pinned-open dock |
| `/lumen reset` | Restore default appearance and native layout |

If the dock is hard to find, `/lumen` always opens its editor. If a layout edit hides something important, reset that element or run `/lumen reset` outside combat.

## Development

Use the existing repository checkout. The client UI source used for compatibility review is [WoW Forever 1.60.1](https://github.com/Gethe/wow-ui-source/tree/1.60.1).

Run the stateful Lua 5.1 API-mock suite from the repository root:

```sh
lua5.1 tests/run.lua
```

Or use Python 3 with Lupa's Lua 5.1 runtime:

```sh
python3 -m pip install --target /tmp/lumenui-lua lupa==2.6
PYTHONPATH=/tmp/lumenui-lua python3 -c 'from lupa.lua51 import LuaRuntime; LuaRuntime().execute("dofile(\"tests/run.lua\")")'
```

Regenerate original rounded-surface textures and line icons, then build the installable archive:

```sh
python3 tools/generate_textures.py
python3 tools/package.py
```

The zip contains only the LumenUI runtime files, textures, and this guide. Tests exercise the actual addon modules with stateful native UI mocks: hover transitions, action routing, profiles, layout editing/restoration, combat deferral, native skin restoration, and editor controls. Mock tests do not render an actual game client.

## In-game smoke check

1. At login, confirm the dock is invisible. Hover the top center, move across its buttons, then move away and verify delayed collapse. Test pinning, compact mode, trigger sizing, reduced motion, and dock scaling.
2. Open the editor with `/lumen`. Try both themes, RGB accents, opacity, and radius; verify each supported native window remains usable and native action buttons still perform their bound actions.
3. Enable and reorder dock shortcuts, including previously disabled Guild, Calendar, and Game layout. Confirm each available panel opens; unavailable or combat-restricted actions report a clear message.
4. Unlock layout, move and scale HUD elements, resize chat/objectives, and test reset. Enter combat with pending protected changes and confirm they apply afterward. Verify target/focus frames stay hidden without those units.
5. Toggle each skin module off and check original artwork returns. Save a profile, reload, load it, and reset to Default. Check all layouts and the dock still behave correctly at your screen resolution.

Actual in-game appearance and compatibility with other UI addons still require this smoke check.
