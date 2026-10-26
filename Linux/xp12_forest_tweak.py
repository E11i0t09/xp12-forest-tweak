#!/usr/bin/env python3
"""
XP12 Forest Tweak - macOS / Linux version
Version 1.4.0

Denser forests and optionally smaller trees for X-Plane 12.
Same logic and same backup log as the Windows (PowerShell) version, so a tweak made
on one system can be restored on the other (e.g. dual boot with a shared X-Plane folder).

What it does
- Tree spacing: SPACING and RANDOM in the forest files (.for) are multiplied by a factor
  (0.7 = about twice as many trees per area). The vegetation slider in X-Plane can never
  go above the density set there.
- Global Forests v2 "cropland" forests (field trees and hedgerows between fields) get an
  extra factor of 0.8 on top, so field edges are filled more evenly.
- Files with SPACING <= 3.1 m (grass, shrubs, hedges) are left untouched.
- Optional tree height factor (0.5 - 1.0): min and max height of every tree are scaled.
  "realistic" profile: conifers shrink less, palms a bit less, shrubs/orchards hardly.
  TREE2 3D trees scale by themselves (nominal height is kept); the 3D models of TREE
  trees are drawn at their modelled size, so their vertices are scaled too. Before that,
  a compressed copy (with SHA-256 checksum) of the original file is stored in
  <X-Plane>/ForestDensityTweak/mesh_backup for an exact restore.
- Every original line is logged in <X-Plane>/ForestDensityTweak/backup.log, so
  "Restore original" puts back the exact original values.
- Optional: simHeaven hedges "default" or "enhanced" (about 4-5 m high, visible up to 8 km).
- Actions are written to <X-Plane>/ForestDensityTweak/tool.log (helpful for bug reports).

Needs only Python 3.8 or newer, no extra packages.
Use at your own risk. Free community project - CC BY-NC-SA 4.0, see LICENSE.
"""

import gzip
import hashlib
import json
import multiprocessing
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP

VERSION = "1.4.0"
TESTED_XP = (12, 4)      # X-Plane version the tool was tested with
REPO = "E11i0t09/xp12-forest-tweak"
THRESHOLD = 3.1          # files with a smaller tree spacing are grass/shrubs/hedges -> kept
PRESETS = [("Natural", 0.8, "noticeably denser"),
           ("Dense", 0.7, "about 2x trees, recommended"),
           ("Very dense", 0.6, "about 2.8x trees, needs a strong GPU")]
DEFAULT_FAC = 0.7        # preset [2]
MIN_FAC = 0.4
MIN_HEIGHT = 0.5         # lowest allowed height factor
CROP_FAC = 0.8           # extra spacing factor for Global Forests v2 cropland forests
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
        if not os.path.isdir(os.path.join(xp, "Custom Scenery", name)) or low.startswith(("simheaven", "global_forests", "global forests")):
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
    xe = rnd(x * CROP_FAC, 4) if x < 1.0 and "/cropland/" in norm(r).lower() else x
    he = h
    if h < 1.0 and hp == "realistic":
        he = rnd(1.0 - (1.0 - h) * height_weight(r), 4)
    return xe, he


def stored_effective(e):
    return float(e.get("xe", e["x"])), float(e.get("he", get_h(e)))


def outdated(r, e):
    """Tweaked with values that differ from the 1.4 rules for its settings (e.g. cropland from 1.3)."""
    want = effective(r, float(e["x"]), get_h(e), get_hp(e))
    have = stored_effective(e)
    return abs(want[0] - have[0]) > 1e-9 or abs(want[1] - have[1]) > 1e-9


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
            s += " - run Choose settings once to apply the 1.4 improvements"
    if hstate:
        s += f" | hedges {hstate}"
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
        new_head = LINE_RX.sub(lambda m: m.group(1) + m.group(2) + m.group(3)
                               + fmt(float(m.group(4)) * xe) + m.group(5)
                               + fmt(float(m.group(6)) * xe), fo.head)
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


# ---------------------------------------------------------------- [1] choose settings
def ask_spacing(current, tweaked):
    say("  Step 1  Tree spacing (forest density)")
    say("          Lower spacing = closer trees = denser forest. 1.0 = original.")
    for i, (name, v, note) in enumerate(PRESETS, 1):
        say(f"          [{i}] {name:<11} {v:<4}  {note}")
    say("          [4] Custom      your own value from 0.4 to 1.0")
    cur_choice = next((str(i) for i, p in enumerate(PRESETS, 1) if p[1] == current), None)
    if not tweaked:
        cur_choice, current = "2", DEFAULT_FAC
    hint = f"Enter = {cur_choice}" if cur_choice else f"Enter = keep {fmt(current)}"
    while True:
        a = input(f"  Choose 1-4 ({hint}): ").strip()
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


def ask_profile(hf, current):
    def ex(w):
        return fmt(rnd(1.0 - (1.0 - hf) * w, 4))
    say("  Step 3  Height profile")
    say(f"          [1] uniform    every tree {fmt(hf)}")
    say(f"          [2] realistic  broadleaf {fmt(hf)}, conifers {ex(0.6)}, palms {ex(0.8)}, shrubs/orchards {ex(0.5)}")
    say("                         (conifers are often the tallest trees in reality, so they shrink less)")
    cur = "1" if current == "uniform" else "2"
    while True:
        a = input(f"  Choose 1-2 (Enter = {cur}): ").strip() or cur
        if a in ("1", "2"):
            return "uniform" if a == "1" else "realistic"
        warn("  Please choose 1 or 2.")


def choose_settings(xp, targets):
    if blocked_by_xplane():
        return
    st = forest_state(xp, targets)
    tweaked = st["n"] > 0
    cur_x, cur_h, cur_hp = st["x"], st["h"], st["hp"]
    hfiles, hstate, hlog = hedge_overview(xp)
    has_gf = any(rel(xp, t).startswith("Custom Scenery/") for t in targets)
    say()
    say("  Nothing is changed until you confirm at the end.")
    say()
    fac = ask_spacing(cur_x, tweaked)
    say()
    say("  Step 2  Tree height")
    say(f"          1.0 = original, 0.8 = trees 20 % smaller (lowest {fmt(MIN_HEIGHT)}). Includes the 3D tree models.")
    hf = ask_value(MIN_HEIGHT, cur_h, "tree height")
    hp = "uniform"
    if hf < 1.0:
        say()
        hp = ask_profile(hf, cur_hp if cur_h < 1.0 else "realistic")
    want_h = None
    if hfiles:
        say()
        say("  Step 4  simHeaven hedges (e.g. the Knicks in northern Germany)")
        say("          [1] default   2.2 - 2.8 m high, visible up to 4 km")
        say("          [2] enhanced  about 4 - 5 m high, visible up to 8 km")
        cur = "2" if hstate == "enhanced" else "1"
        while want_h is None:
            a = input(f"  Choose 1-2 (Enter = {cur}): ").strip() or cur
            want_h = {"1": "default", "2": "enhanced"}.get(a)
    # summary
    same = (fac, hf, hp) == (cur_x, cur_h, cur_hp)
    rebuild = tweaked and (not same or st["n_old"] > 0)       # restore first, then apply the new values
    refresh = tweaked and same and not st["n_old"] and st["n_orig"] > 0
    forest_change = rebuild or refresh or (not tweaked and (fac, hf) != (1.0, 1.0))
    hedge_change = bool(hfiles) and want_h != hstate
    say()
    say("  Summary")
    say("  -------")
    now = format_forest(cur_x, cur_h, cur_hp) if tweaked else "original"
    if refresh:
        why = "reset by an update" if st["n_reset"] else "not tweaked yet"
        say(f"  Forests : {now}  ->  apply to {st['n_orig']} files {why}")
    elif tweaked and same and st["n_old"]:
        say(f"  Forests : {now}  ->  re-apply with the 1.4 improvements")
    elif forest_change:
        say(f"  Forests : {now}  ->  {format_forest(fac, hf, hp)}")
    else:
        say(f"  Forests : {now}  (unchanged)")
    if forest_change and has_gf and fac < 1.0:
        say(f"            Global Forests v2 cropland (field trees, hedgerows): extra x{CROP_FAC} -> spacing {fmt(rnd(fac * CROP_FAC, 4))}")
    if hfiles:
        say(f"  Hedges  : {hstate}" + (f"  ->  {want_h}" if hedge_change else "  (unchanged)"))
    if not forest_change and not hedge_change:
        say("  Nothing to change.")
        return
    if forest_change and hf < 1.0:
        files = get_files(targets)
        need = int(sum(os.path.getsize(f) for f in files) * 0.35)
        free = free_space(xp)
        say("  Smaller trees also scale the 3D tree models. A compressed backup of the originals is kept")
        say(f"  for an exact restore: about {need / 2**30:.1f} GB (free on disk: {free / 2**30:.1f} GB).")
        if free < need + 2**30:
            say("  Not enough free disk space.", C_RED)
            return
    if forest_change:
        warn(f"  Estimated time: {time_range(estimate(st, hf, rebuild))} (depends on your computer).")
        warn("  Please keep this window open.")
    if not ask_yes("  Apply these settings now? [Y/n] "):
        say("  Cancelled - nothing was changed.")
        return
    tlog(f"choose: {now} -> spacing {fac} height {hf} {hp}; hedges {hstate} -> {want_h}")
    ok = True
    if forest_change:
        if rebuild:
            say("  Restoring the original forests first ...")
            ok = restore(xp, targets, quiet=True)
            if not ok:
                say("  Stopped before applying the new values.", C_RED)
                return
        if (fac, hf) != (1.0, 1.0):
            ok = apply_values(xp, targets, fac, hf, hp)
        else:
            say("  Forests are original again.", C_GREEN)
    if hedge_change and ok:
        if want_h == "enhanced":
            hedges_apply(xp, hfiles, hlog)
        else:
            hedges_restore(xp, hfiles, hlog)
    if ok:
        say()
        say("  Done! You can start X-Plane now. Type Q and press Enter to close this window.", C_GREEN)


# ---------------------------------------------------------------- [2] restore, [3] status, [4] check & repair
def restore_all(xp, targets):
    if blocked_by_xplane():
        return
    if not ask_yes("  Restore the original forests and hedges? [Y/n] "):
        say("  Cancelled - nothing was changed.")
        return
    ok = restore(xp, targets)
    hfiles, hstate, hlog = hedge_overview(xp)
    if hfiles and hstate != "default":
        hedges_restore(xp, hfiles, hlog)
    if ok:
        say()
        say("  Done! You can start X-Plane now. Type Q and press Enter to close this window.", C_GREEN)


def show_status(xp, targets):
    st = forest_state(xp, targets)
    hfiles, hstate, _ = hedge_overview(xp)
    say()
    say(f"  Forest files checked : {st['files']}")
    say(f"  Tweaked              : {st['n']}" + (f"   ({format_forest(st['x'], st['h'], st['hp'])})" if st["n"] else ""), C_GREEN)
    say(f"  Original (tweakable) : {st['n_orig']}" + ("   -> run Choose settings to tweak them" if st["n"] and st["n_orig"] else ""))
    say(f"  Grass/shrubs (kept)  : {st['n_skip']}")
    if st["n_old"]:
        warn(f"  From an older version: {st['n_old']} files -> run Choose settings once for the 1.4 improvements")
    say(f"  simHeaven hedges     : {hedge_status_text(hfiles, hstate)}")
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
    say("  Checking backups and log ...")
    t0 = time.time()
    lp = log_path(xp)
    log = read_log(lp)
    tmp = cleanup_temp(xp, targets)
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
    st = forest_state(xp, targets)
    _hf, hstate, _hl = hedge_overview(xp)
    say(f"  Status  : {status_line(st, hstate)}")
    environment_hints(xp, targets, gf)
    upd_thread.join(timeout=3)
    tag = upd.get("tag", "")
    if tag and vtuple(tag) > vtuple(VERSION):
        say(f"  Update  : version {tag.lstrip('vV')} is available - github.com/{REPO}/releases", C_CYAN)
    while True:
        say()
        say("  [1] Choose settings   [2] Restore original   [3] Status   [4] Check & repair   [Q] Quit")
        a = input("  Choice: ").strip()
        if a == "1":
            choose_settings(xp, targets)
        elif a == "2":
            restore_all(xp, targets)
        elif a == "3":
            show_status(xp, targets)
        elif a == "4":
            check_repair(xp, targets)
        elif a.lower() == "q":
            return


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
