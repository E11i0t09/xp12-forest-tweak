# Changelog

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
