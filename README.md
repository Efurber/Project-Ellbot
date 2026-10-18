# ForeverXP

A Lua addon for **World of Warcraft Retail** that gives your leveling XP bar animated RGB color. Supports Retail **12.1.0 (Interface 120100)** and **12.1.5 (Interface 120105)**; no libraries, accounts, or network services are required.

## Install

1. Download or build `dist/ForeverXP.zip` and extract it into your WoW installation's `_retail_/Interface/AddOns/` folder. You can also copy the repository's `ForeverXP` folder there directly.
2. Confirm the path is `_retail_/Interface/AddOns/ForeverXP/ForeverXP.toc`, without an extra nested directory.
3. Start WoW, enable **ForeverXP** on the character selection AddOns screen, and log in. If WoW is already open, restart it so it discovers the addon.
4. Type **`/fxp`** or **`/foreverxp`** to open the appearance panel. The bar starts near the bottom center of the screen, above the default action bars.

The selected client target is Retail. For a server with a customized client, its client version and API must match; Vanilla and Wrath clients are not supported by this build. If a future Retail patch marks the addon out of date, check its API compatibility before updating the TOC's Interface number.

### If WoW reports an incompatible addon

Version **1.0.1** corrects the original package's 12.1.5-only Interface declaration to include **12.1.0**. Exit WoW, replace the old `ForeverXP` addon folder with this package, then restart the client. Your saved appearance settings are kept in WoW's separate WTF folder.

If incompatibility remains, run `/run print(GetBuildInfo())` in chat. The first number is the game client version; the last is its Interface number. Version numbers shown on other addons can describe those addons' own releases and do not necessarily identify your game client. An actual **1.6.3 game client** requires a different addon implementation; this Retail build does not support it.

## Make it yours

- **Rainbow:** a flowing spectrum across the filled part of the bar, with a moving light sweep.
- **Solid color:** your chosen RGB color with a still glow at the progress edge.
- **Breathing:** a slow brightness pulse and a light sweep in your chosen color.
- Change brightness, glow intensity, and animation speed independently. RGB sliders affect Solid and Breathing; Rainbow supplies its own spectrum.
- Adjust width, height, and scale; toggle XP text and the blue rested XP overlay.
- Unlock the bar in **Layout & behavior**, then drag it with the left mouse button. Right-click the bar to open settings.
- Enable **Reduce motion** for a stationary rainbow or a still base color. Disable glow with its intensity slider.

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

The tests load the actual addon through its TOC and exercise XP/rested updates, animation and reduced motion, saved preferences, invalid saved data, maximum-level behavior, dragging, and settings controls. They do not emulate WoW rendering or prove that a particular custom server permits addons.

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

No in-game validation is claimed by the automated tests.
