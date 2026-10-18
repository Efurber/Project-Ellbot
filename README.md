# ForeverXP

A Lua addon for **WoW Forever 1.60.1 (Interface 16001)** that adds animated RGB and class effects directly to Blizzard's XP bar, with a draggable minimap button. Also declares support for Retail **12.1.0 (Interface 120100)** and **12.1.5 (Interface 120105)**. No libraries, accounts, or network services are required.

## Install

1. Download or build `dist/ForeverXP.zip` and extract it into the **`Interface/AddOns/` folder used by your WoW Forever client**, alongside your other working addons. You can also copy the repository's `ForeverXP` folder there directly. Retail users use their `_retail_/Interface/AddOns/` folder.
2. Confirm the path ends in `Interface/AddOns/ForeverXP/ForeverXP.toc`, without an extra nested directory.
3. Start WoW, enable **ForeverXP** on the character selection AddOns screen, and log in. If WoW is already open, restart it so it discovers the addon.
4. Type **`/fxp`** or **`/foreverxp`** to open settings. By default, effects attach to **Blizzard's existing XP bar** in its normal position, without a second floating XP bar.
5. You can also left-click the **ForeverXP minimap button** to open settings. Drag the button around the minimap to reposition it; right-click it to toggle the custom replacement bar's position lock. Its visibility is independent of the XP bar, so settings remain accessible at maximum level.

The primary target is **WoW Forever 1.60.1**, a contemporary client with its own Interface number. It is different from the original 2005-era 1.6 client. The supported-version declaration is based on the [1.60.1 client UI source](https://github.com/Gethe/wow-ui-source/tree/1.60.1) and its addon APIs. Custom server clients must expose those APIs. Older original Vanilla and Wrath clients are not covered by this build.

### If WoW reports an incompatible addon

Version **1.1.0** retains the correct **16001** Interface declaration for **WoW Forever 1.60.1** and adds native-bar styling and class effects. Exit WoW, replace the old `ForeverXP` addon folder in your Forever client's AddOns directory with this package, then restart the client. Your saved appearance settings are kept in WoW's separate WTF folder.

If incompatibility remains, check the installed `ForeverXP.toc`: it should show `## Version: 1.1.0` and an Interface line containing `16001`. Confirm you replaced the folder used by the Forever client you actually launch. Where Lua chat commands are available, `/run print(GetBuildInfo())` reports the game version and Interface number; it is not required to use ForeverXP. Version numbers shown on other addons can describe those addons' own releases and do not necessarily identify your game client.

## Make it yours

- **Rainbow:** a flowing spectrum across the filled part of the bar, with a moving light sweep.
- **Solid color:** your chosen RGB color with a still glow at the progress edge.
- **Breathing:** a slow brightness pulse and a light sweep in your chosen color.
- **Flame:** a hot orange/gold gradient, rising flame tongues, and drifting embers.
- **Frost:** an icy blue fill with drifting crystals and sparkling shards.
- **Arcane:** violet energy, orbiting motes, and rotating magical sigils.
- **Shadow / Void:** dark smoke, heavy purple shadows, and luminous void rims.
- **Class:** Mages use Arcane, Death Knights use Frost, Priests and Warlocks use Void, and other classes use Flame. You can always select any theme manually.
- Change brightness, glow intensity, and animation speed independently in **Color & light**. RGB sliders affect Solid and Breathing; the other modes use their own palettes.
- Enable **Reduce motion** to freeze the gradient and suppress moving theme particles. The glow slider controls the intensity of additional light and particle effects.
- Choose **Blizzard bar** or **Custom replacement** under **Bar & behavior**. Blizzard mode follows the game's existing XP bar geometry and layout. Custom mode hides Blizzard's XP bars and gives you width, height, scale, and dragging controls; reputation and honor bars remain available.
- Unlock the custom bar, then drag it with the left mouse button. Right-click the XP bar to open settings.
- Hide the minimap button under **Bar & behavior**, or toggle it with `/fxp minimap`. Its position and visibility are saved with your other preferences.

Settings show clearly labeled **sample XP** so you can see the effects even at maximum level. Closing settings restores your real XP. The bar hides at your current maximum level by default; turn that off in Layout & behavior if desired. All appearance and position preferences are saved per account in WoW's SavedVariables when you log out or reload the UI.

**Blizzard bar** mode recolors the actual native XP status bar and mounts the animation renderer on that bar. Its original text and rested visuals are replaced by the addon's matching visuals while styled. It follows native visibility and resizing, leaving reputation, honor, and pet XP bars alone. **Custom replacement** mode suppresses the native player XP frames and their XP-only borders/dividers, then places the addon bar at your saved position. Shared borders return when a container displays reputation or honor. Switching modes restores native XP state as needed. If the native XP frame is unavailable, the addon uses its custom bar as a fallback. Protected layout changes requested during combat are applied when combat ends. The addon does not change XP gain or game rules.

| Command | Action |
| --- | --- |
| `/fxp` | Open or close settings |
| `/fxp rainbow` | Use the animated rainbow |
| `/fxp solid` | Use your chosen static color |
| `/fxp pulse` | Use the breathing effect |
| `/fxp flame`, `/fxp frost`, `/fxp arcane`, `/fxp void` | Select a class-style effect |
| `/fxp class` | Select a theme automatically by character class |
| `/fxp native` | Apply effects directly to Blizzard's XP bar |
| `/fxp custom` | Use the movable replacement and hide native XP bars |
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

The tests load the actual addon through its TOC and exercise XP/rested updates, animation and reduced motion, saved preferences, invalid saved data, maximum-level behavior, dragging, settings controls, minimap interactions, native XP integration, and themed effects. They do not emulate WoW rendering or prove that a particular custom server permits addons.

Build the installable package:

```sh
python3 tools/package.py
```

Original glow, flame, frost, arcane, and smoke textures are included. To regenerate them, run `python3 tools/generate_textures.py`; their output is deterministic. Only the `ForeverXP` runtime folder and this guide go into the zip.

### In-game smoke check

An actual WoW client is required to complete visual and integration validation:

1. Enable Lua errors with `/console scriptErrors 1`, then `/reload`.
2. On a leveling character, confirm there is one styled XP bar in Blizzard's normal position. Gain XP and confirm it updates; check a level-up if practical. Inspect zero, partial, and full XP to confirm the gradient clips to progress and rested XP stays blue.
3. Open `/fxp`; try Rainbow, Breathing, Flame, Frost, Arcane, and Shadow / Void. Test RGB sliders in Solid color, disable glow, and enable reduced motion. Check that void smoke looks dark and other themes have distinct motion.
4. Switch to Custom replacement, confirm native XP is hidden, then unlock, move, resize, and scale the replacement. Switch back to Blizzard bar, verify its layout returns, and `/reload` to confirm preferences persist. Test native resizing, XP/reputation switching, and switching modes after combat ends.
5. On a character at maximum level, confirm the default bar is hidden, settings show a sample, and closing settings hides it again.
6. Left-click the minimap button to open settings, right-click to toggle the bar lock, and drag it around the edge. Hide/show it with `/fxp minimap`, then `/reload` to confirm its visibility and position persist. Confirm it remains available when XP is hidden at maximum level.

No in-game validation is claimed by the automated tests.
