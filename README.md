# XP12 Forest Tweak

**Denser, more realistic forests for X-Plane 12 – for vanilla, simHeaven X-World and Global Forests v2. Optionally smaller trees. Windows, macOS and Linux.**

> **Free community project – not for sale.** Free to use for everyone, including companies and flight schools. See [License](#license).

Even with the vegetation slider at maximum, X-Plane 12 forests often look like loose groups of trees instead of a forest. That's because the slider can never go above the density set in the forest definition files (`.for`). This tool lowers the tree spacing in those files, safely and reversibly.

Default factor 0.7 ≈ **twice as many trees per area.**

## Screenshots

Same view over the Inn valley near Innsbruck, with simHeaven X-World and Global Forests v2.

| Before (original density) | After (Forest Tweak applied) |
|---|---|
| ![Original X-Plane 12 forest: single trees standing apart on the slope](screenshots/before.jpg) | ![Forest Tweak applied: closed, dense forest on the same slope](screenshots/after.jpg) |

Autumn, wide view over a hilly forest region: the original forests show ground between the trees, with the tweak the forest canopy is closed.

| Before (original density) | After (Forest Tweak applied) |
|---|---|
| ![Original X-Plane 12 autumn forest from altitude: trees with visible ground in between](screenshots/before_autumn.jpg) | ![Forest Tweak applied: closed autumn forest canopy over the same area](screenshots/after_autumn.jpg) |

In-sim window (`ForestDensityToggle.lua`): density steps, scenery reload option and the tree height set by the tweak (here density 0.5, tree height 60 %).

![Forest Tweak window in X-Plane 12 over a dense forest slope](screenshots/window.jpg)

---

## Features

- **Windows, macOS and Linux:** PowerShell version for Windows, Python version for macOS/Linux. Same logic and same backup log, so a tweak made on one system can be restored on the other
- **Simple menu:** Choose settings · Restore original · Status. You pick all values first and confirm a summary before anything is changed. No command line needed
- **Factor of your choice:** 0.4 – 1.0, default 0.7
- **Optional tree height:** factor 0.5 – 1.0 scales min and max height of the trees, so the height variation shrinks along. The 3D tree models are scaled too, so near and far trees match
- **Fully reversible:** the original values are logged and restored byte-for-byte
- **Quick to reapply after updates:** X-Plane or Global Forests updates may reset the forest files. Just run *Choose settings* again and confirm: reset files are detected and tweaked again, already tweaked files are skipped
- **Never applied twice:** all versions share one backup log, so the default forests are only ever scaled once
- **Grass, shrubs and hedges are left alone:** only files with a spacing above 3.1 m are changed
- **Optional: taller simHeaven hedges (Knicks):** step 3 of *Choose settings*, *default* or *enhanced*, see below
- **Minimal changes:** density only edits two header lines per file (`SPACING`, `RANDOM`). The height option also edits the tree list and scales the 3D tree models, with a compressed backup for an exact restore
- **Safe if interrupted:** the change is logged before each file is written, and every file is written to a temp copy and then swapped in
- **Optional in-sim window:** a small FlyWithLua script switches the forest density in 4 steps during flight, see below

## Installation & usage

> **This is not a plugin.** It is a small tool you run once, outside X-Plane. Do not copy it into `Resources\plugins`. Only the optional in-sim window (`ForestDensityToggle.lua`) goes into the FlyWithLua folder, see below.

1. **Close X-Plane.**
2. Download the ZIP for your system from [Releases](../../releases) (`…_Windows.zip`, `…_macOS.zip` or `…_Linux.zip`) and unzip it anywhere. No renaming needed. If you unzip it into your X-Plane 12 folder, X-Plane is found automatically. Otherwise the tool reads `x-plane_install_12.txt` or asks for the path.
3. Start the tool for your system (see below).
4. Choose from the menu:
   - `1` **Choose settings.** Three steps: density factor (first time Enter = the tool's preset 0.7), tree height factor (1 = unchanged); later Enter keeps the current values and – if simHeaven X-World is installed – hedges *default* or *enhanced*. Then a summary is shown; nothing is changed until you confirm it. Depending on your PC this can take several minutes (longer with tree height and Global Forests v2)
   - `2` **Restore original.** Puts back the original forests and hedges
   - `3` **Status.** Shows how many forest files are tweaked or original

Run it once. Run it again only after an X-Plane or Global Forests update.

### Windows

Double-click the `.bat` for your setup:

| Your setup | Run |
|---|---|
| Plain X-Plane 12 | `Start_Vanilla-simHeaven.bat` |
| X-Plane 12 + simHeaven X-World | `Start_Vanilla-simHeaven.bat` |
| X-Plane 12 + Global Forests v2 (GeoReality) | `Start_GlobalForestsV2.bat` |

simHeaven X-World links its forests to the X-Plane default forest files, so the vanilla edition covers it.
The GFv2 edition also tweaks the default forests, because they are still used outside GFv2 coverage.
No admin rights needed. Uses PowerShell, which ships with Windows 10/11.

### macOS

Double-click `Start_ForestTweak_macOS.command`.

- macOS blocks downloaded scripts the first time: right-click the file → *Open* → *Open*.
- Needs Python 3.8 or newer. If it is missing, macOS offers to install the *Command Line Developer Tools*, which include Python 3. Alternatively install it from [python.org](https://www.python.org/downloads/macos/).
- Without double-click: open Terminal and run `python3 ` followed by the path of `xp12_forest_tweak.py` (drag the file into the Terminal window).

### Linux

Open a terminal in the unzipped folder and run:

```
sh start_forest_tweak_linux.sh
```

Needs Python 3.8 or newer (preinstalled on most distributions).

On macOS and Linux there is one tool for all setups: if Global Forests v2 is installed, it asks whether to include it.

### Choosing a factor

| Factor | Effect | GPU load |
|---|---|---|
| 0.8 | noticeably denser | low |
| **0.7** | **≈ 2× trees, recommended** | medium |
| 0.6 | very dense | high |

### Tree height (optional)

| Height factor | Effect |
|---|---|
| **1.0** | **unchanged (default)** |
| 0.8 | trees 20 % smaller |
| 0.5 | half height (minimum) |

**Smaller trees – all of them, including the 3D models.** The height factor scales every tree in the forest files: the distant billboards *and* the close-up 3D models, so near and far trees match without popping. Undergrowth scales along. Example: at 0.8 a 12–17 m tree becomes 9.6–13.6 m.

Scaling the 3D models rewrites the forest files (a few minutes). A compressed copy of each original is kept in `ForestDensityTweak/mesh_backup` (about 1.5 GB with Global Forests v2) for an exact restore. Free disk space is checked first.

To change a value later, just run *Choose settings* again: the tool restores the originals first and then applies the new values.

### simHeaven hedges / Knicks (optional)

simHeaven X-World draws hedges from OpenStreetMap, for example the typical *Knicks* (hedgerows on earth walls) in northern Germany. By default they are only 2.2–2.8 m high and disappear 4 km away, so from the air the fields look bare.

Step 3 of *Choose settings* switches them between:

| Setting | Height | Visible up to |
|---|---|---|
| **default** | 2.2–2.8 m | 4 km |
| **enhanced** | about 4–5 m | 8 km |

Only the hedge files of the *simHeaven X-World Vegetation Library* are changed; the original lines are logged in `ForestDensityTweak/hedges.log` and restored exactly when you switch back. You can change it on its own by pressing Enter for density and height. Hedges are simple 2D billboards, so the cost is small, but in hedge-rich regions there are a lot of them. Not shown without simHeaven X-World. After a simHeaven update, run *Choose settings* again and confirm.

## In-sim window (optional)

Switch the density in flight in 4 steps and see the tree height set by the tweak. Needs the tweak applied and [FlyWithLua NG+](https://github.com/X-Friese/FlyWithLua).

1. Copy `FlyWithLua/ForestDensityToggle.lua` from the ZIP to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`
2. In the sim: *Plugins → Forest Tweak → Show / hide window* (fallback: *Plugins → FlyWithLua → FlyWithLua Macros → Forest Tweak: window*)
3. Pick a step and press **Apply**. With *Reload scenery on apply* ticked it shows at once (the reload takes a while), otherwise on scenery loaded as you fly on.

Key bindings: search `ForestDensity` in the keyboard settings.

## How it works

- **Density:** `SPACING` (tree distance) and `RANDOM` in each `.for` file are multiplied by the factor. The vegetation slider can never go above this value.
- **Height:** min/max height in each file's tree list is multiplied by the factor. The 3D models are scaled to match.
- **Changed folders:** `Resources/default scenery/1200 forests`, plus `Custom Scenery/Global_Forests_v2` in the GFv2 edition (macOS/Linux: if you include it). Hedges option: `Custom Scenery/simHeaven_X-World_Vegetation_Library` (hedge files only).
- **Backup:** original values in `<X-Plane 12>/ForestDensityTweak/backup.log`. **Keep this folder while the tweak is active.**

## Undo

- Use **Restore original** in the menu. It writes back the exact original values.
- Alternative for the default forests: run the X-Plane installer and choose *Update*. It repairs modified files.

## Performance

More trees means more GPU work, especially when flying low over large forests. Check your FPS after applying. If needed, restore and try 0.8.

## Compatibility

- Tested with **X-Plane 12.4.4** and FlyWithLua NG 2.8.12 on Windows. The macOS/Linux version is new in 1.3.0: it produces byte-identical results to the Windows version (checked on real forest files), but has not been tested by many users yet – feedback welcome.
- The `.for` format and the `SPACING` command are documented in Laminar's [forest file format specification](https://developer.x-plane.com/article/forest-for-file-format-specification).
- Works alongside simHeaven X-World and Global Forests v2.
- Forests from other add-ons are not touched.

## Repository layout

| Folder | Content | Download |
|---|---|---|
| `Windows/` | `.bat` starters and PowerShell scripts | `XP12_ForestTweak_v1.3.0_Windows.zip` |
| `macOS/` | `Start_ForestTweak_macOS.command` + `xp12_forest_tweak.py` | `XP12_ForestTweak_v1.3.0_macOS.zip` |
| `Linux/` | `start_forest_tweak_linux.sh` + `xp12_forest_tweak.py` | `XP12_ForestTweak_v1.3.0_Linux.zip` |
| `FlyWithLua/` | `ForestDensityToggle.lua` (in-sim window, all systems) | included in every ZIP |

Download the ZIP for your system from [Releases](../../releases) – each one contains everything you need.

## Credits

Inspired by the `.for` spacing approach discussed on the X-Plane.org forums.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

© E11i0t09 – licensed under [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)](LICENSE).

**Additional permission:** anyone – including companies, schools and flight schools – may download and use XP12 Forest Tweak free of charge, also in a commercial environment (e.g. training, simulators, operations).

**Not allowed** without written permission: selling or renting it, bundling it with paid products or services, charging for downloads, or distributing modified versions commercially.

You may share and adapt it non-commercially, as long as you give appropriate credit and share your changes under the same license. Copies of v1.0.0 to v1.2.1 obtained before 21 October 2026 were licensed under the MIT License.

## Disclaimer

Use at your own risk. Not affiliated with Laminar Research, simHeaven or GeoReality.
