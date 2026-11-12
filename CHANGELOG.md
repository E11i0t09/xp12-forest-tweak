# Changelog

## 1.6.0
- **Windows: a window instead of the console.** All settings on one page with a live preview of what will change. The console menu stays (`Start_ForestTweak_Console.bat`).
- **Windows setup** (`…_Setup.exe`): installs for your user without admin rights, finds X-Plane, optionally the in-sim window. Uninstall offers to restore the original forests first. The ZIP works without installation as before.
- **Updates from the window:** downloads the new version from GitHub, checks its SHA-256 and installs it.
- Hedge choices renamed: *Green hedges* and *+ Hedgebanks* (was *Enhanced* / *Hedgebanks*). No earth banks are built: the Knick look is mixed bushes with single tall trees.
- Fix (Windows): *[0] Recommended setup* with X-WORLD Pro chose only Germany instead of all countries with Pro tiles.

## 1.5.2
- **[0] Recommended setup:** one key for good default settings.
- **After an update** the tool offers to put the tweak back right at the start; the in-sim window warns when forests were reset.
- **Hedge build safe if interrupted:** it goes on where it stopped.
- Fix (Windows): hedge build stopped with "empty path" on tiles without a simHeaven file.
- simHeaven packs on other drives are found; disk space is checked before building.
- X-WORLD Pro: countries with Pro tiles are preselected.
- macOS/Linux: hedge tiles are built on several CPU cores.

## 1.5.1
- **simHeaven X-WORLD Pro:** the tool now finds which simHeaven add-ons are installed (free X-World, X-WORLD Pro, or none) and gives the same look for forests, hedges and bushes with both. X-WORLD Pro draws hedges as flat textured walls (facades) without seasons; with *Enhanced* or *Hedgebanks* they become green hedges with all four seasons in the countries you choose (Germany, Denmark, Benelux, Austria, Switzerland, or all Pro tiles). Built on your computer, nothing of simHeaven is shipped.
- **Official hedge maps for more regions:** besides Schleswig-Holstein now also Niedersachsen/Bremen/Hamburg, Nordrhein-Westfalen, Bayern, Brandenburg and the Danish earth banks (diger). Hedges that OpenStreetMap does not have are added. In the Knick areas they become hedgebanks, elsewhere green hedges. All map files come with the tool, each under its own open license (see `data/DATA_LICENSES.txt`).
- **Shorter menu, three steps:** tree spacing, tree height, hedges. The height profile is always *realistic* now (an existing *uniform* tweak changes at the next *Choose settings*, shown in the summary). New defaults when nothing is tweaked yet: spacing 0.7, height 0.7. The summary lists what will be changed.
- **Hedges:** *[1] Original*, *[2] Enhanced* (green hedges 4–5 m), *[3] Hedgebanks (Knicks)*. With free X-World, *Enhanced* works worldwide at once; the hedge maps are added in their regions.
- Free X-World and X-WORLD Pro both active for the same region: the tool offers to turn off the free packs (backup of `scenery_packs.ini` kept).
- After a simHeaven update, *Check & repair* rebuilds only the hedge tiles whose simHeaven source changed.
- *Choose settings* no longer reads all forest files a second time right after the start.
- In-sim window: shows the hedge setting (*enhanced* or *hedgebanks*) and whether hedge maps are used.

## 1.5.0
- **Hedgerow map Northern Germany/Denmark (optional):** with Knicks on, the tool can use the official map of all Knicks, field hedges, tree rows and avenues of Schleswig-Holstein (LLUR SH, CC BY 4.0, included in the ZIP) and builds exact Knicks on your computer in about a minute. Where the map has nothing (Denmark, Lower Saxony, Mecklenburg, gardens), the simHeaven hedges stay. *Restore original* removes everything.
- **More natural Knicks:** bushes in three sizes (1.5–8 m) and Ueberhaelter in three ages (6–14 m), all scaled by your tree height. Heights change in sections of about 100 m, and there are sections with and without Ueberhaelter.
- **Quick switch [5]:** switch between your tweak and the original forests, hedges and Knicks in a few seconds, without calculating again. Both versions are kept side by side.
- **Tree height presets:** *Original*, *Slightly smaller* 0.8, *Smaller* 0.7, *Much smaller* 0.6 or your own value, like the tree spacing.
- **No more lines in dense forests:** trees are spread more randomly within their grid, so the planting rows no longer show from above. Orchards and other planted rows stay as they are. No FPS cost.
- One ZIP with Windows, macOS and Linux for download sites. License notice in every file.
- Run *Choose settings* once to apply it to an existing tweak.

## 1.4.1
- **Knicks (optional):** new choice *[3] Knicks* in the hedge step. In northern Germany and Denmark the flat simHeaven hedges become real Knicks: dense bushes with single trees, tree rows with mixed trees, denser scrub. Elsewhere the hedges are *enhanced*. Knicks follow the tree height setting and are removed completely by *Restore original*.
- **Fuller sparse forests (Global Forests v2):** sparse forest areas get more trees, dense areas stay as they are.
- **In-sim window:** buttons show how many trees compared to the original (1.0x up to 2.8x), steps above the tool setting are greyed out. The window remembers the chosen step and sets it again at the next sim start.
- *Check & repair* also checks the Knicks.

## 1.4.0
- **One Windows tool:** `Start_ForestTweak.bat` replaces the two editions. It finds Global Forests v2 and asks whether to include it, like the macOS/Linux version. Existing tweaks keep working (same backup log).
- **Presets for the tree spacing:** *Natural* 0.8, *Dense* 0.7 (recommended), *Very dense* 0.6 or *Custom*. Clearer wording: "tree spacing – lower = closer trees = denser forest". Input like `0,7` or `70` is accepted.
- **Realistic height profile (optional):** below height factor 1.0 you choose *uniform* or *realistic*. Realistic: conifers shrink less, palms a bit less, shrubs/orchards hardly (e.g. 0.8 → conifers 0.88, shrubs 0.9).
- **Global Forests v2 cropland:** field trees and hedgerows between fields get an extra spacing factor 0.8, so field edges fill more evenly. A tweak from an older version is updated by running *Choose settings* once.
- **New menu item Check & repair:** checks the 3D model backups, removes leftovers of an interrupted run, unused backups and empty folders, cleans up the log.
- **Safer backups:** SHA-256 checksum for every 3D model backup, checked before a restore. A damaged backup is never used; the file stays tweaked and is never scaled twice. Free disk space is checked before every write. The backup log is kept compact (one line per file).
- **Helpful hints:** one-line status at start; warnings if the vegetation slider is not at maximum, if Global Forests v2 is disabled in `scenery_packs.ini` or active but not tweaked, and for untested X-Plane versions; *Status* lists other scenery with its own forests (e.g. Orbx TrueEarth); hint when a new version is on GitHub (max. 3 s, display only).
- Changes are blocked while X-Plane is running. The summary shows an estimated time, the progress the remaining time; Ctrl+C stops cleanly with a clear message; "Done!" message at the end; the window only stays open after an error.
- macOS/Linux: 3D tree models are scaled on several CPU cores (noticeably faster on multi-core computers).
- `ForestDensityTweak/tool.log` records what the tool did (for bug reports).
- In-sim window: shows the height profile and the simHeaven hedge setting.
- README: new section *I don't see a difference* (vegetation slider, forest data of the scenery, other add-ons).

## 1.3.0
- **macOS and Linux:** new Python version (`xp12_forest_tweak.py`, needs Python 3.8+, no extra packages) with starters for macOS (`Start_ForestTweak_macOS.command`) and Linux (`start_forest_tweak_linux.sh`). Same logic as the Windows version, byte-identical results, same backup log.
- **Shared backup log across systems:** the Windows version now also reads log entries written on macOS/Linux, so a tweak can be restored from either system (e.g. dual boot with one X-Plane folder).
- The tools find X-Plane automatically when the ZIP is unzipped into the X-Plane 12 folder, also from a subfolder. The macOS/Linux version also accepts the X-Plane path as an argument.
- **New menu flow:** `[1] Choose settings` asks density, tree height and hedges step by step, shows a summary and only changes files after you confirm. Changing values no longer needs a manual *Restore* first. After an update, running it again re-applies the tweak to reset files.
- **simHeaven hedges / Knicks (optional):** step 3 of *Choose settings* switches the simHeaven X-World hedges between *default* (2.2–2.8 m, visible up to 4 km) and *enhanced* (about 4–5 m, up to 8 km). Exact restore via `ForestDensityTweak/hedges.log`.
- **Three downloads:** separate ZIPs for Windows, macOS and Linux; in the repository the files are in the folders `Windows/`, `macOS/`, `Linux/` and `FlyWithLua/`.
- Clearer install notes: it is not a plugin, no renaming needed, run it once and again only after updates.
- All files now carry the same version number.

## 1.2.2
- Free community project – not for sale. License changed to **CC BY-NC-SA 4.0** with an additional permission: free use for everyone, including companies and flight schools; selling, bundling with paid products, paid downloads and commercial distribution of modified versions are not allowed. No functional changes. Older releases were removed.

## 1.2.1
- Renamed to **XP12 Forest Tweak** (it now changes tree height too). Script files, window title and Plugins menu use the new name. The backup folder `ForestDensityTweak`, the Lua file name and the FlyWithLua commands stay the same, so existing tweaks and key bindings keep working.
- Window shows both reload modes; remembers the active step across "Reload all Lua script files".

## 1.2.0
- **Tree height (optional):** Apply now also asks for a height factor (0.5 – 1.0). Min and max height of all trees are scaled, so the height variation shrinks along.
- **3D trees scale too:** the 3D models of `TREE` trees are scaled with the same factor, so close-up trees match the distant billboards (no popping). `TREE2` trees scale by themselves through their nominal height.
- **Exact restore with 3D models:** before 3D models are changed, a compressed copy of each original file is kept in `ForestDensityTweak\mesh_backup` (about 30 % of the file size). Restore puts it back byte for byte and deletes the copy.
- **In-sim window (ForestDensityToggle.lua):** four density steps with Apply, optional scenery reload (off by default, at most one per minute), overview of the tree height set by the tweak, own entry under *Plugins → Forest Density*, remembered position and settings.
- Backup logs from 1.0 / 1.1 keep working.

## 1.1.0
- Optional FlyWithLua script to toggle between dense and original forests in flight.

## 1.0.0
- First release: density tweak with menu (apply / restore / status), editions for vanilla/simHeaven and Global Forests v2, exact restore, update detection.
