# XP12 Forest Tweak

**Denser, more realistic forests for X-Plane 12 – for vanilla, simHeaven X-World and Global Forests v2. Optionally smaller trees.**

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

- **Two editions:** pick the one that matches your scenery setup
- **Simple menu:** Apply · Restore original · Status. No command line needed
- **Factor of your choice:** 0.4 – 1.0, default 0.7
- **Optional tree height:** factor 0.5 – 1.0 scales min and max height of the trees, so the height variation shrinks along. The 3D tree models are scaled too, so near and far trees match
- **Fully reversible:** the original values are logged and restored byte-for-byte
- **Survives updates:** after an X-Plane or Global Forests update, just run *Apply* again. Files that were reset are detected and tweaked again
- **Never applied twice:** both editions share one backup log, so the default forests are only ever scaled once
- **Grass, shrubs and hedges are left alone:** only files with a spacing above 3.1 m are changed
- **Minimal changes:** density only edits two header lines per file (`SPACING`, `RANDOM`). The height option also edits the tree list and scales the 3D tree models, with a compressed backup for an exact restore
- **Safe if interrupted:** the change is logged before each file is written, and every file is written to a temp copy and then swapped in
- **Optional in-sim window:** a small FlyWithLua script switches the forest density in 4 steps during flight, see below

## Which edition?

| Your setup | Run |
|---|---|
| Plain X-Plane 12 | `Start_Vanilla-simHeaven.bat` |
| X-Plane 12 + simHeaven X-World | `Start_Vanilla-simHeaven.bat` |
| X-Plane 12 + Global Forests v2 (GeoReality) | `Start_GlobalForestsV2.bat` |

simHeaven X-World links its forests to the X-Plane default forest files, so the vanilla edition covers it.
The GFv2 edition also tweaks the default forests, because they are still used outside GFv2 coverage.

## Installation & usage

1. **Close X-Plane.**
2. Download the latest ZIP from [Releases](../../releases) and unzip it anywhere. If you unzip it into your X-Plane 12 folder, it finds X-Plane automatically. Otherwise it reads `x-plane_install_12.txt` or asks for the path.
3. Double-click the `.bat` for your edition.
4. Choose from the menu:
   - `1` **Apply.** Asks for the density factor (Enter = 0.7) and the height factor (Enter = 1 = unchanged)
   - `2` **Restore original**
   - `3` **Status.** Shows how many forest files are tweaked or original

No admin rights needed. Windows only (PowerShell, which ships with Windows 10/11).

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

Scaling the 3D models rewrites the forest files (a few minutes). A compressed copy of each original is kept in `ForestDensityTweak\mesh_backup` (about 1.5 GB with Global Forests v2) for an exact restore. Free disk space is checked first.

To change a factor: *Restore*, then *Apply* with the new values.

## In-sim window (optional)

Switch the density in flight in 4 steps and see the tree height set by the tweak. Needs the tweak applied and [FlyWithLua NG+](https://github.com/X-Friese/FlyWithLua).

1. Copy `ForestDensityToggle.lua` to `X-Plane 12\Resources\plugins\FlyWithLua\Scripts\`
2. In the sim: *Plugins → Forest Tweak → Show / hide window*
3. Pick a step and press **Apply**. With *Reload scenery on apply* ticked it shows at once (the reload takes a while), otherwise on scenery loaded as you fly on.

Key bindings: search `ForestDensity` in the keyboard settings.

## How it works

- **Density:** `SPACING` (tree distance) and `RANDOM` in each `.for` file are multiplied by the factor. The vegetation slider can never go above this value.
- **Height:** min/max height in each file's tree list is multiplied by the factor. The 3D models are scaled to match.
- **Changed folders:** `Resources\default scenery\1200 forests`, plus `Custom Scenery\Global_Forests_v2` in the GFv2 edition.
- **Backup:** original values in `<X-Plane 12>\ForestDensityTweak\backup.log`. **Keep this folder while the tweak is active.**

## Undo

- Use **Restore original** in the menu. It writes back the exact original values.
- Alternative for the default forests: run the X-Plane installer and choose *Update*. It repairs modified files.

## Performance

More trees means more GPU work, especially when flying low over large forests. Check your FPS after applying. If needed, restore and try 0.8.

## Compatibility

- Tested with **X-Plane 12.4.4** and FlyWithLua NG 2.8.12. The `.for` format and the `SPACING` command are documented in Laminar's [forest file format specification](https://developer.x-plane.com/article/forest-for-file-format-specification).
- Works alongside simHeaven X-World and Global Forests v2.
- Forests from other add-ons are not touched.

## Credits

Inspired by the `.for` spacing approach discussed on the X-Plane.org forums.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

© E11i0t09 – licensed under [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)](LICENSE).

- **No commercial use** – you may not sell it, bundle it with paid products or use it commercially in any other way.
- You may share and adapt it for non-commercial purposes, as long as you give appropriate credit and share your changes under the same license.

Releases v1.0.0 to v1.2.1 were published under the MIT License and remain available under it.

## Disclaimer

Use at your own risk. Not affiliated with Laminar Research, simHeaven or GeoReality.
