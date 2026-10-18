# ForeverXP

A Lua addon for **WoW Forever 1.60.1 (Interface 16001)** that gives your leveling XP bar animated RGB color and provides a draggable minimap button. Also declares support for Retail **12.1.0 (Interface 120100)** and **12.1.5 (Interface 120105)**. No libraries, accounts, or network services are required.

## Install

1. Download or build `dist/ForeverXP.zip` and extract it into the **`Interface/AddOns/` folder used by your WoW Forever client**, alongside your other working addons. You can also copy the repository's `ForeverXP` folder there directly. Retail users use their `_retail_/Interface/AddOns/` folder.
2. Confirm the path ends in `Interface/AddOns/ForeverXP/ForeverXP.toc`, without an extra nested directory.
3. Start WoW, enable **ForeverXP** on the character selection AddOns screen, and log in. If WoW is already open, restart it so it discovers the addon.
4. Type **`/fxp`** or **`/foreverxp`** to open the appearance panel. The bar starts near the bottom center of the screen, above the default action bars.
5. In **1.0.2**, you can also left-click the **ForeverXP minimap button** to open settings. Drag the button around the minimap to reposition it; right-click it to lock or unlock the XP bar. Its visibility is independent of the bar, so settings remain accessible at maximum level.

The primary target is **WoW Forever 1.60.1**, a contemporary client with its own Interface number. It is different from the original 2005-era 1.6 client. The supported-version declaration is based on the [1.60.1 client UI source](https://github.com/Gethe/wow-ui-source/tree/1.60.1) and its addon APIs. Custom server clients must expose those APIs. Older original Vanilla and Wrath clients are not covered by this build.

### If WoW reports an incompatible addon

Version **1.0.3** adds the correct **16001** Interface declaration for **WoW Forever 1.60.1**, retaining the minimap button introduced in 1.0.2 and Retail declarations from 1.0.1. Exit WoW, replace the old `ForeverXP` addon folder in your Forever client's AddOns directory with this package, then restart the client. Your saved appearance settings are kept in WoW's separate WTF folder.

If incompatibility remains, check the installed `ForeverXP.toc`: it should show `## Version: 1.0.3` and an Interface line containing `16001`. Confirm you replaced the folder used by the Forever client you actually launch. Where Lua chat commands are available, `/run print(GetBuildInfo())` reports the game version and Interface number; it is not required to use ForeverXP. Version numbers shown on other addons can describe those addons' own releases and do not necessarily identify your game client.

## Make it yours

- **Rainbow:** a flowing spectrum across the filled part of the bar, with a moving light sweep.
- **Solid color:** your chosen RGB color with a still glow at the progress edge.
- **Breathing:** a slow brightness pulse and a light sweep in your chosen color.
- Change brightness, glow intensity, and animation speed independently. RGB sliders affect Solid and Breathing; Rainbow supplies its own spectrum.
- Adjust width, height, and scale; toggle XP text and the blue rested XP overlay.
- Unlock the bar in **Layout & behavior**, then drag it with the left mouse button. Right-click the bar to open settings.
- Enable **Reduce motion** for a stationary rainbow or a still base color. Disable glow with its intensity slider.
- Hide the minimap button under **Layout & behavior**, or toggle it with `/fxp minimap`. Its position and visibility are saved with your other preferences.

Settings show clearly labeled **sample XP** so you can see the effects even at maximum level. Closing settings restores your real XP. The bar hides at your current maximum level by default; turn that off in Layout & behavior if desired. All appearance and position preferences are saved per account in WoW's SavedVariables when you log out or reload the UI.

ForeverXP provides a separate customizable XP bar. Blizzard's default XP, reputation, and honor bars remain visible and untouched, so you may see both XP bars. The addon does not change XP gain or game rules.

| Command | Action |
| --- | --- |
| `/fxp` | Open or close settings |
| `/fxp rainbow` | Use the animated rainbow |
| `/fxp solid` | Use your chosen static color |
| `/fxp pulse` | Use the breathing effect |
| `/fxp lock` | Toggle dragging |
| `/fxp preview` | Toggle a sample bar without the settings panel |
| `/fxp minimap` | Show or hide the minimap button |
| `/fxp reset` | Reset appearance and position |

## Development and checks

Use the existing checkout; no game files or credentials are needed to edit the addon.

With **Lua 5.1**, run the stateful API-mock suite from the repository root:

```sh
lua5.1 tests/run.lua
```

If Lua is unavailable, the same Lua 5.1 suite can run with Python 3 and Lupa:

```sh
python3 -m pip install --target /tmp/foreverxp-lua lupa==2.6
PYTHONPATH=/tmp/foreverxp-lua python3 -c 'from lupa.lua51 import LuaRuntime; LuaRuntime().execute("dofile(\"tests/run.lua\")")'
```

The tests load the actual addon through its TOC and exercise XP/rested updates, animation and reduced motion, saved preferences, invalid saved data, maximum-level behavior, dragging, settings controls, and minimap interactions. They do not emulate WoW rendering or prove that a particular custom server permits addons.

Build the installable package:

```sh
python3 tools/package.py
```

Original soft-glow textures are included. To regenerate them, run `python3 tools/generate_textures.py`; their output is deterministic. Only the `ForeverXP` runtime folder and this guide go into the zip.

### In-game smoke check

An actual WoW client is required to complete visual and integration validation:

1. Enable Lua errors with `/console scriptErrors 1`, then `/reload`.
2. On a leveling character, compare current XP and rested XP with Blizzard's bar. Gain XP and confirm both update; check a level-up if practical. Inspect zero, partial, and full XP to confirm the rainbow clips to progress and rested XP stays blue.
3. Open `/fxp`; try all effects and RGB sliders, disable glow, and enable reduced motion.
4. Unlock, move, resize, and scale the bar, then `/reload` to confirm preferences persist.
5. On a character at maximum level, confirm the default bar is hidden, settings show a sample, and closing settings hides it again.
6. Left-click the minimap button to open settings, right-click to toggle the bar lock, and drag it around the edge. Hide/show it with `/fxp minimap`, then `/reload` to confirm its visibility and position persist. Confirm it remains available when XP is hidden at maximum level.

No in-game validation is claimed by the automated tests.
