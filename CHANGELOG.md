# Changelog

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
