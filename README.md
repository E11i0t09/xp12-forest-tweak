# XP12 Forest Tweak

**Denser, more realistic forests for X-Plane 12 – for vanilla, simHeaven X-World, simHeaven X-WORLD Pro and Global Forests v2. Optionally smaller trees and real-looking hedges. Windows, macOS and Linux.**

> **Free community project – not for sale.** Free to use for everyone, including companies and flight schools. See [License](#license).

Even with the vegetation slider at maximum, X-Plane 12 forests often look like loose groups of trees instead of a forest. That's because the slider can never go above the density set in the forest definition files (`.for`). This tool lowers the tree spacing in those files, safely and reversibly.

Tree spacing 0.7 (preset *Dense*) ≈ **twice as many trees per area.**

## Screenshots

Same view over the Inn valley near Innsbruck, with simHeaven X-World and Global Forests v2.

| Before (original density) | After (Forest Tweak applied) |
|---|---|
| ![Original X-Plane 12 forest: single trees standing apart on the slope](screenshots/before.jpg) | ![Forest Tweak applied: closed, dense forest on the same slope](screenshots/after.jpg) |

Autumn, wide view over a hilly forest region: the original forests show ground between the trees, with the tweak the forest canopy is closed.

| Before (original density) | After (Forest Tweak applied) |
|---|---|
| ![Original X-Plane 12 autumn forest from altitude: trees with visible ground in between](screenshots/before_autumn.jpg) | ![Forest Tweak applied: closed autumn forest canopy over the same area](screenshots/after_autumn.jpg) |

Dense autumn forest with the tweak applied.

![Forest Tweak applied: dense mixed autumn forest along a motorway](screenshots/autumn_forest.jpg)

Hedgebanks (Knicks) in northern Germany: hedges and tree rows become Knicks with bushes and single trees.

| Knicks near the ground | Knicks from the air |
|---|---|
| ![Knicks option: rows of bushes with single trees between the fields](screenshots/knicks.jpg) | ![Knicks option from a Cessna: field pattern framed by Knicks](screenshots/knicks_air.jpg) |

Hedge maps: in Schleswig-Holstein the hedgebanks (Knicks) follow the real hedgerow lines from the state biotope mapping (LLUR SH, CC BY 4.0). Since 1.5.1 also for Lower Saxony, Bremen, Hamburg, North Rhine-Westphalia, Bavaria, Brandenburg and Denmark.

![Hedgerow map: dense Knicks along the real field boundaries in Schleswig-Holstein, low evening sun](screenshots/knicks_map.jpg)

In-sim window (`ForestDensityToggle.lua`): density from 1.0x to 2.8x as many trees as the original, scenery reload option and the settings of the tweak.

![Forest Tweak window in X-Plane 12 with density buttons 1.0x to 2.8x over a dense forest slope](screenshots/window.jpg)

---

## Features

- **Windows, macOS and Linux:** one tool per system with the same logic and the same backup log, so a tweak made on one system can be restored on the other
- **Simple menu:** Choose settings · Restore original · Status · Check & repair. Three steps (tree spacing, tree height, hedges); you pick all values first and confirm a summary before anything is changed
- **Presets for the tree spacing:** *Natural* 0.8, *Dense* 0.7 (recommended), *Very dense* 0.6, or your own value from 0.4 to 1.0
- **Optional tree height:** factor 0.5 – 1.0 with a realistic height profile (conifers shrink less, shrubs hardly). The 3D tree models are scaled too, so near and far trees match
- **Global Forests v2 cropland:** field trees and hedgerows between fields get an extra factor 0.8, so field edges are filled more evenly
- **Fuller sparse forests (Global Forests v2):** sparse forest areas get extra trees, dense areas stay as they are
- **Optional: hedges** *original*, *enhanced* (green hedges 4–5 m, all four seasons) or **hedgebanks (Knicks)** with bushes and single trees in northern Germany and Denmark – with simHeaven X-World (free) and X-WORLD Pro, see below
- **Official hedge maps** of Schleswig-Holstein, Lower Saxony/Bremen/Hamburg, North Rhine-Westphalia, Bavaria, Brandenburg and Denmark add the hedges OpenStreetMap does not have
- **simHeaven X-WORLD Pro:** detected automatically. Its hedges (grey walls) become green hedges in the countries you choose
- **Fully reversible:** the original values are logged and restored byte-for-byte; 3D model backups are protected by a checksum
- **Quick to reapply after updates:** reset files are detected and tweaked again, already tweaked files are skipped
- **Never applied twice:** all versions share one backup log
- **Grass, shrubs and hedges are left alone:** only files with a spacing above 3.1 m are changed
- **Safe if interrupted:** every change is logged before the file is swapped in; Ctrl+C or a full disk stops cleanly
- **Helpful checks at start:** vegetation slider not at maximum, Global Forests v2 disabled in `scenery_packs.ini` or active but not tweaked, X-Plane running, untested X-Plane version, new tool version available
- **Optional in-sim window:** a small FlyWithLua script switches the forest density during flight, from original up to the tool setting (1.0x · 1.25x · 1.5x · 1.8x · 2.0x · 2.5x · 2.8x as many trees), see below

## Installation & usage

> **This is not a plugin.** It is a small tool you run once, outside X-Plane. Do not copy it into `Resources\plugins`. Only the optional in-sim window (`ForestDensityToggle.lua`) goes into the FlyWithLua folder, see below.

1. **Quit X-Plane.** The tool won't change anything while X-Plane is running.
2. Download the ZIP for your system from [Releases](../../releases) (`…_Windows.zip`, `…_macOS.zip` or `…_Linux.zip`) and unzip it anywhere. No renaming needed. If you unzip it into your X-Plane 12 folder, X-Plane is found automatically. Otherwise the tool reads `x-plane_install_12.txt` or asks for the path.
3. Start the tool for your system (see below). If Global Forests v2 is installed, it asks whether to include it.
4. Choose from the menu:
   - `1` **Choose settings** – tree spacing, tree height and (with simHeaven) hedges, in three steps. Then a summary of what will be changed, with an estimated time; nothing is changed until you confirm it. With tree height and Global Forests v2 it can take 10 minutes or more
   - `2` **Restore original** – puts back the original forests and hedges
   - `3` **Status** – how many forest files are tweaked, hedges, other scenery with its own forests
   - `4` **Check & repair** – checks the backups, removes leftovers of an interrupted run and cleans up the log
   - `5` **Switch to original / back to tweak** – switches between your tweak and the original forests, hedges and Knicks in a few seconds, without calculating again

Run it once. Run it again only after an X-Plane or Global Forests update.

### Windows

Double-click `Start_ForestTweak.bat`. One tool for vanilla X-Plane, simHeaven X-World and Global Forests v2.

No admin rights needed. Uses PowerShell, which ships with Windows 10/11.

Coming from 1.3 or older: just use the new tool – it reads the same backup log. You can delete the old `Start_Vanilla-simHeaven.bat`, `Start_GlobalForestsV2.bat` and their `.ps1` files.

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

### Tree spacing

Lower spacing = closer trees = denser forest. 1.0 = original.

| Preset | Spacing | Effect | GPU load |
|---|---|---|---|
| Natural | 0.8 | noticeably denser (≈ 1.6× trees) | low |
| **Dense** | **0.7** | **≈ 2× trees, recommended** | medium |
| Very dense | 0.6 | ≈ 2.8× trees | high |
| Custom | 0.4 – 1.0 | your own value | |

Values can be typed as `0.7`, `0,7` or `70`.

**Global Forests v2 cropland:** the *cropland* forests of GFv2 (single trees and hedgerows between fields) get an extra factor 0.8, e.g. spacing 0.7 → 0.56 there. This fills field edges more evenly without making the real forests even denser.

**Fuller sparse forests (Global Forests v2):** GFv2 sorts every forest area by satellite data into one of four density steps, from very sparse to very dense. The very sparse areas get almost twice as many trees as before, the sparse ones a few more, the dense ones stay as they are. A sparse forest still looks lighter than a dense one, but no longer empty. This is always on when Global Forests v2 is included.

### Tree height (optional)

| Preset | Height factor | Effect |
|---|---|---|
| Original | 1.0 | unchanged |
| Slightly smaller | 0.8 | trees 20 % smaller |
| **Smaller** | **0.7** | **30 % smaller (default for a first tweak)** |
| Much smaller | 0.6 | 40 % smaller |
| Custom | 0.5 – 1.0 | your own value |

The height profile is realistic: conifers are often the tallest trees in reality, while shrubs and orchards are small anyway. Example at 0.8: broadleaf, mixed, cropland 0.8 · conifers 0.88 · palms 0.84 · shrubs, orchards, cacti 0.9. (Up to 1.5.0 a *uniform* profile could be chosen; such a tweak becomes realistic at the next *Choose settings*, the summary shows it.)

**All trees, including the 3D models.** The height factor scales the distant billboards *and* the close-up 3D models, so near and far trees match without popping. Example: at 0.8 a 12–17 m tree becomes 9.6–13.6 m.

Scaling the 3D models rewrites the forest files (a few minutes; the macOS/Linux version uses several CPU cores). A compressed copy of each original, with a SHA-256 checksum, is kept in `ForestDensityTweak/mesh_backup` (about 1.5 GB with Global Forests v2) for an exact restore. Free disk space is checked before every file is written.

To change a value later, just run *Choose settings* again: the tool restores the originals first and then applies the new values.

### Hedges and hedgebanks (optional, with simHeaven)

simHeaven X-World draws hedges from OpenStreetMap, for example the typical *Knicks* (hedgebanks: hedges on earth walls) in northern Germany. In the free X-World they are only 2.2–2.8 m high and disappear 4 km away. simHeaven X-WORLD Pro draws them as grey walls without seasons. Many hedges are missing in OpenStreetMap altogether, so from the air the fields look bare.

The tool finds out which simHeaven add-ons are installed. Step 3 of *Choose settings* gives the same look with both:

| Choice | Free X-World | X-WORLD Pro |
|---|---|---|
| **[1] Original** | as simHeaven made them | as simHeaven made them |
| **[2] Enhanced** | green hedges about 4–5 m, visible up to 8 km, worldwide | the walls become green hedges about 4–5 m in the countries you choose |
| **[3] Hedgebanks (Knicks)** | hedgebanks in the Knick areas, elsewhere *enhanced* | hedgebanks in the Knick areas, *enhanced* in the other chosen countries |

All new hedges change with the four seasons. Without simHeaven, step 3 is skipped.

**Hedgebanks (Knicks):** in the Knick and Wallhecken areas – Schleswig-Holstein, Hamburg, north-west Lower Saxony, west Mecklenburg and Denmark – hedges become bushes of 1.5–8 m with hedgerow trees (Überhälter) of 6–14 m (oaks, ashes, maples), changing in sections of about 100 m. Tree rows get mixed trees with bushes in between, scrub areas get dense bushes with a few small trees. Everything follows your tree height. X-Plane can only limit this to whole 1×1° tiles, so some neighbouring areas are included too (e.g. Hannover, Rostock, western Skåne).

**X-WORLD Pro countries:** with Pro, *Enhanced* and *Hedgebanks* ask for the countries: Germany, Denmark, Benelux, Austria, Switzerland, or all Pro tiles on your computer. The Knick areas are always included. The tool reads the Pro hedge lines on your computer and builds green hedges from them (a few seconds per tile).

**Official hedge maps:** with *Enhanced* or *Hedgebanks*, the tool adds the hedges, tree rows and copses of official maps that come with it (folder `data/`, about 30 MB):

| Region | Source |
|---|---|
| Schleswig-Holstein | LLUR SH, Biotopkartierung SH4 |
| Lower Saxony, Bremen, Hamburg | ML/SLA Niedersachsen, landscape elements |
| North Rhine-Westphalia | Land NRW, landscape elements |
| Bavaria | StMELF Bayern, landscape elements |
| Brandenburg | MLEUV Brandenburg, landscape elements |
| Denmark | Slots- og Kulturstyrelsen, protected earth banks (*diger*; stone walls left out) |

With *Hedgebanks* the map hedges become hedgebanks in the Knick areas and green hedges elsewhere; with *Enhanced* they are green hedges everywhere. Where a map has a hedge, it replaces the simHeaven one; the simHeaven hedges the maps don't have are taken over, so nothing is lost and nothing is doubled.

**Where it goes:** the hedges are built on your computer into `Custom Scenery/XP12_ForestTweak_HedgerowMap` (up to about 250 MB with Pro in five countries), the hedge types into the small library `Custom Scenery/XP12_ForestTweak_Knicks` (trees copied from the X-Plane default forests, about 13 MB). Both are listed in `scenery_packs.ini` above simHeaven (a backup is kept in `ForestDensityTweak`). With the free X-World, *Enhanced* also changes the hedge files of the *simHeaven X-World Vegetation Library*; the original lines are logged in `ForestDensityTweak/hedges.log`. simHeaven files are otherwise only read, nothing of simHeaven is shipped. *Restore original* removes everything again.

If the free X-World and X-WORLD Pro are both active for the same region, the tool offers to turn the free packs off. After a simHeaven update, run **Check & repair**: it rebuilds the hedge tiles whose simHeaven source changed.

## I don't see a difference

The tool raises the maximum density in the forest files. What you see is still limited by:

- **The vegetation slider** in X-Plane (*Settings → Graphics*). It scales everything down from that maximum. The tool warns at start if it is not at maximum.
- **The forest data of the scenery.** Trees only grow where the scenery has forest areas. Where there are none (e.g. many fields, towns, some regions), no trees are added.
- **Other scenery with its own forests** (e.g. Orbx TrueEarth or photo scenery with own vegetation). Where it covers an area, its forests are shown. *Status* lists such scenery.
- **Global Forests v2 not included or disabled.** In GFv2 areas only the GFv2 forests count. The tool warns if GFv2 is active but not tweaked, or tweaked but disabled in `scenery_packs.ini`.
- **An X-Plane or GFv2 update** reset the files. Run *Choose settings* again.

## Antivirus warning (Windows)

Some antivirus programs (e.g. Bitdefender, "Gen:Variant.MSIL…") report a file in your Temp folder when the tool starts. That's a false positive. The Windows tool is only a `.bat` and a PowerShell script you can read in Notepad. A small part of the script is written in C# for the heavy work (3D trees, hedge tiles), and Windows PowerShell compiles that part into a temporary .NET file at every start. A new unsigned .NET file with a random name is what the heuristics flag. Avoiding that would need a paid code-signing certificate, which this free project doesn't have. Pause the antivirus while the tool runs, or report the false positive to your antivirus vendor.

## In-sim window (optional)

Switch the density in flight and see the tree height, height profile and hedge setting set by the tweak. The buttons show how many trees compared to the original: 1.0x · 1.25x · 1.5x · 1.8x · 2.0x · 2.5x · 2.8x (rounded). Steps above the tool setting are greyed out – the window can only show up to what the tool wrote into the forest files (0.7 = 2.0x, 0.6 = 2.8x). Needs the tweak applied and [FlyWithLua NG+](https://github.com/X-Friese/FlyWithLua).

1. Copy `FlyWithLua/ForestDensityToggle.lua` from the ZIP to `X-Plane 12/Resources/plugins/FlyWithLua/Scripts/`
2. In the sim: *Plugins → Forest Tweak → Show / hide window* (fallback: *Plugins → FlyWithLua → FlyWithLua Macros → Forest Tweak: window*)
3. Pick a step and press **Apply**. With *Reload scenery on apply* ticked it shows at once (the reload takes a while), otherwise on scenery loaded as you fly on. **Reload scenery** reloads at once at any time. The chosen step is remembered for the next flight; if it is below the tool setting, a note is shown on screen and in the window.

Key bindings: search `ForestDensity` in the keyboard settings.

## How it works

- **Tree spacing:** `SPACING` (tree distance) and `RANDOM` in each `.for` file are multiplied by the factor. The vegetation slider can never go above this value.
- **No grid lines:** in natural forests `RANDOM` (how far a tree may move away from its grid position) is set to at least half the tree spacing. With less, X-Plane leaves empty strips between the tree rows, which show up as lines in dense forests. Planted rows like orchards keep their grid.
- **Height:** min/max height in each file's tree list is multiplied by the factor (per forest type with the *realistic* profile). The 3D models are scaled to match.
- **Changed folders:** `Resources/default scenery/1200 forests`, plus `Custom Scenery/Global_Forests_v2` if you include it. Hedges: `Custom Scenery/simHeaven_X-World_Vegetation_Library` (hedge files only, free X-World) and the tool's own folders `Custom Scenery/XP12_ForestTweak_Knicks` and `Custom Scenery/XP12_ForestTweak_HedgerowMap` plus their lines in `scenery_packs.ini`. simHeaven X-World and X-WORLD Pro link their forests to the default forest files, so they are covered too.
- **Backup:** original values in `<X-Plane 12>/ForestDensityTweak/backup.log`. **Keep this folder while the tweak is active.**
- **Tool log:** `ForestDensityTweak/tool.log` lists what the tool did – please attach it to bug reports.
- **Update check:** at start the tool asks GitHub for the latest release (max. 3 s, nothing is sent, silent if offline). It only shows a hint, it never downloads anything.

## Undo

- Use **Restore original** in the menu. It writes back the exact original values.
- To compare, use **[5] Switch to original**: forests, hedges and Knicks are original again, your tweak is kept next to the files (`.fdt_tweak` / `.fdt_orig`). **[5]** again switches back in a few seconds. The first switch keeps a copy of the original files (about as much disk space as the tweaked files, with 3D trees and Global Forests v2 a few GB). *Choose settings*, *Restore original* and *Check & repair* switch back to the tweak first.
- If a 3D model backup is missing or damaged, that file stays tweaked (it is never scaled twice). Run the X-Plane installer (*Update*) or reinstall Global Forests v2, then **Check & repair**.

## Performance

More trees means more GPU work, especially when flying low over large forests. Check your FPS after applying. If needed, choose *Natural* (0.8).

## Compatibility

- Tested with **X-Plane 12.4.x**, simHeaven X-World (free) and X-WORLD Pro Europe, and FlyWithLua NG 2.8.12. Windows, macOS and Linux versions produce byte-identical results (checked on real forest files of X-Plane and Global Forests v2 and on the hedge tiles).
- Backup logs of all earlier versions keep working. Running *Choose settings* once applies the latest improvements (GFv2 cropland and sparse forests) to a tweak made with an older version.
- The `.for` format and the `SPACING` command are documented in Laminar's [forest file format specification](https://developer.x-plane.com/article/forest-for-file-format-specification).
- Forests from other add-ons are not touched.

## Repository layout

| Folder | Content | Download |
|---|---|---|
| `Windows/` | `Start_ForestTweak.bat` + `XP12_ForestTweak.ps1` | `XP12_ForestTweak_v1.5.1_Windows.zip` |
| `macOS/` | `Start_ForestTweak_macOS.command` + `xp12_forest_tweak.py` | `XP12_ForestTweak_v1.5.1_macOS.zip` |
| `Linux/` | `start_forest_tweak_linux.sh` + `xp12_forest_tweak.py` | `XP12_ForestTweak_v1.5.1_Linux.zip` |
| `FlyWithLua/` | `ForestDensityToggle.lua` (in-sim window, all systems) | included in every ZIP |
| `data/` | `hedgerow_map_*.dat` (official hedge maps) + `DATA_LICENSES.txt` – each map under its own license | included in every ZIP |

Download the ZIP for your system from [Releases](../../releases) – each one contains everything you need.

## Credits

Inspired by the `.for` spacing approach discussed on the X-Plane.org forums.

Official hedge maps in `data/` (only outlines and type kept, coordinates converted and stored in a compact format; turned into X-Plane forest strips and tree rows by the tool). Each map file is licensed under the license of its source, not under the tool license. Full details, dataset links and changes: [data/DATA_LICENSES.txt](data/DATA_LICENSES.txt).

- `hedgerow_map_sh.dat` – LLUR SH, [Biotopkartierung SH4 – Alleen, Knicks, Feldhecken und Baumreihen](https://opendata.schleswig-holstein.de/dataset/sh4-biotopkartierung-der-alleen-knicks-feldhecken-und-baumreihen) (2023), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- `hedgerow_map_ni.dat` – © ML/SLA Niedersachsen/CC BY 4.0 – [Landschaftselemente in Niedersachsen, Bremen und Hamburg](https://inspire-geoportal.ec.europa.eu/srv/api/records/c0f447eb-151b-42a7-bdd0-e99b1062f67c), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- `hedgerow_map_nrw.dat` – Land NRW – [Landschaftselemente in NRW](https://ckan.open.nrw.de/dataset/landschaftselemente-in-nrw-geo-nrw) (retrieved 2026-11-07), [dl-de/by-2-0](https://www.govdata.de/dl-de/by-2-0)
- `hedgerow_map_by.dat` – Bayerisches Staatsministerium für Ernährung, Landwirtschaft, Forsten und Tourismus – [InVeKoS Landschaftselemente](https://gdk.gdi-de.org/geonetwork/srv/api/records/2bf51905-de03-4a56-93c4-1bea034b3a4d), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- `hedgerow_map_bb.dat` – © Ministerium für Land- und Ernährungswirtschaft, Umwelt und Verbraucherschutz – [InVeKoS Landschaftselemente BB](https://gdk.gdi-de.org/geonetwork/srv/api/records/72ed0323-7f32-400f-8bc1-7f0bb6cb83ba) (retrieved 2026-11-07), [dl-de/by-2-0](https://www.govdata.de/dl-de/by-2-0)
- `hedgerow_map_dk.dat` – Slots- og Kulturstyrelsen – [Beskyttede sten- og jorddiger](https://arealdata.miljoeportal.dk/datasets/urn:dmp:ds:beskyttede-sten-og-jorddiger), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

The data providers do not endorse this project. Hedges and tree rows elsewhere come from simHeaven X-World or X-WORLD Pro (OpenStreetMap data, © OpenStreetMap contributors, ODbL) on your own computer and are not part of this tool.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

© E11i0t09 – licensed under [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)](LICENSE).

**Additional permission:** anyone – including companies, schools and flight schools – may download and use XP12 Forest Tweak free of charge, also in a commercial environment (e.g. training, simulators, operations).

**Not allowed** without written permission: selling or renting it, bundling it with paid products or services, charging for downloads, or distributing modified versions commercially.

You may share and adapt it non-commercially, as long as you give appropriate credit and share your changes under the same license. **Exception:** the hedge maps `data/hedgerow_map_*.dat` are not under the tool license. Each one keeps the license of its source (CC BY 4.0, dl-de/by-2-0 or CC0 1.0), see Credits and [data/DATA_LICENSES.txt](data/DATA_LICENSES.txt). Copies of v1.0.0 to v1.2.1 obtained before 21 October 2026 were licensed under the MIT License.

## Disclaimer

Use at your own risk. Not affiliated with Laminar Research, simHeaven or GeoReality.
