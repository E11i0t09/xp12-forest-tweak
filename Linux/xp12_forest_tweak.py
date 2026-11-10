#!/usr/bin/env python3
"""
XP12 Forest Tweak - macOS / Linux version
Version 1.5.2

Denser forests and optionally smaller trees for X-Plane 12.
Same logic and same backup log as the Windows (PowerShell) version, so a tweak made
on one system can be restored on the other (e.g. dual boot with a shared X-Plane folder).

What it does
- Tree spacing: SPACING and RANDOM in the forest files (.for) are multiplied by a factor
  (0.7 = about twice as many trees per area). The vegetation slider in X-Plane can never
  go above the density set there.
- RANDOM (how far a tree may move away from its grid position) is set to at least half the
  tree spacing in natural forests, so dense forests show no lines from the planting grid.
  Planted rows (orchards etc.) keep their grid.
- Global Forests v2 "cropland" forests (field trees and hedgerows between fields) get an
  extra factor of 0.8 on top, so field edges are filled more evenly. Sparse Global Forests v2
  forests (density classes 25 and 50) get an extra 0.75 / 0.85, so they look less empty.
- Files with SPACING <= 3.1 m (grass, shrubs, hedges) are left untouched.
- Optional tree height factor (0.5 - 1.0): min and max height of every tree are scaled.
  "realistic" profile: conifers shrink less, palms a bit less, shrubs/orchards hardly.
  TREE2 3D trees scale by themselves (nominal height is kept); the 3D models of TREE
  trees are drawn at their modelled size, so their vertices are scaled too. Before that,
  a compressed copy (with SHA-256 checksum) of the original file is stored in
  <X-Plane>/ForestDensityTweak/mesh_backup for an exact restore.
- Every original line is logged in <X-Plane>/ForestDensityTweak/backup.log, so
  "Restore original" puts back the exact original values.
- Optional, with simHeaven X-World (free) or X-WORLD Pro: hedges "original", "enhanced"
  (green hedges about 4-5 m high, all four seasons) or "hedgebanks (Knicks)" (in northern
  Germany and Denmark bushes on earth banks with single hedgerow trees, elsewhere enhanced).
  Free X-World: the hedge files of its Vegetation Library are changed (originals logged in
  ForestDensityTweak/hedges.log). X-WORLD Pro draws hedges as walls, which can not be changed
  through a library, so the tool rebuilds them as hedges in the countries you choose.
  Official hedge maps (Schleswig-Holstein, Niedersachsen/Bremen/Hamburg, Nordrhein-Westfalen,
  Bayern, Brandenburg, Denmark; see DATA_LICENSES.txt) add the hedges that OpenStreetMap does
  not have. Both are built on this computer into Custom Scenery/XP12_ForestTweak_HedgerowMap.
  The tool library Custom Scenery/XP12_ForestTweak_Knicks (textures copied from the X-Plane
  default forests) defines the hedge types. Both folders are listed in scenery_packs.ini
  (backup kept). simHeaven files are only read; nothing of simHeaven is shipped.
- Actions are written to <X-Plane>/ForestDensityTweak/tool.log (helpful for bug reports).

Needs only Python 3.8 or newer, no extra packages.
Use at your own risk.
(c) E11i0t09. Free community project, not for sale. License: CC BY-NC-SA 4.0 with additional permission (free use also for companies and flight schools), see the LICENSE file.
"""

import gzip
import hashlib
import json
import math
import multiprocessing
import webbrowser
import os
import re
import shutil
import signal
import struct
from array import array
import subprocess
import sys
import threading
import time
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP

VERSION = "1.5.2"
TESTED_XP = (12, 4)      # X-Plane version the tool was tested with
REPO = "E11i0t09/xp12-forest-tweak"
THRESHOLD = 3.1          # files with a smaller tree spacing are grass/shrubs/hedges -> kept
PRESETS = [("Natural", 0.8, "noticeably denser"),
           ("Dense", 0.7, "about 2x trees, recommended"),
           ("Very dense", 0.6, "about 2.8x trees, needs a strong GPU")]
DEFAULT_FAC = 0.7        # preset [2]
MIN_FAC = 0.4
MIN_HEIGHT = 0.5         # lowest allowed height factor
DEFAULT_HEIGHT = 0.7     # preset [3]
HEIGHT_PRESETS = [("Original", 1.0, "trees as in X-Plane"), ("Slightly smaller", 0.8, "20 % smaller"),
                  ("Smaller", 0.7, "30 % smaller"), ("Much smaller", 0.6, "40 % smaller")]
CROP_FAC = 0.8           # extra spacing factor for Global Forests v2 cropland forests
RANDOM_TARGET = 0.5      # RANDOM at least half the tree spacing (no empty strips between grid rows)
RANDOM_MIN_RATIO = 0.25  # below this ratio the forest is a planted row grid on purpose (orchards etc.)
SPARSE_FAC = {"25": 0.75, "50": 0.85}   # extra spacing factor for sparse Global Forests v2 density classes
SPARSE_RX = re.compile(r"_(25|50)_y\d+\.for$")
TWEAK_DIR = "ForestDensityTweak"   # folder name kept from earlier versions (shared with Windows)
HEDGE_FAC = 1.8          # simHeaven hedges "enhanced": 2.2-2.8 m -> about 4-5 m (typical Knick height)
HEDGE_LOD = 8000         # simHeaven hedges "enhanced": visible up to 8 km instead of 4 km
HEDGE_VPATH = "simheaven/forests/hedge.for"
DISK_MARGIN = 200 * 2**20  # always keep this much free space
MESH_WEIGHT = 6          # a file whose 3D models are scaled takes about 6x longer than one with only new header lines
RATE = 45 * 2**20        # rough work units per second and CPU core (for the time estimate only)
RATE_RESTORE = 40 * 2**20  # bytes per second when restoring

# Same patterns as the PowerShell version. Files are handled as Latin-1 text, which maps
# every byte 1:1 to one character, so unchanged parts stay byte-identical.
LINE_RX = re.compile(r"(?m)^([ \t]*)(SPACING|RANDOM)([ \t]+)([0-9]*\.?[0-9]+)([ \t]+)([0-9]*\.?[0-9]+)")
HEADER_END = re.compile(r"(?m)^[ \t]*(TREE|TREE2|MESH|MESH_3D|GROUP)\b")
# TREE  <s> <t> <w> <h> <offset> <frequency> <min h> <max h> ...
# TREE2 <s1> <t1> <w> <h> <sw> <percent> <min_height> <max_height> <nominal_height> ...
TREE_RX = re.compile(r"(?m)^([ \t]*TREE2?)((?:[ \t]+\S+){6})([ \t]+)([0-9]*\.?[0-9]+)([ \t]+)([0-9]*\.?[0-9]+)(?=[ \t\r\n]|$)")
MESH_DATA_RX = re.compile(r"(?m)^[ \t]*(VERTEX|IDX\d*)\b[^\n]*\n?")
VERTEX_RX = re.compile(rb"^([ \t]*VERTEX)([ \t]+)(\S+)([ \t]+)(\S+)([ \t]+)(\S+)")
MESH_RX = re.compile(rb"^[ \t]*MESH[ \t]+(\S+)")
LOD_RX = re.compile(r"(?m)^([ \t]*LOD[ \t]+)([0-9]*\.?[0-9]+)")
# realistic height profile: weight of the height reduction per forest type (first match wins)
#   1.0 = full factor, 0.6 = only 60 % of the reduction (0.8 -> 0.88)
SHRUB_RX = re.compile(r"shrub|_shr_|cact|orch|fruit|agave|yucca")
OTHER_FOREST_RX = re.compile(r"(?i)true[ _-]?earth|forest|trees|vegetation")

IS_MAC = sys.platform == "darwin"
C_CYAN, C_GREEN, C_YELLOW, C_RED, C_OFF = ("\033[36m", "\033[32m", "\033[33m", "\033[31m", "\033[0m") \
    if sys.stdout.isatty() else ("", "", "", "", "")
TOOL_LOG = None


def say(text="", color=""):
    print(f"{color}{text}{C_OFF if color else ''}")


def warn(text):
    say(text, C_YELLOW)


def tlog(msg):
    """One line in ForestDensityTweak/tool.log (kept below about 1 MB)."""
    if not TOOL_LOG:
        return
    try:
        if os.path.exists(TOOL_LOG) and os.path.getsize(TOOL_LOG) > 2**20:
            with open(TOOL_LOG, encoding="utf-8", errors="replace") as f:
                keep = f.readlines()[-2000:]
            with open(TOOL_LOG, "w", encoding="utf-8", newline="\n") as f:
                f.writelines(keep)
        with open(TOOL_LOG, "a", encoding="utf-8", newline="\n") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S") + "  " + msg + "\n")
    except OSError:
        pass


def _dec(v):
    return Decimal("%.15g" % v)


def fmt(v, decimals=3):
    """Like .NET '0.###': up to n decimals, half away from zero, no trailing zeros."""
    s = format(_dec(v).quantize(Decimal(1).scaleb(-decimals), rounding=ROUND_HALF_UP), "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def fmt_vertex(v):
    """Like .NET '0.#######' (same rounding as the Windows version, so results are byte-identical)."""
    return fmt(v, 7)


def rnd(v, decimals):
    """Round half away from zero (same as [Math]::Round(v, n, AwayFromZero) in the Windows version)."""
    return float(_dec(v).quantize(Decimal(1).scaleb(-decimals), rounding=ROUND_HALF_UP))


def trees_x(f):
    return 1.0 / (f * f)


# ---------------------------------------------------------------- input
def parse_value(a, minimum):
    """Tolerant number input: '0.7', '0,7', '.7', '70', '70 %' -> 0.7. None if not valid."""
    s = a.strip().replace(",", ".").rstrip("%").strip()
    try:
        v = float(s)
    except ValueError:
        return None
    if 1.0 < v <= 100.0:
        v /= 100.0
    v = rnd(v, 3)
    return v if minimum <= v <= 1.0 else None


def ask_value(minimum, current, what):
    while True:
        a = input(f"  Type a value from {fmt(minimum)} to 1.0, or press Enter for {fmt(current)}: ").strip()
        if a == "":
            return current
        v = parse_value(a, minimum)
        if v is not None:
            return v
        warn(f"  '{a}' is not a valid {what}. Example: 0.7")


def ask_yes(prompt, default=True):
    a = input(prompt).strip()
    if a == "":
        return default
    return a[:1] in "yYjJ"


# ---------------------------------------------------------------- X-Plane path
def is_xplane(p):
    return bool(p) and os.path.isdir(os.path.join(p, "Resources", "default scenery")) \
        and os.path.isdir(os.path.join(p, "Custom Scenery"))


def install_txt():
    if IS_MAC:
        return os.path.expanduser("~/Library/Preferences/x-plane_install_12.txt")
    return os.path.expanduser("~/.x-plane/x-plane_install_12.txt")


def find_xplane():
    # optional: path given on the command line, e.g.  python3 xp12_forest_tweak.py "/path/to/X-Plane 12"
    if len(sys.argv) > 1:
        p = os.path.expanduser(sys.argv[1].rstrip("/"))
        if is_xplane(p):
            return p
        raise RuntimeError(f"No X-Plane 12 folder at '{p}'.")
    here = os.path.dirname(os.path.abspath(__file__))
    # the tool folder itself, or up to two levels above it (e.g. X-Plane 12/XP12_ForestTweak/macOS)
    p = here
    for _ in range(3):
        if is_xplane(p):
            return p
        p = os.path.dirname(p)
    cands = []
    try:
        with open(install_txt(), encoding="utf-8", errors="replace") as f:
            for line in f:
                p = line.strip().rstrip("/")
                if is_xplane(p) and p not in cands:
                    cands.append(p)
    except OSError:
        pass
    if len(cands) == 1:
        if ask_yes(f"  X-Plane 12 found at '{cands[0]}'. Use it? [Y/n] "):
            return cands[0]
    elif len(cands) > 1:
        say("  Several X-Plane 12 installations found:")
        for i, c in enumerate(cands, 1):
            say(f"    [{i}] {c}")
        a = input("  Number (or Enter to type a path): ").strip()
        if a.isdigit() and 1 <= int(a) <= len(cands):
            return cands[int(a) - 1]
    while True:
        p = input("  Path to your X-Plane 12 folder (drag the folder in here): ").strip().strip("'\"").rstrip("/")
        p = os.path.expanduser(p.replace("\\ ", " "))
        if is_xplane(p):
            return p
        warn("  -> 'Resources/default scenery' / 'Custom Scenery' not found there.")


def find_gfv2(xp):
    cs = os.path.join(xp, "Custom Scenery")
    out = []
    for name in sorted(os.listdir(cs)):
        full = os.path.join(cs, name)
        if os.path.isdir(full) and re.match(r"(?i)^Global[ _-]?Forests", name) and re.search(r"(?i)v2", name):
            out.append(full)
    return out


def get_targets(xp):
    default = os.path.join(xp, "Resources", "default scenery", "1200 forests")
    if not os.path.isdir(default):
        raise RuntimeError(f"Default forest folder not found: {default}")
    targets = [default]
    gf = find_gfv2(xp)
    if gf and ask_yes("  Global Forests v2 found. Tweak it too? [Y/n] "):
        targets += gf
    return targets, gf


# ---------------------------------------------------------------- environment checks (display only)
def xplane_running():
    for name in ("X-Plane", "X-Plane-x86_64"):
        try:
            if subprocess.run(["pgrep", "-x", name], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0:
                return True
        except OSError:
            return False
    return False


def blocked_by_xplane():
    if xplane_running():
        warn("  X-Plane is running. Please quit X-Plane first - forest files can't be changed while it runs.")
        return True
    return False


def xplane_version(xp):
    try:
        with open(os.path.join(xp, "Log.txt"), encoding="latin-1") as f:
            m = re.search(r"X-Plane (\d+)\.(\d+)\.(\d+)(\S*)", f.readline())
        if m:
            return (int(m.group(1)), int(m.group(2))), f"{m.group(1)}.{m.group(2)}.{m.group(3)}{m.group(4)}"
    except OSError:
        pass
    return None, None


def vegetation_slider(xp):
    """Vegetation density slider from X-Plane.prf (0-4, 4 = maximum) or None."""
    try:
        with open(os.path.join(xp, "Output", "preferences", "X-Plane.prf"), encoding="latin-1") as f:
            for line in f:
                tok = line.split()
                if len(tok) >= 2 and tok[0] == "renopt_vegetation_quality_04":
                    return int(float(tok[1]))
    except (OSError, ValueError):
        pass
    return None


def pack_states(xp):
    """scenery_packs.ini: folder name (lower case) -> True (enabled) / False (disabled)."""
    out = {}
    try:
        with open(os.path.join(xp, "Custom Scenery", "scenery_packs.ini"), encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.match(r"\s*(SCENERY_PACK(?:_DISABLED)?)\s+(.+?)\s*$", line)
                if m:
                    name = m.group(2).replace("\\", "/").rstrip("/").split("/")[-1].lower()
                    out[name] = m.group(1) == "SCENERY_PACK"
    except OSError:
        pass
    return out


def other_forest_addons(xp):
    """Custom Scenery folders that probably bring their own forests (not changed by this tool)."""
    packs = pack_states(xp)
    out = []
    for name in sorted(os.listdir(os.path.join(xp, "Custom Scenery"))):
        low = name.lower()
        if not os.path.isdir(os.path.join(xp, "Custom Scenery", name)) or low.startswith(("simheaven", "global_forests", "global forests", "xp12_foresttweak")):
            continue
        if OTHER_FOREST_RX.search(name) and packs.get(low, True):
            out.append(name)
    return out


def start_update_check():
    """Asks GitHub for the latest release in the background (max 3 s, silent if offline)."""
    res = {}

    def run():
        try:
            import urllib.request
            req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases/latest",
                                         headers={"User-Agent": "xp12-forest-tweak", "Accept": "application/vnd.github+json"})
            with urllib.request.urlopen(req, timeout=3) as r:
                res["tag"] = json.loads(r.read().decode("utf-8")).get("tag_name", "")
        except Exception:
            pass
    t = threading.Thread(target=run, daemon=True)
    t.start()
    return t, res


def vtuple(s):
    return tuple(int(x) for x in re.findall(r"\d+", s)[:3])


def environment_hints(xp, targets, gf):
    """Warnings shown at start: vegetation slider, Global Forests v2 enabled/disabled, X-Plane version."""
    v = vegetation_slider(xp)
    if v is not None and v < 4:
        warn("  Note    : the vegetation density slider in X-Plane is not at maximum. It limits what you see;")
        warn("            set it to maximum (Settings > Graphics) to get the full effect.")
    packs = pack_states(xp)
    for g in gf:
        en = packs.get(os.path.basename(g).lower())
        if g in targets and en is False:
            warn(f"  Note    : {os.path.basename(g)} is disabled in scenery_packs.ini - X-Plane doesn't show its forests.")
        if g not in targets and en is not False:
            warn(f"  Note    : {os.path.basename(g)} is active in X-Plane but not tweaked - forests in its areas stay as they are.")
    ver, vs = xplane_version(xp)
    if ver and ver != TESTED_XP:
        warn(f"  Note    : tested with X-Plane {TESTED_XP[0]}.{TESTED_XP[1]}.x, you have {vs}. It should work; if forests look")
        warn("            wrong, use Restore original and please report it.")


# ---------------------------------------------------------------- backup log
def norm(rel):
    return rel.replace("\\", "/")


def tweak_dir(xp):
    d = os.path.join(xp, TWEAK_DIR)
    os.makedirs(d, exist_ok=True)
    return d


def log_path(xp):
    return os.path.join(tweak_dir(xp), "backup.log")


def read_log(path):
    """Last entry per file wins. Keys are normalised to '/' (Windows writes '\\')."""
    h = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8-sig") as f:
            for line in f:
                if line.strip():
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue          # a line cut off by a crash; the file it names is handled as original
                    h[norm(e["f"])] = e
    return h


def write_log(path, entries):
    """Rewrites a log with one line per file (compact), via a temp file."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as lf:
        for e in entries:
            lf.write(json.dumps(e, separators=(",", ":")) + "\n")
        lf.flush()
        os.fsync(lf.fileno())
    os.replace(tmp, path)


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


# ---------------------------------------------------------------- file helpers
class ForFile:
    """A .for file = header + 3D mesh data (VERTEX/IDX) + tree list (TREE/TREE2) at the end.
    Only header and tree list are read and changed; the mesh data in between is copied byte for byte."""

    def __init__(self, path, quick=False):
        with open(path, "rb") as fs:
            fs.seek(0, 2)
            self.length = length = fs.tell()
            fs.seek(0)
            text = fs.read(min(length, 65536)).decode("latin-1")
            m = HEADER_END.search(text)
            self.head_len = m.start() if m else len(text)
            self.head = text[:self.head_len]
            size = 131072
            while True:
                start = max(self.head_len, length - size)
                fs.seek(start)
                chunk = fs.read(length - start).decode("latin-1")
                last = None
                for last in MESH_DATA_RX.finditer(chunk):
                    pass
                if last is not None:
                    self.tail_start = start + last.end()
                    self.tail = chunk[last.end():]
                    break
                if start == self.head_len:
                    self.tail_start = self.head_len
                    self.tail = chunk
                    break
                size *= 4
            self.data = None
            if not quick:
                fs.seek(0)
                self.data = fs.read()
        self.lines = [m.group(0) for m in LINE_RX.finditer(self.head)]
        self.tlines = [m.group(0) for m in TREE_RX.finditer(self.tail)]


def write_bytes(path, out):
    tmp = path + ".fdt_tmp"
    with open(tmp, "wb") as f:
        f.write(out)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)          # atomic swap, never a half-written .for


def disk_ok(xp, need_xp, need_cs):
    """Enough free space (plus 1 GB reserve) for need_xp bytes in the X-Plane folder and need_cs bytes in
    Custom Scenery, which may be a link to another drive. Shows a message and returns False if not."""
    cs = os.path.realpath(os.path.join(xp, "Custom Scenery"))
    try:
        same = os.stat(xp).st_dev == os.stat(cs).st_dev
    except OSError:
        same = True
    checks = [(xp, need_xp + need_cs)] if same else [(xp, need_xp), (cs, need_cs)]
    for path, need in checks:
        if need and free_space(path) < need + 2**30:
            say(f"  Not enough free disk space on {path}: needs about {need / 2**30:.1f} GB plus 1 GB reserve, "
                f"free {free_space(path) / 2**30:.1f} GB.", C_RED)
            return False
    return True


def free_space(path):
    try:
        return shutil.disk_usage(path).free
    except OSError:
        return 1 << 62


def tree_meshes(tail):
    """3D meshes used by TREE lines (drawn at modelled size). TREE2 meshes are scaled by
    X-Plane via their nominal height and stay untouched; a mesh used by both is left alone."""
    t1, t2, kind = set(), set(), None
    for line in tail.split("\n"):
        tok = line.split()
        if not tok:
            continue
        if tok[0] == "TREE":
            kind = t1
        elif tok[0] == "TREE2":
            kind = t2
        elif tok[0] == "MESH_3D" and kind is not None and len(tok) > 1:
            kind.add(tok[1])
    return t1 - t2


def scale_meshes(data, start, end, names, f):
    """Multiply x/y/z of the VERTEX lines of the given meshes, everything else byte for byte."""
    out = []
    active = False
    for line in data[start:end].split(b"\n"):
        m = MESH_RX.match(line)
        if m:
            active = m.group(1).decode("latin-1") in names
            out.append(line)
        elif active:
            v = VERTEX_RX.match(line)
            if v:
                g = v.groups()
                out.append(g[0] + g[1] + fmt_vertex(float(g[2]) * f).encode() + g[3]
                           + fmt_vertex(float(g[4]) * f).encode() + g[5]
                           + fmt_vertex(float(g[6]) * f).encode() + line[v.end():])
            else:
                out.append(line)
        else:
            out.append(line)
    return b"\n".join(out)


def backup_path(xp, rel):
    return os.path.join(xp, TWEAK_DIR, "mesh_backup", *norm(rel).split("/")) + ".gz"


def set_seq(text, rx, values):
    """Replace the n-th regex match in text with values[n]."""
    values = as_list(values)
    parts, pos, i = [], 0, 0
    for m in rx.finditer(text):
        if i >= len(values):
            break
        parts.append(text[pos:m.start()])
        parts.append(values[i])
        pos = m.end()
        i += 1
    parts.append(text[pos:])
    return "".join(parts)


def get_h(e):
    return float(e.get("h", 1.0)) if e else 1.0


def get_hp(e):
    return e.get("hp", "uniform") if e and get_h(e) < 1.0 else "uniform"


def min_spacing(head):
    v = [min(float(m.group(4)), float(m.group(6))) for m in LINE_RX.finditer(head) if m.group(2) == "SPACING"]
    return min(v) if v else 0.0


def state(fo, e):
    if not e:
        return "original"
    trees_ok = ("nt" not in e) or fo.tlines == as_list(e["nt"])
    if fo.lines == as_list(e.get("n")) and trees_ok:
        return "tweaked"
    return "original"          # reset by an update (or changed by the author) -> treat as original


def get_files(targets):
    files = []
    for t in targets:
        for root, _dirs, names in os.walk(t):
            for n in names:
                if n.lower().endswith(".for"):
                    files.append(os.path.join(root, n))
    return sorted(files)


def rel(xp, full):
    return os.path.relpath(full, xp).replace(os.sep, "/")


def sha256_file_gz(path):
    h = hashlib.sha256()
    with gzip.open(path, "rb") as g:
        while True:
            b = g.read(4 * 2**20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def remove_empty_dirs(top):
    if not os.path.isdir(top):
        return 0
    n = 0
    for root, dirs, files in os.walk(top, topdown=False):
        if root != top and not os.listdir(root):
            try:
                os.rmdir(root)
                n += 1
            except OSError:
                pass
    return n


# ---------------------------------------------------------------- effective factors per file
def height_weight(r):
    """Realistic profile: share of the height reduction a forest type gets."""
    r = norm(r).lower()
    base = r.rsplit("/", 1)[-1]
    if SHRUB_RX.search(r):
        return 0.5          # shrubs, cacti, orchards, fruit trees, agave, yucca: small anyway
    if "palm" in r:
        return 0.8
    if "needle" in r or base.startswith("coni"):
        return 0.6          # conifers: often the tallest trees in reality
    return 1.0              # broadleaf, mixed, woodland, cropland, single trees


def effective(r, x, h, hp):
    """(spacing factor, height factor) actually used for one file."""
    rl = norm(r).lower()
    f = 1.0
    if x < 1.0 and "/cropland/" in rl:
        f *= CROP_FAC
    m = SPARSE_RX.search(rl) if x < 1.0 and rl.startswith("custom scenery/") else None
    if m:
        f *= SPARSE_FAC[m.group(1)]
    xe = rnd(x * f, 4) if f != 1.0 else x
    he = h
    if h < 1.0 and hp == "realistic":
        he = rnd(1.0 - (1.0 - h) * height_weight(r), 4)
    return xe, he


def stored_effective(e):
    return float(e.get("xe", e["x"])), float(e.get("he", get_h(e)))


def scale_head(head, xe):
    """SPACING and RANDOM times xe. For natural forests (RANDOM 0.25 - 0.5 x SPACING) RANDOM is raised to
    half the tree spacing: below that X-Plane leaves empty strips between the grid rows, which show up as
    lines in dense forests. Planted rows (RANDOM below 0.25 x SPACING, e.g. orchards) keep their grid."""
    sp = next(((float(m.group(4)), float(m.group(6))) for m in LINE_RX.finditer(head) if m.group(2) == "SPACING"), None)

    def val(v, s, is_random):
        n = v * xe
        if is_random and s > 0 and RANDOM_MIN_RATIO <= v / s < RANDOM_TARGET:
            n = RANDOM_TARGET * s * xe
        return fmt(n)

    def sub(m):
        rnd_line = m.group(2) == "RANDOM" and sp is not None
        sx, sz = sp if sp else (0.0, 0.0)
        return (m.group(1) + m.group(2) + m.group(3) + val(float(m.group(4)), sx, rnd_line)
                + m.group(5) + val(float(m.group(6)), sz, rnd_line))
    return LINE_RX.sub(sub, head)


def outdated(r, e):
    """Tweaked with values that differ from the current rules for its settings (e.g. cropland from 1.3,
    RANDOM from 1.4.1 or older)."""
    want = effective(r, float(e["x"]), get_h(e), get_hp(e))
    have = stored_effective(e)
    if abs(want[0] - have[0]) > 1e-9 or abs(want[1] - have[1]) > 1e-9:
        return True
    if want[0] < 1.0 and e.get("o") and e.get("n"):
        exp = [m.group(0) for m in LINE_RX.finditer(scale_head("\n".join(as_list(e["o"])), want[0]))]
        if exp != as_list(e["n"]):
            return True
    return False


# ---------------------------------------------------------------- progress with remaining time
class Progress:
    def __init__(self, label, total_units):
        self.label, self.total = label, max(1, total_units)
        self.t0 = self.last = time.time()
        self.tty = sys.stdout.isatty()

    def update(self, units, i, n, force=False):
        if not self.tty:
            return
        now = time.time()
        if not force and now - self.last < 0.3:
            return
        self.last = now
        pct = min(100, int(100 * units / self.total))
        eta = ""
        el = now - self.t0
        if units > 0 and units < self.total and el >= 10 and (units >= 0.1 * self.total or el >= 30):
            rest = el * (self.total - units) / units
            eta = "  about %d min left" % round(rest / 60) if rest >= 90 else "  about %d s left" % (int(rest / 10 + 1) * 10)
        sys.stdout.write(f"\r  {self.label}: {i} / {n} ({pct} %){eta}" + " " * 10)
        sys.stdout.flush()

    def end(self):
        if self.tty:
            sys.stdout.write("\r" + " " * 90 + "\r")
            sys.stdout.flush()


def work_units(size, heavy):
    return size * (MESH_WEIGHT if heavy else 1)


def time_range(sec):
    """Rough range for an estimated duration, e.g. 'about 4-10 min'."""
    lo, hi = sec * 0.6, sec * 1.6
    if hi < 90:
        return "about 1 min or less"
    lo_m = max(1, round(lo / 60))
    return f"about {lo_m}-{max(lo_m + 1, round(hi / 60))} min"


def speedup():
    return 1 + 0.75 * (min(workers(), 6) - 1)


def estimate(st, hf, rebuild):
    """Seconds for restore (if needed) + apply, from the file sizes found by forest_state."""
    heavy = hf < 1.0
    mesh = st["b_orig_mesh"] + (st["b_tw_mesh"] if rebuild else 0)
    plain = st["b_orig_plain"] + (st["b_tw_plain"] if rebuild else 0)
    sec = (work_units(mesh, heavy) + plain) / (RATE * speedup())
    if rebuild:
        sec += (st["b_tw_mesh"] + st["b_tw_plain"]) / RATE_RESTORE
    return sec


def took(t0):
    s = time.time() - t0
    return f"{s:.0f} s" if s < 90 else f"{s / 60:.0f} min"


# ---------------------------------------------------------------- forest state
def forest_state(xp, targets):
    """Current forest tweak in the chosen folders."""
    log = read_log(log_path(xp))
    st = {"n": 0, "n_orig": 0, "n_reset": 0, "n_skip": 0, "n_old": 0, "files": 0, "x": 1.0, "h": 1.0, "hp": "uniform",
          "b_orig_mesh": 0, "b_orig_plain": 0, "b_tw_mesh": 0, "b_tw_plain": 0}     # bytes, for the time estimate
    settings = Counter()
    files = get_files(targets)
    st["files"] = len(files)
    pr = Progress("Checking", len(files))
    for i, f in enumerate(files, 1):
        pr.update(i, i, len(files))
        r = rel(xp, f)
        fo = ForFile(f, quick=True)
        e = log.get(r)
        kind = "mesh" if tree_meshes(fo.tail) else "plain"
        if e and state(fo, e) == "tweaked":
            st["n"] += 1
            st["b_tw_" + kind] += fo.length
            settings[(float(e["x"]), get_h(e), get_hp(e))] += 1
            if outdated(r, e):
                st["n_old"] += 1
        elif min_spacing(fo.head) > THRESHOLD:
            st["n_orig"] += 1
            st["b_orig_" + kind] += fo.length
            if e:
                st["n_reset"] += 1      # logged as tweaked, but the file is original again (update)
        else:
            st["n_skip"] += 1
    pr.end()
    if settings:
        st["x"], st["h"], st["hp"] = settings.most_common(1)[0][0]
    return st


def format_forest(x, h, hp):
    if (x, h) == (1.0, 1.0):
        return "original"
    s = f"tree spacing {fmt(x)} (about {trees_x(x):.1f}x trees)" if x < 1.0 else "tree spacing 1 (original)"
    if h < 1.0:
        s += f", tree height {fmt(h)} {hp}"
    return s


def status_line(st, hstate):
    if st["n"] == 0:
        s = "forests original"
    else:
        s = "forests tweaked: " + format_forest(st["x"], st["h"], st["hp"])
        if st["n_reset"]:
            s += f" - {st['n_reset']} files reset by an update, run Choose settings"
        elif st["n_orig"]:
            s += f" - {st['n_orig']} files not tweaked"
        elif st["n_old"]:
            s += " - run Choose settings once to apply the latest improvements"
    if hstate:
        s += f" | hedges {CHOICE_NAMES.get(hstate, hstate)}"
    return s


# ---------------------------------------------------------------- apply (parallel worker)
def _worker_init():
    signal.signal(signal.SIGINT, signal.SIG_IGN)     # Ctrl+C is handled by the main process


def tweak_job(job):
    """Computes the tweaked file and writes it as <file>.fdt_tmp (plus the .gz backup if 3D models change).
    The main process logs the entry first and only then swaps the temp file in."""
    path, xp, r, x, h, hp = job
    xe, he = effective(r, x, h, hp)
    fo = ForFile(path)
    new_head, new_tail, do_trees, odd = fo.head, fo.tail, he < 1.0, False
    if do_trees and len(TREE_RX.findall(fo.data.decode("latin-1"))) != len(fo.tlines):
        do_trees, odd = False, True     # safety: all TREE lines of the file must be in the tree list at the end
    if xe < 1.0:
        new_head = scale_head(fo.head, xe)
    new_mid, meshes = None, set()
    if do_trees:
        # min and max height scaled alike -> the height variation shrinks with them
        new_tail = TREE_RX.sub(lambda m: m.group(1) + m.group(2) + m.group(3)
                               + fmt(float(m.group(4)) * he) + m.group(5)
                               + fmt(float(m.group(6)) * he), fo.tail)
        meshes = tree_meshes(fo.tail)
        if meshes:
            new_mid = scale_meshes(fo.data, fo.head_len, fo.tail_start, meshes, he)
    if new_head == fo.head and new_tail == fo.tail and new_mid is None:
        return ("skip", r, None, fo.length, 0, odd)
    if new_mid is None:
        new_mid = fo.data[fo.head_len:fo.tail_start]
    out = new_head.encode("latin-1") + new_mid + new_tail.encode("latin-1")
    need = len(out) + (len(fo.data) // 2 if meshes else 0) + DISK_MARGIN
    if free_space(os.path.dirname(path)) < need or (meshes and free_space(os.path.join(xp, TWEAK_DIR)) < need):
        return ("nospace", r, None, fo.length, 0, odd)
    entry = {"f": r, "x": x, "h": h}
    if h < 1.0:
        entry["hp"] = hp
    if xe != x:
        entry["xe"] = xe
        entry["cb"] = True
    if he != h:
        entry["he"] = he
    entry["o"] = fo.lines
    entry["n"] = [m.group(0) for m in LINE_RX.finditer(new_head)]
    if new_tail != fo.tail:
        entry["ot"] = fo.tlines
        entry["nt"] = [m.group(0) for m in TREE_RX.finditer(new_tail)]
    if meshes:
        # 3D meshes change -> keep a compressed copy of the original file (with checksum) for an exact restore
        bp = backup_path(xp, r)
        os.makedirs(os.path.dirname(bp), exist_ok=True)
        with gzip.open(bp + ".tmp", "wb", compresslevel=6) as g:
            g.write(fo.data)
        os.replace(bp + ".tmp", bp)
        entry["mb"] = True
        entry["ms"] = hashlib.sha256(fo.data).hexdigest()
    tmp = path + ".fdt_tmp"
    with open(tmp, "wb") as f:
        f.write(out)
        f.flush()
        os.fsync(f.fileno())
    return ("ok", r, entry, fo.length, len(meshes), odd)


def workers():
    try:
        return max(1, int(os.environ["XP12FT_WORKERS"]))     # optional override, e.g. for tests
    except (KeyError, ValueError):
        return max(1, min((os.cpu_count() or 2) - 1, 6))


def apply_values(xp, targets, fac, hf, hp):
    """Applies the settings to all forest files that are not tweaked yet. Returns True if completed."""
    lp = log_path(xp)
    log = read_log(lp)
    files = get_files(targets)
    jobs, already, skip = [], 0, 0
    weight = {}
    for f in files:
        r = rel(xp, f)
        fo = ForFile(f, quick=True)
        if state(fo, log.get(r)) == "tweaked":
            already += 1
        elif min_spacing(fo.head) <= THRESHOLD:
            skip += 1
        else:
            jobs.append((f, xp, r, fac, hf, hp))
            weight[r] = work_units(fo.length, hf < 1.0 and bool(tree_meshes(fo.tail)))
    total = sum(weight.values())
    tlog(f"apply: spacing {fac} height {hf} {hp}, {len(jobs)} files to tweak, {already} already tweaked, {workers()} workers")
    pr = Progress("Tweaking forest files", total)
    done = odd = mesh_count = units = 0
    no_space = False
    by_rel = {j[2]: j[0] for j in jobs}
    pool = None
    t0 = time.time()
    try:
        if workers() > 1 and len(jobs) > 20:
            try:
                pool = multiprocessing.Pool(workers(), initializer=_worker_init)
                results = pool.imap_unordered(tweak_job, jobs, chunksize=2)
            except (OSError, ImportError, ValueError):
                pool = None
        if pool is None:
            results = map(tweak_job, jobs)
        with open(lp, "a", encoding="utf-8", newline="\n") as lf:
            for i, (status, r, entry, size, nm, o) in enumerate(results, 1):
                units += weight[r]
                pr.update(units, i, len(jobs))
                odd += o
                if status == "nospace":
                    no_space = True
                    break
                if status == "skip":
                    skip += 1
                    continue
                # log first, then swap the file in: an interruption can never lead to double scaling
                lf.write(json.dumps(entry, separators=(",", ":")) + "\n")
                lf.flush()
                os.fsync(lf.fileno())
                f = by_rel[r]
                drop_sides(f)                    # kept copies of the quick switch belong to the old state
                os.replace(f + ".fdt_tmp", f)
                log[r] = entry
                done += 1
                mesh_count += nm
    except KeyboardInterrupt:
        if pool:
            pool.terminate()
            pool.join()
        pr.end()
        cleanup_temp(xp, targets)
        say()
        warn(f"  Stopped. {done} files were tweaked and logged - nothing is broken.")
        warn("  Run Choose settings again to finish, or Restore original.")
        tlog(f"apply: stopped by user after {done} files")
        return False
    finally:
        if pool:
            pool.close()
            pool.join()
    pr.end()
    cleanup_temp(xp, targets)
    write_log(lp, list(log.values()))          # compact: one line per file
    say()
    say(f"  Tweaked now          : {done}   ({took(t0)})", C_GREEN)
    say(f"  Already tweaked      : {already}")
    say(f"  Grass/shrubs (kept)  : {skip}")
    if mesh_count:
        bk = os.path.join(xp, TWEAK_DIR, "mesh_backup")
        mb = sum(os.path.getsize(os.path.join(r_, n)) for r_, _d, ns in os.walk(bk) for n in ns) / 2**20
        say(f"  3D tree models scaled: {mesh_count}   (backup: {mb:.0f} MB in {TWEAK_DIR}/mesh_backup)")
    if odd:
        warn(f"  Unusual layout       : {odd} (spacing changed, tree heights left as they are)")
    tlog(f"apply: {done} tweaked, {already} already, {skip} kept, {mesh_count} meshes, {odd} unusual, no_space={no_space}")
    if no_space:
        say()
        say("  Not enough free disk space - stopped. Everything done so far is logged and safe.", C_RED)
        say("  Free some space and run Choose settings again, or use Restore original.", C_RED)
        return False
    return True


def cleanup_temp(xp, targets):
    """Removes leftover temp files of an interrupted run."""
    n = 0
    for top in list(targets) + [os.path.join(xp, TWEAK_DIR, "mesh_backup")]:
        for root, _d, names in os.walk(top):
            for name in names:
                if name.endswith(".fdt_tmp") or name.endswith(".gz.tmp"):
                    try:
                        os.remove(os.path.join(root, name))
                        n += 1
                    except OSError:
                        pass
    return n


# ---------------------------------------------------------------- restore
def restore(xp, targets, quiet=False):
    """Restores all tweaked files in the chosen folders. Returns True if nothing failed."""
    lp = log_path(xp)
    log = read_log(lp)
    if not log:
        if not quiet:
            say("  Forests: nothing to restore (no backup log).")
        return True
    files = [f for f in get_files(targets) if rel(xp, f) in log]
    total = sum(os.path.getsize(f) for f in files)
    pr = Progress("Restoring", total)
    done = units = 0
    damaged = []
    t0 = time.time()
    try:
        for i, f in enumerate(files, 1):
            units += os.path.getsize(f)
            pr.update(units, i, len(files))
            r = rel(xp, f)
            e = log[r]
            drop_sides(f)
            fo = ForFile(f, quick=True)
            bp = backup_path(xp, r)
            if state(fo, e) != "tweaked":
                # file was reset by an update -> its backup is outdated
                if os.path.exists(bp):
                    os.remove(bp)
                del log[r]
                continue
            if e.get("mb"):
                data = None
                if os.path.exists(bp):
                    try:
                        with gzip.open(bp, "rb") as g:
                            data = g.read()
                    except (OSError, EOFError):
                        data = None
                if data is None or ("ms" in e and hashlib.sha256(data).hexdigest() != e["ms"]):
                    damaged.append(r)      # keep it tweaked and logged: never scale its 3D models twice
                    continue
                if free_space(os.path.dirname(f)) < len(data) + DISK_MARGIN:
                    raise RuntimeError("Not enough free disk space to restore. Free some space and try again.")
                write_bytes(f, data)
                os.remove(bp)
                del log[r]
                done += 1
                continue
            fo = ForFile(f)
            new_head = set_seq(fo.head, LINE_RX, e.get("o"))
            new_tail = set_seq(fo.tail, TREE_RX, e["ot"]) if "ot" in e else fo.tail
            write_bytes(f, new_head.encode("latin-1") + fo.data[fo.head_len:fo.tail_start] + new_tail.encode("latin-1"))
            del log[r]
            done += 1
    finally:
        pr.end()
        # keep log entries of files outside the chosen folders (e.g. GFv2 when it was not included)
        # and of files that could not be restored
        write_log(lp, list(log.values()))
        remove_empty_dirs(os.path.join(xp, TWEAK_DIR, "mesh_backup"))
    tlog(f"restore: {done} restored, {len(damaged)} damaged backups")
    if not quiet:
        say()
        say(f"  Forests restored     : {done} files   ({took(t0)})", C_GREEN)
    if damaged:
        say()
        say(f"  {len(damaged)} files could not be restored: their 3D model backup is missing or damaged.", C_RED)
        say("  They stay tweaked (safe). To repair them, run the X-Plane installer (Update) or reinstall", C_RED)
        say("  Global Forests v2, then run Check & repair. First file: " + damaged[0], C_RED)
        for r in damaged:
            tlog(f"restore: damaged backup {r}")
    return not damaged


# ---------------------------------------------------------------- simHeaven hedges
def hedge_files(xp):
    """Hedge files the simHeaven X-World Vegetation Library exports as simheaven/forests/hedge.for."""
    cs = os.path.join(xp, "Custom Scenery")
    out = []
    for name in sorted(os.listdir(cs)):
        lib = os.path.join(cs, name)
        if not (os.path.isdir(lib) and re.match(r"(?i)^simheaven.*vegetation.*librar", name)):
            continue
        try:
            with open(os.path.join(lib, "library.txt"), encoding="latin-1") as f:
                lines = f.readlines()
        except OSError:
            continue
        real_lib = os.path.realpath(lib)
        for line in lines:
            tok = line.split()
            if len(tok) >= 3 and tok[0].startswith("EXPORT") and HEDGE_VPATH in tok:
                target = line.strip().split(HEDGE_VPATH, 1)[1].strip()
                full = os.path.join(lib, *target.replace("\\", "/").split("/"))
                real = os.path.realpath(full)
                # only real files inside the library itself (never the linked default forests)
                if os.path.isfile(full) and real.startswith(real_lib + os.sep) and full not in out:
                    out.append(full)
    return out


def hedge_log_path(xp):
    return os.path.join(tweak_dir(xp), "hedges.log")


def lod_line(text):
    m = LOD_RX.search(text)
    return m.group(0) if m else ""


def hedge_state(text, e):
    if e and [m.group(0) for m in TREE_RX.finditer(text)] == as_list(e.get("nt")) and lod_line(text) == e.get("nl", ""):
        return "enhanced"
    return "default"


def hedge_overview(xp):
    files = hedge_files(xp)
    if not files:
        return files, None, {}
    log = read_log(hedge_log_path(xp))
    states = {}
    for f in files:
        with open(f, "rb") as fh:
            states[f] = hedge_state(fh.read().decode("latin-1"), log.get(rel(xp, f)))
    n = sum(1 for v in states.values() if v == "enhanced")
    overall = "enhanced" if n == len(files) else ("default" if n == 0 else "partly enhanced")
    return files, overall, log


def hedge_status_text(files, overall):
    if not files:
        return "not installed"
    return {"enhanced": "enhanced (about 4-5 m, visible up to 8 km)",
            "default": "default (2.2-2.8 m, visible up to 4 km)"}.get(overall, overall)


def hedges_apply(xp, files, log):
    lp = hedge_log_path(xp)
    done = 0
    with open(lp, "a", encoding="utf-8", newline="\n") as lf:
        for f in files:
            r = rel(xp, f)
            with open(f, "rb") as fh:
                text = fh.read().decode("latin-1")
            if hedge_state(text, log.get(r)) == "enhanced":
                continue
            if re.search(r"(?m)^[ \t]*MESH", text):
                warn(f"  Skipped (unexpected 3D content): {r}")
                continue
            new = TREE_RX.sub(lambda m: m.group(1) + m.group(2) + m.group(3)
                              + fmt(float(m.group(4)) * HEDGE_FAC) + m.group(5)
                              + fmt(float(m.group(6)) * HEDGE_FAC), text)
            lm = LOD_RX.search(new)
            if lm and float(lm.group(2)) < HEDGE_LOD:
                new = new[:lm.start()] + lm.group(1) + str(HEDGE_LOD) + new[lm.end():]
            if free_space(os.path.dirname(f)) < len(new) + DISK_MARGIN:
                raise RuntimeError("Not enough free disk space.")
            entry = {"f": r, "ol": lod_line(text), "nl": lod_line(new),
                     "ot": [m.group(0) for m in TREE_RX.finditer(text)],
                     "nt": [m.group(0) for m in TREE_RX.finditer(new)]}
            lf.write(json.dumps(entry, separators=(",", ":")) + "\n")     # log first, then write
            lf.flush()
            os.fsync(lf.fileno())
            write_bytes(f, new.encode("latin-1"))
            log[r] = entry
            done += 1
    write_log(lp, list(log.values()))
    tlog(f"hedges: enhanced {done} files")
    say(f"  simHeaven hedges enhanced: {done} files", C_GREEN)


def hedges_restore(xp, files, log):
    done = 0
    for f in files:
        r = rel(xp, f)
        e = log.get(r)
        with open(f, "rb") as fh:
            text = fh.read().decode("latin-1")
        if e and hedge_state(text, e) == "enhanced":
            new = set_seq(text, TREE_RX, e.get("ot"))
            if e.get("ol"):
                new = set_seq(new, LOD_RX, [e["ol"]])
            write_bytes(f, new.encode("latin-1"))
            done += 1
        log.pop(r, None)
    write_log(hedge_log_path(xp), list(log.values()))
    tlog(f"hedges: back to default {done} files")
    say(f"  simHeaven hedges back to default: {done} files", C_GREEN)


# ---------------------------------------------------------------- Knicks (northern Germany / Denmark)
# Own small library that replaces the simHeaven hedges (OSM barrier=hedge) and tree rows
# (OSM natural=tree_row) and scrub only in KNICK_RECTS with Knicks: bushes plus single trees. Uses the
# X-Plane default tree billboards (copied, they may not be shipped) and the same XP12 shader
# settings as the default forests. simHeaven files are not changed for it.
KNICK_DIR = "XP12_ForestTweak_Knicks"
KNICK_MARK = "# generated by XP12 Forest Tweak"
# Knick / Wallhecken areas, whole 1x1 degree tiles "west south east north" (south-west corners):
# Schleswig-Holstein (everywhere), Niedersachsen (Ostfriesland, Oldenburg, Elbe-Weser, Emsland,
# Osnabrueck-Nord, Heidekreis - NLWKN), West-Mecklenburg (LUNG), Hamburg, Denmark (diger, hegn).
KNICK_RECTS = ("7 52 9 52", "7 53 11 53", "8 54 12 54", "8 55 12 55", "14 55 14 55", "8 56 11 57")
KNICK_AREA = "Schleswig-Holstein, Hamburg, north-west Lower Saxony, west Mecklenburg, Denmark"
KNICK_SEASONS = (("spr", "trees_bb1_ALB_sp", "trees_bb1_ALB", "trees_bb1_SM"),
                 ("sum", "trees_bb1_ALB", "trees_bb1_ALB_fa", "trees_bb1_SM"),
                 ("fal", "trees_bb1_ALB_fa", "trees_bb1_ALB_wi", "trees_bb1_SM"),
                 ("win", "trees_bb1_ALB_wi", "trees_bb1_ALB_sp", "trees_bb1_SM_wi"))
KNICK_TEXTURES = ("trees_bb1_ALB", "trees_bb1_ALB_sp", "trees_bb1_ALB_fa", "trees_bb1_ALB_wi",
                  "trees_bb1_NML", "trees_bb1_SM", "trees_bb1_SM_wi")
#   s     t     w    h    off  freq min  max   kind  name   (kind b = bush, t = tree)
# Knick (heights at tree height 1.0, the tree height factor is applied on top):
#   bushes in three sizes (1.5-3, 3-5, 5-8 m), Ueberhaelter in three ages (6-9, 9-12, 12-14 m).
#   HEIGHT_PARAMS: heights change in sections of about 100 m (like a Knick cut a few years ago next to an
#   old one) instead of from tree to tree. CHOICE_PARAMS + GROUP: sections of pure bushes and sections with
#   Ueberhaelter, about 40 / 60 %.
#   s     t     w    h    off  freq min  max  kind  name   (kind b = bush, t = tree)
KNICK_HEDGE = (("P", "HEIGHT_PARAMS 100 0.7 25 0.3 0 0 0 0"), ("P", "CHOICE_PARAMS 150 0.8 30 0.2 0 0 0 0"),
               ("G", 40),                                                     # pure bush sections
               (224, 2848, 118, 124, 59, 18, 1.5, 3, "b", "decid_03"),
               (224, 2848, 118, 124, 59, 14, 3, 5, "b", "decid_03"),
               (1900, 2848, 128, 124, 64, 16, 3, 5, "b", "sorbus_07"),
               (1900, 2848, 128, 124, 64, 10, 5, 8, "b", "sorbus_07"),
               (1792, 2848, 108, 124, 54, 16, 1.5, 3, "b", "lilac_06"),
               (1792, 2848, 108, 124, 54, 10, 3, 5, "b", "lilac_06"),
               (332, 2080, 110, 124, 55, 16, 5, 8, "b", "locust_01"),
               ("G", 60),                                                     # sections with Ueberhaelter
               (224, 2848, 118, 124, 59, 14, 1.5, 3, "b", "decid_03"),
               (224, 2848, 118, 124, 59, 12, 3, 5, "b", "decid_03"),
               (1900, 2848, 128, 124, 64, 13, 3, 5, "b", "sorbus_07"),
               (1900, 2848, 128, 124, 64, 9, 5, 8, "b", "sorbus_07"),
               (1792, 2848, 108, 124, 54, 13, 1.5, 3, "b", "lilac_06"),
               (1792, 2848, 108, 124, 54, 8, 3, 5, "b", "lilac_06"),
               (332, 2080, 110, 124, 55, 14, 5, 8, "b", "locust_01"),
               (776, 2976, 184, 252, 92, 4, 6, 9, "t", "maple_07"),
               (1452, 3584, 190, 252, 95, 4, 9, 12, "t", "ash_07"),
               (1050, 3584, 104, 252, 52, 3, 9, 12, "t", "oak1_08"),
               (880, 3584, 170, 252, 85, 4, 12, 14, "t", "oak1_07"),
               (1050, 3584, 104, 252, 52, 2, 12, 14, "t", "oak1_08"))
KNICK_ROW = ((880, 3584, 170, 252, 85, 8, 12, 20, "t", "oak1_07"),
             (1050, 3584, 104, 252, 52, 8, 12, 18, "t", "oak1_08"),
             (1154, 3584, 128, 252, 64, 7, 12, 19, "t", "oak1_09"),
             (1452, 3584, 190, 252, 95, 7, 11, 18, "t", "ash_07"),
             (776, 2976, 184, 252, 92, 6, 10, 16, "t", "maple_07"),
             (250, 2592, 208, 252, 104, 6, 11, 17, "t", "elm_05"),
             (294, 3584, 118, 252, 59, 5, 10, 15, "t", "birch_07"),
             (1296, 2976, 110, 252, 55, 4, 11, 17, "t", "aspen_05"),
             (0, 2976, 208, 252, 104, 4, 12, 18, "t", "redoak_04"),
             (224, 2848, 118, 124, 59, 15, 4, 6, "b", "decid_03"),
             (1900, 2848, 128, 124, 64, 15, 4, 6, "b", "sorbus_07"),
             (1792, 2848, 108, 124, 54, 15, 4, 5.5, "b", "lilac_06"))
# scrub areas (OSM natural=scrub, often narrow Knick strips): dense bushes 2-6 m, a few small trees
KNICK_SCRUB = ((224, 2848, 118, 124, 59, 25, 2.5, 5, "b", "decid_03"),
               (1900, 2848, 128, 124, 64, 24, 2, 4.5, "b", "sorbus_07"),
               (1792, 2848, 108, 124, 54, 24, 2, 4, "b", "lilac_06"),
               (332, 2080, 110, 124, 55, 24, 3, 6, "b", "locust_01"),
               (294, 3584, 118, 252, 59, 2, 6, 10, "s", "birch_07"),
               (1296, 2976, 110, 252, 55, 1, 6, 10, "s", "aspen_05"))
# hedge outside the Knick areas (simHeaven hedges, X-WORLD Pro hedge walls, official hedge maps): dense bushes
KNICK_PLAIN = ((224, 2848, 118, 124, 59, 20, 3, 5, "b", "decid_03"),
               (1900, 2848, 128, 124, 64, 20, 3, 5, "b", "sorbus_07"),
               (1792, 2848, 108, 124, 54, 20, 2.5, 4.5, "b", "lilac_06"),
               (332, 2080, 110, 124, 55, 15, 4, 5.5, "b", "locust_01"),
               (224, 2848, 118, 124, 59, 15, 2, 3, "b", "decid_03"),
               (1792, 2848, 108, 124, 54, 10, 2, 3, "b", "lilac_06"))
KNICK_KINDS = (("knick", "Knick: bushes in three sizes plus Ueberhaelter in sections",
                "0.8", "0.8", "8000", KNICK_HEDGE, "simheaven/forests/hedge.for"),
               ("treerow", "Knick tree row: mixed broadleaf trees plus bushes in between",
                "2.5", "1.2", "10000", KNICK_ROW, "simheaven/forests/random_tree.for"),
               ("scrub", "Knick scrub: dense bushes 2-6 m with a few small trees",
                "3", "1.5", "8000", KNICK_SCRUB, "simheaven/forests/shrubs.for"),
               ("knickmap", "Knick of the hedgerow map: bushes in three sizes plus Ueberhaelter (1.6 m strips)",
                "1.0", "0.8", "8000", KNICK_HEDGE, None),
               ("hedge", "Hedge: dense bushes 2-5.5 m (hedges outside the Knick areas)",
                "1.0", "0.8", "8000", KNICK_PLAIN, None))


def knick_path(xp):
    return os.path.join(xp, "Custom Scenery", KNICK_DIR)


def knick_info(xp):
    """(active, height, profile) of a library generated by this tool, else (False, None, None)."""
    try:
        with open(os.path.join(knick_path(xp), "library.txt"), encoding="latin-1") as f:
            for line in f.read(2000).splitlines():
                m = re.match(re.escape(KNICK_MARK) + r".*\|\s*height\s+([0-9.]+)\s+(\w+)", line)
                if m:
                    return True, float(m.group(1)), m.group(2)
    except OSError:
        pass
    return False, None, None


def knick_lib_version(xp):
    try:
        with open(os.path.join(knick_path(xp), "library.txt"), encoding="latin-1") as f:
            for line in f.read(2000).splitlines():
                m = re.match(re.escape(KNICK_MARK) + r"\s+(\S+)", line)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return None


def knick_texture_src(xp, name):
    tex = os.path.join(xp, "Resources", "default scenery", "1200 forests", "textures")
    for ext in (".dds", ".png"):
        p = os.path.join(tex, name + ext)
        if os.path.isfile(p):
            return p
    return None


def scenery_ini(xp):
    return os.path.join(xp, "Custom Scenery", "scenery_packs.ini")


def ini_write(xp, lines, nl):
    """Writes scenery_packs.ini via a temp file, after one backup per day in ForestDensityTweak."""
    p = scenery_ini(xp)
    bk = os.path.join(tweak_dir(xp), "scenery_packs.ini.backup-" + time.strftime("%Y%m%d"))
    if os.path.exists(p) and not os.path.exists(bk):
        shutil.copy2(p, bk)
    write_bytes(p, (nl.join(lines)).encode("utf-8"))


def ini_read(xp):
    p = scenery_ini(xp)
    if not os.path.exists(p):
        return None, "\n"
    raw = open(p, "rb").read().decode("utf-8", errors="surrogateescape")
    nl = "\r\n" if "\r\n" in raw else "\n"
    return raw.split(nl), nl


def pack_line_is(line, folder):
    """True for the scenery_packs.ini line of exactly this Custom Scenery folder (enabled or disabled)."""
    m = re.match(r"(?i)^SCENERY_PACK(?:_DISABLED)?\s+Custom Scenery/(.+?)/?\s*$", line)
    return bool(m) and m.group(1).lower() == folder.lower()


def ini_place(xp):
    """Lists the Knick library directly above the simHeaven Vegetation Library. True if changed."""
    lines, nl = ini_read(xp)
    if lines is None:
        return False          # X-Plane creates the file on its next start; new packs are added then
    mine = f"SCENERY_PACK Custom Scenery/{KNICK_DIR}/"
    rest = [l for l in lines if not pack_line_is(l, KNICK_DIR)]
    i = next((k for k, l in enumerate(rest) if re.search(r"(?i)simheaven.*(vegetation.*librar|X-WORLD-Pro_Library)", l)), None)
    if i is None:
        i = next((k for k, l in enumerate(rest) if l.startswith("SCENERY_PACK")), len(rest))
    new = rest[:i] + [mine] + rest[i:]
    if new == lines:
        return False
    ini_write(xp, new, nl)
    return True


def ini_unlist(xp):
    lines, nl = ini_read(xp)
    if lines is None or not any(pack_line_is(l, KNICK_DIR) for l in lines):
        return
    ini_write(xp, [l for l in lines if not pack_line_is(l, KNICK_DIR)], nl)


def knick_write(xp, h, hp, kmap=False, built=None, choice="Knicks"):
    """Creates or updates the tweak library for tree height h / profile hp. built: tiles of the hedge overlay
    (there the simHeaven hedges and tree rows are hidden, the overlay has them). choice: 'Knicks' or 'enhanced'."""
    built = set(built or ())
    d = knick_path(xp)
    os.makedirs(d, exist_ok=True)
    for name in KNICK_TEXTURES:
        src = knick_texture_src(xp, name)
        if not src:
            raise RuntimeError(f"X-Plane default tree texture not found: {name} (run the X-Plane installer 'Update')")
        dst = os.path.join(d, os.path.basename(src))
        if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(src):
            if free_space(d) < os.path.getsize(src) + DISK_MARGIN:
                raise RuntimeError("Not enough free disk space.")
            shutil.copyfile(src, dst + ".tmp")
            os.replace(dst + ".tmp", dst)
    hb = rnd(1.0 - (1.0 - h) * 0.5, 4) if (h < 1.0 and hp == "realistic") else h    # bushes: like shrubs
    for kind, note, spacing, rand, lod, rows, _vpath in KNICK_KINDS:
        for season, tex, seasonal, weather in KNICK_SEASONS:
            out = ["A", "1200", "FOREST", "", f"{KNICK_MARK} {VERSION} - do not edit, Restore original removes it",
                   f"# {note}, season {season}, tree height factor {fmt(h)} {hp}", "",
                   "SHADER_2D", f"\tTEXTURE {tex}.png", f"\tSEASONAL {seasonal}.png",
                   "\tTEXTURE_NORMAL 1\ttrees_bb1_NML.png", f"\tWEATHER {weather}.png",
                   "\tBLEND_HASH 0.5", "\tSUPER_ROUGHNESS 1.0", "\tNORMAL_TRANSLUCENCY", "",
                   f"LOD {lod}", "SCALE_X 2048", "SCALE_Y 4096", f"SPACING {spacing} {spacing}",
                   f"RANDOM {rand} {rand}", "", "#\ts\tt\tw\th\toff\tfreq\tmin\tmax\tquads\tlayer\tname"]
            for row in rows:
                if row[0] == "P":              # perlin noise parameters
                    out.append(row[1])
                    continue
                if row[0] == "G":              # tree group with its share of the forest
                    out.append(f"GROUP 0 {row[1]}")
                    continue
                s_, t_, w_, h_, off, freq, mn, mx, k, name = row
                f = h if k == "t" else hb      # small trees in scrub scale like bushes
                out.append(f"TREE\t{s_}\t{t_}\t{w_}\t{h_}\t{off}\t{freq}\t{fmt(mn * f)}\t{fmt(mx * f)}\t2\t0\t{name}")
            write_bytes(os.path.join(d, f"{kind}_{season}.for"), ("\r\n".join(out) + "\r\n").encode("ascii"))
    blank = ["A", "1200", "FOREST", "", f"{KNICK_MARK} {VERSION} - do not edit, Restore original removes it",
             "# empty forest: hides the simHeaven hedges and tree rows where the hedgerow map has them", "",
             "TEXTURE trees_bb1_ALB.png", "LOD 1", "SCALE_X 2048", "SCALE_Y 4096", "SPACING 10000 10000", "RANDOM 0 0",
             "TREE\t224\t2848\t118\t124\t59\t100\t0.1\t0.1\t2\t0\tnone"]
    write_bytes(os.path.join(d, "blank.for"), ("\r\n".join(blank) + "\r\n").encode("ascii"))
    write_bytes(os.path.join(d, "blank.fac"), BLANK_FAC.encode("ascii"))
    lib = ["A", "800", "LIBRARY", "", f"{KNICK_MARK} {VERSION} | height {fmt(h)} {hp} | choice {choice}" + (" | map" if built else ""),
           "# Hedges: hedgebanks (Knicks) in the Knick areas, enhanced hedges elsewhere, for all four seasons.",
           f"# Knick areas: {KNICK_AREA}.",
           "# simHeaven files are not changed. Restore original removes this folder.", ""]
    for season, *_ in KNICK_SEASONS:
        lib.append(f"EXPORT_SEASON {season} {SH_VPATH_KNICK} knickmap_{season}.for")
        lib.append(f"EXPORT_SEASON {season} {SH_VPATH_ROW} treerow_{season}.for")
        lib.append(f"EXPORT_SEASON {season} {HM_VPATH_HEDGE} hedge_{season}.for")
    lib_tiles = (KNICK_TILES - built) if choice == "Knicks" else set()
    if lib_tiles:
        lib += ["", "# Knick areas without overlay tiles: free X-World hedges, tree rows and scrub become Knicks",
                "REGION_DEFINE xp12_foresttweak_knicks_north"] + [f"REGION_RECT {r}" for r in tiles_rects(lib_tiles)] + [
                "REGION xp12_foresttweak_knicks_north", ""]
        for kind, *_rest in KNICK_KINDS:
            vpath = _rest[-1]
            if vpath:
                for season, *_ in KNICK_SEASONS:
                    lib.append(f"EXPORT_EXCLUDE_SEASON {season} {vpath} {kind}_{season}.for")
    bk = built & KNICK_TILES if choice == "Knicks" else set()
    for name, tiles, rows in (("xp12_foresttweak_overlay_knick", bk, True), ("xp12_foresttweak_overlay", built - bk, False)):
        if not tiles:
            continue
        lib += ["", "# tiles of the hedge overlay: its hedges" + (" and tree rows" if rows else "") + " replace the simHeaven ones",
                f"REGION_DEFINE {name}"] + [f"REGION_RECT {r}" for r in tiles_rects(tiles)] + [f"REGION {name}", ""]
        for vp in PRO_HEDGE_FAC:
            lib.append(f"EXPORT_EXCLUDE {vp} blank.fac")
        for season, *_ in KNICK_SEASONS:
            for vp in (HEDGE_VPATH,) + PRO_HEDGE_FOR + ((ROW_VPATH,) if rows else ()):
                lib.append(f"EXPORT_EXCLUDE_SEASON {season} {vp} blank.for")
            if rows:
                lib.append(f"EXPORT_EXCLUDE_SEASON {season} simheaven/forests/shrubs.for scrub_{season}.for")
    write_bytes(os.path.join(d, "library.txt"), ("\r\n".join(lib) + "\r\n").encode("ascii"))
    moved = ini_place(xp)
    tlog(f"knicks: library written (height {h} {hp}), scenery_packs.ini {'updated' if moved else 'ok'}")


def knick_remove(xp):
    d = knick_path(xp)
    if os.path.isdir(d):
        names = {"library.txt", "blank.for", "blank.fac"} | {f"{k[0]}_{s[0]}.for" for k in KNICK_KINDS for s in KNICK_SEASONS}
        for name in KNICK_TEXTURES:
            names |= {name + ".dds", name + ".png"}
        for n in os.listdir(d):
            if n in names or n.endswith(".tmp") or n.endswith(".fdt_tmp"):
                os.remove(os.path.join(d, n))
        try:
            os.rmdir(d)
        except OSError:
            warn(f"  Folder Custom Scenery/{KNICK_DIR} has other files in it and was left in place (inactive).")
    ini_unlist(xp)
    tlog("knicks: removed")


# ---------------------------------------------------------------- hedgerow map (optional, with Knicks)
# With Knicks on, the tool can use the official map of all Knicks (hedgerows), field hedges, tree rows and
# avenues of Schleswig-Holstein (Biotopkartierung SH4, LLUR SH, CC BY 4.0). It comes with the tool as
# hedgerow_map_sh.dat (lines only, converted from the original shapefile) and is turned into X-Plane
# scenery tiles on this computer. Where the map has nothing (Denmark, Lower Saxony, Mecklenburg, gardens),
# the simHeaven hedges and tree rows of this computer are taken over (they are not shipped).
SH_URL = "https://opendata.schleswig-holstein.de/dataset/sh4-biotopkartierung-der-alleen-knicks-feldhecken-und-baumreihen"
SH_DIR = "XP12_ForestTweak_HedgerowMap"           # scenery pack with the generated DSF tiles
SH_MARK = "# generated by XP12 Forest Tweak"
SH_VPATH_KNICK = "xp12_foresttweak/knick_map.for"
SH_VPATH_ROW = "xp12_foresttweak/treerow_map.for"
SH_HALF_WIDTH = 0.8       # Knick strip: 1.6 m wide
SH_ROW_STEP = 7.0         # tree row: a tree about every 7 m
SH_AVENUE_STEP = 8.0      # avenue: two rows 5 m left and right of the line, a tree about every 8 m
SH_AVENUE_OFF = 5.0
SH_DUP_CELL = 20.0        # simHeaven feature counts as a duplicate when half of it lies within 20-40 m of SH data
P_AREA, P_POINT = 255, 767  # DSF forest parameter: density 255, +512 = point mode (one tree per vertex)
GRS_A, GRS_F, UTM_K0 = 6378137.0, 1 / 298.257222101, 0.9996
DEG = 180.0 / math.pi


def hyp(x, y):
    """sqrt(x*x + y*y), written out so both tool versions compute exactly the same."""
    return math.sqrt(x * x + y * y)


class Lcg:
    """Small deterministic random generator, the same in both tool versions."""
    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFF

    def next(self):
        self.s = (self.s * 1664525 + 1013904223) & 0xFFFFFFFF
        return self.s / 4294967296.0


def _utm_consts():
    n = GRS_F / (2 - GRS_F)
    n2 = n * n
    n3 = n2 * n
    A = GRS_A / (1 + n) * (1 + n2 / 4 + n2 * n2 / 64)
    beta = (n / 2 - 2 * n2 / 3 + 37 * n3 / 96, n2 / 48 + n3 / 15, 17 * n3 / 480)
    delta = (2 * n - 2 * n2 / 3 - 2 * n3, 7 * n2 / 3 - 8 * n3 / 5, 56 * n3 / 15)
    return A, beta, delta


UTM_A, UTM_BETA, UTM_DELTA = _utm_consts()


def utm32_to_ll(e, n):
    """EPSG 4647 (ETRS89 / UTM 32 with leading 32 in the easting) -> (lon, lat) in degrees (Krueger series)."""
    xi = n / (UTM_K0 * UTM_A)
    eta = (e - 32500000.0) / (UTM_K0 * UTM_A)
    xp, ep = xi, eta
    for j in range(3):
        k = 2 * (j + 1)
        xp -= UTM_BETA[j] * math.sin(k * xi) * math.cosh(k * eta)
        ep -= UTM_BETA[j] * math.cos(k * xi) * math.sinh(k * eta)
    chi = math.asin(math.sin(xp) / math.cosh(ep))
    phi = chi
    for j in range(3):
        phi += UTM_DELTA[j] * math.sin(2 * (j + 1) * chi)
    lon = 9.0 + math.atan2(math.sinh(ep), math.cos(xp)) * DEG
    return lon, phi * DEG


def sh_pack(xp):
    return os.path.join(xp, "Custom Scenery", SH_DIR)


def sh_info(xp):
    """True if the hedgerow map pack was generated by this tool."""
    try:
        with open(os.path.join(sh_pack(xp), "hedgerow_map.txt"), encoding="latin-1") as f:
            return f.read(200).startswith(SH_MARK)
    except OSError:
        return False


def _varint(b, o):
    v = sh = 0
    while True:
        c = b[o]
        o += 1
        v |= (c & 0x7F) << sh
        if not c & 0x80:
            return v, o
        sh += 7


def clip_line(pts, w, s):
    """Pieces of a polyline inside the tile [w, w+1] x [s, s+1] (Liang-Barsky per segment)."""
    out, cur = [], []
    for p0, p1 in zip(pts, pts[1:]):
        x0, y0 = p0
        dx, dy = p1[0] - x0, p1[1] - y0
        u0, u1, ok = 0.0, 1.0, True
        for p, q in ((-dx, x0 - w), (dx, w + 1 - x0), (-dy, y0 - s), (dy, s + 1 - y0)):
            if p == 0:
                if q < 0:
                    ok = False
            else:
                u = q / p
                if p < 0:
                    u0 = max(u0, u)
                else:
                    u1 = min(u1, u)
        if not ok or u0 > u1:
            if len(cur) > 1:
                out.append(cur)
            cur = []
            continue
        a = (x0 + u0 * dx, y0 + u0 * dy)
        b = (x0 + u1 * dx, y0 + u1 * dy)
        if cur and cur[-1] == a:
            cur.append(b)
        else:
            if len(cur) > 1:
                out.append(cur)
            cur = [a, b]
    if len(cur) > 1:
        out.append(cur)
    return out


class TileGeo:
    """Local metres <-> degrees for one tile."""
    def __init__(self, s, w):
        self.s, self.w = s, w
        self.ky = 110574.0
        self.kx = 111320.0 * math.cos((s + 0.5) / DEG)

    def to_m(self, p, o):
        return ((p[0] - o[0]) * self.kx, (p[1] - o[1]) * self.ky)

    def to_ll(self, m, o):
        return (o[0] + m[0] / self.kx, o[1] + m[1] / self.ky)

    def clamp(self, p):
        return (min(max(p[0], self.w), self.w + 1), min(max(p[1], self.s), self.s + 1))


def resample(g, line, step, rng):
    """Points every `step` metres along the line (random start), with their direction."""
    o = line[0]
    pts = [g.to_m(p, o) for p in line]
    out, acc, nxt = [], 0.0, step * rng.next()
    for a, b in zip(pts, pts[1:]):
        L = hyp(b[0] - a[0], b[1] - a[1])
        if L == 0:
            continue
        ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        while nxt <= acc + L:
            d = nxt - acc
            out.append(((a[0] + ux * d, a[1] + uy * d), (ux, uy)))
            nxt += step
        acc += L
    return o, out


def ribbon(g, line, half):
    """Closed strip of +-half metres around the line, counter-clockwise (like the simHeaven hedges)."""
    o = line[0]
    pts = [g.to_m(p, o) for p in line]
    q = [pts[0]]
    for p in pts[1:]:
        if hyp(p[0] - q[-1][0], p[1] - q[-1][1]) > 0.3:
            q.append(p)
    if len(q) < 2:
        return None
    n = []
    for a, b in zip(q, q[1:]):
        L = hyp(b[0] - a[0], b[1] - a[1])
        n.append(((b[1] - a[1]) / L, -(b[0] - a[0]) / L))
    left, right = [], []
    for i, p in enumerate(q):
        if i == 0:
            nx, ny = n[0]
        elif i == len(q) - 1:
            nx, ny = n[-1]
        else:
            nx, ny = n[i - 1][0] + n[i][0], n[i - 1][1] + n[i][1]
            L = hyp(nx, ny)
            if L < 1e-6:
                nx, ny = n[i]
            else:
                nx, ny = nx / L, ny / L
                c = nx * n[i][0] + ny * n[i][1]
                f = 1 / max(c, 0.5)
                nx, ny = nx * f, ny * f
        right.append(g.to_ll((p[0] + nx * half, p[1] + ny * half), o))
        left.append(g.to_ll((p[0] - nx * half, p[1] - ny * half), o))
    return right + left[::-1]


# --- DSF reading (simHeaven tile) and writing
def dsf_atoms(b, o, end):
    while o < end:
        aid, ln = struct.unpack_from("<4sI", b, o)
        yield aid[::-1].decode("latin-1"), b[o + 8:o + ln]
        o += ln


def dsf_strings(d):
    return [s.decode("utf-8", "replace") for s in d.split(b"\0")[:-1]]


def dsf_plane(d, o, n):
    enc = d[o]
    o += 1
    vals = []
    if enc in (0, 1):
        vals = list(struct.unpack_from(f"<{n}H", d, o))
        o += 2 * n
    else:
        while len(vals) < n:
            c = d[o]
            o += 1
            if c & 0x80:
                v = struct.unpack_from("<H", d, o)[0]
                o += 2
                vals += [v] * (c & 0x7F)
            else:
                vals += list(struct.unpack_from(f"<{c}H", d, o))
                o += 2 * c
    if enc in (1, 3):
        acc, out = 0, []
        for v in vals:
            acc = (acc + v) & 0xFFFF
            out.append(acc)
        vals = out
    return vals, o


def dsf_read_lines(path, wanted):
    """Forest polygons of the given definitions in a DSF: [(name, param, [(lon, lat), ...]), ...]."""
    b = open(path, "rb").read()
    if b[:8] != b"XPLNEDSF":
        raise RuntimeError(f"not a DSF file (compressed?): {path}")
    top = {}
    for aid, d in dsf_atoms(b, 12, len(b) - 16):
        top.setdefault(aid, []).append(d)
    polyd = []
    for aid, d in dsf_atoms(top["DEFN"][0], 0, len(top["DEFN"][0])):
        if aid == "POLY":
            polyd = dsf_strings(d)
    planes, scal = [], []
    for aid, d in dsf_atoms(top["GEOD"][0], 0, len(top["GEOD"][0])):
        if aid == "POOL":
            n, k = struct.unpack_from("<IB", d)
            o, pl = 5, []
            for _ in range(k):
                v, o = dsf_plane(d, o, n)
                pl.append(v)
            planes.append(pl)
        elif aid == "SCAL":
            scal.append(struct.unpack(f"<{len(d) // 4}f", d))
    pools = []
    for pl, sc in zip(planes, scal):
        pools.append([(pl[0][i] / 65535.0 * sc[0] + sc[1], pl[1][i] / 65535.0 * sc[2] + sc[3]) for i in range(len(pl[0]))])
    out = []
    c = top["CMDS"][0]
    o, pool, defn, n = 0, 0, 0, len(c)
    sizes = {2: 4, 6: 1, 10: 4, 16: 0, 17: 1, 18: 9, 25: 4, 28: 4, 31: 4}

    def add(p, idx):
        if defn < len(polyd) and polyd[defn] in wanted:
            out.append((polyd[defn], p, [pools[pool][i] for i in idx]))
    while o < n:
        cid = c[o]
        o += 1
        if cid == 1:
            pool = struct.unpack_from("<H", c, o)[0]; o += 2
        elif cid == 3:
            defn = c[o]; o += 1
        elif cid == 4:
            defn = struct.unpack_from("<H", c, o)[0]; o += 2
        elif cid == 5:
            defn = struct.unpack_from("<I", c, o)[0]; o += 4
        elif cid == 7:
            o += 2
        elif cid == 8:
            o += 4
        elif cid in (9, 23, 26, 29):
            o += 1 + 2 * c[o]
        elif cid in (11, 24, 27, 30):
            o += 1 + 4 * c[o]
        elif cid == 12:
            p, k = struct.unpack_from("<HB", c, o); o += 3
            add(p, struct.unpack_from(f"<{k}H", c, o)); o += 2 * k
        elif cid == 13:
            p, a, e = struct.unpack_from("<HHH", c, o); o += 6
            add(p, range(a, e))
        elif cid == 14:
            p, w = struct.unpack_from("<HB", c, o); o += 3
            first = None
            for _ in range(w):
                k = c[o]; o += 1
                idx = struct.unpack_from(f"<{k}H", c, o); o += 2 * k
                first = idx if first is None else first
            if first:
                add(p, first)
        elif cid == 15:
            p, w = struct.unpack_from("<HB", c, o); o += 3
            ix = struct.unpack_from(f"<{w + 1}H", c, o); o += 2 * (w + 1)
            add(p, range(ix[0], ix[1]))
        elif cid == 32:
            o += 1 + c[o]
        elif cid == 33:
            o += 2 + struct.unpack_from("<H", c, o)[0]
        elif cid == 34:
            o += 4 + struct.unpack_from("<I", c, o)[0]
        elif cid in sizes:
            o += sizes[cid]
        else:
            raise RuntimeError(f"unknown DSF command {cid} in {path}")
    return out


def dsf_write(path, s, w, defs, feats):
    """Overlay DSF with forest polygons. feats: [(defn index, param, [(lon, lat), ...]), ...]."""
    groups = {}
    for f in feats:
        x, y = f[2][0]
        groups.setdefault((int((x - w) * 16), int((y - s) * 16)), []).append(f)
    pools, cmd = [], bytearray()
    for key in sorted(groups):
        fs, i = groups[key], 0
        while i < len(fs):
            batch, cnt = [], 0
            while i < len(fs) and cnt + len(fs[i][2]) <= 65000:
                batch.append(fs[i])
                cnt += len(fs[i][2])
                i += 1
            xs = [p[0] for f in batch for p in f[2]]
            ys = [p[1] for f in batch for p in f[2]]
            x0, y0 = struct.unpack("<ff", struct.pack("<ff", min(xs), min(ys)))
            sx = max(max(xs) - x0, 1e-6) * 1.000001
            sy = max(max(ys) - y0, 1e-6) * 1.000001
            qx, qy = [], []
            cmd += struct.pack("<BH", 1, len(pools))
            cur = None
            for d, prm, pts in batch:
                if d != cur:
                    cmd += struct.pack("<BB", 3, d)
                    cur = d
                idx = []
                for p in pts:
                    idx.append(len(qx))
                    qx.append(min(65535, max(0, int(math.floor((p[0] - x0) / sx * 65535 + 0.5)))))
                    qy.append(min(65535, max(0, int(math.floor((p[1] - y0) / sy * 65535 + 0.5)))))
                cmd += struct.pack("<BHB", 12, prm, len(idx)) + struct.pack(f"<{len(idx)}H", *idx)
            pools.append((qx, qy, (sx, x0, sy, y0)))

    def atom(aid, payload):
        return struct.pack("<4sI", aid[::-1].encode(), 8 + len(payload)) + payload

    def stab(lst):
        return b"".join(x.encode() + b"\0" for x in lst)
    props = ["sim/planet", "earth", "sim/overlay", "1", "sim/creation_agent", f"XP12 Forest Tweak {VERSION} (hedge overlay, see ATTRIBUTION.txt)",
             "sim/west", str(w), "sim/east", str(w + 1), "sim/north", str(s + 1), "sim/south", str(s)]
    head = atom("HEAD", atom("PROP", stab(props)))
    defn = atom("DEFN", atom("TERT", b"") + atom("OBJT", b"") + atom("POLY", stab(defs)) + atom("NETW", b"") + atom("DEMN", b""))
    geod = b"".join(atom("POOL", struct.pack("<IB", len(qx), 2) + b"\0" + struct.pack(f"<{len(qx)}H", *qx)
                         + b"\0" + struct.pack(f"<{len(qy)}H", *qy)) for qx, qy, _ in pools)
    geod += b"".join(atom("SCAL", struct.pack("<4f", *sc)) for _, _, sc in pools)
    body = b"XPLNEDSF" + struct.pack("<I", 1) + head + defn + atom("GEOD", geod) + atom("CMDS", bytes(cmd))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    write_bytes(path, body + hashlib.md5(body).digest())
    return sum(len(p[0]) for p in pools)


def sh_ini_place(xp):
    """Lists the hedgerow map above all simHeaven X-World packs: their forest exclusions would hide it otherwise."""
    lines, nl = ini_read(xp)
    if lines is None:
        return False
    mine = f"SCENERY_PACK Custom Scenery/{SH_DIR}/"
    rest = [l for l in lines if not pack_line_is(l, SH_DIR)]
    i = next((k for k, l in enumerate(rest) if re.search(r"(?i)^SCENERY_PACK(_DISABLED)?\s+(.*[/\\])?simHeaven_X-World(_|-Pro_(?!Library|Add-ons))", l)), None)
    if i is None:
        i = next((k for k, l in enumerate(rest) if pack_line_is(l, KNICK_DIR)), None)
    if i is None:
        i = next((k for k, l in enumerate(rest) if l.startswith("SCENERY_PACK")), len(rest))
    new = rest[:i] + [mine] + rest[i:]
    if new == lines:
        return False
    ini_write(xp, new, nl)
    return True


def sh_remove(xp):
    d = sh_pack(xp)
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d, topdown=False):
            for n in files:
                if n.endswith(".dsf") or n in ("ATTRIBUTION.txt", "hedgerow_map.txt") or n.endswith(".tmp") or n.endswith(".fdt_tmp"):
                    os.remove(os.path.join(root, n))
            if root != d:
                try:
                    os.rmdir(root)
                except OSError:
                    pass
        try:
            os.rmdir(d)
        except OSError:
            warn(f"  Folder Custom Scenery/{SH_DIR} has other files in it and was left in place.")
    lines, nl = ini_read(xp)
    if lines is not None and any(pack_line_is(l, SH_DIR) for l in lines):
        ini_write(xp, [l for l in lines if not pack_line_is(l, SH_DIR)], nl)
    tlog("hedgerow map: removed")


# ---------------------------------------------------------------- hedge overlay (1.5.1)
# The tool turns hedges and tree rows into X-Plane forests in its own scenery pack (SH_DIR), built on this
# computer. Sources, in this order:
#   1. official hedge maps that come with the tool (hedgerow_map_*.dat, see DATA_LICENSES.txt)
#   2. the simHeaven hedges and tree rows of this computer (free X-World or X-WORLD Pro), only where the
#      official maps have nothing nearby. They are hidden in the built tiles by the tool's library.
# simHeaven X-WORLD Pro draws hedges as walls (facades), which can not become forests through a library, so
# with Pro the hedges of the chosen countries are rebuilt here. Nothing of simHeaven is shipped.
HM_FILES = (
    ("sh", "hedgerow_map_sh.dat", "Schleswig-Holstein",
     "LLUR SH, Biotopkartierung SH4 (Alleen, Knicks, Feldhecken, Baumreihen, 2023), CC BY 4.0", SH_URL),
    ("ni", "hedgerow_map_ni.dat", "Niedersachsen, Bremen, Hamburg",
     "(c) ML/SLA Niedersachsen/CC BY 4.0 - Landschaftselemente in Niedersachsen, Bremen und Hamburg",
     "https://inspire-geoportal.ec.europa.eu/srv/api/records/c0f447eb-151b-42a7-bdd0-e99b1062f67c"),
    ("nrw", "hedgerow_map_nrw.dat", "Nordrhein-Westfalen",
     "Land NRW - Landschaftselemente in NRW (2026-11-07), dl-de/by-2-0 (www.govdata.de/dl-de/by-2-0)",
     "https://ckan.open.nrw.de/dataset/landschaftselemente-in-nrw-geo-nrw"),
    ("by", "hedgerow_map_by.dat", "Bayern",
     "Bayerisches Staatsministerium fuer Ernaehrung, Landwirtschaft, Forsten und Tourismus - InVeKoS Landschaftselemente, CC BY 4.0",
     "https://gdk.gdi-de.org/geonetwork/srv/api/records/2bf51905-de03-4a56-93c4-1bea034b3a4d"),
    ("bb", "hedgerow_map_bb.dat", "Brandenburg",
     "(c) Ministerium fuer Land- und Ernaehrungswirtschaft, Umwelt und Verbraucherschutz - InVeKoS Landschaftselemente BB (2026-11-07), dl-de/by-2-0 (www.govdata.de/dl-de/by-2-0)",
     "https://gdk.gdi-de.org/geonetwork/srv/api/records/72ed0323-7f32-400f-8bc1-7f0bb6cb83ba"),
    ("dk", "hedgerow_map_dk.dat", "Denmark",
     "Slots- og Kulturstyrelsen - Beskyttede sten- og jorddiger, CC0 1.0",
     "https://arealdata.miljoeportal.dk/datasets/urn:dmp:ds:beskyttede-sten-og-jorddiger"))
HM_CODES = ("HW", "HF", "HR", "HA", "AH", "AR", "AC")   # lines: Knick/hedge, field hedge, tree row, avenue;
#                                                         areas: hedge, tree row, copse
HM_VPATH_HEDGE = "xp12_foresttweak/hedge_map.for"
PRO_HEDGE_FAC = ("simheaven/ground/hedge_low.fac", "simheaven/ground/hedge_high.fac")
PRO_HEDGE_FOR = ("simheaven/ground/hedge_low.for", "simheaven/ground/hedge_high.for")
ROW_VPATH = "simheaven/forests/random_tree.for"
BLANK_FAC = "A\r\n800\r\nFACADE\r\n"
# Countries for X-WORLD Pro: whole 1x1 degree tiles {south: (west from, west to)}; border tiles belong to both
COUNTRIES = (("de", "Germany", {47: (7, 13), 48: (7, 13), 49: (6, 13), 50: (5, 14), 51: (5, 14), 52: (6, 14),
                                53: (6, 14), 54: (8, 14), 55: (8, 8)}),
             ("dk", "Denmark", {54: (8, 12), 55: (8, 15), 56: (8, 12), 57: (8, 11)}),
             ("bnl", "Benelux", {49: (5, 6), 50: (2, 6), 51: (2, 6), 52: (3, 7), 53: (4, 7)}),
             ("at", "Austria", {46: (9, 16), 47: (9, 17), 48: (12, 17)}),
             ("ch", "Switzerland", {45: (8, 9), 46: (5, 10), 47: (5, 10)}))
CHOICE_NAMES = {"default": "original", "enhanced": "enhanced", "Knicks": "hedgebanks (Knicks)"}


def rects_tiles(rects):
    out = set()
    for r in rects:
        w0, s0, w1, s1 = (int(v) for v in r.split())
        out |= {(s, w) for s in range(s0, s1 + 1) for w in range(w0, w1 + 1)}
    return out


KNICK_TILES = rects_tiles(KNICK_RECTS)


def tiles_rects(tiles):
    """Tiles -> REGION_RECT lines "west south east north", one run per row of tiles."""
    out = []
    for s in sorted({t[0] for t in tiles}):
        ws = sorted(w for (ss, w) in tiles if ss == s)
        a = b = ws[0]
        for w in ws[1:] + [None]:
            if w is not None and w == b + 1:
                b = w
                continue
            out.append(f"{a} {s} {b} {s}")
            if w is not None:
                a = b = w
    return out


def tile_rel(s, w):
    return "%+03d%+04d" % (s // 10 * 10, w // 10 * 10), "%+03d%+04d.dsf" % (s, w)


def hm_file(name):
    here = os.path.dirname(os.path.abspath(__file__))
    for d in (here, os.path.dirname(here), os.path.join(os.path.dirname(here), "data"), os.path.join(here, "data")):
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return p
    return None


def hm_read(path):
    """One hedge map file -> {tile: [(code, ints), ...]}; ints = E, N pairs in 0.1 m (EPSG 4647)."""
    b = gzip.decompress(open(path, "rb").read())
    if b[:8] != b"XFTHMAP1":
        raise RuntimeError(f"hedge map: unknown file format: {os.path.basename(path)}")
    nl = struct.unpack_from("<I", b, 8)[0]
    tiles = {}
    o = 16
    for _ in range(nl):
        code = HM_CODES[b[o]]
        n, o = _varint(b, o + 1)
        e = nn = 0
        ints = array("i")
        for _k in range(n):
            de, o = _varint(b, o)
            dn, o = _varint(b, o)
            e += (de >> 1) ^ -(de & 1)
            nn += (dn >> 1) ^ -(dn & 1)
            ints.append(e)
            ints.append(nn)
        xs, ys = ints[0::2], ints[1::2]
        lons, lats = [], []
        for ce in (min(xs), max(xs)):
            for cn in (min(ys), max(ys)):
                lo, la = utm32_to_ll(ce / 10.0, cn / 10.0)
                lons.append(lo)
                lats.append(la)
        for s in range(int(math.floor(min(lats))), int(math.floor(max(lats))) + 1):
            for w in range(int(math.floor(min(lons))), int(math.floor(max(lons))) + 1):
                tiles.setdefault((s, w), []).append((code, ints))
    return tiles


_HM_CACHE = {}


def hm_data(only=None):
    """All hedge maps that come with the tool: ({tile: [(code, ints)]}, [keys of the files found])."""
    if "all" in _HM_CACHE and only is None:
        return _HM_CACHE["all"]
    tiles, found = {}, []
    for key, name, _region, _att, _url in HM_FILES:
        p = hm_file(name)
        if not p or (only is not None and key not in only):
            continue
        found.append(key)
        for t, recs in hm_read(p).items():
            tiles.setdefault(t, []).extend(recs)
    if only is None:
        _HM_CACHE["all"] = (tiles, found)
    return tiles, found


def to_ll(ints):
    return [utm32_to_ll(ints[i] / 10.0, ints[i + 1] / 10.0) for i in range(0, len(ints), 2)]


def clip_poly(pts, w, s):
    """Polygon clipped to the tile [w, w+1] x [s, s+1] (Sutherland-Hodgman)."""
    def cut(poly, inside, inter):
        out = []
        for i in range(len(poly)):
            a, b = poly[i - 1], poly[i]
            ia, ib = inside(a), inside(b)
            if ib:
                if not ia:
                    out.append(inter(a, b))
                out.append(b)
            elif ia:
                out.append(inter(a, b))
        return out

    def ix(a, b, x):
        t = (x - a[0]) / (b[0] - a[0])
        return (x, a[1] + t * (b[1] - a[1]))

    def iy(a, b, y):
        t = (y - a[1]) / (b[1] - a[1])
        return (a[0] + t * (b[0] - a[0]), y)
    p = list(pts)
    for inside, inter in ((lambda q: q[0] >= w, lambda a, b: ix(a, b, w)), (lambda q: q[0] <= w + 1, lambda a, b: ix(a, b, w + 1)),
                          (lambda q: q[1] >= s, lambda a, b: iy(a, b, s)), (lambda q: q[1] <= s + 1, lambda a, b: iy(a, b, s + 1))):
        if not p:
            break
        p = cut(p, inside, inter)
    return p


def area_ring(pts, w, s):
    """Closed outline -> counter-clockwise ring inside the tile with at most 255 points, or None."""
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    if len(pts) < 3:
        return None
    if min(p[0] for p in pts) < w or max(p[0] for p in pts) > w + 1 or min(p[1] for p in pts) < s or max(p[1] for p in pts) > s + 1:
        pts = clip_poly(pts, w, s)
        if len(pts) < 3:
            return None
    a = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i - 1]
        x1, y1 = pts[i]
        a += x0 * y1 - x1 * y0
    if a < 0:
        pts = pts[::-1]
    while len(pts) > 255:
        pts = pts[::2]
    return [(min(max(p[0], w), w + 1), min(max(p[1], s), s + 1)) for p in pts]


# ---- simHeaven on this computer
def ini_packs(xp, lines):
    """scenery_packs.ini lines -> [(enabled, full path, folder name)]; packs may be listed as
    'Custom Scenery/...' or with an absolute path (e.g. on another drive)."""
    out = []
    for l in lines or []:
        m = re.match(r"(?i)^SCENERY_PACK(_DISABLED)?\s+(.+?)\s*$", l)
        if not m:
            continue
        p = m.group(2).rstrip("/\\")
        full = p if (os.path.isabs(p) or re.match(r"^[A-Za-z]:", p)) else os.path.join(xp, p)
        out.append((not m.group(1), full, re.split(r"[/\\]", p)[-1]))
    return out


def hm_sources(xp):
    """Enabled simHeaven packs with hedges, in scenery_packs.ini order: [(kind, dir with hedges, dir with tree rows, region)]."""
    lines, _nl = ini_read(xp)
    packs = ini_packs(xp, lines)
    by_name = {n.lower(): f for _on, f, n in packs}
    out = []
    for on, full, name in packs:
        if not on:
            continue
        m = re.match(r"(?i)^simHeaven_X-WORLD-Pro_(.+?)-06-extras1$", name)
        if m:
            n2 = name[:-len("06-extras1")] + "07-extras2"
            out.append(("pro", full, by_name.get(n2.lower(), os.path.join(os.path.dirname(full), n2)), m.group(1)))
            continue
        m = re.match(r"(?i)^simHeaven_X-World_(.+?)-4-extras$", name)
        if m:
            out.append(("free", full, full, m.group(1)))
    return out


def hm_count_tiles(d):
    base = os.path.join(d, "Earth nav data")
    n = 0
    if os.path.isdir(base):
        for sub in os.listdir(base):
            p = os.path.join(base, sub)
            if os.path.isdir(p):
                n += sum(1 for x in os.listdir(p) if x.lower().endswith(".dsf"))
    return n


def hm_source_report(xp):
    """One line per simHeaven pack the hedges are read from (for Status and tool.log)."""
    return [f"{'X-WORLD Pro' if k == 'pro' else 'X-World free'} {r}: {d} ({hm_count_tiles(d)} tiles)"
            + ("" if k == "free" or os.path.isdir(d2) else ", tree rows pack not found")
            for k, d, d2, r in hm_sources(xp)]


def hm_detect(xp):
    """{'pro': [regions], 'free': [regions], 'both': [regions with free and Pro on]}"""
    src = hm_sources(xp)
    pro = sorted({r for k, _a, _b, r in src if k == "pro"})
    free = sorted({r for k, _a, _b, r in src if k == "free"})
    both = [r for r in pro if r.lower() in [f.lower() for f in free]]
    return {"pro": pro, "free": free, "both": both}


def hm_pro_tiles(xp):
    """Tiles with X-WORLD Pro hedges on this computer."""
    out = set()
    for kind, d, _d2, _r in hm_sources(xp):
        if kind != "pro":
            continue
        base = os.path.join(d, "Earth nav data")
        if not os.path.isdir(base):
            continue
        for sub in os.listdir(base):
            p = os.path.join(base, sub)
            if os.path.isdir(p):
                for n in os.listdir(p):
                    m = re.match(r"^([+-]\d\d)([+-]\d\d\d)\.dsf$", n)
                    if m:
                        out.add((int(m.group(1)), int(m.group(2))))
    return out


def hm_tile_source(srcs, s, w):
    """The simHeaven DSF files of one tile from the first enabled pack that has them."""
    sub, name = tile_rel(s, w)
    for kind, d, d2, _r in srcs:
        p = os.path.join(d, "Earth nav data", sub, name)
        if os.path.isfile(p):
            p2 = os.path.join(d2, "Earth nav data", sub, name)
            return kind, p, (p2 if os.path.isfile(p2) else None)
    return None, None, None


def country_tiles(key):
    for k, _n, rows in COUNTRIES:
        if k == key:
            return {(s, w) for s, (a, b) in rows.items() for w in range(a, b + 1)}
    return set()


# ---- building
def hm_build_tile(xp, s, w, recs, srcs, knick, path):
    """One DSF tile. Returns (features from the official maps, simHeaven features taken over, source signature)."""
    g = TileGeo(s, w)
    rng = Lcg(s * 1000 + w)
    feats = []
    n_map = 0
    lines = {c: [] for c in HM_CODES}
    for code, ints in recs:
        lines[code].append(ints)
    kind, p1, p2 = hm_tile_source(srcs, s, w)
    sig = []
    for p in (p1, p2):
        if p:
            stt = os.stat(p)
            sig.append(f"{os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(p))))}:{stt.st_size}:{int(stt.st_mtime)}")
    # simHeaven tree rows (for the check below and for Knick tiles)
    src_rows = []
    if kind:
        src_rows = dsf_read_lines(p2 if kind == "pro" else p1, (ROW_VPATH,)) if (p2 or kind == "free") else []
    row_cells = set()
    if not knick:
        for _n, _p, pts in src_rows:
            for p in pts:
                row_cells.add((int(math.floor((p[0] - w) * g.kx / SH_DUP_CELL)), int(math.floor((p[1] - s) * g.ky / SH_DUP_CELL))))

    def near_rows(pts):
        if not row_cells:
            return False
        hit = 0
        for p in pts:
            cx = int(math.floor((p[0] - w) * g.kx / SH_DUP_CELL))
            cy = int(math.floor((p[1] - s) * g.ky / SH_DUP_CELL))
            if any((cx + i, cy + j) in row_cells for i in (-1, 0, 1) for j in (-1, 0, 1)):
                hit += 1
        return hit * 2 >= len(pts)
    # official maps
    for code in ("HW", "HF"):
        for ints in lines[code]:
            for piece in clip_line(to_ll(ints), w, s):
                for i in range(0, len(piece) - 1, 99):
                    r = ribbon(g, piece[i:i + 100], SH_HALF_WIDTH)
                    if r:
                        feats.append((0, P_AREA, [g.clamp(p) for p in r]))
                        n_map += 1
    for code in ("HR", "HA"):
        offs = (0.0,) if code == "HR" else (-SH_AVENUE_OFF, SH_AVENUE_OFF)
        step = SH_ROW_STEP if code == "HR" else SH_AVENUE_STEP
        for ints in lines[code]:
            for piece in clip_line(to_ll(ints), w, s):
                if near_rows(piece):
                    continue
                for off in offs:
                    o, pts = resample(g, piece, step, rng)
                    ll = []
                    for (px, py), (ux, uy) in pts:
                        jx = rng.next() - 0.5
                        jy = rng.next() - 0.5
                        ll.append(g.clamp(g.to_ll((px + uy * off + jx, py - ux * off + jy), o)))
                    for i in range(0, len(ll), 250):
                        feats.append((1, P_POINT, ll[i:i + 250]))
                        n_map += 1
    for code, d in (("AH", 0), ("AR", 1), ("AC", 1)):
        for ints in lines[code]:
            ll = to_ll(ints)
            if d == 1 and near_rows(ll):
                continue
            r = area_ring(ll, w, s)
            if r:
                feats.append((d, P_AREA, r))
                n_map += 1
    # where the official maps have something: 20 m cells along every line and outline
    cov = set()
    for code in HM_CODES:
        for ints in lines[code]:
            ll = to_ll(ints)
            if code[0] == "A":
                ll = ll + ll[:1]
            o, pts = resample(g, ll, 10.0, Lcg(0))
            for p, _u in pts:
                q = g.to_ll(p, o)
                cov.add((int(math.floor((q[0] - w) * g.kx / SH_DUP_CELL)), int(math.floor((q[1] - s) * g.ky / SH_DUP_CELL))))

    def covered(p):
        cx = int(math.floor((p[0] - w) * g.kx / SH_DUP_CELL))
        cy = int(math.floor((p[1] - s) * g.ky / SH_DUP_CELL))
        return any((cx + i, cy + j) in cov for i in (-1, 0, 1) for j in (-1, 0, 1))
    kept = 0
    if kind:
        hedges = dsf_read_lines(p1, (PRO_HEDGE_FAC + PRO_HEDGE_FOR) if kind == "pro" else (HEDGE_VPATH,))
        for name, prm, pts in hedges:
            if not pts or sum(1 for p in pts if covered(p)) * 2 >= len(pts):
                continue
            if name.endswith(".fac"):                 # X-WORLD Pro hedge wall -> strip of bushes
                for i in range(0, len(pts) - 1, 99):
                    r = ribbon(g, pts[i:i + 100], SH_HALF_WIDTH)
                    if r:
                        feats.append((0, P_AREA, [g.clamp(p) for p in r]))
            else:                                      # hedge area (free X-World strips, Pro hedge areas)
                while len(pts) > 255:
                    pts = pts[::2]
                feats.append((0, prm if prm < 512 else P_AREA, pts))
            kept += 1
        if knick:
            for _name, prm, pts in src_rows:
                if not pts or sum(1 for p in pts if covered(p)) * 2 >= len(pts):
                    continue
                if prm >= 512:
                    for i in range(0, len(pts), 250):
                        feats.append((1, prm, pts[i:i + 250]))
                else:
                    while len(pts) > 255:
                        pts = pts[::2]
                    feats.append((1, prm, pts))
                kept += 1
    dsf_write(path, s, w, [SH_VPATH_KNICK if knick else HM_VPATH_HEDGE, SH_VPATH_ROW], feats)
    return n_map, kept, ";".join(sig)


def hm_info(xp):
    """Settings of the built overlay: {'choice', 'countries', 'tiles': {tile: signature}} or None."""
    try:
        with open(os.path.join(sh_pack(xp), "hedgerow_map.txt"), encoding="latin-1") as f:
            text = f.read()
    except OSError:
        return None
    if not text.startswith(SH_MARK):
        return None
    out = {"choice": "Knicks", "countries": [], "tiles": {}, "version": "", "incomplete": False}
    for l in text.splitlines():
        tok = l.split()
        if l.startswith(SH_MARK) and len(tok) > 6:
            out["version"] = tok[6]
        elif tok[:1] == ["choice"] and len(tok) > 1:
            out["choice"] = tok[1]
        elif tok[:1] == ["countries"]:
            out["countries"] = tok[1:]
        elif tok[:1] == ["incomplete"]:
            out["incomplete"] = True
        elif tok[:1] == ["tile"] and len(tok) >= 3:
            out["tiles"][(int(tok[1]), int(tok[2]))] = tok[3] if len(tok) > 3 else ""
    return out


def hm_plan(xp, choice, countries):
    """Tiles to build: all tiles of the official maps, with X-WORLD Pro also its tiles in the Knick areas
    (for hedgebanks) and in the chosen countries."""
    data_tiles = set(hm_data()[0])
    pro = hm_pro_tiles(xp)
    want = set()
    if choice == "Knicks":
        want |= KNICK_TILES
    for c in countries:
        want |= (pro if c == "all" else country_tiles(c))
    return data_tiles | (pro & want), data_tiles


def _hm_job(job):
    xp, s, w, recs, srcs, knick, path = job
    return (s, w) + tuple(hm_build_tile(xp, s, w, recs, srcs, knick, path))


def hm_write_info(d, choice, countries, tiles, sigs, done):
    """hedgerow_map.txt: settings and built tiles. While building it is marked incomplete and lists only the
    tiles finished so far, so an interrupted build goes on where it stopped."""
    info = [f"{SH_MARK} {VERSION} - do not edit", f"choice {choice}", "countries " + " ".join(countries)]
    if not done:
        info.append("incomplete")
    info += [f"tile {s} {w} {sigs.get((s, w), '')}" for (s, w) in tiles if done or (s, w) in sigs]
    write_bytes(os.path.join(d, "hedgerow_map.txt"), ("\r\n".join(info) + "\r\n").encode("ascii"))


def hm_build(xp, choice, countries, only=None, lib=None):
    """Builds the hedge overlay. only: tiles to rebuild (None = all; tiles not built yet are always built).
    lib: (height, profile) - the tweak library is written before the tiles, so X-Plane always finds the
    hedge types, even if the build is interrupted. Returns the set of built tiles."""
    t0 = time.time()
    d = sh_pack(xp)
    os.makedirs(d, exist_ok=True)
    say("  Reading the hedge maps ...")
    data, found = hm_data()
    srcs = hm_sources(xp)
    tiles = sorted(hm_plan(xp, choice, countries)[0])
    info0 = hm_info(xp) or {}
    old = info0.get("tiles", {}) if info0.get("version") == VERSION and info0.get("choice") == choice else {}
    # remove tiles that are not wanted any more (also those of older versions)
    keep = {tile_rel(s, w)[1] for (s, w) in tiles}
    for root, _dirs, names in os.walk(os.path.join(d, "Earth nav data")):
        for n in names:
            if n.endswith(".dsf") and n not in keep:
                os.remove(os.path.join(root, n))
    tset = set(tiles)
    sigs = {t: v for t, v in old.items() if t in tset}
    todo = [t for t in tiles if only is None or t in only or t not in old]
    for t in todo:
        sigs.pop(t, None)
    hm_write_info(d, choice, countries, tiles, sigs, False)
    if lib:
        knick_write(xp, lib[0], lib[1], kmap=True, built=tset, choice=choice)
    sh_ini_place(xp)
    total = kept_all = 0
    jobs = ((xp, s, w, data.get((s, w), []), srcs, choice == "Knicks" and (s, w) in KNICK_TILES,
             os.path.join(d, "Earth nav data", *tile_rel(s, w))) for (s, w) in todo)
    pr = Progress("Hedge tiles", len(todo))
    pool = None
    last = time.time()
    try:
        if workers() > 1 and len(todo) > 8:
            try:
                pool = multiprocessing.Pool(workers(), initializer=_worker_init)
                results = pool.imap_unordered(_hm_job, jobs, chunksize=1)
            except (OSError, ImportError, ValueError):
                pool = None
        if pool is None:
            results = map(_hm_job, jobs)
        for i, (s, w, n_map, kept, sig) in enumerate(results, 1):
            pr.update(i, i, len(todo))
            sigs[(s, w)] = sig
            total += n_map
            kept_all += kept
            if time.time() - last > 10:
                hm_write_info(d, choice, countries, tiles, sigs, False)
                last = time.time()
    except KeyboardInterrupt:
        if pool:
            pool.terminate()
            pool.join()
            pool = None
        pr.end()
        hm_write_info(d, choice, countries, tiles, sigs, False)
        tlog(f"hedge overlay: stopped after {len(sigs)} of {len(tiles)} tiles")
        raise
    finally:
        if pool:
            pool.close()
            pool.join()
    pr.end()
    for sub in os.listdir(os.path.join(d, "Earth nav data")) if os.path.isdir(os.path.join(d, "Earth nav data")) else []:
        p = os.path.join(d, "Earth nav data", sub)
        if os.path.isdir(p) and not os.listdir(p):
            os.rmdir(p)
    att = ["XP12 Forest Tweak - hedge overlay (made on this computer)", "",
           "Hedges, hedgebanks (Knicks), tree rows and copses from official maps (changed: only outlines and type",
           "kept, compact format, turned into X-Plane forest strips and tree rows, cut into 1x1 degree tiles):"]
    for key, _name, region, attrib, url in HM_FILES:
        if key in found:
            att += [f"  {region}: {attrib}", f"    {url}"]
    att += ["", "Hedges and tree rows where the maps have none: taken over from the simHeaven scenery on this",
            "computer (OpenStreetMap data, (c) OpenStreetMap contributors, ODbL).",
            "The data providers do not endorse this project.",
            "Made for use on this computer only - do not share this folder.", "",
            "Restore original in XP12 Forest Tweak removes this folder."]
    write_bytes(os.path.join(d, "ATTRIBUTION.txt"), ("\r\n".join(att) + "\r\n").encode("ascii"))
    hm_write_info(d, choice, countries, tiles, sigs, True)
    sh_ini_place(xp)
    tlog(f"hedge overlay: {len(todo)} of {len(tiles)} tiles built, {total} map features, {kept_all} simHeaven features ({took(t0)})")
    say(f"  Hedge overlay: {len(tiles)} tiles, {total} features from the hedge maps ({took(t0)})", C_GREEN)
    return set(tiles)


def start_offers(xp, targets, st):
    """After an update: offers to put the tweak back at once (same settings), instead of only a hint."""
    if switched_off(xp) or xplane_running():
        return
    if st["n"] and st["n_reset"]:
        say()
        if ask_yes(f"  An update reset {st['n_reset']} forest files. Tweak them again now (same settings)? [Y/n] "):
            apply_values(xp, targets, st["x"], st["h"], st["hp"])
            _ST_CACHE[0] = None
    if hedge_hint(xp):
        say()
        if ask_yes("  Bring the hedges up to date now? [Y/n] "):
            repair_hedges(xp)
            say("  Hedges are up to date.", C_GREEN)


def hedge_hint(xp):
    """Short note when the hedge overlay needs Check & repair (interrupted build, simHeaven changed), else ''."""
    if not knick_info(xp)[0]:
        return ""
    info = hm_info(xp)
    if not info:
        return ""
    if info.get("version") != VERSION:
        return "built with an older version - run Check & repair [4] to update them"
    if info.get("incomplete"):
        return "building was interrupted - run Check & repair [4] to finish it"
    ch = hm_changed(xp)
    if ch:
        return f"simHeaven changed since they were built ({len(ch)} tiles) - run Check & repair [4]"
    return ""


def hm_changed(xp):
    """Tiles whose simHeaven source changed since they were built (e.g. after a simHeaven update)."""
    info = hm_info(xp)
    if not info:
        return set()
    srcs = hm_sources(xp)
    out = set()
    for (s, w), sig in info["tiles"].items():
        kind, p1, p2 = hm_tile_source(srcs, s, w)
        now = []
        for p in (p1, p2):
            if p:
                stt = os.stat(p)
                now.append(f"{os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(p))))}:{stt.st_size}:{int(stt.st_mtime)}")
        if ";".join(now) != sig:
            out.add((s, w))
    return out


def hedge_choice_state(xp, hstate):
    """Current hedge choice: 'default', 'enhanced' or 'Knicks'."""
    k_on = knick_info(xp)[0]
    if k_on:
        lib = ""
        try:
            with open(os.path.join(knick_path(xp), "library.txt"), encoding="latin-1") as f:
                lib = f.read(2000)
        except OSError:
            pass
        m = re.search(r"\|\s*choice\s+(\w+)", lib)
        return m.group(1) if m else "Knicks"
    return hstate or "default"


# ---------------------------------------------------------------- [1] choose settings
def ask_spacing(current, tweaked):
    say("  Step 1/3  Tree spacing")
    say("  Lower = closer trees = denser forest.")
    say()
    for i, (name, v, note) in enumerate(PRESETS, 1):
        say(f"    [{i}] {name:<11} {v:<4}  {note}")
    say(f"    [4] Custom      {fmt(MIN_FAC)} - 1.0")
    say()
    cur_choice = next((str(i) for i, p in enumerate(PRESETS, 1) if p[1] == current), None)
    if not tweaked:
        cur_choice, current = "2", DEFAULT_FAC
    hint = f"Enter = {cur_choice}" if cur_choice else f"Enter = keep {fmt(current)}"
    while True:
        a = input(f"  Choose ({hint}): ").strip()
        if a == "":
            return current
        if a in ("1", "2", "3"):
            return PRESETS[int(a) - 1][1]
        if a == "4":
            return ask_value(MIN_FAC, current, "tree spacing")
        v = parse_value(a, MIN_FAC)      # a value typed directly is fine too
        if v is not None:
            return v
        warn("  Please choose 1, 2, 3 or 4.")


def ask_height(current, tweaked):
    say("  Step 2/3  Tree height")
    say("  Lower = smaller trees. Conifers shrink a bit less. 3D tree models included.")
    say()
    for i, (name, v, _note) in enumerate(HEIGHT_PRESETS, 1):
        say(f"    [{i}] {name:<16} {v:<4.1f}")
    n = len(HEIGHT_PRESETS) + 1
    say(f"    [{n}] Custom           {fmt(MIN_HEIGHT)} - 1.0")
    say()
    if not tweaked:
        current = DEFAULT_HEIGHT
    cur_choice = next((str(i) for i, p in enumerate(HEIGHT_PRESETS, 1) if p[1] == current), None)
    hint = f"Enter = {cur_choice}" if cur_choice else f"Enter = keep {fmt(current)}"
    while True:
        a = input(f"  Choose ({hint}): ").strip()
        if a == "":
            return current
        if a.isdigit() and 1 <= int(a) < n:
            return HEIGHT_PRESETS[int(a) - 1][1]
        if a == str(n):
            return ask_value(MIN_HEIGHT, current, "tree height")
        v = parse_value(a, MIN_HEIGHT)      # a value typed directly is fine too
        if v is not None:
            return v
        warn(f"  Please choose a number from 1 to {n}.")


def ask_hedges(current):
    say("  Step 3/3  Hedges")
    say("  How hedges and tree rows look. Official hedge maps add missing hedges.")
    say()
    say("    [1] Original     as simHeaven made them")
    say("    [2] Enhanced     taller, greener hedges (4 - 5 m)")
    say("    [3] Hedgebanks   Northern Germany and Denmark: bushes on earth banks")
    say("        (Knicks)     with single hedgerow trees. Elsewhere: [2]")
    say()
    cur = {"Knicks": "3", "enhanced": "2"}.get(current, "1")
    while True:
        a = input(f"  Choose (Enter = {cur}): ").strip() or cur
        v = {"1": "default", "2": "enhanced", "3": "Knicks"}.get(a)
        if v:
            return v
        warn("  Please choose 1, 2 or 3.")


def pro_countries(xp):
    """[(key, name, tiles)] of the countries with X-WORLD Pro tiles on this computer."""
    pro = hm_pro_tiles(xp)
    opts = [(k, n, len(pro & country_tiles(k))) for k, n, _r in COUNTRIES]
    return [o for o in opts if o[2]]


def ask_countries(xp, current):
    pro = hm_pro_tiles(xp)
    opts = pro_countries(xp)
    say()
    say("  Countries - X-WORLD Pro hedges are rebuilt here (Knick areas always):")
    say()
    for i, (k, n, cnt) in enumerate(opts, 1):
        say(f"    [{i}] {n:<12} {cnt:>4} tiles")
    say(f"    [A] all X-WORLD Pro tiles on this computer  {len(pro):>4} tiles")
    say()
    cur = current or [o[0] for o in opts]      # first time: all countries with Pro tiles
    if "all" in cur:
        hint = "A"
    else:
        hint = ",".join(str(i) for i, o in enumerate(opts, 1) if o[0] in cur) or "none"
    while True:
        a = input(f"  Choose, e.g. 1,2,5 (Enter = {hint}): ").strip().lower()
        if a == "":
            return list(cur)
        if a == "a":
            return ["all"]
        parts = [p for p in re.split(r"[ ,;]+", a) if p]
        if parts and all(p.isdigit() and 1 <= int(p) <= len(opts) for p in parts):
            return [opts[int(p) - 1][0] for p in sorted(set(parts), key=int)]
        warn(f"  Please type numbers from 1 to {len(opts)} (e.g. 1,2) or A.")


def offer_free_off(xp, det):
    """Free X-World and X-WORLD Pro both on for the same region -> offer to turn the free packs off."""
    if not det["both"]:
        return det
    regions = ", ".join(det["both"])
    say()
    warn(f"  simHeaven X-World (free) and X-WORLD Pro are both on for {regions}.")
    warn("  This shows buildings, forests and roads twice.")
    say()
    if not ask_yes("  Turn off the free packs of these regions in scenery_packs.ini? (backup kept) [Y/n] "):
        return det
    lines, nl = ini_read(xp)
    low = [r.lower() for r in det["both"]]
    new = []
    for l in lines:
        m = re.match(r"(?i)^SCENERY_PACK\s+((?:.*[/\\])?simHeaven_X-World_(.+?)-\d-[^/\\]+[/\\]?)\s*$", l)
        if m and m.group(2).lower() in low:
            l = "SCENERY_PACK_DISABLED " + m.group(1)
        new.append(l)
    ini_write(xp, new, nl)
    tlog(f"free X-World turned off for {regions}")
    say(f"  Free X-World turned off for {regions}.", C_GREEN)
    return hm_detect(xp)


def choose_settings(xp, targets, quick=False):
    """quick: recommended settings without the three steps (tree spacing 0.7, height 0.7, hedgebanks,
    with X-WORLD Pro all countries that have Pro tiles); the summary is still shown for confirmation."""
    if blocked_by_xplane():
        return
    was_off = switched_off(xp)
    ensure_tweak_active(xp, targets)
    # state read at the start (or by Status) is still valid when nothing was changed since then
    st = _ST_CACHE[0]
    if was_off or not st:
        st = forest_state(xp, targets)
    tweaked = st["n"] > 0
    cur_x, cur_h, cur_hp = st["x"], st["h"], st["hp"]
    hfiles, hstate, hlog = hedge_overview(xp)
    k_on, k_h, k_hp = knick_info(xp)
    det = offer_free_off(xp, hm_detect(xp))
    has_sh = bool(hfiles or det["pro"] or det["free"])
    hchoice = hedge_choice_state(xp, hstate) if has_sh else "default"
    info = hm_info(xp)
    cur_c = info["countries"] if info else []
    has_gf = any(rel(xp, t).startswith("Custom Scenery/") for t in targets)
    want_h, want_c = hchoice, cur_c
    if quick:
        say()
        say("  Recommended setup: tree spacing 0.7, tree height 0.7 (realistic)"
            + (", hedgebanks (Knicks)" if has_sh else ""))
        fac, hf = DEFAULT_FAC, DEFAULT_HEIGHT
        if has_sh:
            want_h = "Knicks"
            if det["pro"]:
                want_c = [o[0] for o in pro_countries(xp)]
    else:
        say()
        say("  Nothing is changed until you confirm at the end.")
        say()
        say()
        fac = ask_spacing(cur_x, tweaked)
        say()
        say()
        hf = ask_height(cur_h, tweaked)
        say()
        say()
        if has_sh:
            want_h = ask_hedges(hchoice)
            if det["pro"] and want_h != "default":
                want_c = ask_countries(xp, cur_c)
        else:
            say("  Step 3/3  Hedges   skipped - simHeaven X-World not installed")
    hp = "realistic" if hf < 1.0 else "uniform"
    # summary
    same = (fac, hf, hp) == (cur_x, cur_h, cur_hp) or (fac, hf) == (cur_x, cur_h) == (1.0, 1.0)
    rebuild = tweaked and (not same or st["n_old"] > 0)       # restore first, then apply the new values
    refresh = tweaked and same and not st["n_old"] and st["n_orig"] > 0
    forest_change = rebuild or refresh or (not tweaked and (fac, hf) != (1.0, 1.0))
    overlay_on = want_h != "default"
    if not det["pro"]:
        want_c = []
    changed = set(hm_changed(xp)) if (info and overlay_on) else set()
    # tiles the plan wants that are not built (or built ones it does not want), e.g. after an earlier version
    plan_diff = False
    if info and overlay_on and info.get("version") == VERSION and info["choice"] == want_h:
        say("  Checking the hedge tiles ...")
        plan_diff = hm_plan(xp, want_h, want_c)[0] != set(info["tiles"])
    overlay_change = overlay_on and (not info or info.get("version") != VERSION or info["choice"] != want_h
                                     or sorted(info["countries"]) != sorted(want_c) or bool(changed) or plan_diff)
    lib_change = overlay_on and (not k_on or (k_h, k_hp) != (hf, hp) or knick_lib_version(xp) != VERSION
                                 or hchoice != want_h or overlay_change)
    hedge_change = has_sh and (want_h != hchoice or overlay_change or lib_change)
    hedge_need = 0
    say()
    say()
    say("  Summary")
    say("  -------")
    now = format_forest(cur_x, cur_h, cur_hp) if tweaked else "original"
    if refresh:
        why = "reset by an update" if st["n_reset"] else "not tweaked yet"
        say(f"  Forests   {now}  ->  apply to {st['n_orig']} files {why}")
    elif tweaked and same and st["n_old"]:
        say(f"  Forests   {now}  ->  re-apply with the latest improvements")
    elif forest_change:
        say(f"  Forests   {now}  ->  {format_forest(fac, hf, hp)}")
    else:
        say(f"  Forests   {now}  (unchanged)")
    if has_sh:
        if want_h != hchoice:
            say(f"  Hedges    {CHOICE_NAMES[hchoice]}  ->  {CHOICE_NAMES[want_h]}")
        elif lib_change and want_h == "Knicks" and (k_h, k_hp) != (hf, hp) and k_on:
            say(f"  Hedges    {CHOICE_NAMES[want_h]}  ->  heights follow the new tree height")
        else:
            say(f"  Hedges    {CHOICE_NAMES[want_h]}" + ("  ->  updated" if hedge_change else "  (unchanged)"))
        if det["pro"] and overlay_on:
            names = "all" if "all" in want_c else ", ".join(n for k, n, _r in COUNTRIES if k in want_c) or "none"
            say(f"  Countries {names} (X-WORLD Pro)")
    say()
    say("  What is changed")
    if forest_change:
        say(f"    {st['files']:>6} forest files      backups kept")
    if hedge_change and overlay_on:
        plan, data_tiles = hm_plan(xp, want_h, want_c)
        n_new = len(plan) if (not info or info.get("version") != VERSION or info["choice"] != want_h) else len(plan - set(info["tiles"]) | changed)
        # rough values measured on X-WORLD Pro Europe: tiles with official map data about 15 s and 2.7 MB,
        # other tiles about 2 s and 1.3 MB (this version, one CPU core)
        full = not info or info.get("version") != VERSION or info["choice"] != want_h
        new_t = plan if full else (plan - set(info["tiles"])) | (changed & plan)
        n_d = len(new_t & set(data_tiles))
        n_p = len(new_t) - n_d
        hedge_need = int((n_d * 2.7 + n_p * 1.3) * 2**20)
        size = f"{hedge_need / 2**30:.1f} GB" if hedge_need >= 2**30 else f"{max(1, round(hedge_need / 2**20))} MB"
        if n_new:
            say(f"    {len(plan):>6} hedge tiles       {n_new} to build, {time_range(n_d * 15 + n_p * 2)}, up to about {size}")
        else:
            say(f"    {len(plan):>6} hedge tiles       up to date")
        say("         1 tweak library     hedge types for all four seasons")
    if hedge_change and hfiles and (want_h != "default") != (hstate == "enhanced"):
        say(f"    {len(hfiles):>6} free X-World hedge files")
    if hedge_change and not overlay_on and (k_on or sh_info(xp)):
        say("         2 tweak folders     removed")
    if not forest_change and not hedge_change:
        say("    nothing")
        return
    need = 0
    if forest_change and hf < 1.0:
        files = get_files(targets)
        need = int(sum(os.path.getsize(f) for f in files) * 0.35)
        say()
        say(f"  Disk: about {need / 2**30:.1f} GB backups of the 3D tree models (free: {free_space(xp) / 2**30:.1f} GB)")
    if not disk_ok(xp, need, hedge_need):
        return
    if forest_change:
        say(f"  Time: {time_range(estimate(st, hf, rebuild))} for the forests (depends on your computer)")
        if has_gf and fac < 1.0:
            say(f"  Global Forests v2: cropland extra x{CROP_FAC}, sparse forests extra x{SPARSE_FAC['25']} / x{SPARSE_FAC['50']}")
    say()
    if not ask_yes("  Apply now? [Y/n] "):
        say("  Cancelled - nothing was changed.")
        return
    tlog(f"choose: {now} -> spacing {fac} height {hf} {hp}; hedges {hchoice} -> {want_h}; countries {' '.join(want_c)}")
    ok = True
    say()
    if forest_change:
        if rebuild:
            say("  Restoring originals ...")
            ok = restore(xp, targets, quiet=True)
            if not ok:
                say("  Stopped before applying the new values.", C_RED)
                return
        if (fac, hf) != (1.0, 1.0):
            ok = apply_values(xp, targets, fac, hf, hp)
        else:
            say("  Forests are original again.", C_GREEN)
    if hedge_change and ok:
        if hfiles:
            if want_h in ("enhanced", "Knicks"):
                if hstate != "enhanced":
                    hedges_apply(xp, hfiles, hlog)
            elif hstate != "default":
                hedges_restore(xp, hfiles, hlog)
        if overlay_on:
            if overlay_change:
                only = changed if (info and info.get("version") == VERSION and info["choice"] == want_h) else None
                built = hm_build(xp, want_h, want_c, only=only, lib=(hf, hp))
            else:
                built = set(info["tiles"])
            knick_write(xp, hf, hp, kmap=bool(built), built=built, choice=want_h)
            say(f"  Tweak library: Custom Scenery/{KNICK_DIR}", C_GREEN)
            if not os.path.exists(scenery_ini(xp)):
                warn("  scenery_packs.ini not found - start X-Plane once, then run Check & repair.")
        elif k_on or sh_info(xp):
            sh_remove(xp)
            knick_remove(xp)
            say("  Hedge overlay and tweak library removed.", C_GREEN)
    if ok:
        say()
        say("  Done. Start X-Plane now.   [Q] Quit", C_GREEN)


# ---------------------------------------------------------------- [2] restore, [3] status, [4] check & repair
def restore_all(xp, targets):
    if blocked_by_xplane():
        return
    ensure_tweak_active(xp, targets)
    if not ask_yes("  Restore the original forests and hedges? [Y/n] "):
        say("  Cancelled - nothing was changed.")
        return
    ok = restore(xp, targets)
    hfiles, hstate, hlog = hedge_overview(xp)
    if hfiles and hstate != "default":
        hedges_restore(xp, hfiles, hlog)
    if knick_info(xp)[0] or sh_info(xp):
        sh_remove(xp)
        knick_remove(xp)
        say("  Knicks removed.", C_GREEN)
    if ok:
        say()
        say("  Done! You can start X-Plane now. Type Q and press Enter to close this window.", C_GREEN)


def show_status(xp, targets):
    if switched_off(xp):
        say()
        say("  Switched to ORIGINAL with [5]: forests, hedges and Knicks are original right now.", C_CYAN)
        say("  Your tweak is kept next to the files - [5] switches back in a few seconds.")
        return
    st = _ST_CACHE[0]
    if not st:
        st = _ST_CACHE[0] = forest_state(xp, targets)
    hfiles, hstate, _ = hedge_overview(xp)
    say()
    say(f"  Forest files checked : {st['files']}")
    say(f"  Tweaked              : {st['n']}" + (f"   ({format_forest(st['x'], st['h'], st['hp'])})" if st["n"] else ""), C_GREEN)
    say(f"  Original (tweakable) : {st['n_orig']}" + ("   -> run Choose settings to tweak them" if st["n"] and st["n_orig"] else ""))
    say(f"  Grass/shrubs (kept)  : {st['n_skip']}")
    if st["n_old"]:
        warn(f"  From an older version: {st['n_old']} files -> run Choose settings once for the latest improvements")
    say(f"  simHeaven hedges     : {hedge_status_text(hfiles, hstate)}")
    det = hm_detect(xp)
    say("  simHeaven            : " + ", ".join([f"X-WORLD Pro ({', '.join(det['pro'])})"] if det["pro"] else [])
        + ((", " if det["pro"] and det["free"] else "") + f"X-World free ({', '.join(det['free'])})" if det["free"] else "")
        + ("" if det["pro"] or det["free"] else "not found"))
    for line in hm_source_report(xp):
        say("                         " + line)
    if det["both"]:
        warn(f"  Free X-World and X-WORLD Pro are both on for {', '.join(det['both'])} - Choose settings can turn the free packs off")
    if knick_info(xp)[0]:
        say(f"  Hedges               : {CHOICE_NAMES[hedge_choice_state(xp, hstate)]}")
        info = hm_info(xp)
        if info:
            names = "all" if "all" in info["countries"] else ", ".join(n for k, n, _r in COUNTRIES if k in info["countries"])
            say(f"  Hedge overlay        : {len(info['tiles'])} tiles (Custom Scenery/{SH_DIR})" + (f", X-WORLD Pro: {names}" if names else ""))
            say("                         official hedge maps: see DATA_LICENSES.txt")
        hint = hedge_hint(xp)
        if hint:
            warn("                         " + hint)
    other = other_forest_addons(xp)
    if other:
        say()
        warn("  Other scenery that may bring its own forests (not changed by this tool):")
        for o in other[:8]:
            warn(f"    {o}")
        warn("  Where it covers an area, its forests are shown instead of the tweaked ones.")
    say()
    say("  The visible effect is limited by the vegetation slider in X-Plane and by the forest data of")
    say("  the scenery: where the scenery has no forest areas, no trees are added.")


def check_repair(xp, targets):
    if blocked_by_xplane():
        return
    ensure_tweak_active(xp, targets)
    say("  Checking backups and log ...")
    t0 = time.time()
    lp = log_path(xp)
    log = read_log(lp)
    tmp = cleanup_temp(xp, targets)
    sides = repair_sides(xp, targets)
    roots = [rel(xp, t).lower() + "/" for t in targets]
    gone = reset = bad = ok_gz = 0
    bad_files = []
    items = [(r, e) for r, e in log.items() if any(r.lower().startswith(p) for p in roots)]
    pr = Progress("Checking", len(items))
    for i, (r, e) in enumerate(items, 1):
        pr.update(i, i, len(items))
        f = os.path.join(xp, *r.split("/"))
        bp = backup_path(xp, r)
        if not os.path.isfile(f):
            gone += 1
            del log[r]
            if os.path.exists(bp):
                os.remove(bp)
            continue
        if state(ForFile(f, quick=True), e) != "tweaked":
            reset += 1                 # reset by an update -> the log line and backup are outdated
            del log[r]
            if os.path.exists(bp):
                os.remove(bp)
            continue
        if e.get("mb"):
            try:
                good = os.path.exists(bp) and ("ms" not in e or sha256_file_gz(bp) == e["ms"])
                if good and "ms" not in e:
                    with gzip.open(bp, "rb") as g:      # 1.3 backup without checksum: test it reads to the end
                        while g.read(4 * 2**20):
                            pass
            except (OSError, EOFError):
                good = False
            if good:
                ok_gz += 1
            else:
                bad += 1
                bad_files.append(r)
    pr.end()
    # backups that belong to no tweaked file
    orphans = 0
    bk = os.path.join(xp, TWEAK_DIR, "mesh_backup")
    for root, _d, names in os.walk(bk):
        for name in names:
            full = os.path.join(root, name)
            r = rel(os.path.join(xp, TWEAK_DIR, "mesh_backup"), full)
            r = r[:-3] if r.endswith(".gz") else r
            e = log.get(r)
            if not (e and e.get("mb")):
                os.remove(full)
                orphans += 1
    empty = remove_empty_dirs(bk)
    write_log(lp, list(log.values()))
    # hedges log
    hl = read_log(hedge_log_path(xp))
    hgone = [k for k in hl if not os.path.isfile(os.path.join(xp, *k.split("/")))]
    for k in hgone:
        del hl[k]
    if os.path.exists(hedge_log_path(xp)):
        write_log(hedge_log_path(xp), list(hl.values()))
    say()
    say(f"  3D model backups OK            : {ok_gz}", C_GREEN)
    say(f"  Log lines of reset files       : {reset} removed" + ("  (run Choose settings to tweak them again)" if reset else ""))
    say(f"  Log lines of missing files     : {gone + len(hgone)} removed")
    say(f"  Unused backups / temp files    : {orphans} / {tmp} removed")
    say(f"  Empty backup folders           : {empty} removed")
    if sides:
        say(f"  Quick switch copies            : {sides} fixed or removed")
    repair_hedges(xp)
    tlog(f"check: ok {ok_gz}, reset {reset}, gone {gone}, orphans {orphans}, tmp {tmp}, empty dirs {empty}, bad {bad} ({took(t0)})")
    if bad:
        say()
        say(f"  {bad} backups are missing or damaged. These files stay tweaked (safe), but can't be", C_RED)
        say("  restored exactly. Run the X-Plane installer (Update) or reinstall Global Forests v2,", C_RED)
        say("  then run Check & repair again. First file: " + bad_files[0], C_RED)
        for r in bad_files:
            tlog(f"check: damaged backup {r}")
    else:
        say("  Everything is fine.", C_GREEN)


def repair_hedges(xp):
    """Rebuilds hedge tiles that are missing (interrupted build) or whose simHeaven source changed, rewrites
    the tweak library and fixes scenery_packs.ini."""
    k_on, k_h, k_hp = knick_info(xp)
    if k_on:
        info = hm_info(xp)
        choice = hedge_choice_state(xp, None)
        built = set(info["tiles"]) if info else set()
        if info:
            ch = hm_changed(xp) if info.get("version") == VERSION else None
            if ch is None or ch or info.get("incomplete"):
                what = "all" if ch is None else (f"{len(ch)} tiles out of date" if ch else "")
                if info.get("incomplete") and ch is not None:
                    what = (what + ", " if what else "") + "interrupted build"
                say(f"  Hedge overlay                  : {what} - building again")
                built = hm_build(xp, choice, info["countries"], only=ch, lib=(k_h, k_hp))
            sh_ini_place(xp)
            say("  Hedge overlay                  : checked, listed above simHeaven")
        knick_write(xp, k_h, k_hp, built=built, choice=choice)
        say("  Tweak library                  : checked, listed above the simHeaven libraries")


# ---------------------------------------------------------------- [5] quick switch tweak <-> original
# Both versions of every tweaked file are kept side by side, so switching is only renaming:
#   tweak active   : file.for = tweak,     file.for.fdt_orig  = original (made at the first switch)
#   original active: file.for = original,  file.for.fdt_tweak = tweak
# The simHeaven hedges are set back / enhanced again (4 small files), the Knick library and the hedgerow
# map are switched off / on in scenery_packs.ini. X-Plane ignores the extra files.
SIDE_ORIG, SIDE_TWEAK = ".fdt_orig", ".fdt_tweak"
SWITCH_FILE = "switched_off.json"


def switch_path(xp):
    return os.path.join(tweak_dir(xp), SWITCH_FILE)


def switched_off(xp):
    return os.path.isfile(switch_path(xp))


def drop_sides(f):
    for ext in (SIDE_ORIG, SIDE_TWEAK):
        if os.path.exists(f + ext):
            os.remove(f + ext)


def is_logged_original(fo, e):
    return fo.lines == as_list(e.get("o")) and ("ot" not in e or fo.tlines == as_list(e["ot"]))


def original_bytes(xp, f, r, e):
    """The original file: from the 3D model backup (checked) or by putting the logged lines back."""
    if e.get("mb"):
        bp = backup_path(xp, r)
        try:
            with gzip.open(bp, "rb") as g:
                data = g.read()
        except (OSError, EOFError):
            return None
        if "ms" in e and hashlib.sha256(data).hexdigest() != e["ms"]:
            return None
        return data
    fo = ForFile(f)
    new_head = set_seq(fo.head, LINE_RX, e.get("o"))
    new_tail = set_seq(fo.tail, TREE_RX, e["ot"]) if "ot" in e else fo.tail
    return new_head.encode("latin-1") + fo.data[fo.head_len:fo.tail_start] + new_tail.encode("latin-1")


def ini_set_enabled(xp, folder, on):
    """Switches one pack line on/off in scenery_packs.ini. True if it was changed."""
    lines, nl = ini_read(xp)
    if lines is None:
        return False
    new = []
    for l in lines:
        if pack_line_is(l, folder):
            l = ("SCENERY_PACK" if on else "SCENERY_PACK_DISABLED") + f" Custom Scenery/{folder}/"
        new.append(l)
    if new == lines:
        return False
    ini_write(xp, new, nl)
    return True


def switch_off(xp, targets):
    """Tweak -> original. Returns True if done."""
    lp = log_path(xp)
    log = read_log(lp)
    files = [f for f in get_files(targets) if rel(xp, f) in log]
    todo = []
    for f in files:
        e = log[rel(xp, f)]
        if state(ForFile(f, quick=True), e) == "tweaked":
            todo.append(f)
        else:
            drop_sides(f)                  # reset by an update: the kept copies are outdated
    need = sum(os.path.getsize(f) for f in todo if not os.path.exists(f + SIDE_ORIG))
    if need and free_space(xp) < need + DISK_MARGIN:
        say(f"  Not enough free disk space to keep both versions (needs about {need / 2**30:.1f} GB).", C_RED)
        return False
    if need:
        say(f"  First switch: keeping a copy of the original files ({need / 2**30:.1f} GB, only this time) ...")
    t0 = time.time()
    pr = Progress("Switching to original", len(todo))
    done, damaged = 0, []
    for i, f in enumerate(todo, 1):
        pr.update(i, i, len(todo))
        r = rel(xp, f)
        if not os.path.exists(f + SIDE_ORIG):
            data = original_bytes(xp, f, r, log[r])
            if data is None:
                damaged.append(r)          # stays tweaked; Check & repair tells more
                continue
            write_bytes(f + SIDE_ORIG, data)
        os.replace(f, f + SIDE_TWEAK)
        os.replace(f + SIDE_ORIG, f)
        done += 1
    pr.end()
    _hf, hstate, hlog = hedge_overview(xp)
    hedges = hstate
    if _hf and hstate == "enhanced":
        hedges_restore(xp, _hf, hlog)
    packs = [d for d in (SH_DIR, KNICK_DIR) if ini_set_enabled(xp, d, False)]
    with open(switch_path(xp), "w", encoding="utf-8") as fh:
        json.dump({"version": VERSION, "hedges": hedges, "packs": packs, "files": done}, fh)
    tlog(f"switch: original ({done} files, {len(damaged)} damaged backups, hedges {hedges}, packs off {packs}, {took(t0)})")
    say(f"  Switched to ORIGINAL: {done} forest files" + (", simHeaven hedges default" if hedges == "enhanced" else "")
        + (", Knicks off" if packs else "") + f"   ({took(t0)})", C_GREEN)
    if damaged:
        warn(f"  {len(damaged)} files stay tweaked (their 3D model backup is missing or damaged) - see Check & repair.")
    return True


def switch_on(xp, targets, quiet=False):
    """Original -> tweak. Returns True if done."""
    try:
        with open(switch_path(xp), encoding="utf-8") as fh:
            info = json.load(fh)
    except (OSError, ValueError):
        info = {}
    log = read_log(log_path(xp))
    t0 = time.time()
    done = stale = 0
    files = [f for f in get_files(targets) if rel(xp, f) in log]
    pr = Progress("Switching to tweak", len(files))
    for i, f in enumerate(files, 1):
        pr.update(i, i, len(files))
        if not os.path.exists(f + SIDE_TWEAK):
            continue
        e = log[rel(xp, f)]
        if is_logged_original(ForFile(f, quick=True), e):
            os.replace(f, f + SIDE_ORIG)
            os.replace(f + SIDE_TWEAK, f)
            done += 1
        else:
            os.remove(f + SIDE_TWEAK)      # changed by an X-Plane/GFv2 update meanwhile -> tweak it again
            stale += 1
    pr.end()
    if info.get("hedges") == "enhanced":
        _hf, hstate, hlog = hedge_overview(xp)
        if _hf and hstate != "enhanced":
            hedges_apply(xp, _hf, hlog)
    for d in info.get("packs", []):
        ini_set_enabled(xp, d, True)
    os.remove(switch_path(xp))
    tlog(f"switch: tweak ({done} files, {stale} updated meanwhile, {took(t0)})")
    if not quiet or stale:
        say(f"  Switched to TWEAK: {done} forest files   ({took(t0)})", C_GREEN)
    if stale:
        warn(f"  {stale} files were updated by X-Plane or Global Forests meanwhile - run Choose settings to tweak them again.")
    return True


def repair_sides(xp, targets):
    """After an interrupted switch: puts every file back into the tweak state, drops outdated copies."""
    log = read_log(log_path(xp))
    fixed = 0
    for t in targets:
        for root, _d, names in os.walk(t):
            for name in names:
                if not (name.endswith(SIDE_ORIG) or name.endswith(SIDE_TWEAK)):
                    continue
                full = os.path.join(root, name)
                base = full[:-len(SIDE_ORIG)] if name.endswith(SIDE_ORIG) else full[:-len(SIDE_TWEAK)]
                if not os.path.exists(full):
                    continue                       # handled together with its partner
                e = log.get(rel(xp, base))
                if not os.path.exists(base):
                    os.replace(base + SIDE_TWEAK if os.path.exists(base + SIDE_TWEAK) else full, base)
                    fixed += 1
                    continue
                if e is None:
                    drop_sides(base)
                    fixed += 1
                    continue
                if os.path.exists(base + SIDE_TWEAK) and is_logged_original(ForFile(base, quick=True), e):
                    os.replace(base, base + SIDE_ORIG)
                    os.replace(base + SIDE_TWEAK, base)
                    fixed += 1
                elif state(ForFile(base, quick=True), e) != "tweaked":
                    drop_sides(base)                 # reset by an update: the copies are outdated
                    fixed += 1
                elif os.path.exists(base + SIDE_TWEAK):
                    os.remove(base + SIDE_TWEAK)
                    fixed += 1
    return fixed


def switch_menu(xp, targets):
    if blocked_by_xplane():
        return
    if switched_off(xp):
        if ask_yes("  Switch back to your tweak? [Y/n] "):
            switch_on(xp, targets)
            say("  Done! You can start X-Plane now.", C_GREEN)
        return
    st = forest_state(xp, targets)
    if not st["n"] and not knick_info(xp)[0]:
        say("  Nothing is tweaked - nothing to switch.")
        return
    say("  Switches to the original forests (and hedges/Knicks) without losing your tweak.")
    say("  [5] again switches back in a few seconds. The first time a copy of the originals is kept.")
    if ask_yes("  Switch to original now? [Y/n] "):
        if switch_off(xp, targets):
            say("  Done! You can start X-Plane now.", C_GREEN)


_ST_CACHE = [None]      # forest state read at the start, see main()


def ensure_tweak_active(xp, targets):
    """Choose settings, Restore and Check & repair work on the tweak: switch back first if needed."""
    if switched_off(xp):
        say("  The tweak is switched off - switching back first ...")
        switch_on(xp, targets, quiet=True)


# ---------------------------------------------------------------- main
def main():
    global TOOL_LOG
    if sys.version_info < (3, 8):
        say("Python 3.8 or newer is needed.", C_RED)
        return
    upd_thread, upd = start_update_check()
    say()
    say(f"  XP12 Forest Tweak {VERSION} - macOS / Linux", C_CYAN)
    say("  ------------------------------------------------------------")
    xp = os.path.realpath(find_xplane())
    TOOL_LOG = os.path.join(tweak_dir(xp), "tool.log")
    ver, vs = xplane_version(xp)
    say(f"  X-Plane : {xp}" + (f"   ({vs})" if vs else ""))
    targets, gf = get_targets(xp)
    tlog(f"start {VERSION} ({sys.platform}, Python {sys.version.split()[0]}), X-Plane {vs or '?'} at {xp}, folders: "
         + ", ".join(rel(xp, t) for t in targets))
    say("  Folders : " + ", ".join(rel(xp, t) for t in targets))
    if xplane_running():
        warn("  X-Plane is running - please quit it before changing anything.")
    for line in hm_source_report(xp):
        tlog("simHeaven: " + line)
    st = _ST_CACHE[0] = forest_state(xp, targets)    # reused by Choose settings and Status until a menu action changes files
    _hf, hstate, _hl = hedge_overview(xp)
    if switched_off(xp):
        say("  Status  : switched to ORIGINAL - your tweak is kept, [5] switches back", C_CYAN)
    else:
        say(f"  Status  : {status_line(st, hedge_choice_state(xp, hstate) if (hstate or knick_info(xp)[0]) else None)}")
        det = hm_detect(xp)
        if det["pro"] or det["free"]:
            say("  simHeaven: " + ", ".join(([f"X-WORLD Pro ({', '.join(det['pro'])})"] if det["pro"] else [])
                                         + ([f"X-World free ({', '.join(det['free'])})"] if det["free"] else [])))
        hint = hedge_hint(xp)
        if hint:
            warn("  Hedges  : " + hint)
    environment_hints(xp, targets, gf)
    upd_thread.join(timeout=3)
    tag = upd.get("tag", "")
    if tag and vtuple(tag) > vtuple(VERSION):
        say(f"  Update  : version {tag.lstrip('vV')} is available - github.com/{REPO}/releases", C_CYAN)
        if ask_yes("  Open the download page in your browser? [y/N] ", default=False):
            try:
                webbrowser.open(f"https://github.com/{REPO}/releases/latest")
            except Exception:
                pass
    start_offers(xp, targets, st)
    while True:
        say()
        sw = "[5] Switch back to tweak" if switched_off(xp) else "[5] Switch to original"
        say("  [0] Recommended setup   [1] Choose settings   [2] Restore original   [3] Status")
        say(f"  [4] Check & repair   {sw}   [Q] Quit")
        a = input("  Choice: ").strip()
        if a == "0":
            choose_settings(xp, targets, quick=True)
        elif a == "1":
            choose_settings(xp, targets)
        elif a == "2":
            restore_all(xp, targets)
        elif a == "3":
            show_status(xp, targets)
        elif a == "4":
            check_repair(xp, targets)
        elif a == "5":
            switch_menu(xp, targets)
        elif a.lower() == "q":
            return
        if a in ("0", "1", "2", "4", "5"):
            _ST_CACHE[0] = None      # files may have changed: read the state again next time


if __name__ == "__main__":
    multiprocessing.freeze_support()
    try:
        main()
    except KeyboardInterrupt:
        say()
        warn("  Stopped. Everything done so far is logged and safe.")
        warn("  Start the tool again and use Choose settings to finish, or Restore original.")
        tlog("stopped with Ctrl+C")
        sys.exit(130)
    except EOFError:
        say()
    except Exception as ex:          # show a readable message instead of a traceback
        say()
        say(f"  ERROR: {ex}", C_RED)
        tlog(f"ERROR: {ex!r}")
        sys.exit(1)
