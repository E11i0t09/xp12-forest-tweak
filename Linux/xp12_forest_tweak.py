#!/usr/bin/env python3
"""
XP12 Forest Tweak - macOS / Linux version
Version 1.3.0

Denser forests and optionally smaller trees for X-Plane 12.
Same logic and same backup log as the Windows (PowerShell) version, so a tweak made
on one system can be restored on the other (e.g. dual boot with a shared X-Plane folder).

What it does
- Density: SPACING and RANDOM in the forest files (.for) are multiplied by a factor
  (default 0.7 = about twice as many trees per area). The vegetation slider in X-Plane
  can never go above the density set there.
- Files with SPACING <= 3.1 m (grass, shrubs, hedges) are left untouched.
- Optional height factor (0.5 - 1.0): min and max height of every tree are scaled.
  TREE2 3D trees scale by themselves (nominal height is kept); the 3D models of TREE
  trees are drawn at their modelled size, so their vertices are scaled too. Before
  that, a compressed copy of the original file is stored in
  <X-Plane>/ForestDensityTweak/mesh_backup for an exact restore.
- Every original line is logged in <X-Plane>/ForestDensityTweak/backup.log, so
  "Restore" puts back the exact original values.
- Folders: Resources/default scenery/1200 forests, plus Custom Scenery/Global_Forests_v2
  if it is installed and you choose to include it.
- Optional, step 3 of "Choose settings": simHeaven hedges "default" or "enhanced". Enhanced makes
  the hedges of simHeaven X-World (e.g. the Knicks in northern Germany) about 4-5 m high
  instead of 2.2-2.8 m and visible up to 8 km instead of 4 km. Only the hedge files of the
  simHeaven X-World Vegetation Library are changed; originals are logged in
  <X-Plane>/ForestDensityTweak/hedges.log.

Needs only Python 3.8 or newer, no extra packages.
Use at your own risk. Free community project - CC BY-NC-SA 4.0, see LICENSE.
"""

import gzip
import json
import os
import re
import shutil
import subprocess
import sys
from decimal import Decimal, ROUND_HALF_UP

VERSION = "1.3.0"
THRESHOLD = 3.1          # files with a smaller tree spacing are grass/shrubs/hedges -> kept
DEFAULT_FAC = 0.7        # density factor preset
MIN_HEIGHT = 0.5         # lowest allowed height factor
TWEAK_DIR = "ForestDensityTweak"   # folder name kept from earlier versions (shared with Windows)
HEDGE_FAC = 1.8          # simHeaven hedges "enhanced": 2.2-2.8 m -> about 4-5 m (typical Knick height)
HEDGE_LOD = 8000         # simHeaven hedges "enhanced": visible up to 8 km instead of 4 km
HEDGE_VPATH = "simheaven/forests/hedge.for"

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

IS_MAC = sys.platform == "darwin"
C_CYAN, C_GREEN, C_YELLOW, C_RED, C_OFF = ("\033[36m", "\033[32m", "\033[33m", "\033[31m", "\033[0m") \
    if sys.stdout.isatty() else ("", "", "", "", "")


def say(text="", color=""):
    print(f"{color}{text}{C_OFF if color else ''}")


def fmt(v, decimals=3):
    """Like .NET '0.###': up to n decimals, half away from zero, no trailing zeros."""
    d = Decimal("%.15g" % v).quantize(Decimal(1).scaleb(-decimals), rounding=ROUND_HALF_UP)
    s = format(d, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


_Q7 = Decimal("0.0000001")


def fmt_vertex(v):
    """Like .NET '0.#######' (same rounding as the Windows version, so results are byte-identical)."""
    s = format(Decimal("%.15g" % v).quantize(_Q7, rounding=ROUND_HALF_UP), "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


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
    # the tool folder itself, or up to two levels above it (e.g. X-Plane 12/XP12_ForestTweak/macOS-Linux)
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
        a = input(f"X-Plane 12 found at '{cands[0]}'. Use it? [Y/n] ").strip()
        if a == "" or a[:1] in "yYjJ":
            return cands[0]
    elif len(cands) > 1:
        say("Several X-Plane 12 installations found:")
        for i, c in enumerate(cands, 1):
            say(f"  [{i}] {c}")
        a = input("Number (or Enter to type a path): ").strip()
        if a.isdigit() and 1 <= int(a) <= len(cands):
            return cands[int(a) - 1]
    while True:
        p = input("Path to your X-Plane 12 folder (drag the folder in here): ").strip().strip("'\"").rstrip("/")
        p = os.path.expanduser(p.replace("\\ ", " "))
        if is_xplane(p):
            return p
        say("  -> 'Resources/default scenery' / 'Custom Scenery' not found there.", C_YELLOW)


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
    if gf:
        a = input("  Global Forests v2 found. Tweak it too? [Y/n] ").strip()
        if a == "" or a[:1] in "yYjJ":
            targets += gf
    return targets


# ---------------------------------------------------------------- backup log
def norm(rel):
    return rel.replace("\\", "/")


def log_path(xp):
    d = os.path.join(xp, TWEAK_DIR)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "backup.log")


def read_log(path):
    """Last entry per file wins. Keys are normalised to '/' (Windows writes '\\')."""
    h = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8-sig") as f:
            for line in f:
                if line.strip():
                    e = json.loads(line)
                    h[norm(e["f"])] = e
    return h


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


def write_for(path, fo, new_head, new_tail, new_mid=None):
    if new_mid is None:
        new_mid = fo.data[fo.head_len:fo.tail_start]
    write_bytes(path, new_head.encode("latin-1") + new_mid + new_tail.encode("latin-1"))


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


def progress(label, i, n):
    if sys.stdout.isatty() and (i % 25 == 0 or i == n):
        sys.stdout.write(f"\r  {label}: {i} / {n}   ")
        sys.stdout.flush()


def progress_end():
    if sys.stdout.isatty():
        sys.stdout.write("\r" + " " * 60 + "\r")
        sys.stdout.flush()


# ---------------------------------------------------------------- actions
def show_status(xp, targets):
    log = read_log(log_path(xp))
    c = {"tweaked": 0, "original": 0, "skipped": 0}
    fac = set()
    files = get_files(targets)
    for i, f in enumerate(files, 1):
        progress("Checking", i, len(files))
        fo = ForFile(f, quick=True)
        e = log.get(rel(xp, f))
        if state(fo, e) == "tweaked":
            c["tweaked"] += 1
            fac.add(f"density {e['x']}, height {get_h(e):g}")
        elif min_spacing(fo.head) <= THRESHOLD:
            c["skipped"] += 1
        else:
            c["original"] += 1
    progress_end()
    say()
    say(f"  Forest files checked : {len(files)}")
    say(f"  Tweaked              : {c['tweaked']}" + (f"   ({' / '.join(sorted(fac))})" if fac else ""), C_GREEN)
    say(f"  Original (tweakable) : {c['original']}")
    say(f"  Grass/shrubs (kept)  : {c['skipped']}")
    say(f"  simHeaven hedges     : {hedge_status_line(xp)}")


def apply_values(xp, targets, fac, hf):
    """Apply density factor fac and height factor hf to all forest files that are not tweaked yet."""
    lp = log_path(xp)
    log = read_log(lp)
    files = get_files(targets)
    done = already = skip = odd = mesh_count = 0
    with open(lp, "a", encoding="utf-8", newline="\n") as lf:
        for i, f in enumerate(files, 1):
            progress(f"Applying density {fac:g} / height {hf:g}", i, len(files))
            r = rel(xp, f)
            fo = ForFile(f, quick=True)
            if state(fo, log.get(r)) == "tweaked":
                already += 1
                continue
            if min_spacing(fo.head) <= THRESHOLD:
                skip += 1
                continue
            fo = ForFile(f)
            new_head, new_tail, do_trees = fo.head, fo.tail, hf < 1.0
            if do_trees:
                # safety: all TREE lines of the file must be in the tree list at the end
                if len(TREE_RX.findall(fo.data.decode("latin-1"))) != len(fo.tlines):
                    do_trees = False
                    odd += 1
            if fac < 1.0:
                new_head = LINE_RX.sub(lambda m: m.group(1) + m.group(2) + m.group(3)
                                       + fmt(float(m.group(4)) * fac) + m.group(5)
                                       + fmt(float(m.group(6)) * fac), fo.head)
            if do_trees:
                # min and max height scaled alike -> the height variation shrinks with them
                new_tail = TREE_RX.sub(lambda m: m.group(1) + m.group(2) + m.group(3)
                                       + fmt(float(m.group(4)) * hf) + m.group(5)
                                       + fmt(float(m.group(6)) * hf), fo.tail)
            new_mid, meshes = None, set()
            if do_trees:
                meshes = tree_meshes(fo.tail)
                if meshes:
                    new_mid = scale_meshes(fo.data, fo.head_len, fo.tail_start, meshes, hf)
            if new_head == fo.head and new_tail == fo.tail and new_mid is None:
                skip += 1
                continue
            entry = {"f": r, "x": fac, "h": hf, "o": fo.lines,
                     "n": [m.group(0) for m in LINE_RX.finditer(new_head)]}
            if new_tail != fo.tail:
                entry["ot"] = fo.tlines
                entry["nt"] = [m.group(0) for m in TREE_RX.finditer(new_tail)]
            if new_mid is not None:
                # 3D meshes change -> keep a compressed copy of the original file for an exact restore
                bp = backup_path(xp, r)
                os.makedirs(os.path.dirname(bp), exist_ok=True)
                with gzip.open(bp, "wb") as g:
                    g.write(fo.data)
                entry["mb"] = True
                mesh_count += len(meshes)
            # log first, then write: an interruption can never lead to double scaling
            lf.write(json.dumps(entry, separators=(",", ":")) + "\n")
            lf.flush()
            os.fsync(lf.fileno())
            write_for(f, fo, new_head, new_tail, new_mid)
            done += 1
    progress_end()
    say()
    say(f"  Tweaked now          : {done}", C_GREEN)
    say(f"  Already tweaked      : {already}")
    say(f"  Grass/shrubs (kept)  : {skip}")
    if mesh_count:
        bk = os.path.join(xp, TWEAK_DIR, "mesh_backup")
        mb = sum(os.path.getsize(os.path.join(r_, n)) for r_, _d, ns in os.walk(bk) for n in ns) / 2**20
        say(f"  3D tree models scaled: {mesh_count}   (backup: {mb:.0f} MB in {TWEAK_DIR}/mesh_backup)")
    if odd:
        say(f"  Unusual layout       : {odd} (density changed, tree heights left as they are)", C_YELLOW)


def restore(xp, targets, quiet=False):
    lp = log_path(xp)
    log = read_log(lp)
    if not log:
        if not quiet:
            say("  Forests: nothing to restore (no backup log).")
        return
    files = get_files(targets)
    done = 0
    for i, f in enumerate(files, 1):
        progress("Restoring", i, len(files))
        r = rel(xp, f)
        e = log.get(r)
        if not e:
            continue
        fo = ForFile(f)
        bp = backup_path(xp, r)
        if state(fo, e) != "tweaked":
            # file was reset by an update -> its backup is outdated
            if os.path.exists(bp):
                os.remove(bp)
            del log[r]
            continue
        if e.get("mb") and os.path.exists(bp):
            with gzip.open(bp, "rb") as g:
                write_bytes(f, g.read())
            os.remove(bp)
            del log[r]
            done += 1
            continue
        new_head = set_seq(fo.head, LINE_RX, e.get("o"))
        new_tail = set_seq(fo.tail, TREE_RX, e["ot"]) if "ot" in e else fo.tail
        write_for(f, fo, new_head, new_tail)
        del log[r]
        done += 1
    progress_end()
    # keep log entries of files outside the chosen folders (e.g. GFv2 when it was not included)
    roots = [rel(xp, t) + "/" for t in targets]
    keep = [e for k, e in log.items() if not any(k.lower().startswith(p.lower()) for p in roots)]
    with open(lp, "w", encoding="utf-8", newline="\n") as lf:
        for e in keep:
            lf.write(json.dumps(e, separators=(",", ":")) + "\n")
    if not quiet:
        say()
        say(f"  Forests restored     : {done} files", C_GREEN)


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
    d = os.path.join(xp, TWEAK_DIR)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "hedges.log")


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


def hedge_status_line(xp):
    files, overall, _ = hedge_overview(xp)
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
                say(f"  Skipped (unexpected 3D content): {r}", C_YELLOW)
                continue
            new = TREE_RX.sub(lambda m: m.group(1) + m.group(2) + m.group(3)
                              + fmt(float(m.group(4)) * HEDGE_FAC) + m.group(5)
                              + fmt(float(m.group(6)) * HEDGE_FAC), text)
            lm = LOD_RX.search(new)
            if lm and float(lm.group(2)) < HEDGE_LOD:
                new = new[:lm.start()] + lm.group(1) + str(HEDGE_LOD) + new[lm.end():]
            entry = {"f": r, "ol": lod_line(text), "nl": lod_line(new),
                     "ot": [m.group(0) for m in TREE_RX.finditer(text)],
                     "nt": [m.group(0) for m in TREE_RX.finditer(new)]}
            lf.write(json.dumps(entry, separators=(",", ":")) + "\n")     # log first, then write
            lf.flush()
            os.fsync(lf.fileno())
            write_bytes(f, new.encode("latin-1"))
            done += 1
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
    with open(hedge_log_path(xp), "w", encoding="utf-8", newline="\n") as lf:
        for e in log.values():
            lf.write(json.dumps(e, separators=(",", ":")) + "\n")
    say(f"  simHeaven hedges back to default: {done} files", C_GREEN)


# ---------------------------------------------------------------- [1] choose settings
def forest_state(xp, targets):
    """Current forest tweak: (tweaked files, tweakable files still original, density, height)."""
    log = read_log(log_path(xp))
    n, n_orig, x, h = 0, 0, None, None
    files = get_files(targets)
    for i, f in enumerate(files, 1):
        progress("Checking", i, len(files))
        fo = ForFile(f, quick=True)
        e = log.get(rel(xp, f))
        if e and state(fo, e) == "tweaked":
            n += 1
            x, h = float(e["x"]), get_h(e)
        elif min_spacing(fo.head) > THRESHOLD:
            n_orig += 1
    progress_end()
    return n, n_orig, x, h


def ask_value(prompt, current, minimum):
    while True:
        a = input(f"{prompt} (Enter = {current:g}): ").strip()
        if a == "":
            return current
        try:
            v = float(a.replace(",", "."))
        except ValueError:
            v = -1
        if minimum <= v <= 1.0:
            return v
        say(f"  Please enter a value from {minimum:g} to 1.0.", C_YELLOW)


def choose_settings(xp, targets):
    n, n_orig, cur_x, cur_h = forest_state(xp, targets)
    cur_x = cur_x if n else 1.0
    cur_h = cur_h if n else 1.0
    hfiles, hstate, hlog = hedge_overview(xp)
    steps = 3 if hfiles else 2
    say()
    say("  Nothing is changed until you confirm at the end.")
    say()
    say(f"  Step 1/{steps}  Density factor: 0.4 - 1.0. Lower = denser, 1 = original.")
    say(f"               {DEFAULT_FAC} = about twice as many trees (recommended).")
    fac = ask_value("  Density factor", cur_x if n else DEFAULT_FAC, 0.4)
    say()
    say(f"  Step 2/{steps}  Tree height factor: {MIN_HEIGHT} - 1.0. Lower = smaller trees, 1 = original.")
    say("               Scales all trees including the 3D models, e.g. 0.8 = 20 % smaller.")
    hf = ask_value("  Tree height factor", cur_h, MIN_HEIGHT)
    want_h = None
    if hfiles:
        say()
        say(f"  Step 3/{steps}  simHeaven hedges (e.g. the Knicks in northern Germany):")
        say("               [1] default   2.2 - 2.8 m high, visible up to 4 km")
        say("               [2] enhanced  about 4 - 5 m high, visible up to 8 km")
        cur = "2" if hstate == "enhanced" else "1"
        while want_h is None:
            a = input(f"  Hedges [1/2] (Enter = {cur}): ").strip() or cur
            want_h = {"1": "default", "2": "enhanced"}.get(a)
    # summary
    # also re-apply unchanged values when an update has reset some files to original
    refresh = n and n_orig and (fac, hf) == (cur_x, cur_h)
    forest_change = (fac, hf) != (cur_x, cur_h) or bool(refresh)
    hedge_change = hfiles and want_h != hstate
    say()
    say("  Summary")
    say("  -------")
    def fv(x, h):
        return "original" if (x, h) == (1.0, 1.0) else f"density {x:g}, tree height {h:g}"
    if refresh:
        say(f"  Forests : {fv(cur_x, cur_h)}  ->  re-apply to {n_orig} files reset by an update")
    else:
        say(f"  Forests : {fv(cur_x, cur_h)}" + (f"  ->  {fv(fac, hf)}" if forest_change else "  (unchanged)"))
    if hfiles:
        say(f"  Hedges  : {hstate}" + (f"  ->  {want_h}" if hedge_change else "  (unchanged)"))
    if not forest_change and not hedge_change:
        say("  Nothing to change.")
        return
    if forest_change and hf < 1.0:
        files = get_files(targets)
        need = int(sum(os.path.getsize(f) for f in files) * 0.35)
        free = shutil.disk_usage(xp).free
        say(f"  Smaller trees also scale the 3D tree models. A compressed backup of the originals is kept")
        say(f"  for an exact restore: about {need / 2**30:.1f} GB (free on disk: {free / 2**30:.1f} GB).")
        if free < need + 2**30:
            say("  Not enough free disk space.", C_YELLOW)
            return
    if forest_change:
        say("  Depending on your PC this can take several minutes", C_YELLOW)
        say("  (longer with tree height and Global Forests v2). Please keep this window open.", C_YELLOW)
    if input("  Apply these settings now? [Y/n] ").strip()[:1] in ("n", "N"):
        say("  Cancelled - nothing was changed.")
        return
    if forest_change:
        if n and not refresh:
            say("  Restoring the original forests first ...")
            restore(xp, targets, quiet=True)
        if (fac, hf) != (1.0, 1.0):
            apply_values(xp, targets, fac, hf)
        else:
            say("  Forests are original again.", C_GREEN)
    if hedge_change:
        if want_h == "enhanced":
            hedges_apply(xp, hfiles, hlog)
        else:
            hedges_restore(xp, hfiles, hlog)


def restore_all(xp, targets):
    restore(xp, targets)
    hfiles, hstate, hlog = hedge_overview(xp)
    if hfiles and hstate != "default":
        hedges_restore(xp, hfiles, hlog)


def xplane_running():
    for name in ("X-Plane", "X-Plane-x86_64"):
        try:
            if subprocess.run(["pgrep", "-x", name], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0:
                return True
        except OSError:
            return False
    return False


def main():
    if sys.version_info < (3, 8):
        say("Python 3.8 or newer is needed.", C_RED)
        return
    say()
    say(f"  XP12 Forest Tweak {VERSION} - macOS / Linux", C_CYAN)
    say("  ------------------------------------------------------------")
    xp = os.path.realpath(find_xplane())
    targets = get_targets(xp)
    say(f"  X-Plane : {xp}")
    for t in targets:
        say(f"  Folder  : {rel(xp, t)}")
    if xplane_running():
        say("  X-Plane is running - please close it first.", C_YELLOW)
    show_status(xp, targets)
    while True:
        say()
        say("  [1] Choose settings   [2] Restore original   [3] Status   [Q] Quit")
        a = input("  Choice: ").strip()
        if a == "1":
            choose_settings(xp, targets)
        elif a == "2":
            restore_all(xp, targets)
        elif a == "3":
            show_status(xp, targets)
        elif a.lower() == "q":
            return


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        say()
    except Exception as ex:          # show a readable message instead of a traceback
        say()
        say(f"  ERROR: {ex}", C_RED)
        sys.exit(1)
