XP12 Forest Tweak  v1.6.1  (Windows)
====================================

Denser forests, optionally smaller trees (3D trees included) and real-looking
hedges for X-Plane 12, also with simHeaven X-World and X-WORLD Pro.
The vegetation slider can never exceed the tree density defined in the forest
files (.for) - this tool changes those files directly. Tree spacing 0.7 =
roughly twice as many trees per area. Windows, macOS and Linux.

Tested with X-Plane 12.4.x.

THIS IS NOT A PLUGIN. It is a small tool you run once, outside X-Plane.
Do not copy it into Resources/plugins. No renaming needed.


WHAT'S IN THE ZIP
-----------------
  Start_ForestTweak.bat          -> double-click: the window (no admin rights needed)
  Start_ForestTweak_Console.bat  -> the same tool with the keyboard menu
  XP12_ForestTweak_Gui.ps1       -> the window
  XP12_ForestTweak.ps1           -> the tool (PowerShell, ships with Windows 10/11)
  forest.ico                     -> icon of the window
  FlyWithLua/ForestDensityToggle.lua  (optional in-sim window, see below)

Prefer an installation? XP12_ForestTweak_v1.6.1_Setup.exe (same release page)
installs for your user without admin rights, with a shortcut in your X-Plane
12 folder and an uninstall that restores the original forests first.

One tool for vanilla X-Plane, simHeaven X-World and Global Forests v2: if
Global Forests v2 is installed, the Settings page has a tick box to include it
(the console asks).
Coming from 1.3 or older: just use the new tool, it reads the same backup log.
You can delete the old Start_Vanilla-simHeaven.bat, Start_GlobalForestsV2.bat
and their .ps1 files.

HOW TO USE
----------
Installed with the setup? Then start it with the shortcut "Forest Tweak" in
your X-Plane 12 folder (or the Start menu entry, if chosen) and skip steps 2
and 3. Uninstall: Windows Settings > Apps > XP12 Forest Tweak.

1. Quit X-Plane (the tool changes nothing while X-Plane is running).
2. Unzip anywhere (or into your X-Plane 12 folder - then it is found
   automatically). Otherwise the tool finds X-Plane via x-plane_install_12.txt
   or asks for the path.
3. Double-click Start_ForestTweak.bat (or the shortcut "Forest Tweak" of the
   setup). The first start of the ZIP version shows the license.
   "Windows protected your PC" for the setup: More info > Run anyway (the
   setup is not code-signed, that costs money every year).
4. The window (Windows):
   Recommended       Dense, Smaller and (with simHeaven) + Hedgebanks in one
                     click; shows what is active in X-Plane now
   Settings          all choices on one page, with a live preview of what
                     will change (files, hedge tiles, time, disk space)
   Status            what is tweaked, simHeaven packs found, tool.log
   Check & repair    checks the backups, finishes/updates the hedge tiles
   Quick switch      tweak <-> original in a few seconds
   Restore original  puts back the original forests and hedges
   Log / help        everything the tool wrote, README, console version
   Apply always shows the summary first. While X-Plane runs, Apply is locked.
   Updates: at start the window asks GitHub for a newer version. "Update now"
   downloads it, checks its SHA-256 against the checksum GitHub publishes and
   installs it; afterwards it offers to apply your settings again.

  The choices (the same in the console menu, Start_ForestTweak_Console.bat):
  Step 1  Tree spacing. Lower spacing = closer trees = denser forest.
            [1] Natural     0.8   noticeably denser (about 1.6x trees)
            [2] Dense       0.7   about 2x trees, recommended
            [3] Very dense  0.6   about 2.8x trees, needs a strong GPU
            [4] Custom      your own value from 0.4 to 1.0 (1.0 = original)
          Values can be typed as 0.7, 0,7 or 70.
          Global Forests v2 cropland forests (field trees, hedgerows) get an
          extra factor 0.8, e.g. 0.7 -> 0.56, so field edges fill more evenly.
          Sparse Global Forests v2 areas get extra trees, dense areas stay.
  Step 2  Tree height: Original 1.0, Slightly smaller 0.8, Smaller 0.7,
          Much smaller 0.6 or your own value from 0.5 to 1.0.
          Realistic profile: conifers shrink less (0.8 -> 0.88), palms 0.84,
          shrubs/orchards 0.9, broadleaf 0.8.
          The 3D tree models are scaled too. This rewrites the files
          and keeps a compressed backup of the originals (with checksum) in
          ForestDensityTweak/mesh_backup (about 1.5 GB with GFv2).
  Step 3  Hedges (only with simHeaven X-World or X-WORLD Pro, see below):
            [1] Original  [2] Green hedges  [3] + Hedgebanks (Knicks)
          With X-WORLD Pro and [2] or [3]: choose the countries (all
          countries with Pro tiles are preselected).
  Step 4  Forests from (only with simHeaven and Global Forests v2, see
          FORESTS FROM SIMHEAVEN OR GLOBAL FORESTS V2 below).
  To change values later, just run Choose settings again.
  The summary shows an estimated time. With tree height and Global Forests
  v2 it can take 10 minutes or more.

Run it once. Run it again only after an X-Plane or Global Forests update.
Grass, shrubs and hedges (spacing <= 3.1 m) are not changed.
In natural forests the trees are spread more randomly, so dense forests show
no lines from the planting grid.
At start the tool shows a short status line and warns if the vegetation
slider is not at maximum, if Global Forests v2 is disabled or not tweaked,
or if a newer version is available (it only asks GitHub, nothing is sent).


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


FORESTS FROM SIMHEAVEN OR GLOBAL FORESTS V2
-------------------------------------------
X-Plane removes the forests of all packs below an exclusion in
scenery_packs.ini. Read from the DSF files of the packs:
- Global Forests v2 cuts away the forests below it for the whole 1x1 degree
  tile, everywhere.
- simHeaven Europe (X-WORLD Pro Europe-10-forests, free X-World Europe) does
  the same for the whole tile.
- simHeaven X-WORLD Pro Africa, America, Asia, Antarctica cut away only their
  own forest areas.
So with simHeaven above Global Forests v2: in Europe only simHeaven forests,
on the other continents simHeaven forests plus Global Forests v2 in the rest
of the tile. With Global Forests v2 above: only Global Forests v2.
  simHeaven          forests from OpenStreetMap: exact outlines, also parks,
                     gardens, cemeteries, vineyards; in Europe gaps where
                     nothing is mapped
  Global Forests v2  forests from satellite data, also in remote areas
If both are installed and Global Forests v2 is included, step 4 of Choose
settings (Windows: "Forests from" on the Settings page) lets you choose per
continent. For Global Forests v2 the tool switches the simHeaven forest pack
of that continent off in scenery_packs.ini (backup kept); Restore original
switches it on again.
Global Forests v2 listed with a full path outside Custom Scenery (e.g. Orbx
Central) is found and shown in Status, but not tweaked and not moved.
The hedge packs (06-extras1, 07-extras2) are not affected. The tool reads the
X-WORLD Pro hedges from them even when they are switched off in X-Plane.


HEDGES AND HEDGEBANKS (OPTIONAL, WITH SIMHEAVEN)
------------------------------------------------
The tool finds out which simHeaven add-ons are installed (free X-World,
X-WORLD Pro). The hedge choice gives the same look with both:
  [1] Original      as simHeaven made them
  [2] Green hedges  about 4 - 5 m, visible up to 8 km.
                    Free X-World: worldwide. X-WORLD Pro (flat walls): rebuilt
                    as green hedges in the countries you choose (Germany,
                    Denmark, Benelux, Austria, Switzerland or all Pro tiles).
  [3] + Hedgebanks  green hedges, plus the Knick look in the Knick areas
                    (Schleswig-Holstein, Hamburg, NW Lower Saxony,
                    W Mecklenburg, Denmark): mixed bushes with single tall
                    hedgerow trees (Ueberhaelter), mixed tree rows, denser
                    scrub. Only the bushes and trees are drawn, not the
                    earth bank itself.
All new hedges change with the four seasons.
Official hedge maps (folder data/, see data/DATA_LICENSES.txt) add the hedges
that OpenStreetMap does not have: Schleswig-Holstein, Lower Saxony/Bremen/
Hamburg, North Rhine-Westphalia, Bavaria, Brandenburg, Denmark (earth banks,
diger). Where a map has a hedge it replaces the simHeaven one, the others are
taken over.
The tool builds the hedges on your computer into
Custom Scenery/XP12_ForestTweak_HedgerowMap (up to about 250 MB) and the hedge
types into Custom Scenery/XP12_ForestTweak_Knicks, both listed above
simHeaven in scenery_packs.ini (backup kept). Free X-World: [2] and [3] also
change the hedge files of its Vegetation Library (originals logged in
ForestDensityTweak/hedges.log). Nothing of simHeaven is shipped.
Free X-World and X-WORLD Pro both on for one region: the tool offers to turn
the free packs off. After a simHeaven update run Check & repair.
Restore original removes everything again.


BACKUP / UNDO / CHECK & REPAIR
------------------------------
Original values are logged in  <X-Plane 12>/ForestDensityTweak/backup.log
"Restore original" writes them back exactly (forests and hedges).
Quick switch ([5] in the console) switches between tweak and original in a
few seconds: both versions are
kept next to the files (.fdt_tweak / .fdt_orig, the first switch needs about as
much disk space as the tweaked files). Do not
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
steps during flight (1.0x to 2.8x as many trees as original, up to the tool
setting). Needs FlyWithLua NG+ and the tweak applied.

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
The chosen step is remembered and set again at the next sim start
(without reload, so it applies to scenery loaded from then on).


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
Hedge maps (data/hedgerow_map_*.dat) are NOT under the tool license: each
keeps the license of its source (CC BY 4.0, dl-de/by-2-0 or CC0 1.0).
Sources, links and changes: data/DATA_LICENSES.txt.
  SH:  LLUR SH, Biotopkartierung SH4 (2023), CC BY 4.0
  NI:  (c) ML/SLA Niedersachsen/CC BY 4.0 - Landschaftselemente NI/HB/HH
  NRW: Land NRW - Landschaftselemente in NRW (2026-11-07), dl-de/by-2-0
  BY:  Bayerisches Staatsministerium fuer Ernaehrung, Landwirtschaft, Forsten
       und Tourismus - InVeKoS Landschaftselemente, CC BY 4.0
  BB:  (c) Ministerium fuer Land- und Ernaehrungswirtschaft, Umwelt und
       Verbraucherschutz - InVeKoS Landschaftselemente BB (2026-11-07),
       dl-de/by-2-0
  DK:  Slots- og Kulturstyrelsen - Beskyttede sten- og jorddiger, CC0 1.0
License: (c) E11i0t09 - CC BY-NC-SA 4.0 + additional permission,
see LICENSE.txt. https://creativecommons.org/licenses/by-nc-sa/4.0/
