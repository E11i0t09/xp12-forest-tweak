XP12 Forest Tweak  v1.4.0
=========================

Denser forests and optionally smaller trees (3D trees included) for X-Plane 12.
The vegetation slider can never exceed the tree density defined in the forest
files (.for) - this tool changes those files directly. Tree spacing 0.7 =
roughly twice as many trees per area. Windows, macOS and Linux.

Tested with X-Plane 12.4.x.

THIS IS NOT A PLUGIN. It is a small tool you run once, outside X-Plane.
Do not copy it into Resources/plugins. No renaming needed.


DOWNLOADS / FOLDERS
-------------------
Download the ZIP for your system - each one contains everything you need:
  XP12_ForestTweak_v1.4.0_Windows.zip  (folder Windows/ in the repository)
      Start_ForestTweak.bat            (double-click), no admin rights needed
  XP12_ForestTweak_v1.4.0_macOS.zip    (folder macOS/)
      Start_ForestTweak_macOS.command  (double-click), needs Python 3.8+
  XP12_ForestTweak_v1.4.0_Linux.zip    (folder Linux/)
      start_forest_tweak_linux.sh      (sh start_forest_tweak_linux.sh), Python 3.8+
  FlyWithLua/ForestDensityToggle.lua (optional in-sim window, in every ZIP)

One tool per system for all setups: if Global Forests v2 is installed, it
asks whether to include it. All versions share one backup log, nothing is
ever scaled twice.

HOW TO USE
----------
1. Quit X-Plane (the tool changes nothing while X-Plane is running).
2. Unzip anywhere (or into your X-Plane 12 folder - then it is found
   automatically). Otherwise the tool finds X-Plane via x-plane_install_12.txt
   or asks for the path.
3. Start the tool for your system (see above).
4. Menu: [1] Choose settings  [2] Restore original  [3] Status  [4] Check & repair

  Choose settings asks step by step - nothing is changed until you confirm
  the summary at the end:
  Step 1  Tree spacing. Lower spacing = closer trees = denser forest.
            [1] Natural     0.8   noticeably denser (about 1.6x trees)
            [2] Dense       0.7   about 2x trees, recommended
            [3] Very dense  0.6   about 2.8x trees, needs a strong GPU
            [4] Custom      your own value from 0.4 to 1.0 (1.0 = original)
          Values can be typed as 0.7, 0,7 or 70.
          Global Forests v2 cropland forests (field trees, hedgerows) get an
          extra factor 0.8, e.g. 0.7 -> 0.56, so field edges fill more evenly.
  Step 2  Tree height 0.5 - 1.0 (1.0 = original, 0.8 = 20 % smaller).
          The 3D tree models are scaled too. This rewrites the files
          and keeps a compressed backup of the originals (with checksum) in
          ForestDensityTweak/mesh_backup (about 1.5 GB with GFv2).
  Step 3  Height profile (only below 1.0):
            uniform    every tree gets the same factor
            realistic  conifers shrink less (0.8 -> 0.88), palms 0.84,
                       shrubs/orchards 0.9, broadleaf 0.8
  Step 4  simHeaven hedges default or enhanced (only with simHeaven X-World).
  To change values later, just run Choose settings again.
  The summary shows an estimated time. With tree height and Global Forests
  v2 it can take 10 minutes or more.

Run it once. Run it again only after an X-Plane or Global Forests update.
Grass, shrubs and hedges (spacing <= 3.1 m) are not changed.
At start the tool shows a short status line and warns if the vegetation
slider is not at maximum, if Global Forests v2 is disabled or not tweaked,
or if a newer version is available (it only asks GitHub, max. 3 s).


I DON'T SEE A DIFFERENCE
------------------------
The tool raises the maximum density in the forest files. What you see is
still limited by
- the vegetation slider in X-Plane (Settings > Graphics): set it to maximum,
- the forest data of the scenery: trees only grow where the scenery has
  forest areas - where there are none, no trees are added,
- other scenery with its own forests (e.g. Orbx TrueEarth): Status lists it,
- Global Forests v2 not included or disabled in scenery_packs.ini,
- an X-Plane or GFv2 update: run Choose settings again.


SIMHEAVEN HEDGES / KNICKS (OPTIONAL)
------------------------------------
Step 4 of Choose settings switches the hedges of simHeaven X-World (e.g. the
Knicks in northern Germany) between
  default   2.2 - 2.8 m high, visible up to 4 km
  enhanced  about 4 - 5 m high, visible up to 8 km
Only the hedge files of the simHeaven X-World Vegetation Library are changed.
Originals are logged in ForestDensityTweak/hedges.log and restored exactly.
After a simHeaven update, run Choose settings again and confirm.


BACKUP / UNDO / CHECK & REPAIR
------------------------------
Original values are logged in  <X-Plane 12>/ForestDensityTweak/backup.log
"Restore original" writes them back exactly (forests and hedges). Do not
delete this folder while the tweak is active.
"Check & repair" checks the 3D model backups (checksum), removes leftovers of
an interrupted run, unused backups and empty folders, and cleans up the log.
If a backup is damaged, that file stays tweaked (never scaled twice): run the
X-Plane installer ("Update") or reinstall Global Forests v2, then Check &
repair again.
ForestDensityTweak/tool.log lists what the tool did - please attach it to
bug reports.


IN-SIM WINDOW (OPTIONAL)
------------------------
ForestDensityToggle.lua adds a small window to switch the forest density in
4 steps during flight. Needs FlyWithLua NG+ and the tweak applied.

  1. Copy FlyWithLua/ForestDensityToggle.lua to
     X-Plane 12/Resources/plugins/FlyWithLua/Scripts/
  2. In the sim: Plugins > Forest Tweak > Show / hide window
     (fallback: Plugins > FlyWithLua > FlyWithLua Macros > Forest Tweak: window)
     or bind keys: search "ForestDensity" in the keyboard settings
     (window / toggle / dense / original).

Pick a step and press Apply. The new density applies to scenery that loads
as you fly on. With "Reload scenery on apply" ticked, X-Plane loads all
scenery around you again so it shows at once - that takes a while. The window
also shows the tree height, height profile and hedge setting of the tweak.


PERFORMANCE
-----------
More trees = more GPU load, especially low over large forests. Check your FPS
and choose Natural (0.8) if needed.


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
see LICENSE. https://creativecommons.org/licenses/by-nc-sa/4.0/
