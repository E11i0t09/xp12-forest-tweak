XP12 Forest Tweak  v1.5.2
=========================

Denser forests, optionally smaller trees (3D trees included) and real-looking
hedges for X-Plane 12, also with simHeaven X-World and X-WORLD Pro.
The vegetation slider can never exceed the tree density defined in the forest
files (.for) - this tool changes those files directly. Tree spacing 0.7 =
roughly twice as many trees per area. Windows, macOS and Linux.

Tested with X-Plane 12.4.x.

THIS IS NOT A PLUGIN. It is a small tool you run once, outside X-Plane.
Do not copy it into Resources/plugins. No renaming needed.


DOWNLOADS / FOLDERS
-------------------
Download the ZIP for your system - each one contains everything you need:
  XP12_ForestTweak_v1.5.2_Windows.zip  (folder Windows/ in the repository)
      Start_ForestTweak.bat            (double-click), no admin rights needed
  XP12_ForestTweak_v1.5.2_macOS.zip    (folder macOS/)
      Start_ForestTweak_macOS.command  (double-click), needs Python 3.8+
  XP12_ForestTweak_v1.5.2_Linux.zip    (folder Linux/)
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
4. Menu: [0] Recommended setup  [1] Choose settings  [2] Restore original
   [3] Status  [4] Check & repair
   [5] Switch to original / back to tweak (a few seconds, nothing calculated again)

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
          Sparse Global Forests v2 areas get extra trees, dense areas stay.
  Step 2  Tree height: Original 1.0, Slightly smaller 0.8, Smaller 0.7,
          Much smaller 0.6 or your own value from 0.5 to 1.0.
          Realistic profile: conifers shrink less (0.8 -> 0.88), palms 0.84,
          shrubs/orchards 0.9, broadleaf 0.8.
          The 3D tree models are scaled too. This rewrites the files
          and keeps a compressed backup of the originals (with checksum) in
          ForestDensityTweak/mesh_backup (about 1.5 GB with GFv2).
  Step 3  Hedges (only with simHeaven X-World or X-WORLD Pro, see below):
            [1] Original  [2] Enhanced  [3] Hedgebanks (Knicks)
          With X-WORLD Pro and [2] or [3]: choose the countries.
  To change values later, just run Choose settings again.
  The summary shows an estimated time. With tree height and Global Forests
  v2 it can take 10 minutes or more.

Run it once. Run it again only after an X-Plane or Global Forests update.
Grass, shrubs and hedges (spacing <= 3.1 m) are not changed.
In natural forests the trees are spread more randomly, so dense forests show
no lines from the planting grid.
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


HEDGES AND HEDGEBANKS (OPTIONAL, WITH SIMHEAVEN)
------------------------------------------------
The tool finds out which simHeaven add-ons are installed (free X-World,
X-WORLD Pro). Step 3 of Choose settings gives the same look with both:
  [1] Original    as simHeaven made them
  [2] Enhanced    green hedges about 4 - 5 m, visible up to 8 km.
                  Free X-World: worldwide. X-WORLD Pro (flat walls): rebuilt
                  as green hedges in the countries you choose (Germany,
                  Denmark, Benelux, Austria, Switzerland or all Pro tiles).
  [3] Hedgebanks  (Knicks) in the Knick areas (Schleswig-Holstein, Hamburg,
                  NW Lower Saxony, W Mecklenburg, Denmark): bushes on earth
                  banks with single hedgerow trees (Ueberhaelter), mixed tree
                  rows, denser scrub. Elsewhere as [2].
All new hedges change with the four seasons.
Official hedge maps (folder data/, see data/DATA_LICENSES.txt) add the hedges
that OpenStreetMap does not have: Schleswig-Holstein, Lower Saxony/Bremen/
Hamburg, North Rhine-Westphalia, Bavaria, Brandenburg, Denmark (earth banks,
diger). Where a map has a hedge it replaces the simHeaven one, the others are
taken over.
The tool builds the hedges on your computer into
Custom Scenery/XP12_ForestTweak_HedgerowMap (up to about 250 MB) and the hedge
types into Custom Scenery/XP12_ForestTweak_Knicks, both listed above
simHeaven in scenery_packs.ini (backup kept). Free X-World: Enhanced also
changes the hedge files of its Vegetation Library (originals logged in
ForestDensityTweak/hedges.log). Nothing of simHeaven is shipped.
Free X-World and X-WORLD Pro both on for one region: the tool offers to turn
the free packs off. After a simHeaven update run Check & repair.
Restore original removes everything again.


BACKUP / UNDO / CHECK & REPAIR
------------------------------
Original values are logged in  <X-Plane 12>/ForestDensityTweak/backup.log
"Restore original" writes them back exactly (forests and hedges).
[5] switches between tweak and original in a few seconds: both versions are
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
see LICENSE. https://creativecommons.org/licenses/by-nc-sa/4.0/
