XP12 Forest Tweak  v1.3.0
=========================

Denser forests and optionally smaller trees (3D trees included) for X-Plane 12.
The vegetation slider can never exceed the tree density defined in the forest
files (.for) - this tool changes those files directly. Default factor 0.7 =
roughly twice as many trees per area. Windows, macOS and Linux.

Tested with X-Plane 12.4.4.

THIS IS NOT A PLUGIN. It is a small tool you run once, outside X-Plane.
Do not copy it into Resources/plugins. No renaming needed.


DOWNLOADS / FOLDERS
-------------------
Download the ZIP for your system - each one contains everything you need:
  XP12_ForestTweak_v1.3.0_Windows.zip  (folder Windows/ in the repository)
      Start_Vanilla-simHeaven.bat  -> plain X-Plane 12, or with simHeaven X-World
      Start_GlobalForestsV2.bat    -> with Global Forests v2 (also tweaks the
                                      default forests used outside GFv2)
  XP12_ForestTweak_v1.3.0_macOS.zip    (folder macOS/)
      Start_ForestTweak_macOS.command  (double-click), needs Python 3.8+
  XP12_ForestTweak_v1.3.0_Linux.zip    (folder Linux/)
      start_forest_tweak_linux.sh      (sh start_forest_tweak_linux.sh), Python 3.8+
  On macOS/Linux one tool covers all setups: it asks whether to include GFv2.
  FlyWithLua/ForestDensityToggle.lua (optional in-sim window, in every ZIP)

All versions share one backup log, nothing is ever scaled twice.


HOW TO USE
----------
1. Close X-Plane.
2. Unzip anywhere (or into your X-Plane 12 folder - then it is found
   automatically). Otherwise the tool finds X-Plane via x-plane_install_12.txt
   or asks for the path.
3. Start the tool for your system (see above).
   macOS: the first time, right-click the .command file > Open > Open.
   If Python 3 is missing, macOS offers to install the Command Line Developer
   Tools (they include Python 3), or get it from python.org.
4. Menu: [1] Choose settings   [2] Restore original   [3] Status

  Choose settings asks step by step - nothing is changed until you confirm
  the summary at the end:
  Density factor: 0.4 - 1.0 (1 = unchanged). Enter keeps the current value;
                  on first use Enter = the tool's preset 0.7.
                  0.8 = milder / cheaper, 0.6 = very dense (strong GPU).
  Height factor:  0.5 - 1.0 (1 = unchanged, Enter keeps the current value). Scales min and max height
                  of the trees, so the height variation shrinks along.
                  The 3D tree models are scaled too. This rewrites the files
                  (a few minutes) and keeps a compressed backup of the originals
                  in ForestDensityTweak/mesh_backup (about 1.5 GB with GFv2).
  Hedges:         default or enhanced (only with simHeaven X-World, see below).
  To change values later, just run Choose settings again.
  Depending on your PC this can take several minutes (longer with tree
  height and Global Forests v2).

Run it once. Run it again only after an X-Plane or Global Forests update.
Grass, shrubs and hedges (spacing <= 3.1 m) are not changed.


SIMHEAVEN HEDGES / KNICKS (OPTIONAL)
------------------------------------
Step 3 of Choose settings switches the hedges of simHeaven X-World (e.g. the Knicks in
northern Germany) between
  default   2.2 - 2.8 m high, visible up to 4 km
  enhanced  about 4 - 5 m high, visible up to 8 km
Only the hedge files of the simHeaven X-World Vegetation Library are changed.
Originals are logged in ForestDensityTweak/hedges.log and restored exactly.
After a simHeaven update, run Choose settings again and confirm.


BACKUP / UNDO
-------------
Original values are logged in  <X-Plane 12>/ForestDensityTweak/backup.log
"Restore original" writes them back exactly (forests and hedges). Do not delete this folder while the tweak
is active. Alternative for the default forests: run the X-Plane installer
("Update") - it repairs modified files.


AFTER AN UPDATE
---------------
X-Plane and Global Forests updates may reset the forest files to originals.
Just run "Choose settings" again and confirm - the tool detects which files
were reset and skips the ones that are still tweaked.


IN-SIM WINDOW (OPTIONAL)
------------------------
ForestDensityToggle.lua adds a small window to switch the forest density in
4 steps during flight. Needs FlyWithLua NG+ and the tweak applied (without the
tweak it can only thin out the vanilla forests).

  1. Copy FlyWithLua/ForestDensityToggle.lua to
     X-Plane 12/Resources/plugins/FlyWithLua/Scripts/
  2. In the sim: Plugins > Forest Tweak > Show / hide window
     (fallback: Plugins > FlyWithLua > FlyWithLua Macros > Forest Tweak: window)
     or bind keys: search "ForestDensity" in the keyboard settings
     (window / toggle / dense / original).

Pick a step and press Apply. The new density applies to scenery that loads
as you fly on. With "Reload scenery on apply" ticked, X-Plane loads all
scenery around you again so it shows at once - that takes a while, because
trees are placed while scenery loads. The window also shows the tree height
set by the tweak. Window position and settings are remembered.


PERFORMANCE
-----------
More trees = more GPU load, especially low over large forests. Check your FPS
and go to 0.8 if needed.


Use at your own risk. Not affiliated with Laminar Research, simHeaven or
GeoReality.

FREE COMMUNITY PROJECT - NOT FOR SALE
-------------------------------------
Free to use for everyone, including companies and flight schools.
Not allowed: selling or renting it, bundling it with paid products or
services, charging for downloads, or distributing modified versions
commercially. Changed versions may be shared non-commercially under the
same license, with credit to the author.
License: (c) E11i0t09 - CC BY-NC-SA 4.0 + additional permission,
see LICENSE.txt. https://creativecommons.org/licenses/by-nc-sa/4.0/
