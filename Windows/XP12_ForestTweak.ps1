<#
  XP12 Forest Tweak  -  Windows
  Version 1.5.1 (2026-11-08)   https://github.com/E11i0t09/xp12-forest-tweak

  Denser forests and optionally smaller trees for X-Plane 12 - for vanilla X-Plane,
  simHeaven X-World and Global Forests v2 (one tool for all; if Global Forests v2 is
  installed, it asks whether to include it).

  What it does
  - Tree spacing: SPACING and RANDOM in the forest files (.for) are multiplied by a factor
    (0.7 = about twice as many trees per area). The vegetation slider in X-Plane can
    never go above the density set there. RANDOM is scaled too, so the trees keep the
    same relative irregularity instead of clumping together.
  - RANDOM (how far a tree may move away from its grid position) is set to at least half
    the tree spacing in natural forests, so dense forests show no lines from the planting
    grid. Planted rows (orchards etc.) keep their grid.
  - Global Forests v2 "cropland" forests (field trees and hedgerows between fields) get
    an extra factor of 0.8 on top, so field edges are filled more evenly. Sparse Global
    Forests v2 forests (density classes 25 and 50) get an extra 0.75 / 0.85.
  - Files with SPACING <= 3.1 m (grass, shrubs, hedges) are left untouched.
  - Optional tree height factor (0.5 - 1.0): min and max height of every tree are scaled.
    "realistic" profile: conifers shrink less, palms a bit less, shrubs/orchards hardly.
    TREE2 3D trees scale by themselves (nominal height is kept); the 3D models of TREE
    trees are drawn at their modelled size, so their vertices are scaled too. Before
    that, a compressed copy (with SHA-256 checksum) of the original file is stored in
    <X-Plane>\ForestDensityTweak\mesh_backup for an exact restore.
  - Every original line is logged in <X-Plane>\ForestDensityTweak\backup.log
    (shared with the macOS/Linux version and all earlier versions), so "Restore original"
    puts back the exact original values and nothing is ever scaled twice.
  - Optional, with simHeaven X-World (free) or X-WORLD Pro: hedges "original", "enhanced"
    (green hedges about 4-5 m high, all four seasons) or "hedgebanks (Knicks)" (in northern
    Germany and Denmark bushes on earth banks with single hedgerow trees, elsewhere enhanced).
    Free X-World: the hedge files of its Vegetation Library are changed (originals logged in
    ForestDensityTweak\hedges.log). X-WORLD Pro draws hedges as walls, which can not be changed
    through a library, so the tool rebuilds them as hedges in the countries you choose.
    Official hedge maps (Schleswig-Holstein, Niedersachsen/Bremen/Hamburg, Nordrhein-Westfalen,
    Bayern, Brandenburg, Denmark; see DATA_LICENSES.txt) add the hedges that OpenStreetMap does
    not have. Both are built on this computer into Custom Scenery\XP12_ForestTweak_HedgerowMap.
    The tool library Custom Scenery\XP12_ForestTweak_Knicks (textures copied from the X-Plane
    default forests) defines the hedge types. Both folders are listed in scenery_packs.ini
    (backup kept). simHeaven files are only read; nothing of simHeaven is shipped.
  - Actions are written to ForestDensityTweak\tool.log (helpful for bug reports).

  After an X-Plane or Global Forests update the updated files are original again.
  Just run "Choose settings" once more and confirm: reset files are tweaked again.

  Performance: more trees cost GPU time. Start with 0.7, go to 0.8 if FPS drop too much,
  0.6 only on strong GPUs. Use at your own risk.
  (c) E11i0t09. Free community project, not for sale. License: CC BY-NC-SA 4.0 with additional permission (free use also for companies and flight schools), see the LICENSE file.
#>

$ErrorActionPreference = 'Stop'
$Version    = '1.5.1'
$TestedXP   = '12.4'          # X-Plane version the tool was tested with
$Repo       = 'E11i0t09/xp12-forest-tweak'
$Threshold  = 3.1             # files with a smaller tree spacing are grass/shrubs/hedges -> kept
$Presets    = @(@('Natural', 0.8, 'noticeably denser'), @('Dense', 0.7, 'about 2x trees, recommended'), @('Very dense', 0.6, 'about 2.8x trees, needs a strong GPU'))
$DefaultFac = 0.7             # preset [2]
$DefaultHeight = 0.7          # height preset [3]
$MinFac     = 0.4
$MinHeight  = 0.5             # lowest allowed height factor
$HeightPresets = @(@('Original', 1.0, 'trees as in X-Plane'), @('Slightly smaller', 0.8, '20 % smaller'), @('Smaller', 0.7, '30 % smaller'), @('Much smaller', 0.6, '40 % smaller'))
$CropFac    = 0.8             # extra spacing factor for Global Forests v2 cropland forests
$SparseFac  = @{ '25' = 0.75; '50' = 0.85 }   # extra spacing factor for sparse Global Forests v2 density classes
$SparseRx   = [regex]'_(25|50)_y\d+\.for$'
$RandTarget = 0.5             # RANDOM at least half the tree spacing (no empty strips between grid rows)
$RandMinRatio = 0.25          # below this ratio the forest is a planted row grid on purpose (orchards etc.)
$DiskMargin = 200MB           # always keep this much free space
$MeshWeight = 6               # a file whose 3D models are scaled takes about 6x longer than one with only new header lines
$Rate       = 45MB            # rough work units per second (for the time estimate only)
$RateRestore = 40MB           # bytes per second when restoring
$Inv        = [Globalization.CultureInfo]::InvariantCulture
$Latin1     = [Text.Encoding]::GetEncoding(28591)   # 1:1 byte <-> char, keeps files byte-exact
$Utf8       = New-Object Text.UTF8Encoding($false)
$LineRx     = [regex]'(?m)^([ \t]*)(SPACING|RANDOM)([ \t]+)([0-9]*\.?[0-9]+)([ \t]+)([0-9]*\.?[0-9]+)'
$HeaderEnd  = [regex]'(?m)^[ \t]*(TREE|TREE2|MESH|MESH_3D|GROUP)\b'
# TREE  <s> <t> <w> <h> <offset> <frequency> <min h> <max h> ...
# TREE2 <s1> <t1> <w> <h> <sw> <percent> <min_height> <max_height> <nominal_height> ...
$TreeRx     = [regex]'(?m)^([ \t]*TREE2?)((?:[ \t]+\S+){6})([ \t]+)([0-9]*\.?[0-9]+)([ \t]+)([0-9]*\.?[0-9]+)(?=[ \t\r\n]|$)'
$MeshDataRx = [regex]'(?m)^[ \t]*(VERTEX|IDX\d*)\b[^\n]*\n?'
$ShrubRx    = [regex]'shrub|_shr_|cact|orch|fruit|agave|yucca'
$OtherRx    = [regex]'(?i)true[ _-]?earth|forest|trees|vegetation'
$Sep        = [IO.Path]::DirectorySeparatorChar
$script:ToolLog = $null

function Fmt([double]$v) { $v.ToString('0.###', $Inv) }
function Rnd([double]$v, [int]$d) { [Math]::Round($v, $d, [MidpointRounding]::AwayFromZero) }
function Warn([string]$t) { Write-Host $t -ForegroundColor Yellow }

function TLog([string]$msg) {
    if (-not $script:ToolLog) { return }
    try {
        if ((Test-Path -LiteralPath $script:ToolLog) -and (Get-Item -LiteralPath $script:ToolLog).Length -gt 1MB) {
            $keep = @([IO.File]::ReadAllLines($script:ToolLog) | Select-Object -Last 2000)
            [IO.File]::WriteAllLines($script:ToolLog, [string[]]$keep, $Utf8)
        }
        [IO.File]::AppendAllText($script:ToolLog, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg + "`n", $Utf8)
    } catch { }
}

# Fast helpers in C# (compiled once at start, no install needed):
#  - ScaleMeshes: multiplies x/y/z of the VERTEX lines of the given 3D meshes, everything else byte for byte
#  - Gzip / Gunzip: compressed backup of the original file before its 3D meshes are changed
#  - Sha256 / Sha256Gz: checksum of the original file, checked before a restore
if (-not ('FdtMesh14' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.IO; using System.IO.Compression; using System.Collections.Generic; using System.Globalization; using System.Text; using System.Security.Cryptography;
public static class FdtMesh14 {
    static bool Ws(byte b) { return b == 32 || b == 9; }
    static bool At(byte[] d, int k, int end, string w) {
        if (k + w.Length >= end) return false;
        for (int i = 0; i < w.Length; i++) if (d[k + i] != (byte)w[i]) return false;
        return Ws(d[k + w.Length]);
    }
    public static byte[] ScaleMeshes(byte[] d, int start, int end, string[] names, double f) {
        var set = new HashSet<string>(names);
        var ms = new MemoryStream(end - start + 1024);
        var inv = CultureInfo.InvariantCulture;
        bool active = false; int i = start;
        while (i < end) {
            int j = Array.IndexOf(d, (byte)10, i, end - i); int le = j < 0 ? end : j + 1;
            int k = i; while (k < le && Ws(d[k])) k++;
            if (At(d, k, le, "MESH")) {
                int a = k + 4; while (a < le && Ws(d[a])) a++;
                int b = a; while (b < le && !Ws(d[b]) && d[b] != 13 && d[b] != 10) b++;
                active = set.Contains(Encoding.ASCII.GetString(d, a, b - a));
                ms.Write(d, i, le - i);
            } else if (active && At(d, k, le, "VERTEX")) {
                int p = k + 6; ms.Write(d, i, p - i);
                for (int n = 0; n < 3; n++) {
                    int a = p; while (a < le && Ws(d[a])) a++;
                    ms.Write(d, p, a - p);
                    int b = a; while (b < le && !Ws(d[b]) && d[b] != 13 && d[b] != 10) b++;
                    double v = double.Parse(Encoding.ASCII.GetString(d, a, b - a), NumberStyles.Float, inv);
                    string t = (v * f).ToString("0.#######", inv);
                    if (t == "-0") t = "0";     // same result on every .NET version (and in the macOS/Linux version)
                    byte[] o = Encoding.ASCII.GetBytes(t);
                    ms.Write(o, 0, o.Length); p = b;
                }
                ms.Write(d, p, le - p);
            } else ms.Write(d, i, le - i);
            i = le;
        }
        return ms.ToArray();
    }
    public static void Gzip(byte[] data, string path) {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        string tmp = path + ".tmp";
        using (var fs = File.Create(tmp)) using (var gz = new GZipStream(fs, CompressionMode.Compress)) gz.Write(data, 0, data.Length);
        if (File.Exists(path)) File.Delete(path);
        File.Move(tmp, path);
    }
    public static byte[] Gunzip(string path) {
        using (var fs = File.OpenRead(path)) using (var gz = new GZipStream(fs, CompressionMode.Decompress)) using (var ms = new MemoryStream()) { gz.CopyTo(ms); return ms.ToArray(); }
    }
    static string Hex(byte[] h) { var sb = new StringBuilder(); foreach (byte b in h) sb.Append(b.ToString("x2")); return sb.ToString(); }
    public static string Sha256(byte[] data) { using (var s = SHA256.Create()) return Hex(s.ComputeHash(data)); }
    public static string Sha256Gz(string path) {
        using (var fs = File.OpenRead(path)) using (var gz = new GZipStream(fs, CompressionMode.Decompress)) using (var s = SHA256.Create()) return Hex(s.ComputeHash(gz));
    }
}
"@
}

# Hedge overlay: reads the official hedge maps (hedgerow_map_*.dat, shipped with the tool) and the simHeaven
# hedges/tree rows of this computer and turns them into X-Plane DSF tiles (same steps as the macOS/Linux version).
if (-not ('FdtHedgeMap' -as [type])) {
    try { Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue } catch { }
    # Windows PowerShell 5.1 needs the ZIP assembly listed; PowerShell 7 references it by default
    $kmArgs = @{}
    if ($PSVersionTable.PSEdition -eq 'Desktop') { $kmArgs.ReferencedAssemblies = @('System.IO.Compression') }
Add-Type @kmArgs -TypeDefinition @"
using System; using System.IO; using System.IO.Compression; using System.Collections.Generic; using System.Text; using System.Security.Cryptography;
// Hedge overlay: official hedge maps + simHeaven hedges/tree rows -> X-Plane DSF tiles.
// Same algorithm as the macOS/Linux version (step by step, same results byte for byte).
public static class FdtHedgeMap {
    public const double GrsA = 6378137.0, GrsF = 1 / 298.257222101, K0 = 0.9996;
    public static readonly double Deg = 180.0 / Math.PI;
    static double UA; static double[] Beta, Delta;
    static FdtHedgeMap() {
        double n = GrsF / (2 - GrsF), n2 = n * n, n3 = n2 * n;
        UA = GrsA / (1 + n) * (1 + n2 / 4 + n2 * n2 / 64);
        Beta = new double[] { n / 2 - 2 * n2 / 3 + 37 * n3 / 96, n2 / 48 + n3 / 15, 17 * n3 / 480 };
        Delta = new double[] { 2 * n - 2 * n2 / 3 - 2 * n3, 7 * n2 / 3 - 8 * n3 / 5, 56 * n3 / 15 };
    }
    static double Hyp(double x, double y) { return Math.Sqrt(x * x + y * y); }
    public static double[] Utm(double e, double nn) {
        double xi = nn / (K0 * UA), eta = (e - 32500000.0) / (K0 * UA), xp = xi, ep = eta;
        for (int j = 0; j < 3; j++) { double k = 2 * (j + 1); xp -= Beta[j] * Math.Sin(k * xi) * Math.Cosh(k * eta); ep -= Beta[j] * Math.Cos(k * xi) * Math.Sinh(k * eta); }
        double chi = Math.Asin(Math.Sin(xp) / Math.Cosh(ep)), phi = chi;
        for (int j = 0; j < 3; j++) phi += Delta[j] * Math.Sin(2 * (j + 1) * chi);
        return new double[] { 9.0 + Math.Atan2(Math.Sinh(ep), Math.Cos(xp)) * Deg, phi * Deg };
    }
    public class Lcg { uint s; public Lcg(long seed) { s = (uint)(seed & 0xFFFFFFFF); }
        public double Next() { unchecked { s = s * 1664525u + 1013904223u; } return s / 4294967296.0; } }

    // codes: lines 0 HW (Knick/hedge), 1 HF (field hedge), 2 HR (tree row), 3 HA (avenue); areas 4 AH (hedge), 5 AR (tree row), 6 AC (copse)
    public class Rec { public int Code; public int[] Ints; public Rec(int c, int[] i) { Code = c; Ints = i; } }
    public static Dictionary<long, List<Rec>> Data = new Dictionary<long, List<Rec>>();
    public static long TileKey(int s, int w) { return ((long)(s + 1000) << 16) + (long)(w + 1000); }
    static int Varint(byte[] b, ref int o) { int v = 0, sh = 0; while (true) { int c = b[o++]; v |= (c & 0x7F) << sh; if ((c & 0x80) == 0) return v; sh += 7; } }

    // hedge map shipped with the tool: gzip, "XFTHMAP1", line count, point count, then per line:
    // code, point count, zigzag varint deltas of easting/northing in 0.1 m (EPSG 4647)
    public static void ReadMap(string path) {
        byte[] b;
        using (FileStream fs = File.OpenRead(path)) using (GZipStream gz = new GZipStream(fs, CompressionMode.Decompress)) using (MemoryStream ms = new MemoryStream()) { gz.CopyTo(ms); b = ms.ToArray(); }
        if (Encoding.ASCII.GetString(b, 0, 8) != "XFTHMAP1") throw new Exception("hedge map: unknown file format: " + Path.GetFileName(path));
        int nl = BitConverter.ToInt32(b, 8), o = 16;
        for (int li = 0; li < nl; li++) {
            int ci = b[o++]; int n = Varint(b, ref o); long e = 0, nn = 0;
            int[] ints = new int[2 * n]; long mnx = long.MaxValue, mxx = long.MinValue, mny = long.MaxValue, mxy = long.MinValue;
            for (int k = 0; k < n; k++) {
                int de = Varint(b, ref o), dn = Varint(b, ref o);
                e += (de >> 1) ^ -(de & 1); nn += (dn >> 1) ^ -(dn & 1);
                ints[2 * k] = (int)e; ints[2 * k + 1] = (int)nn;
                if (e < mnx) mnx = e; if (e > mxx) mxx = e; if (nn < mny) mny = nn; if (nn > mxy) mxy = nn;
            }
            double lo0 = double.MaxValue, lo1 = double.MinValue, la0 = double.MaxValue, la1 = double.MinValue;
            foreach (long ce in new long[] { mnx, mxx }) foreach (long cn in new long[] { mny, mxy }) {
                double[] ll = Utm(ce / 10.0, cn / 10.0);
                if (ll[0] < lo0) lo0 = ll[0]; if (ll[0] > lo1) lo1 = ll[0]; if (ll[1] < la0) la0 = ll[1]; if (ll[1] > la1) la1 = ll[1];
            }
            Rec r = new Rec(ci, ints);
            for (int s = (int)Math.Floor(la0); s <= (int)Math.Floor(la1); s++)
                for (int w = (int)Math.Floor(lo0); w <= (int)Math.Floor(lo1); w++) {
                    long key = TileKey(s, w); List<Rec> l;
                    if (!Data.TryGetValue(key, out l)) { l = new List<Rec>(); Data[key] = l; }
                    l.Add(r);
                }
        }
    }
    public static void Clear() { Data = new Dictionary<long, List<Rec>>(); }
    public static int[] DataTiles() {
        List<int> r = new List<int>();
        foreach (long k in Data.Keys) { r.Add((int)(k >> 16) - 1000); r.Add((int)(k & 0xFFFF) - 1000); }
        return r.ToArray();
    }
    static List<double[]> ToLL(int[] ints) { List<double[]> r = new List<double[]>(ints.Length / 2); for (int i = 0; i < ints.Length; i += 2) r.Add(Utm(ints[i] / 10.0, ints[i + 1] / 10.0)); return r; }

    static List<List<double[]>> Clip(List<double[]> pts, int w, int s) {
        List<List<double[]>> outp = new List<List<double[]>>(); List<double[]> cur = new List<double[]>();
        for (int i = 0; i + 1 < pts.Count; i++) {
            double x0 = pts[i][0], y0 = pts[i][1], dx = pts[i + 1][0] - x0, dy = pts[i + 1][1] - y0, u0 = 0.0, u1 = 1.0; bool ok = true;
            double[] P = { -dx, dx, -dy, dy }, Q = { x0 - w, w + 1 - x0, y0 - s, s + 1 - y0 };
            for (int k = 0; k < 4; k++) {
                if (P[k] == 0) { if (Q[k] < 0) ok = false; }
                else { double u = Q[k] / P[k]; if (P[k] < 0) u0 = Math.Max(u0, u); else u1 = Math.Min(u1, u); }
            }
            if (!ok || u0 > u1) { if (cur.Count > 1) outp.Add(cur); cur = new List<double[]>(); continue; }
            double[] a = { x0 + u0 * dx, y0 + u0 * dy }, b = { x0 + u1 * dx, y0 + u1 * dy };
            if (cur.Count > 0 && cur[cur.Count - 1][0] == a[0] && cur[cur.Count - 1][1] == a[1]) cur.Add(b);
            else { if (cur.Count > 1) outp.Add(cur); cur = new List<double[]>(); cur.Add(a); cur.Add(b); }
        }
        if (cur.Count > 1) outp.Add(cur);
        return outp;
    }
    // polygon clipped to the tile (Sutherland-Hodgman), edges in the order west, east, south, north
    static List<double[]> ClipPoly(List<double[]> pts, int w, int s) {
        List<double[]> p = new List<double[]>(pts);
        for (int edge = 0; edge < 4 && p.Count > 0; edge++) {
            List<double[]> outp = new List<double[]>();
            for (int i = 0; i < p.Count; i++) {
                double[] a = p[i == 0 ? p.Count - 1 : i - 1], b = p[i];
                bool ia = Inside(a, edge, w, s), ib = Inside(b, edge, w, s);
                if (ib) { if (!ia) outp.Add(Inter(a, b, edge, w, s)); outp.Add(b); }
                else if (ia) outp.Add(Inter(a, b, edge, w, s));
            }
            p = outp;
        }
        return p;
    }
    static bool Inside(double[] q, int edge, int w, int s) {
        switch (edge) { case 0: return q[0] >= w; case 1: return q[0] <= w + 1; case 2: return q[1] >= s; default: return q[1] <= s + 1; }
    }
    static double[] Inter(double[] a, double[] b, int edge, int w, int s) {
        if (edge < 2) { double x = edge == 0 ? w : w + 1; double t = (x - a[0]) / (b[0] - a[0]); return new double[] { x, a[1] + t * (b[1] - a[1]) }; }
        double y = edge == 2 ? s : s + 1; double u = (y - a[1]) / (b[1] - a[1]); return new double[] { a[0] + u * (b[0] - a[0]), y };
    }
    static List<double[]> AreaRing(List<double[]> pts, int w, int s) {
        if (pts.Count > 1 && pts[0][0] == pts[pts.Count - 1][0] && pts[0][1] == pts[pts.Count - 1][1]) pts = pts.GetRange(0, pts.Count - 1);
        if (pts.Count < 3) return null;
        double mnx = double.MaxValue, mxx = double.MinValue, mny = double.MaxValue, mxy = double.MinValue;
        foreach (double[] p in pts) { if (p[0] < mnx) mnx = p[0]; if (p[0] > mxx) mxx = p[0]; if (p[1] < mny) mny = p[1]; if (p[1] > mxy) mxy = p[1]; }
        if (mnx < w || mxx > w + 1 || mny < s || mxy > s + 1) { pts = ClipPoly(pts, w, s); if (pts.Count < 3) return null; }
        double area = 0.0;
        for (int i = 0; i < pts.Count; i++) { double[] p0 = pts[i == 0 ? pts.Count - 1 : i - 1], p1 = pts[i]; area += p0[0] * p1[1] - p1[0] * p0[1]; }
        if (area < 0) { pts = new List<double[]>(pts); pts.Reverse(); }
        while (pts.Count > 255) pts = Half(pts);
        List<double[]> r = new List<double[]>(pts.Count);
        foreach (double[] p in pts) r.Add(new double[] { Math.Min(Math.Max(p[0], w), w + 1), Math.Min(Math.Max(p[1], s), s + 1) });
        return r;
    }
    static List<double[]> Half(List<double[]> pts) { List<double[]> h = new List<double[]>(); for (int i = 0; i < pts.Count; i += 2) h.Add(pts[i]); return h; }

    // --- tile geometry
    class Geo { public int S, W; public double Kx, Ky = 110574.0;
        public Geo(int s, int w) { S = s; W = w; Kx = 111320.0 * Math.Cos((s + 0.5) / Deg); }
        public double[] ToM(double[] p, double[] o) { return new double[] { (p[0] - o[0]) * Kx, (p[1] - o[1]) * Ky }; }
        public double[] ToLL(double mx, double my, double[] o) { return new double[] { o[0] + mx / Kx, o[1] + my / Ky }; }
        public double[] Clamp(double[] p) { return new double[] { Math.Min(Math.Max(p[0], W), W + 1), Math.Min(Math.Max(p[1], S), S + 1) }; }
        public long Cell(double[] p) { return Key((long)Math.Floor((p[0] - W) * Kx / 20.0), (long)Math.Floor((p[1] - S) * Ky / 20.0)); }
        public bool Near(HashSet<long> set, double[] p) {
            long cx = (long)Math.Floor((p[0] - W) * Kx / 20.0), cy = (long)Math.Floor((p[1] - S) * Ky / 20.0);
            for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) if (set.Contains(Key(cx + i, cy + j))) return true;
            return false;
        }
        public bool HalfNear(HashSet<long> set, List<double[]> pts) { int hit = 0; foreach (double[] p in pts) if (Near(set, p)) hit++; return hit * 2 >= pts.Count; }
    }
    static long Key(long x, long y) { return (x << 32) ^ (y & 0xFFFFFFFFL); }
    static List<double[]> Resample(Geo g, List<double[]> line, double step, Lcg rng) {
        double[] o = line[0]; List<double[]> outp = new List<double[]>(); double acc = 0.0, nxt = step * rng.Next();
        for (int i = 0; i + 1 < line.Count; i++) {
            double[] a = g.ToM(line[i], o), b = g.ToM(line[i + 1], o);
            double L = Hyp(b[0] - a[0], b[1] - a[1]);
            if (L == 0) continue;
            double ux = (b[0] - a[0]) / L, uy = (b[1] - a[1]) / L;
            while (nxt <= acc + L) { double d = nxt - acc; outp.Add(new double[] { a[0] + ux * d, a[1] + uy * d, ux, uy }); nxt += step; }
            acc += L;
        }
        return outp;
    }
    static List<double[]> Ribbon(Geo g, List<double[]> line, double half) {
        double[] o = line[0]; List<double[]> q = new List<double[]>(); q.Add(g.ToM(line[0], o));
        for (int i = 1; i < line.Count; i++) { double[] p = g.ToM(line[i], o); double[] l = q[q.Count - 1]; if (Hyp(p[0] - l[0], p[1] - l[1]) > 0.3) q.Add(p); }
        if (q.Count < 2) return null;
        List<double[]> n = new List<double[]>();
        for (int i = 0; i + 1 < q.Count; i++) { double L = Hyp(q[i + 1][0] - q[i][0], q[i + 1][1] - q[i][1]); n.Add(new double[] { (q[i + 1][1] - q[i][1]) / L, -(q[i + 1][0] - q[i][0]) / L }); }
        List<double[]> left = new List<double[]>(), right = new List<double[]>();
        for (int i = 0; i < q.Count; i++) {
            double nx, ny;
            if (i == 0) { nx = n[0][0]; ny = n[0][1]; }
            else if (i == q.Count - 1) { nx = n[n.Count - 1][0]; ny = n[n.Count - 1][1]; }
            else {
                nx = n[i - 1][0] + n[i][0]; ny = n[i - 1][1] + n[i][1]; double L = Hyp(nx, ny);
                if (L < 1e-6) { nx = n[i][0]; ny = n[i][1]; }
                else { nx = nx / L; ny = ny / L; double c = nx * n[i][0] + ny * n[i][1]; double f = 1 / Math.Max(c, 0.5); nx = nx * f; ny = ny * f; }
            }
            right.Add(g.ToLL(q[i][0] + nx * half, q[i][1] + ny * half, o)); left.Add(g.ToLL(q[i][0] - nx * half, q[i][1] - ny * half, o));
        }
        left.Reverse(); right.AddRange(left); return right;
    }

    // --- DSF reading (forest and facade polygons of a simHeaven tile)
    class Feat { public int D; public int P; public List<double[]> Pts; public Feat(int d, int p, List<double[]> pts) { D = d; P = p; Pts = pts; } }
    static string Id(byte[] b, int o) { return new string(new char[] { (char)b[o + 3], (char)b[o + 2], (char)b[o + 1], (char)b[o] }); }
    static List<int[]> Atoms(byte[] b, int o, int end) { List<int[]> r = new List<int[]>(); while (o < end) { int ln = BitConverter.ToInt32(b, o + 4); r.Add(new int[] { o, ln }); o += ln; } return r; }
    static int Plane(byte[] d, int o, int n, ushort[] vals) {
        int enc = d[o]; o++; int c = 0;
        if (enc == 0 || enc == 1) { for (int i = 0; i < n; i++) vals[i] = BitConverter.ToUInt16(d, o + 2 * i); o += 2 * n; }
        else {
            while (c < n) {
                int k = d[o]; o++;
                if ((k & 0x80) != 0) { ushort v = BitConverter.ToUInt16(d, o); o += 2; for (int i = 0; i < (k & 0x7F); i++) vals[c++] = v; }
                else { for (int i = 0; i < k; i++) vals[c++] = BitConverter.ToUInt16(d, o + 2 * i); o += 2 * k; }
            }
        }
        if (enc == 1 || enc == 3) { int acc = 0; for (int i = 0; i < n; i++) { acc = (acc + vals[i]) & 0xFFFF; vals[i] = (ushort)acc; } }
        return o;
    }
    static List<object[]> ReadDsf(string path, string[] wanted) {
        HashSet<string> want = new HashSet<string>(wanted);
        byte[] b = File.ReadAllBytes(path);
        if (Encoding.ASCII.GetString(b, 0, 8) != "XPLNEDSF") throw new Exception("not a DSF file (compressed?): " + path);
        int dO = -1, dL = 0, gO = 0, gL = 0, cO = 0, cL = 0;
        foreach (int[] a in Atoms(b, 12, b.Length - 16)) {
            string id = Id(b, a[0]);
            if (id == "DEFN" && dO < 0) { dO = a[0] + 8; dL = a[1] - 8; }
            else if (id == "GEOD" && gL == 0) { gO = a[0] + 8; gL = a[1] - 8; }
            else if (id == "CMDS" && cL == 0) { cO = a[0] + 8; cL = a[1] - 8; }
        }
        List<string> polyd = new List<string>();
        foreach (int[] a in Atoms(b, dO, dO + dL)) {
            if (Id(b, a[0]) != "POLY") continue;
            int st = a[0] + 8, en = a[0] + a[1];
            for (int i = st; i < en; i++) if (b[i] == 0) { polyd.Add(Encoding.UTF8.GetString(b, st, i - st)); st = i + 1; }
        }
        List<ushort[][]> planes = new List<ushort[][]>(); List<float[]> scal = new List<float[]>();
        foreach (int[] a in Atoms(b, gO, gO + gL)) {
            string id = Id(b, a[0]); int p = a[0] + 8;
            if (id == "POOL") {
                int n = BitConverter.ToInt32(b, p), k = b[p + 4]; int o = p + 5; ushort[][] pl = new ushort[k][];
                for (int j = 0; j < k; j++) { pl[j] = new ushort[n]; o = Plane(b, o, n, pl[j]); }
                planes.Add(pl);
            } else if (id == "SCAL") {
                int m = (a[1] - 8) / 4; float[] sc = new float[m]; for (int j = 0; j < m; j++) sc[j] = BitConverter.ToSingle(b, p + 4 * j); scal.Add(sc);
            }
        }
        List<object[]> outp = new List<object[]>();
        int pool = 0, def = 0, oo = cO, end = cO + cL;
        Action<int, int[]> add = delegate (int prm, int[] idx) {
            if (def >= polyd.Count) return;
            string nm = polyd[def];
            if (!want.Contains(nm)) return;
            ushort[][] pl = planes[pool]; float[] sc = scal[pool]; List<double[]> pts = new List<double[]>(idx.Length);
            foreach (int i in idx) pts.Add(new double[] { pl[0][i] / 65535.0 * sc[0] + sc[1], pl[1][i] / 65535.0 * sc[2] + sc[3] });
            outp.Add(new object[] { nm, prm, pts });
        };
        while (oo < end) {
            int cid = b[oo]; oo++;
            switch (cid) {
                case 1: pool = BitConverter.ToUInt16(b, oo); oo += 2; break;
                case 2: oo += 4; break;
                case 3: def = b[oo]; oo += 1; break;
                case 4: def = BitConverter.ToUInt16(b, oo); oo += 2; break;
                case 5: def = BitConverter.ToInt32(b, oo); oo += 4; break;
                case 6: oo += 1; break;
                case 7: oo += 2; break;
                case 8: oo += 4; break;
                case 9: case 23: case 26: case 29: oo += 1 + 2 * b[oo]; break;
                case 10: oo += 4; break;
                case 11: case 24: case 27: case 30: oo += 1 + 4 * b[oo]; break;
                case 12: { int prm = BitConverter.ToUInt16(b, oo), k = b[oo + 2]; oo += 3; int[] idx = new int[k]; for (int i = 0; i < k; i++) idx[i] = BitConverter.ToUInt16(b, oo + 2 * i); oo += 2 * k; add(prm, idx); break; }
                case 13: { int prm = BitConverter.ToUInt16(b, oo), a0 = BitConverter.ToUInt16(b, oo + 2), e0 = BitConverter.ToUInt16(b, oo + 4); oo += 6; int[] idx = new int[Math.Max(0, e0 - a0)]; for (int i = 0; i < idx.Length; i++) idx[i] = a0 + i; add(prm, idx); break; }
                case 14: { int prm = BitConverter.ToUInt16(b, oo), w = b[oo + 2]; oo += 3; int[] first = null;
                    for (int j = 0; j < w; j++) { int k = b[oo]; oo++; int[] idx = new int[k]; for (int i = 0; i < k; i++) idx[i] = BitConverter.ToUInt16(b, oo + 2 * i); oo += 2 * k; if (first == null) first = idx; }
                    if (first != null && first.Length > 0) add(prm, first); break; }
                case 15: { int prm = BitConverter.ToUInt16(b, oo), w = b[oo + 2]; oo += 3; int a0 = BitConverter.ToUInt16(b, oo), e0 = BitConverter.ToUInt16(b, oo + 2); oo += 2 * (w + 1);
                    int[] idx = new int[Math.Max(0, e0 - a0)]; for (int i = 0; i < idx.Length; i++) idx[i] = a0 + i; add(prm, idx); break; }
                case 16: break;
                case 17: oo += 1; break;
                case 18: oo += 9; break;
                case 25: case 28: case 31: oo += 4; break;
                case 32: oo += 1 + b[oo]; break;
                case 33: oo += 2 + BitConverter.ToUInt16(b, oo); break;
                case 34: oo += 4 + BitConverter.ToInt32(b, oo); break;
                default: throw new Exception("unknown DSF command " + cid + " in " + path);
            }
        }
        return outp;
    }

    static List<double[]> ClampAll(Geo g, List<double[]> r) { List<double[]> c = new List<double[]>(r.Count); foreach (double[] p in r) c.Add(g.Clamp(p)); return c; }
    static void Ribbons(Geo g, List<double[]> line, List<Feat> feats, ref int n) {
        for (int i = 0; i < line.Count - 1; i += 99) {
            List<double[]> r = Ribbon(g, line.GetRange(i, Math.Min(100, line.Count - i)), 0.8);
            if (r != null) { feats.Add(new Feat(0, 255, ClampAll(g, r))); n++; }
        }
    }

    // --- one tile: returns DSF bytes; counts in LastMap / LastKept
    public static int LastMap, LastKept;
    static readonly string[] ProHedges = { "simheaven/ground/hedge_low.fac", "simheaven/ground/hedge_high.fac", "simheaven/ground/hedge_low.for", "simheaven/ground/hedge_high.for" };
    static readonly string[] FreeHedges = { "simheaven/forests/hedge.for" };
    static readonly string[] Rows = { "simheaven/forests/random_tree.for" };
    public static byte[] BuildTile(int s, int w, string kind, string p1, string p2, bool knick, string agent, string vHedge, string vRow) {
        Geo g = new Geo(s, w); Lcg rng = new Lcg(s * 1000 + w);
        List<Feat> feats = new List<Feat>(); int nMap = 0;
        List<Rec> recs; if (!Data.TryGetValue(TileKey(s, w), out recs)) recs = new List<Rec>();
        List<int[]>[] lines = new List<int[]>[7]; for (int c = 0; c < 7; c++) lines[c] = new List<int[]>();
        foreach (Rec r in recs) lines[r.Code].Add(r.Ints);
        List<object[]> srcRows = new List<object[]>();
        if (kind != null && (p2 != null || kind == "free")) srcRows = ReadDsf(kind == "pro" ? p2 : p1, Rows);
        HashSet<long> rowCells = new HashSet<long>();
        if (!knick) foreach (object[] f in srcRows) foreach (double[] p in (List<double[]>)f[2]) rowCells.Add(g.Cell(p));
        Func<List<double[]>, bool> nearRows = delegate (List<double[]> pts) { return rowCells.Count > 0 && g.HalfNear(rowCells, pts); };
        // official maps
        for (int ci = 0; ci < 2; ci++)
            foreach (int[] ints in lines[ci])
                foreach (List<double[]> piece in Clip(ToLL(ints), w, s)) Ribbons(g, piece, feats, ref nMap);
        for (int ci = 2; ci < 4; ci++) {
            double[] offs = ci == 2 ? new double[] { 0.0 } : new double[] { -5.0, 5.0 }; double step = ci == 2 ? 7.0 : 8.0;
            foreach (int[] ints in lines[ci])
                foreach (List<double[]> piece in Clip(ToLL(ints), w, s)) {
                    if (nearRows(piece)) continue;
                    foreach (double off in offs) {
                        double[] o = piece[0]; List<double[]> pts = Resample(g, piece, step, rng); List<double[]> ll = new List<double[]>(pts.Count);
                        foreach (double[] p in pts) { double jx = rng.Next() - 0.5; double jy = rng.Next() - 0.5; ll.Add(g.Clamp(g.ToLL(p[0] + p[3] * off + jx, p[1] - p[2] * off + jy, o))); }
                        for (int i = 0; i < ll.Count; i += 250) { feats.Add(new Feat(1, 767, ll.GetRange(i, Math.Min(250, ll.Count - i)))); nMap++; }
                    }
                }
        }
        for (int ci = 4; ci < 7; ci++) {
            int d = ci == 4 ? 0 : 1;
            foreach (int[] ints in lines[ci]) {
                List<double[]> ll = ToLL(ints);
                if (d == 1 && nearRows(ll)) continue;
                List<double[]> r = AreaRing(ll, w, s);
                if (r != null) { feats.Add(new Feat(d, 255, r)); nMap++; }
            }
        }
        // where the official maps have something: 20 m cells along every line and outline
        HashSet<long> cov = new HashSet<long>();
        for (int ci = 0; ci < 7; ci++)
            foreach (int[] ints in lines[ci]) {
                List<double[]> ll = ToLL(ints);
                if (ci >= 4) ll.Add(ll[0]);
                double[] o = ll[0];
                foreach (double[] p in Resample(g, ll, 10.0, new Lcg(0))) cov.Add(g.Cell(g.ToLL(p[0], p[1], o)));
            }
        int kept = 0;
        if (kind != null) {
            foreach (object[] f in ReadDsf(p1, kind == "pro" ? ProHedges : FreeHedges)) {
                string nm = (string)f[0]; int prm = (int)f[1]; List<double[]> pts = (List<double[]>)f[2];
                if (pts.Count == 0 || g.HalfNear(cov, pts)) continue;
                if (nm.EndsWith(".fac")) { int dummy = 0; Ribbons(g, pts, feats, ref dummy); }
                else { while (pts.Count > 255) pts = Half(pts); feats.Add(new Feat(0, prm < 512 ? prm : 255, pts)); }
                kept++;
            }
            if (knick)
                foreach (object[] f in srcRows) {
                    int prm = (int)f[1]; List<double[]> pts = (List<double[]>)f[2];
                    if (pts.Count == 0 || g.HalfNear(cov, pts)) continue;
                    if (prm >= 512) { for (int i = 0; i < pts.Count; i += 250) feats.Add(new Feat(1, prm, pts.GetRange(i, Math.Min(250, pts.Count - i)))); }
                    else { while (pts.Count > 255) pts = Half(pts); feats.Add(new Feat(1, prm, pts)); }
                    kept++;
                }
        }
        LastMap = nMap; LastKept = kept;
        return WriteDsf(s, w, new string[] { vHedge, vRow }, feats, agent);
    }

    static void Atom(MemoryStream m, string id, byte[] payload) {
        m.WriteByte((byte)id[3]); m.WriteByte((byte)id[2]); m.WriteByte((byte)id[1]); m.WriteByte((byte)id[0]);
        byte[] l = BitConverter.GetBytes(8 + payload.Length); m.Write(l, 0, 4); m.Write(payload, 0, payload.Length);
    }
    static byte[] Stab(string[] a) { MemoryStream m = new MemoryStream(); foreach (string x in a) { byte[] b = Encoding.UTF8.GetBytes(x); m.Write(b, 0, b.Length); m.WriteByte(0); } return m.ToArray(); }
    static byte[] Wrap(string id, byte[] payload) { MemoryStream m = new MemoryStream(); Atom(m, id, payload); return m.ToArray(); }
    static byte[] Cat(params byte[][] a) { MemoryStream m = new MemoryStream(); foreach (byte[] x in a) m.Write(x, 0, x.Length); return m.ToArray(); }

    static byte[] WriteDsf(int s, int w, string[] defs, List<Feat> feats, string agent) {
        SortedDictionary<long, List<Feat>> groups = new SortedDictionary<long, List<Feat>>();
        foreach (Feat f in feats) {
            long gx = (long)(int)((f.Pts[0][0] - w) * 16), gy = (long)(int)((f.Pts[0][1] - s) * 16);
            long key = (gx + 1000000) * 10000000 + (gy + 1000000);
            List<Feat> l; if (!groups.TryGetValue(key, out l)) { l = new List<Feat>(); groups[key] = l; } l.Add(f);
        }
        List<ushort[][]> pq = new List<ushort[][]>(); List<float[]> ps = new List<float[]>(); MemoryStream cmd = new MemoryStream();
        foreach (List<Feat> fs in groups.Values) {
            int i = 0;
            while (i < fs.Count) {
                List<Feat> batch = new List<Feat>(); int cnt = 0;
                while (i < fs.Count && cnt + fs[i].Pts.Count <= 65000) { batch.Add(fs[i]); cnt += fs[i].Pts.Count; i++; }
                double mnx = double.MaxValue, mny = double.MaxValue, mxx = double.MinValue, mxy = double.MinValue;
                foreach (Feat f in batch) foreach (double[] p in f.Pts) { if (p[0] < mnx) mnx = p[0]; if (p[0] > mxx) mxx = p[0]; if (p[1] < mny) mny = p[1]; if (p[1] > mxy) mxy = p[1]; }
                double x0 = (double)(float)mnx, y0 = (double)(float)mny;
                double sx = Math.Max(mxx - x0, 1e-6) * 1.000001, sy = Math.Max(mxy - y0, 1e-6) * 1.000001;
                List<ushort> qx = new List<ushort>(cnt), qy = new List<ushort>(cnt);
                cmd.WriteByte(1); cmd.Write(BitConverter.GetBytes((ushort)pq.Count), 0, 2);
                int cur = -1;
                foreach (Feat f in batch) {
                    if (f.D != cur) { cmd.WriteByte(3); cmd.WriteByte((byte)f.D); cur = f.D; }
                    cmd.WriteByte(12); cmd.Write(BitConverter.GetBytes((ushort)f.P), 0, 2); cmd.WriteByte((byte)f.Pts.Count);
                    foreach (double[] p in f.Pts) {
                        cmd.Write(BitConverter.GetBytes((ushort)qx.Count), 0, 2);
                        qx.Add((ushort)Math.Min(65535, Math.Max(0, (int)Math.Floor((p[0] - x0) / sx * 65535 + 0.5))));
                        qy.Add((ushort)Math.Min(65535, Math.Max(0, (int)Math.Floor((p[1] - y0) / sy * 65535 + 0.5))));
                    }
                }
                pq.Add(new ushort[][] { qx.ToArray(), qy.ToArray() }); ps.Add(new float[] { (float)sx, (float)x0, (float)sy, (float)y0 });
            }
        }
        string[] props = { "sim/planet", "earth", "sim/overlay", "1", "sim/creation_agent", agent,
                           "sim/west", w.ToString(), "sim/east", (w + 1).ToString(), "sim/north", (s + 1).ToString(), "sim/south", s.ToString() };
        byte[] head = Wrap("HEAD", Wrap("PROP", Stab(props)));
        byte[] defn = Wrap("DEFN", Cat(Wrap("TERT", new byte[0]), Wrap("OBJT", new byte[0]), Wrap("POLY", Stab(defs)), Wrap("NETW", new byte[0]), Wrap("DEMN", new byte[0])));
        MemoryStream gm = new MemoryStream();
        foreach (ushort[][] q in pq) {
            MemoryStream p = new MemoryStream(); p.Write(BitConverter.GetBytes(q[0].Length), 0, 4); p.WriteByte(2);
            for (int k = 0; k < 2; k++) { p.WriteByte(0); foreach (ushort v in q[k]) p.Write(BitConverter.GetBytes(v), 0, 2); }
            Atom(gm, "POOL", p.ToArray());
        }
        foreach (float[] sc in ps) { MemoryStream p = new MemoryStream(); foreach (float v in sc) p.Write(BitConverter.GetBytes(v), 0, 4); Atom(gm, "SCAL", p.ToArray()); }
        byte[] body = Cat(Encoding.ASCII.GetBytes("XPLNEDSF"), BitConverter.GetBytes(1), head, defn, Wrap("GEOD", gm.ToArray()), Wrap("CMDS", cmd.ToArray()));
        byte[] md5; using (MD5 h = MD5.Create()) md5 = h.ComputeHash(body);
        return Cat(body, md5);
    }
}
"@
}

# ---------------------------------------------------------------- input
function Parse-Value([string]$a, [double]$min) {
    # tolerant: '0.7', '0,7', '.7', '70', '70 %' -> 0.7; $null if not valid
    $s = $a.Trim().Replace(',', '.').TrimEnd('%').Trim()
    $v = 0.0
    if (-not [double]::TryParse($s, [Globalization.NumberStyles]::Float, $Inv, [ref]$v)) { return $null }
    if ($v -gt 1.0 -and $v -le 100.0) { $v = $v / 100.0 }
    $v = Rnd $v 3
    if ($v -ge $min -and $v -le 1.0) { return $v }
    return $null
}

function Read-Value([double]$min, [double]$current, [string]$what) {
    while ($true) {
        $a = (Read-Host "  Type a value from $(Fmt $min) to 1.0, or press Enter for $(Fmt $current)").Trim()
        if ($a -eq '') { return $current }
        $v = Parse-Value $a $min
        if ($null -ne $v) { return $v }
        Warn "  '$a' is not a valid $what. Example: 0.7"
    }
}

function Ask-Yes([string]$prompt) { $a = (Read-Host $prompt).Trim(); return ($a -eq '' -or $a -match '^[yYjJ]') }

# ---------------------------------------------------------------- X-Plane path
function Test-XP($p) { $p -and (Test-Path -LiteralPath (Join-Path $p 'Resources/default scenery')) -and (Test-Path -LiteralPath (Join-Path $p 'Custom Scenery')) }

function Find-XPlane {
    # optional: path as first argument, e.g. XP12_ForestTweak.ps1 "D:\X-Plane 12"
    if ($args.Count -gt 0 -and $args[0]) { if (Test-XP $args[0]) { return $args[0] }; throw "No X-Plane 12 folder at '$($args[0])'." }
    # the tool folder itself, or up to two levels above it (e.g. X-Plane 12\XP12_ForestTweak\Windows)
    $d = $PSScriptRoot
    for ($k = 0; $k -lt 3 -and $d; $k++) { if (Test-XP $d) { return $d }; $d = Split-Path -Parent $d }
    $cands = @()
    $inst = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'x-plane_install_12.txt' } else { '' }
    if ($inst -and (Test-Path -LiteralPath $inst)) {
        foreach ($l in Get-Content -LiteralPath $inst) {
            $p = $l.Trim().TrimEnd('\', '/')
            if (Test-XP $p) { $cands += $p }
        }
    }
    $cands = @($cands | Select-Object -Unique)
    if ($cands.Count -eq 1) {
        if (Ask-Yes "  X-Plane 12 found at '$($cands[0])'. Use it? [Y/n]") { return $cands[0] }
    } elseif ($cands.Count -gt 1) {
        Write-Host '  Several X-Plane 12 installations found:'
        for ($i = 0; $i -lt $cands.Count; $i++) { Write-Host "    [$($i+1)] $($cands[$i])" }
        $a = Read-Host '  Number (or Enter to type a path)'
        if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $cands.Count) { return $cands[[int]$a - 1] }
    }
    while ($true) {
        $p = (Read-Host '  Path to your X-Plane 12 folder (contains X-Plane.exe)').Trim('"', ' ').TrimEnd('\')
        if (Test-XP $p) { return $p }
        Warn '  -> Resources\default scenery / Custom Scenery not found there.'
    }
}

function Find-GFv2($xp) {
    @(Get-ChildItem -LiteralPath (Join-Path $xp 'Custom Scenery') -Directory |
      Where-Object { $_.Name -match '^Global[ _-]?Forests' -and $_.Name -match 'v2' } | ForEach-Object { $_.FullName })
}

function Get-Targets($xp, $gf) {
    $def = Join-Path $xp 'Resources/default scenery/1200 forests'
    if (-not (Test-Path -LiteralPath $def)) { throw "Default forest folder not found: $def" }
    $t = @((Get-Item -LiteralPath $def).FullName)
    if ($gf.Count -and (Ask-Yes '  Global Forests v2 found. Tweak it too? [Y/n]')) { $t += $gf }
    return $t
}

# ---------------------------------------------------------------- environment checks (display only)
function Test-XPRunning { [bool](Get-Process -Name 'X-Plane' -ErrorAction SilentlyContinue) }

function Test-Blocked {
    if (Test-XPRunning) { Warn "  X-Plane is running. Please quit X-Plane first - forest files can't be changed while it runs."; return $true }
    return $false
}

function Get-XPVersion($xp) {
    $lt = Join-Path $xp 'Log.txt'
    if (Test-Path -LiteralPath $lt) {
        $first = Get-Content -LiteralPath $lt -TotalCount 1
        if ($first -match 'X-Plane (\d+)\.(\d+)\.(\d+)(\S*)') { return @("$($Matches[1]).$($Matches[2])", "$($Matches[1]).$($Matches[2]).$($Matches[3])$($Matches[4])") }
    }
    return @($null, $null)
}

function Get-VegSlider($xp) {
    # vegetation density slider from X-Plane.prf (0-4, 4 = maximum)
    $prf = Join-Path $xp 'Output/preferences/X-Plane.prf'
    if (-not (Test-Path -LiteralPath $prf)) { return $null }
    foreach ($l in [IO.File]::ReadAllLines($prf, $Latin1)) {
        $tok = $l.Trim() -split '\s+'
        if ($tok.Count -ge 2 -and $tok[0] -eq 'renopt_vegetation_quality_04') { $v = 0.0; if ([double]::TryParse($tok[1], [Globalization.NumberStyles]::Float, $Inv, [ref]$v)) { return [int]$v } }
    }
    return $null
}

function Get-PackStates($xp) {
    # scenery_packs.ini: folder name (lower case) -> $true (enabled) / $false (disabled)
    $h = @{}
    $ini = Join-Path $xp 'Custom Scenery/scenery_packs.ini'
    if (Test-Path -LiteralPath $ini) {
        foreach ($l in [IO.File]::ReadAllLines($ini)) {
            if ($l -match '^\s*(SCENERY_PACK(?:_DISABLED)?)\s+(.+?)\s*$') {
                $name = ($Matches[2].Replace('\', '/').TrimEnd('/') -split '/')[-1].ToLower()
                $h[$name] = ($Matches[1] -eq 'SCENERY_PACK')
            }
        }
    }
    return $h
}

function Get-OtherForestAddons($xp) {
    # Custom Scenery folders that probably bring their own forests (not changed by this tool)
    $packs = Get-PackStates $xp
    @(Get-ChildItem -LiteralPath (Join-Path $xp 'Custom Scenery') -Directory | Sort-Object Name | Where-Object {
        $low = $_.Name.ToLower()
        -not ($low.StartsWith('simheaven') -or $low.StartsWith('global_forests') -or $low.StartsWith('global forests') -or $low.StartsWith('xp12_foresttweak')) -and
        $OtherRx.IsMatch($_.Name) -and -not ($packs.ContainsKey($low) -and -not $packs[$low])
    } | ForEach-Object { $_.Name })
}

function Start-UpdateCheck {
    # asks GitHub for the latest release in the background (max 3 s, silent if offline)
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $c = New-Object Net.Http.HttpClient
        $c.Timeout = [TimeSpan]::FromSeconds(3)
        $c.DefaultRequestHeaders.Add('User-Agent', 'xp12-forest-tweak')
        return $c.GetStringAsync("https://api.github.com/repos/$Repo/releases/latest")
    } catch { return $null }
}

function Get-VTuple([string]$s) { $n = @([regex]::Matches($s, '\d+') | Select-Object -First 3 | ForEach-Object { [int]$_.Value }); while ($n.Count -lt 3) { $n += 0 }; ($n[0] * 1000000 + $n[1] * 1000 + $n[2]) }

function Show-EnvHints($xp, $targets, $gf, $verShort, $verLong) {
    $v = Get-VegSlider $xp
    if ($null -ne $v -and $v -lt 4) {
        Warn '  Note    : the vegetation density slider in X-Plane is not at maximum. It limits what you see;'
        Warn '            set it to maximum (Settings > Graphics) to get the full effect.'
    }
    $packs = Get-PackStates $xp
    foreach ($g in $gf) {
        $name = Split-Path -Leaf $g; $low = $name.ToLower()
        $en = if ($packs.ContainsKey($low)) { $packs[$low] } else { $null }
        if (($targets -contains $g) -and $en -eq $false) { Warn "  Note    : $name is disabled in scenery_packs.ini - X-Plane doesn't show its forests." }
        if (-not ($targets -contains $g) -and $en -ne $false) { Warn "  Note    : $name is active in X-Plane but not tweaked - forests in its areas stay as they are." }
    }
    if ($verShort -and $verShort -ne $TestedXP) {
        Warn "  Note    : tested with X-Plane $TestedXP.x, you have $verLong. It should work; if forests look"
        Warn '            wrong, use Restore original and please report it.'
    }
}

# ---------------------------------------------------------------- backup log
function Get-TweakDir($xp) {
    $d = Join-Path $xp 'ForestDensityTweak'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    return $d
}
function Get-LogPath($xp) { Join-Path (Get-TweakDir $xp) 'backup.log' }
function NormKey([string]$f) { $f.Replace('/', $Sep).Replace('\', $Sep) }

function Read-Log($log) {
    $h = @{}
    if (Test-Path -LiteralPath $log) {
        foreach ($l in [IO.File]::ReadAllLines($log)) {
            if ($l.Trim()) {
                try { $e = $l | ConvertFrom-Json } catch { continue }   # a line cut off by a crash: the file it names is handled as original
                $h[(NormKey $e.f)] = $e                                 # last entry per file wins; the macOS/Linux version writes '/'
            }
        }
    }
    return $h
}

function Write-Log($path, $entries) {
    # rewrites a log with one line per file (compact), via a temp file
    $tmp = "$path.tmp"
    [IO.File]::WriteAllLines($tmp, [string[]]@($entries | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 4 }), $Utf8)
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}

# ---------------------------------------------------------------- file helpers
function Read-Chunk($fs, [long]$offset, [int]$count) {
    $buf = New-Object byte[] $count; [void]$fs.Seek($offset, 'Begin'); $got = 0
    while ($got -lt $count) { $k = $fs.Read($buf, $got, $count - $got); if ($k -le 0) { break }; $got += $k }
    $Latin1.GetString($buf, 0, $got)
}

# A .for file = header (SPACING/RANDOM ...) + 3D mesh data (VERTEX/IDX) + tree list (TREE/TREE2) at the end.
# Only header and tree list are read and changed; the mesh data in between is copied byte for byte.
function Read-For($path, [switch]$Quick) {
    $fs = [IO.File]::OpenRead($path)
    try {
        $len  = $fs.Length
        $text = Read-Chunk $fs 0 ([Math]::Min($len, 65536))
        $m    = $HeaderEnd.Match($text)
        $hlen = if ($m.Success) { $m.Index } else { $text.Length }
        $head = $text.Substring(0, $hlen)
        # tree list starts after the last mesh data line
        $size = 131072
        while ($true) {
            $start = [Math]::Max([long]$hlen, $len - $size)
            $chunk = Read-Chunk $fs $start ([int]($len - $start))
            $mm = $MeshDataRx.Matches($chunk)
            if ($mm.Count -gt 0) { $last = $mm[$mm.Count - 1]; $tstart = $start + $last.Index + $last.Length; $tail = $chunk.Substring($last.Index + $last.Length); break }
            if ($start -eq $hlen) { $tstart = [long]$hlen; $tail = $chunk; break }
            $size *= 4
        }
        $bytes = $null
        if (-not $Quick) { $bytes = New-Object byte[] $len; [void]$fs.Seek(0, 'Begin'); $got = 0
            while ($got -lt $len) { $k = $fs.Read($bytes, $got, [int]($len - $got)); if ($k -le 0) { break }; $got += $k } }
    } finally { $fs.Close() }
    [pscustomobject]@{
        Bytes = $bytes; Len = $len; HeadLen = $hlen; Head = $head; TailStart = $tstart; Tail = $tail
        Lines  = @($LineRx.Matches($head) | ForEach-Object { $_.Value })
        TLines = @($TreeRx.Matches($tail) | ForEach-Object { $_.Value })
    }
}

function Get-Free($path) {
    try { (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $path).ProviderPath))).AvailableFreeSpace } catch { [long]::MaxValue }
}

function Write-Bytes($path, [byte[]]$out) {
    if ((Get-Free (Split-Path -Parent $path)) -lt $out.Length + $DiskMargin) { throw 'Not enough free disk space - stopped. Everything done so far is logged and safe.' }
    $tmp = "$path.fdt_tmp"
    [IO.File]::WriteAllBytes($tmp, $out)
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) }   # atomic swap, never a half-written .for
    else { [IO.File]::Move($tmp, $path) }
}

function Join-For($fo, [string]$newHead, [string]$newTail, [byte[]]$newMid = $null) {
    $hb  = $Latin1.GetBytes($newHead)
    $tb  = $Latin1.GetBytes($newTail)
    if ($null -eq $newMid) {
        $midLen = [int]($fo.TailStart - $fo.HeadLen)
        $newMid = New-Object byte[] $midLen
        [Array]::Copy($fo.Bytes, $fo.HeadLen, $newMid, 0, $midLen)
    }
    $out = New-Object byte[] ($hb.Length + $newMid.Length + $tb.Length)
    [Array]::Copy($hb, 0, $out, 0, $hb.Length)
    [Array]::Copy($newMid, 0, $out, $hb.Length, $newMid.Length)
    [Array]::Copy($tb, 0, $out, $hb.Length + $newMid.Length, $tb.Length)
    return ,$out
}

# 3D meshes used by TREE lines (drawn at their modelled size); TREE2 meshes are scaled by X-Plane
# via their nominal height and must not be touched. A mesh used by both is left alone.
function Get-TreeMeshes([string]$tail) {
    $t1 = @{}; $t2 = @{}; $kind = $null
    foreach ($line in $tail -split "`n") {
        $tok = $line.Trim() -split '\s+'
        if ($tok[0] -eq 'TREE')  { $kind = $t1 } elseif ($tok[0] -eq 'TREE2') { $kind = $t2 }
        elseif ($tok[0] -eq 'MESH_3D' -and $kind -and $tok.Count -gt 1) { $kind[$tok[1]] = 1 }
    }
    [string[]]@($t1.Keys | Where-Object { -not $t2.ContainsKey($_) })
}

function Get-BackupRoot($xp) { Join-Path $xp 'ForestDensityTweak/mesh_backup' }
function Get-BackupPath($xp, $rel) { Join-Path (Get-BackupRoot $xp) ($rel + '.gz') }

# replace the n-th regex match in $text with $list[n]
function Set-Seq([string]$text, $rx, $list) {
    $list = @($list); $parts = $rx.Matches($text); $sb = New-Object Text.StringBuilder; $pos = 0
    for ($j = 0; $j -lt $parts.Count -and $j -lt $list.Count; $j++) {
        [void]$sb.Append($text.Substring($pos, $parts[$j].Index - $pos)); [void]$sb.Append($list[$j]); $pos = $parts[$j].Index + $parts[$j].Length
    }
    [void]$sb.Append($text.Substring($pos)); $sb.ToString()
}

function Has($e, $name) { $e -and $e.PSObject.Properties[$name] }
function Get-H($e) { if (Has $e 'h') { [double]$e.h } else { 1.0 } }
function Get-HP($e) { if ((Get-H $e) -lt 1.0 -and (Has $e 'hp')) { [string]$e.hp } else { 'uniform' } }

function Get-MinSpacing([string]$head) {
    $v = @($LineRx.Matches($head) | Where-Object { $_.Groups[2].Value -eq 'SPACING' } |
           ForEach-Object { [Math]::Min([double]::Parse($_.Groups[4].Value, $Inv), [double]::Parse($_.Groups[6].Value, $Inv)) })
    if ($v.Count -eq 0) { return 0 }
    ($v | Measure-Object -Minimum).Minimum
}

function Same($a, $b) { ($a -join "`n") -eq ($b -join "`n") }

function Get-State($fo, $e) {
    if (-not $e) { return 'original' }
    $treesOk = (-not (Has $e 'nt')) -or (Same $fo.TLines $e.nt)
    if ((Same $fo.Lines $e.n) -and $treesOk) { return 'tweaked' }
    return 'original'     # restored by an update (or changed by the author) -> treat as original
}

function Get-Files($targets) {
    @(foreach ($t in $targets) { Get-ChildItem -LiteralPath $t -Recurse -File -Filter '*.for' | Where-Object { $_.Extension -eq '.for' } }) | Sort-Object FullName
}

function Rel($xp, $full) { $full.Substring($xp.Length).TrimStart('\', '/') }

function Remove-EmptyDirs($top) {
    $n = 0
    if (-not (Test-Path -LiteralPath $top)) { return 0 }
    foreach ($d in @(Get-ChildItem -LiteralPath $top -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not (Get-ChildItem -LiteralPath $d.FullName -Force | Select-Object -First 1)) { try { Remove-Item -LiteralPath $d.FullName; $n++ } catch { } }
    }
    return $n
}

# ---------------------------------------------------------------- effective factors per file
function Get-HeightWeight([string]$rel) {
    # realistic profile: share of the height reduction a forest type gets
    $r = $rel.Replace('\', '/').ToLower(); $base = ($r -split '/')[-1]
    if ($ShrubRx.IsMatch($r)) { return 0.5 }                              # shrubs, cacti, orchards, fruit trees, agave, yucca
    if ($r.Contains('palm')) { return 0.8 }
    if ($r.Contains('needle') -or $base.StartsWith('coni')) { return 0.6 }  # conifers: often the tallest trees in reality
    return 1.0                                                            # broadleaf, mixed, woodland, cropland, single trees
}

function Get-Effective([string]$rel, [double]$x, [double]$h, [string]$hp) {
    # (spacing factor, height factor) actually used for one file
    $rl = $rel.Replace('\', '/').ToLower()
    $f = 1.0
    if ($x -lt 1.0 -and $rl.Contains('/cropland/')) { $f *= $CropFac }
    if ($x -lt 1.0 -and $rl.StartsWith('custom scenery/')) { $m = $SparseRx.Match($rl); if ($m.Success) { $f *= $SparseFac[$m.Groups[1].Value] } }
    $xe = if ($f -ne 1.0) { Rnd ($x * $f) 4 } else { $x }
    $he = $h
    if ($h -lt 1.0 -and $hp -eq 'realistic') { $he = Rnd (1.0 - (1.0 - $h) * (Get-HeightWeight $rel)) 4 }
    return @($xe, $he)
}

function Scale-Head([string]$head, [double]$xe) {
    # SPACING and RANDOM times xe. For natural forests (RANDOM 0.25 - 0.5 x SPACING) RANDOM is raised to
    # half the tree spacing: below that X-Plane leaves empty strips between the grid rows, which show up
    # as lines in dense forests. Planted rows (RANDOM below 0.25 x SPACING, e.g. orchards) keep their grid.
    $sp = $null
    foreach ($m in $LineRx.Matches($head)) {
        if ($m.Groups[2].Value -eq 'SPACING') { $sp = @([double]::Parse($m.Groups[4].Value, $Inv), [double]::Parse($m.Groups[6].Value, $Inv)); break }
    }
    $LineRx.Replace($head, {
        param($m)
        $isRnd = ($m.Groups[2].Value -eq 'RANDOM') -and ($null -ne $sp)
        $out = $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value
        foreach ($k in 0, 1) {
            $v = [double]::Parse($m.Groups[4 + 2 * $k].Value, $Inv)
            $n = $v * $xe
            if ($isRnd) {
                $s = $sp[$k]
                if ($s -gt 0 -and ($v / $s) -ge $RandMinRatio -and ($v / $s) -lt $RandTarget) { $n = $RandTarget * $s * $xe }
            }
            $out += (Fmt $n)
            if ($k -eq 0) { $out += $m.Groups[5].Value }
        }
        $out
    })
}

function Test-Outdated([string]$rel, $e) {
    # tweaked with values that differ from the current rules for its settings (e.g. cropland from 1.3,
    # RANDOM from 1.4.1 or older)
    $want = Get-Effective $rel ([double]$e.x) (Get-H $e) (Get-HP $e)
    $xs = if (Has $e 'xe') { [double]$e.xe } else { [double]$e.x }
    $hs = if (Has $e 'he') { [double]$e.he } else { Get-H $e }
    if (([Math]::Abs($want[0] - $xs) -gt 1e-9) -or ([Math]::Abs($want[1] - $hs) -gt 1e-9)) { return $true }
    if ($want[0] -lt 1.0 -and (Has $e 'o') -and (Has $e 'n')) {
        $exp = @($LineRx.Matches((Scale-Head (@($e.o) -join "`n") $want[0])) | ForEach-Object { $_.Value })
        $have = @($e.n)
        if ($exp.Count -ne $have.Count) { return $true }
        for ($i = 0; $i -lt $exp.Count; $i++) { if ($exp[$i] -ne $have[$i]) { return $true } }
    }
    return $false
}

# ---------------------------------------------------------------- progress with remaining time
function New-Prog([string]$activity, [long]$total) { [pscustomobject]@{ A = $activity; Total = [Math]::Max([long]1, [long]$total); T0 = [DateTime]::Now; Last = [DateTime]::MinValue } }
function Step-Prog($p, [long]$units, [int]$i, [int]$n) {
    $now = [DateTime]::Now
    if (($now - $p.Last).TotalMilliseconds -lt 300) { return }
    $p.Last = $now
    $pct = [Math]::Min(100, [int](100 * $units / $p.Total))
    $el = ($now - $p.T0).TotalSeconds
    if ($units -gt 0 -and $units -lt $p.Total -and $el -ge 10 -and ($units -ge 0.1 * $p.Total -or $el -ge 30)) {
        $rest = [int]($el * ($p.Total - $units) / $units)
        Write-Progress -Activity $p.A -Status "$i / $n" -PercentComplete $pct -SecondsRemaining $rest
    } else { Write-Progress -Activity $p.A -Status "$i / $n" -PercentComplete $pct }
}
function End-Prog($p) { Write-Progress -Activity $p.A -Completed }
function Get-WorkUnits([long]$size, [bool]$heavy) { if ($heavy) { $size * $MeshWeight } else { $size } }

function Format-TimeRange([double]$sec) {
    # rough range for an estimated duration, e.g. 'about 4-10 min'
    $lo = $sec * 0.6; $hi = $sec * 1.6
    if ($hi -lt 90) { return 'about 1 min or less' }
    $loM = [Math]::Max(1, [int][Math]::Round($lo / 60))
    return "about $loM-$([Math]::Max($loM + 1, [int][Math]::Round($hi / 60))) min"
}

function Get-Estimate($st, [double]$hf, [bool]$rebuild) {
    # seconds for restore (if needed) + apply, from the file sizes found by Get-ForestState
    $mesh = $st.BOrigMesh; $plain = $st.BOrigPlain
    if ($rebuild) { $mesh += $st.BTwMesh; $plain += $st.BTwPlain }
    $sec = ((Get-WorkUnits $mesh ($hf -lt 1.0)) + $plain) / $Rate
    if ($rebuild) { $sec += ($st.BTwMesh + $st.BTwPlain) / $RateRestore }
    return $sec
}

function Took($t0) { $s = ([DateTime]::Now - $t0).TotalSeconds; if ($s -lt 90) { '{0:N0} s' -f $s } else { '{0:N0} min' -f ($s / 60) } }

# ---------------------------------------------------------------- forest state
function Get-ForestState($xp, $targets) {
    $log = Read-Log (Get-LogPath $xp)
    $st = [pscustomobject]@{ N = 0; NOrig = 0; NReset = 0; NSkip = 0; NOld = 0; Files = 0; X = 1.0; H = 1.0; HP = 'uniform'
        BOrigMesh = [long]0; BOrigPlain = [long]0; BTwMesh = [long]0; BTwPlain = [long]0 }     # bytes, for the time estimate
    $count = @{}
    $files = @(Get-Files $targets); $st.Files = $files.Count; $i = 0
    $p = New-Prog 'Checking' $files.Count
    foreach ($f in $files) {
        $i++; Step-Prog $p $i $i $files.Count
        $rel = Rel $xp $f.FullName
        $fo = Read-For $f.FullName -Quick
        $e  = $log[$rel]
        $hasMesh = (Get-TreeMeshes $fo.Tail).Count -gt 0
        if ((Get-State $fo $e) -eq 'tweaked') {
            $st.N++
            if ($hasMesh) { $st.BTwMesh += $fo.Len } else { $st.BTwPlain += $fo.Len }
            $k = '{0}|{1}|{2}' -f ([double]$e.x).ToString($Inv), (Get-H $e).ToString($Inv), (Get-HP $e)
            $count[$k] = 1 + $(if ($count.ContainsKey($k)) { $count[$k] } else { 0 })
            if (Test-Outdated $rel $e) { $st.NOld++ }
        } elseif ((Get-MinSpacing $fo.Head) -gt $Threshold) {
            $st.NOrig++
            if ($hasMesh) { $st.BOrigMesh += $fo.Len } else { $st.BOrigPlain += $fo.Len }
            if ($e) { $st.NReset++ }     # logged as tweaked, but the file is original again (update)
        } else { $st.NSkip++ }
    }
    End-Prog $p
    if ($count.Count) {
        $top = ($count.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key -split '\|'
        $st.X = [double]::Parse($top[0], $Inv); $st.H = [double]::Parse($top[1], $Inv); $st.HP = $top[2]
    }
    return $st
}

function Format-Forest([double]$x, [double]$h, [string]$hp) {
    if ($x -eq 1.0 -and $h -eq 1.0) { return 'original' }
    $s = if ($x -lt 1.0) { 'tree spacing {0} (about {1}x trees)' -f (Fmt $x), (1.0 / ($x * $x)).ToString('0.0', $Inv) } else { 'tree spacing 1 (original)' }
    if ($h -lt 1.0) { $s += ", tree height $(Fmt $h) $hp" }
    return $s
}

function Get-StatusLine($st, $hstate) {
    if ($st.N -eq 0) { $s = 'forests original' }
    else {
        $s = 'forests tweaked: ' + (Format-Forest $st.X $st.H $st.HP)
        if ($st.NReset) { $s += " - $($st.NReset) files reset by an update, run Choose settings" }
        elseif ($st.NOrig) { $s += " - $($st.NOrig) files not tweaked" }
        elseif ($st.NOld) { $s += ' - run Choose settings once to apply the latest improvements' }
    }
    if ($hstate) { $s += " | hedges " + $(if ($ChoiceNames.ContainsKey($hstate)) { $ChoiceNames[$hstate] } else { $hstate }) }
    return $s
}

# ---------------------------------------------------------------- apply
function Invoke-ApplyValues($xp, $targets, [double]$fac, [double]$hf, [string]$hp) {
    $logPath = Get-LogPath $xp
    $log = Read-Log $logPath
    $jobs = New-Object Collections.ArrayList; $already = 0; $skip = 0; $weight = @{}; $total = [long]0
    foreach ($f in @(Get-Files $targets)) {
        $rel = Rel $xp $f.FullName
        $fo  = Read-For $f.FullName -Quick
        if ((Get-State $fo $log[$rel]) -eq 'tweaked') { $already++ }
        elseif ((Get-MinSpacing $fo.Head) -le $Threshold) { $skip++ }
        else {
            [void]$jobs.Add($f)
            $w = Get-WorkUnits $f.Length ($hf -lt 1.0 -and (Get-TreeMeshes $fo.Tail).Count -gt 0)
            $weight[$f.FullName] = $w; $total += $w
        }
    }
    TLog "apply: spacing $fac height $hf $hp, $($jobs.Count) files to tweak, $already already tweaked"
    $sw = New-Object IO.StreamWriter($logPath, $true, $Utf8)
    $sw.AutoFlush = $true
    $done = 0; $odd = 0; $i = 0; $meshCount = 0; $units = 0; $completed = $false; $t0 = [DateTime]::Now
    $p = New-Prog 'Tweaking forest files' $total
    try {
        foreach ($f in $jobs) {
            $i++; $units += $weight[$f.FullName]; Step-Prog $p $units $i $jobs.Count
            $rel = Rel $xp $f.FullName
            $eff = Get-Effective $rel $fac $hf $hp; $xe = $eff[0]; $he = $eff[1]
            $fo  = Read-For $f.FullName
            $newHead = $fo.Head; $newTail = $fo.Tail; $doTrees = $he -lt 1.0
            if ($doTrees) {
                # safety: all TREE lines of the file must be in the tree list at the end
                $all = $TreeRx.Matches($Latin1.GetString($fo.Bytes)).Count
                if ($all -ne $fo.TLines.Count) { $doTrees = $false; $odd++ }
            }
            if ($xe -lt 1.0) { $newHead = Scale-Head $fo.Head $xe }
            $newMid = $null; $meshes = @()
            if ($doTrees) {
                # min and max height scaled alike -> the height variation shrinks with them
                $newTail = $TreeRx.Replace($fo.Tail, {
                    param($m)
                    $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value +
                    (Fmt ([double]::Parse($m.Groups[4].Value, $Inv) * $he)) + $m.Groups[5].Value +
                    (Fmt ([double]::Parse($m.Groups[6].Value, $Inv) * $he))
                })
                $meshes = Get-TreeMeshes $fo.Tail
                if ($meshes.Count) { $newMid = [FdtMesh14]::ScaleMeshes($fo.Bytes, [int]$fo.HeadLen, [int]$fo.TailStart, $meshes, $he) }
            }
            if ($newHead -eq $fo.Head -and $newTail -eq $fo.Tail -and $null -eq $newMid) { $skip++; continue }
            $out = Join-For $fo $newHead $newTail $newMid
            $need = $out.Length + $DiskMargin + $(if ($meshes.Count) { [long]($fo.Len / 2) } else { 0 })
            if ((Get-Free $f.DirectoryName) -lt $need -or ($meshes.Count -and (Get-Free (Get-TweakDir $xp)) -lt $need)) {
                throw 'Not enough free disk space - stopped. Everything done so far is logged and safe. Free some space and run Choose settings again, or use Restore original.'
            }
            $entry = [ordered]@{ f = $rel; x = $fac; h = $hf }
            if ($hf -lt 1.0) { $entry.hp = $hp }
            if ($xe -ne $fac) { $entry.xe = $xe; $entry.cb = $true }
            if ($he -ne $hf) { $entry.he = $he }
            $entry.o = [string[]]$fo.Lines
            $entry.n = [string[]]@($LineRx.Matches($newHead) | ForEach-Object { $_.Value })
            if ($newTail -ne $fo.Tail) {
                $entry.ot = [string[]]$fo.TLines
                $entry.nt = [string[]]@($TreeRx.Matches($newTail) | ForEach-Object { $_.Value })
            }
            if ($null -ne $newMid) {
                # 3D meshes change -> keep a compressed copy of the original file (with checksum) for an exact restore
                [FdtMesh14]::Gzip($fo.Bytes, (Get-BackupPath $xp $rel))
                $entry.mb = $true; $entry.ms = [FdtMesh14]::Sha256($fo.Bytes); $meshCount += $meshes.Count
            }
            # log first, then write: an interruption can never lead to double scaling
            $sw.WriteLine((New-Object PSObject -Property $entry | ConvertTo-Json -Compress))
            $tmp = "$($f.FullName).fdt_tmp"
            [IO.File]::WriteAllBytes($tmp, $out)
            Remove-Sides $f.FullName           # kept copies of the quick switch belong to the old state
            [IO.File]::Replace($tmp, $f.FullName, [NullString]::Value)
            $log[$rel] = New-Object PSObject -Property $entry
            $done++
        }
        $completed = $true
    } finally {
        $sw.Close(); End-Prog $p
        Remove-TempFiles $xp $targets | Out-Null
        if (-not $completed) {
            Write-Host ''
            Warn "  Stopped. $done files were tweaked and logged - nothing is broken."
            Warn '  Run Choose settings again to finish, or Restore original.'
            TLog "apply: stopped after $done files"
        }
    }
    Write-Log $logPath $log.Values          # compact: one line per file
    Write-Host ''
    Write-Host "  Tweaked now          : $done   ($(Took $t0))" -ForegroundColor Green
    Write-Host "  Already tweaked      : $already"
    Write-Host "  Grass/shrubs (kept)  : $skip"
    if ($meshCount) {
        $mb = [Math]::Round(((Get-ChildItem -LiteralPath (Get-BackupRoot $xp) -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB)
        Write-Host "  3D tree models scaled: $meshCount   (backup: $mb MB in ForestDensityTweak\mesh_backup)"
    }
    if ($odd) { Warn "  Unusual layout       : $odd (spacing changed, tree heights left as they are)" }
    TLog "apply: $done tweaked, $already already, $skip kept, $meshCount meshes, $odd unusual"
    return $true
}

function Remove-TempFiles($xp, $targets) {
    # leftover temp files of an interrupted run
    $n = 0
    foreach ($t in @($targets) + @(Get-BackupRoot $xp)) {
        if (-not (Test-Path -LiteralPath $t)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $t -Recurse -File | Where-Object { $_.Name.EndsWith('.fdt_tmp') -or $_.Name.EndsWith('.gz.tmp') })) {
            try { Remove-Item -LiteralPath $f.FullName; $n++ } catch { }
        }
    }
    return $n
}

# ---------------------------------------------------------------- restore
function Invoke-Restore($xp, $targets, [switch]$Quiet) {
    # restores all tweaked files in the chosen folders; returns $true if nothing failed
    $logPath = Get-LogPath $xp
    $log = Read-Log $logPath
    if ($log.Count -eq 0) { if (-not $Quiet) { Write-Host '  Forests: nothing to restore (no backup log).' }; return $true }
    $files = @(Get-Files $targets | Where-Object { $log.ContainsKey((Rel $xp $_.FullName)) })
    $total = [long](($files | Measure-Object Length -Sum).Sum)
    $p = New-Prog 'Restoring' $total
    $done = 0; $i = 0; $units = 0; $damaged = @(); $t0 = [DateTime]::Now
    try {
        foreach ($f in $files) {
            $i++; $units += $f.Length; Step-Prog $p $units $i $files.Count
            $rel = Rel $xp $f.FullName; $e = $log[$rel]
            Remove-Sides $f.FullName
            $fo = Read-For $f.FullName -Quick
            $bp = Get-BackupPath $xp $rel
            if ((Get-State $fo $e) -ne 'tweaked') {
                # file was reset by an update -> its backup is outdated
                if (Test-Path -LiteralPath $bp) { Remove-Item -LiteralPath $bp }
                $log.Remove($rel); continue
            }
            if (Has $e 'mb') {
                $data = $null
                if (Test-Path -LiteralPath $bp) { try { $data = [FdtMesh14]::Gunzip($bp) } catch { $data = $null } }
                if ($null -eq $data -or ((Has $e 'ms') -and [FdtMesh14]::Sha256($data) -ne $e.ms)) {
                    $damaged += $rel; continue     # keep it tweaked and logged: never scale its 3D models twice
                }
                Write-Bytes $f.FullName $data
                Remove-Item -LiteralPath $bp
                $log.Remove($rel); $done++; continue
            }
            $fo = Read-For $f.FullName
            $newHead = Set-Seq $fo.Head $LineRx $e.o
            $newTail = if (Has $e 'ot') { Set-Seq $fo.Tail $TreeRx $e.ot } else { $fo.Tail }
            Write-Bytes $f.FullName (Join-For $fo $newHead $newTail)
            $log.Remove($rel); $done++
        }
    } finally {
        End-Prog $p
        # keep log entries of files outside the chosen folders (e.g. GFv2 when it was not included)
        # and of files that could not be restored
        Write-Log $logPath $log.Values
        Remove-EmptyDirs (Get-BackupRoot $xp) | Out-Null
    }
    TLog "restore: $done restored, $($damaged.Count) damaged backups"
    if (-not $Quiet) { Write-Host ''; Write-Host "  Forests restored     : $done files   ($(Took $t0))" -ForegroundColor Green }
    if ($damaged.Count) {
        Write-Host ''
        Write-Host "  $($damaged.Count) files could not be restored: their 3D model backup is missing or damaged." -ForegroundColor Red
        Write-Host '  They stay tweaked (safe). To repair them, run the X-Plane installer (Update) or reinstall' -ForegroundColor Red
        Write-Host "  Global Forests v2, then run Check & repair. First file: $($damaged[0])" -ForegroundColor Red
        foreach ($r in $damaged) { TLog "restore: damaged backup $r" }
        return $false
    }
    return $true
}

# ---------------------------------------------------------------- simHeaven hedges
# "enhanced": hedges of simHeaven X-World (e.g. the Knicks in northern Germany) about 4-5 m high instead
# of 2.2-2.8 m and visible up to 8 km instead of 4 km. Only the hedge files of the simHeaven X-World
# Vegetation Library are changed; the original lines are logged in ForestDensityTweak\hedges.log.
$HedgeFac   = 1.8
$HedgeLod   = 8000
$HedgeVPath = 'simheaven/forests/hedge.for'
$LodRx      = [regex]'(?m)^([ \t]*LOD[ \t]+)([0-9]*\.?[0-9]+)'

function Get-HedgeFiles($xp) {
    $out = @()
    $libs = @(Get-ChildItem -LiteralPath (Join-Path $xp 'Custom Scenery') -Directory | Where-Object { $_.Name -match '(?i)^simheaven.*vegetation.*librar' })
    foreach ($lib in $libs) {
        $lt = Join-Path $lib.FullName 'library.txt'
        if (-not (Test-Path -LiteralPath $lt)) { continue }
        foreach ($line in [IO.File]::ReadAllLines($lt, $Latin1)) {
            $t = $line.Trim()
            if ($t -notmatch '^EXPORT' -or $t.IndexOf($HedgeVPath) -lt 0) { continue }
            $target = $t.Substring($t.IndexOf($HedgeVPath) + $HedgeVPath.Length).Trim()
            if (-not $target) { continue }
            $full = Join-Path $lib.FullName ($target.Replace('/', $Sep).Replace('\', $Sep))
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
            # only real files inside the library itself (never the linked default forests)
            $item = Get-Item -LiteralPath $full
            $linked = $false; $p = $item.Directory
            while ($p -and $p.FullName.Length -gt $lib.FullName.Length) { if ($p.Attributes -band [IO.FileAttributes]::ReparsePoint) { $linked = $true }; $p = $p.Parent }
            if (-not $linked -and $out -notcontains $item.FullName) { $out += $item.FullName }
        }
    }
    return $out
}

function Get-HedgeLogPath($xp) { Join-Path (Get-TweakDir $xp) 'hedges.log' }
function Get-LodLine([string]$text) { $m = $LodRx.Match($text); if ($m.Success) { $m.Value } else { '' } }

function Get-HedgeState([string]$text, $e) {
    if ($e -and (Same @($TreeRx.Matches($text) | ForEach-Object { $_.Value }) $e.nt) -and (Get-LodLine $text) -eq $e.nl) { return 'enhanced' }
    return 'default'
}

function Get-HedgeOverview($xp) {
    $files = @(Get-HedgeFiles $xp)
    $log = Read-Log (Get-HedgeLogPath $xp)
    $n = 0
    foreach ($f in $files) { if ((Get-HedgeState ([IO.File]::ReadAllText($f, $Latin1)) $log[(Rel $xp $f)]) -eq 'enhanced') { $n++ } }
    $overall = if ($files.Count -eq 0) { $null } elseif ($n -eq $files.Count) { 'enhanced' } elseif ($n -eq 0) { 'default' } else { 'partly enhanced' }
    [pscustomobject]@{ Files = $files; Overall = $overall; Log = $log }
}

function Get-HedgeStatusText($o) {
    if (-not $o.Files.Count) { return 'not installed' }
    switch ($o.Overall) { 'enhanced' { 'enhanced (about 4-5 m, visible up to 8 km)' } 'default' { 'default (2.2-2.8 m, visible up to 4 km)' } default { $o.Overall } }
}

function Apply-Hedges($xp, $o) {
    $sw = New-Object IO.StreamWriter((Get-HedgeLogPath $xp), $true, $Utf8)
    $sw.AutoFlush = $true; $done = 0
    try {
        foreach ($f in $o.Files) {
            $rel = Rel $xp $f; $text = [IO.File]::ReadAllText($f, $Latin1)
            if ((Get-HedgeState $text $o.Log[$rel]) -eq 'enhanced') { continue }
            if ($text -match '(?m)^[ \t]*MESH') { Warn "  Skipped (unexpected 3D content): $rel"; continue }
            $new = $TreeRx.Replace($text, {
                param($m)
                $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value +
                (Fmt ([double]::Parse($m.Groups[4].Value, $Inv) * $HedgeFac)) + $m.Groups[5].Value +
                (Fmt ([double]::Parse($m.Groups[6].Value, $Inv) * $HedgeFac))
            })
            $lm = $LodRx.Match($new)
            if ($lm.Success -and [double]::Parse($lm.Groups[2].Value, $Inv) -lt $HedgeLod) {
                $new = $new.Substring(0, $lm.Index) + $lm.Groups[1].Value + $HedgeLod + $new.Substring($lm.Index + $lm.Length)
            }
            $entry = [ordered]@{ f = $rel; ol = (Get-LodLine $text); nl = (Get-LodLine $new)
                ot = [string[]]@($TreeRx.Matches($text) | ForEach-Object { $_.Value })
                nt = [string[]]@($TreeRx.Matches($new) | ForEach-Object { $_.Value }) }
            $sw.WriteLine((New-Object PSObject -Property $entry | ConvertTo-Json -Compress))   # log first, then write
            Write-Bytes $f ($Latin1.GetBytes($new)); $done++
            $o.Log[$rel] = New-Object PSObject -Property $entry
        }
    } finally { $sw.Close() }
    Write-Log (Get-HedgeLogPath $xp) $o.Log.Values
    TLog "hedges: enhanced $done files"
    Write-Host "  simHeaven hedges enhanced: $done files" -ForegroundColor Green
}

function Restore-Hedges($xp, $o) {
    $done = 0
    foreach ($f in $o.Files) {
        $rel = Rel $xp $f; $e = $o.Log[$rel]; $text = [IO.File]::ReadAllText($f, $Latin1)
        if ($e -and (Get-HedgeState $text $e) -eq 'enhanced') {
            $new = Set-Seq $text $TreeRx $e.ot
            if ($e.ol) { $new = Set-Seq $new $LodRx @($e.ol) }
            Write-Bytes $f ($Latin1.GetBytes($new)); $done++
        }
        $o.Log.Remove($rel)
    }
    Write-Log (Get-HedgeLogPath $xp) $o.Log.Values
    TLog "hedges: back to default $done files"
    Write-Host "  simHeaven hedges back to default: $done files" -ForegroundColor Green
}

# ---------------------------------------------------------------- Knicks (northern Germany / Denmark)
# Own small library that replaces the simHeaven hedges (OSM barrier=hedge) and tree rows
# (OSM natural=tree_row) and scrub only in the Knick areas with Knicks: bushes plus single trees. Uses the
# X-Plane default tree billboards (copied, they may not be shipped) and the same XP12 shader
# settings as the default forests. simHeaven files are not changed for it.
$KnickDir  = 'XP12_ForestTweak_Knicks'
$KnickMark = '# generated by XP12 Forest Tweak'
# Knick / Wallhecken areas, whole 1x1 degree tiles "west south east north" (south-west corners):
# Schleswig-Holstein (everywhere), Niedersachsen (Ostfriesland, Oldenburg, Elbe-Weser, Emsland,
# Osnabrueck-Nord, Heidekreis - NLWKN), West-Mecklenburg (LUNG), Hamburg, Denmark (diger, hegn).
$KnickRects = @('7 52 9 52', '7 53 11 53', '8 54 12 54', '8 55 12 55', '14 55 14 55', '8 56 11 57')
$KnickArea  = 'Schleswig-Holstein, Hamburg, north-west Lower Saxony, west Mecklenburg, Denmark'
$KnickSeasons = @(@('spr', 'trees_bb1_ALB_sp', 'trees_bb1_ALB', 'trees_bb1_SM'), @('sum', 'trees_bb1_ALB', 'trees_bb1_ALB_fa', 'trees_bb1_SM'),
                  @('fal', 'trees_bb1_ALB_fa', 'trees_bb1_ALB_wi', 'trees_bb1_SM'), @('win', 'trees_bb1_ALB_wi', 'trees_bb1_ALB_sp', 'trees_bb1_SM_wi'))
$KnickTextures = @('trees_bb1_ALB', 'trees_bb1_ALB_sp', 'trees_bb1_ALB_fa', 'trees_bb1_ALB_wi', 'trees_bb1_NML', 'trees_bb1_SM', 'trees_bb1_SM_wi')
#   s t w h off freq min max kind name   (kind b = bush, t = tree)
# Knick (heights at tree height 1.0, the tree height factor is applied on top):
#   bushes in three sizes (1.5-3, 3-5, 5-8 m), Ueberhaelter in three ages (6-9, 9-12, 12-14 m).
#   HEIGHT_PARAMS: heights change in sections of about 100 m (like a Knick cut a few years ago next to an
#   old one) instead of from tree to tree. CHOICE_PARAMS + GROUP: sections of pure bushes and sections with
#   Ueberhaelter, about 40 / 60 %.
$KnickHedge = @(@('P', 'HEIGHT_PARAMS 100 0.7 25 0.3 0 0 0 0'), @('P', 'CHOICE_PARAMS 150 0.8 30 0.2 0 0 0 0'),
                @('G', 40),
                @(224,2848,118,124,59,18,1.5,3,'b','decid_03'), @(224,2848,118,124,59,14,3,5,'b','decid_03'),
                @(1900,2848,128,124,64,16,3,5,'b','sorbus_07'), @(1900,2848,128,124,64,10,5,8,'b','sorbus_07'),
                @(1792,2848,108,124,54,16,1.5,3,'b','lilac_06'), @(1792,2848,108,124,54,10,3,5,'b','lilac_06'),
                @(332,2080,110,124,55,16,5,8,'b','locust_01'),
                @('G', 60),
                @(224,2848,118,124,59,14,1.5,3,'b','decid_03'), @(224,2848,118,124,59,12,3,5,'b','decid_03'),
                @(1900,2848,128,124,64,13,3,5,'b','sorbus_07'), @(1900,2848,128,124,64,9,5,8,'b','sorbus_07'),
                @(1792,2848,108,124,54,13,1.5,3,'b','lilac_06'), @(1792,2848,108,124,54,8,3,5,'b','lilac_06'),
                @(332,2080,110,124,55,14,5,8,'b','locust_01'),
                @(776,2976,184,252,92,4,6,9,'t','maple_07'), @(1452,3584,190,252,95,4,9,12,'t','ash_07'),
                @(1050,3584,104,252,52,3,9,12,'t','oak1_08'), @(880,3584,170,252,85,4,12,14,'t','oak1_07'),
                @(1050,3584,104,252,52,2,12,14,'t','oak1_08'))
$KnickRow = @(@(880,3584,170,252,85,8,12,20,'t','oak1_07'), @(1050,3584,104,252,52,8,12,18,'t','oak1_08'),
              @(1154,3584,128,252,64,7,12,19,'t','oak1_09'), @(1452,3584,190,252,95,7,11,18,'t','ash_07'),
              @(776,2976,184,252,92,6,10,16,'t','maple_07'), @(250,2592,208,252,104,6,11,17,'t','elm_05'),
              @(294,3584,118,252,59,5,10,15,'t','birch_07'), @(1296,2976,110,252,55,4,11,17,'t','aspen_05'),
              @(0,2976,208,252,104,4,12,18,'t','redoak_04'), @(224,2848,118,124,59,15,4,6,'b','decid_03'),
              @(1900,2848,128,124,64,15,4,6,'b','sorbus_07'), @(1792,2848,108,124,54,15,4,5.5,'b','lilac_06'))
# scrub areas (OSM natural=scrub, often narrow Knick strips): dense bushes 2-6 m, a few small trees
$KnickScrub = @(@(224,2848,118,124,59,25,2.5,5,'b','decid_03'), @(1900,2848,128,124,64,24,2,4.5,'b','sorbus_07'),
                @(1792,2848,108,124,54,24,2,4,'b','lilac_06'), @(332,2080,110,124,55,24,3,6,'b','locust_01'),
                @(294,3584,118,252,59,2,6,10,'s','birch_07'), @(1296,2976,110,252,55,1,6,10,'s','aspen_05'))
# hedge outside the Knick areas (simHeaven hedges, X-WORLD Pro hedge walls, official hedge maps): dense bushes
$KnickPlain = @(@(224,2848,118,124,59,20,3,5,'b','decid_03'), @(1900,2848,128,124,64,20,3,5,'b','sorbus_07'),
                @(1792,2848,108,124,54,20,2.5,4.5,'b','lilac_06'), @(332,2080,110,124,55,15,4,5.5,'b','locust_01'),
                @(224,2848,118,124,59,15,2,3,'b','decid_03'), @(1792,2848,108,124,54,10,2,3,'b','lilac_06'))
$KnickKinds = @(@('knick', 'Knick: bushes in three sizes plus Ueberhaelter in sections', '0.8', '0.8', '8000', $KnickHedge, 'simheaven/forests/hedge.for'),
                @('treerow', 'Knick tree row: mixed broadleaf trees plus bushes in between', '2.5', '1.2', '10000', $KnickRow, 'simheaven/forests/random_tree.for'),
                @('scrub', 'Knick scrub: dense bushes 2-6 m with a few small trees', '3', '1.5', '8000', $KnickScrub, 'simheaven/forests/shrubs.for'),
                @('knickmap', 'Knick of the hedgerow map: bushes in three sizes plus Ueberhaelter (1.6 m strips)', '1.0', '0.8', '8000', $KnickHedge, $null),
                @('hedge', 'Hedge: dense bushes 2-5.5 m (hedges outside the Knick areas)', '1.0', '0.8', '8000', $KnickPlain, $null))

# ---------------------------------------------------------------- hedge overlay
# The tool turns hedges and tree rows into X-Plane forests in its own scenery pack ($ShDir), built on this
# computer. Sources, in this order:
#   1. official hedge maps that come with the tool (hedgerow_map_*.dat, see DATA_LICENSES.txt)
#   2. the simHeaven hedges and tree rows of this computer (free X-World or X-WORLD Pro), only where the
#      official maps have nothing nearby. They are hidden in the built tiles by the tool's library.
# simHeaven X-WORLD Pro draws hedges as walls (facades), which can not become forests through a library, so
# with Pro the hedges of the chosen countries are rebuilt here. Nothing of simHeaven is shipped.
$ShUrl    = 'https://opendata.schleswig-holstein.de/dataset/sh4-biotopkartierung-der-alleen-knicks-feldhecken-und-baumreihen'
$ShDir    = 'XP12_ForestTweak_HedgerowMap'
$ShVKnick = 'xp12_foresttweak/knick_map.for'
$ShVRow   = 'xp12_foresttweak/treerow_map.for'
$HmVHedge = 'xp12_foresttweak/hedge_map.for'
$HmFiles = @(
    @('sh', 'hedgerow_map_sh.dat', 'Schleswig-Holstein', 'LLUR SH, Biotopkartierung SH4 (Alleen, Knicks, Feldhecken, Baumreihen, 2023), CC BY 4.0', $ShUrl),
    @('ni', 'hedgerow_map_ni.dat', 'Niedersachsen, Bremen, Hamburg', '(c) ML/SLA Niedersachsen/CC BY 4.0 - Landschaftselemente in Niedersachsen, Bremen und Hamburg',
      'https://inspire-geoportal.ec.europa.eu/srv/api/records/c0f447eb-151b-42a7-bdd0-e99b1062f67c'),
    @('nrw', 'hedgerow_map_nrw.dat', 'Nordrhein-Westfalen', 'Land NRW - Landschaftselemente in NRW (2026-11-07), dl-de/by-2-0 (www.govdata.de/dl-de/by-2-0)',
      'https://ckan.open.nrw.de/dataset/landschaftselemente-in-nrw-geo-nrw'),
    @('by', 'hedgerow_map_by.dat', 'Bayern', 'Bayerisches Staatsministerium fuer Ernaehrung, Landwirtschaft, Forsten und Tourismus - InVeKoS Landschaftselemente, CC BY 4.0',
      'https://gdk.gdi-de.org/geonetwork/srv/api/records/2bf51905-de03-4a56-93c4-1bea034b3a4d'),
    @('bb', 'hedgerow_map_bb.dat', 'Brandenburg', '(c) Ministerium fuer Land- und Ernaehrungswirtschaft, Umwelt und Verbraucherschutz - InVeKoS Landschaftselemente BB (2026-11-07), dl-de/by-2-0 (www.govdata.de/dl-de/by-2-0)',
      'https://gdk.gdi-de.org/geonetwork/srv/api/records/72ed0323-7f32-400f-8bc1-7f0bb6cb83ba'),
    @('dk', 'hedgerow_map_dk.dat', 'Denmark', 'Slots- og Kulturstyrelsen - Beskyttede sten- og jorddiger, CC0 1.0',
      'https://arealdata.miljoeportal.dk/datasets/urn:dmp:ds:beskyttede-sten-og-jorddiger'))
$ProHedgeFac = @('simheaven/ground/hedge_low.fac', 'simheaven/ground/hedge_high.fac')
$ProHedgeFor = @('simheaven/ground/hedge_low.for', 'simheaven/ground/hedge_high.for')
$RowVPath    = 'simheaven/forests/random_tree.for'
$BlankFac    = "A`r`n800`r`nFACADE`r`n"
# Countries for X-WORLD Pro (not named $Countries: PowerShell names ignore case and the parameter $countries would hide it): whole 1x1 degree tiles south -> (west from, west to); border tiles belong to both
$CountryTable = @(@('de', 'Germany', @{ 47 = @(7, 13); 48 = @(7, 13); 49 = @(6, 13); 50 = @(5, 14); 51 = @(5, 14); 52 = @(6, 14); 53 = @(6, 14); 54 = @(8, 14); 55 = @(8, 8) }),
               @('dk', 'Denmark', @{ 54 = @(8, 12); 55 = @(8, 15); 56 = @(8, 12); 57 = @(8, 11) }),
               @('bnl', 'Benelux', @{ 49 = @(5, 6); 50 = @(2, 6); 51 = @(2, 6); 52 = @(3, 7); 53 = @(4, 7) }),
               @('at', 'Austria', @{ 46 = @(9, 16); 47 = @(9, 17); 48 = @(12, 17) }),
               @('ch', 'Switzerland', @{ 45 = @(8, 9); 46 = @(5, 10); 47 = @(5, 10) }))
$ChoiceNames = @{ 'default' = 'original'; 'enhanced' = 'enhanced'; 'Knicks' = 'hedgebanks (Knicks)' }

function TK([int]$s, [int]$w) { "$s,$w" }
function Get-RectsTiles($rects) {
    $out = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($r in $rects) { $v = @($r.Split(' ') | ForEach-Object { [int]$_ }); for ($s = $v[1]; $s -le $v[3]; $s++) { for ($w = $v[0]; $w -le $v[2]; $w++) { [void]$out.Add((TK $s $w)) } } }
    return ,$out
}
$KnickTiles = Get-RectsTiles $KnickRects
function Split-TK([string]$k) { $p = $k.Split(','); @([int]$p[0], [int]$p[1]) }
function Sort-Tiles($tiles) { @($tiles | Sort-Object @{ Expression = { (Split-TK $_)[0] } }, @{ Expression = { (Split-TK $_)[1] } }) }
function Get-TilesRects($tiles) {
    # tiles -> REGION_RECT lines "west south east north", one run per row of tiles
    $out = @()
    $rows = @{}
    foreach ($t in $tiles) { $sw = Split-TK $t; if (-not $rows.ContainsKey($sw[0])) { $rows[$sw[0]] = @() }; $rows[$sw[0]] += $sw[1] }
    foreach ($s in @($rows.Keys | Sort-Object)) {
        $ws = @($rows[$s] | Sort-Object)
        $a = $ws[0]; $b = $ws[0]
        for ($i = 1; $i -le $ws.Count; $i++) {
            if ($i -lt $ws.Count -and $ws[$i] -eq $b + 1) { $b = $ws[$i]; continue }
            $out += "$a $s $b $s"
            if ($i -lt $ws.Count) { $a = $ws[$i]; $b = $ws[$i] }
        }
    }
    return $out
}
function Get-TileRelDir([int]$s, [int]$w) { (Get-ShTileRel $s $w) }

function Get-HmFile([string]$name) {
    $up = Split-Path -Parent $PSScriptRoot
    foreach ($d in @($PSScriptRoot, $up, (Join-Path $up 'data'), (Join-Path $PSScriptRoot 'data'))) { $p = Join-Path $d $name; if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}
$script:HmLoaded = $false; $script:HmFound = @()
function Read-HmData {
    if ($script:HmLoaded) { return }
    [FdtHedgeMap]::Clear()
    $script:HmFound = @()
    foreach ($f in $HmFiles) { $p = Get-HmFile $f[1]; if ($p) { [FdtHedgeMap]::ReadMap($p); $script:HmFound += $f[0] } }
    $script:HmLoaded = $true
}
function Get-HmDataTiles {
    Read-HmData
    $a = [FdtHedgeMap]::DataTiles(); $out = New-Object 'System.Collections.Generic.HashSet[string]'
    for ($i = 0; $i -lt $a.Length; $i += 2) { [void]$out.Add((TK $a[$i] $a[$i + 1])) }
    return ,$out
}

# ---- simHeaven on this computer
function Get-HmSources($xp) {
    # enabled simHeaven packs with hedges, in scenery_packs.ini order
    $ini = Read-Ini $xp
    $out = @()
    if (-not $ini) { return ,$out }
    foreach ($l in $ini.Lines) {
        if ($l -match '(?i)^SCENERY_PACK\s+Custom Scenery/(simHeaven_X-WORLD-Pro_(.+?)-06-extras1)/?\s*$') {
            $n = $Matches[1]; $r = $Matches[2]
            $out += [pscustomobject]@{ Kind = 'pro'; D = (Join-Path $xp "Custom Scenery/$n"); D2 = (Join-Path $xp ("Custom Scenery/" + $n.Substring(0, $n.Length - 10) + '07-extras2')); Region = $r }
        } elseif ($l -match '(?i)^SCENERY_PACK\s+Custom Scenery/(simHeaven_X-World_(.+?)-4-extras)/?\s*$') {
            $n = $Matches[1]; $r = $Matches[2]
            $out += [pscustomobject]@{ Kind = 'free'; D = (Join-Path $xp "Custom Scenery/$n"); D2 = (Join-Path $xp "Custom Scenery/$n"); Region = $r }
        }
    }
    return ,$out
}
function Get-HmDetect($xp) {
    $src = Get-HmSources $xp
    $pro = @($src | Where-Object { $_.Kind -eq 'pro' } | ForEach-Object { $_.Region } | Sort-Object -Unique)
    $free = @($src | Where-Object { $_.Kind -eq 'free' } | ForEach-Object { $_.Region } | Sort-Object -Unique)
    $both = @($pro | Where-Object { $p = $_; @($free | Where-Object { $_.ToLower() -eq $p.ToLower() }).Count })
    [pscustomobject]@{ Pro = $pro; Free = $free; Both = $both }
}
function Get-HmProTiles($xp) {
    $out = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($src in (Get-HmSources $xp)) {
        if ($src.Kind -ne 'pro') { continue }
        $base = Join-Path $src.D 'Earth nav data'
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.dsf')) {
            if ($f.Name -match '^([+-]\d\d)([+-]\d\d\d)\.dsf$') { [void]$out.Add((TK ([int]$Matches[1]) ([int]$Matches[2]))) }
        }
    }
    return ,$out
}
function Get-HmTileSource($srcs, [int]$s, [int]$w) {
    $rel = Get-ShTileRel $s $w
    foreach ($src in $srcs) {
        $p = Join-Path $src.D "Earth nav data/$rel"
        if (Test-Path -LiteralPath $p) {
            $p2 = Join-Path $src.D2 "Earth nav data/$rel"
            return [pscustomobject]@{ Kind = $src.Kind; P1 = $p; P2 = $(if (Test-Path -LiteralPath $p2) { $p2 } else { $null }) }
        }
    }
    return [pscustomobject]@{ Kind = $null; P1 = $null; P2 = $null }
}
function Get-CountryTiles([string]$key) {
    $out = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($c in $CountryTable) { if ($c[0] -eq $key) { foreach ($s in $c[2].Keys) { for ($w = $c[2][$s][0]; $w -le $c[2][$s][1]; $w++) { [void]$out.Add((TK $s $w)) } } } }
    return ,$out
}
function Get-SrcSig($t) {
    $sig = @()
    foreach ($p in @($t.P1, $t.P2)) {
        if ($p) {
            $fi = Get-Item -LiteralPath $p
            $mt = [long][Math]::Floor(($fi.LastWriteTimeUtc - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalSeconds)
            $sig += "$($fi.Directory.Parent.Parent.Name):$($fi.Length):$mt"
        }
    }
    return ($sig -join ';')
}

function Get-HmInfo($xp) {
    # settings of the built overlay or $null
    $m = Join-Path (Get-ShPack $xp) 'hedgerow_map.txt'
    if (-not (Test-Path -LiteralPath $m)) { return $null }
    $text = [IO.File]::ReadAllText($m, $Latin1)
    if (-not $text.StartsWith($KnickMark)) { return $null }
    $o = [pscustomobject]@{ Choice = 'Knicks'; Countries = @(); Tiles = @{}; Version = '' }
    foreach ($l in ($text -split "`r?`n")) {
        $tok = @($l.Split(' ', [StringSplitOptions]::RemoveEmptyEntries))
        if ($l.StartsWith($KnickMark) -and $tok.Count -gt 6) { $o.Version = $tok[6] }
        elseif ($tok.Count -gt 1 -and $tok[0] -eq 'choice') { $o.Choice = $tok[1] }
        elseif ($tok.Count -ge 1 -and $tok[0] -eq 'countries') { $o.Countries = @($tok | Select-Object -Skip 1) }
        elseif ($tok.Count -ge 3 -and $tok[0] -eq 'tile') { $o.Tiles[(TK ([int]$tok[1]) ([int]$tok[2]))] = $(if ($tok.Count -gt 3) { $tok[3] } else { '' }) }
    }
    return $o
}

function Get-HmWant($xp, [string]$choice, $countries) {
    $pro = Get-HmProTiles $xp
    $want = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($choice -eq 'Knicks') { $want.UnionWith($KnickTiles) }
    foreach ($c in $countries) { if ($c -eq 'all') { $want.UnionWith($pro) } else { $want.UnionWith((Get-CountryTiles $c)) } }
    $want.IntersectWith($pro)
    $want.UnionWith((Get-HmDataTiles))
    return ,$want
}

function Build-HedgeOverlay($xp, [string]$choice, $countries, $only) {
    # builds the hedge overlay; $only: tiles to rebuild ($null = all). Returns the set of built tiles.
    $t0 = [DateTime]::Now
    $d = Get-ShPack $xp
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    Write-Host '  Reading the hedge maps ...'
    Read-HmData
    $srcs = Get-HmSources $xp
    $tiles = Sort-Tiles (Get-HmWant $xp $choice $countries)
    $info0 = Get-HmInfo $xp
    $old = @{}
    if ($info0 -and $info0.Version -eq $Version -and $info0.Choice -eq $choice) { $old = $info0.Tiles }
    # remove tiles that are not wanted any more (also those of older versions)
    $keep = @{}; foreach ($t in $tiles) { $sw = Split-TK $t; $keep[(Split-Path -Leaf (Get-ShTileRel $sw[0] $sw[1]))] = $true }
    $end = Join-Path $d 'Earth nav data'
    if (Test-Path -LiteralPath $end) { foreach ($f in @(Get-ChildItem -LiteralPath $end -Recurse -File -Filter '*.dsf')) { if (-not $keep.ContainsKey($f.Name)) { Remove-Item -LiteralPath $f.FullName } } }
    $sigs = @{}; foreach ($k in $old.Keys) { if ($tiles -contains $k) { $sigs[$k] = $old[$k] } }
    $todo = @($tiles | Where-Object { $null -eq $only -or $only.Contains($_) -or -not $old.ContainsKey($_) })
    $total = 0; $kept = 0
    $agent = "XP12 Forest Tweak $Version (hedge overlay, see ATTRIBUTION.txt)"
    $p = New-Prog 'Hedge tiles' $todo.Count; $i = 0
    foreach ($t in $todo) {
        $i++; Step-Prog $p $i $i $todo.Count
        $sw = Split-TK $t; $s = $sw[0]; $w = $sw[1]
        $knick = $choice -eq 'Knicks' -and $KnickTiles.Contains($t)
        $src = Get-HmTileSource $srcs $s $w
        $bytes = [FdtHedgeMap]::BuildTile($s, $w, $src.Kind, $src.P1, $src.P2, $knick, $agent, $(if ($knick) { $ShVKnick } else { $HmVHedge }), $ShVRow)
        $path = Join-Path $d ('Earth nav data/' + (Get-ShTileRel $s $w))
        $pd = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $pd)) { New-Item -ItemType Directory -Path $pd | Out-Null }
        Write-Bytes $path $bytes
        $sigs[$t] = Get-SrcSig $src
        $total += [FdtHedgeMap]::LastMap; $kept += [FdtHedgeMap]::LastKept
    }
    End-Prog $p
    if (Test-Path -LiteralPath $end) { foreach ($sub in @(Get-ChildItem -LiteralPath $end -Directory)) { if (@(Get-ChildItem -LiteralPath $sub.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $sub.FullName } } }
    $att = @('XP12 Forest Tweak - hedge overlay (made on this computer)', '',
             'Hedges, hedgebanks (Knicks), tree rows and copses from official maps (changed: only outlines and type',
             'kept, compact format, turned into X-Plane forest strips and tree rows, cut into 1x1 degree tiles):')
    foreach ($f in $HmFiles) { if ($script:HmFound -contains $f[0]) { $att += "  $($f[2]): $($f[3])"; $att += "    $($f[4])" } }
    $att += @('', 'Hedges and tree rows where the maps have none: taken over from the simHeaven scenery on this',
              'computer (OpenStreetMap data, (c) OpenStreetMap contributors, ODbL).',
              'The data providers do not endorse this project.',
              'Made for use on this computer only - do not share this folder.', '',
              'Restore original in XP12 Forest Tweak removes this folder.')
    Write-Bytes (Join-Path $d 'ATTRIBUTION.txt') ([Text.Encoding]::ASCII.GetBytes(($att -join "`r`n") + "`r`n"))
    $info = @("$KnickMark $Version - do not edit", "choice $choice", ('countries ' + ($countries -join ' ')))
    foreach ($t in $tiles) { $sw = Split-TK $t; $info += "tile $($sw[0]) $($sw[1]) $($sigs[$t])" }
    Write-Bytes (Join-Path $d 'hedgerow_map.txt') ([Text.Encoding]::ASCII.GetBytes(($info -join "`r`n") + "`r`n"))
    [void](Set-ShIniPlace $xp)
    $took = Took $t0
    TLog "hedge overlay: $($todo.Count) of $($tiles.Count) tiles built, $total map features, $kept simHeaven features ($took)"
    Write-Host "  Hedge overlay: $($tiles.Count) tiles, $total features from the hedge maps ($took)" -ForegroundColor Green
    $set = New-Object 'System.Collections.Generic.HashSet[string]'; foreach ($t in $tiles) { [void]$set.Add($t) }
    return ,$set
}

function Get-HmChanged($xp) {
    # tiles whose simHeaven source changed since they were built (e.g. after a simHeaven update)
    $out = New-Object 'System.Collections.Generic.HashSet[string]'
    $info = Get-HmInfo $xp
    if (-not $info) { return ,$out }
    $srcs = Get-HmSources $xp
    foreach ($t in $info.Tiles.Keys) { $sw = Split-TK $t; if ((Get-SrcSig (Get-HmTileSource $srcs $sw[0] $sw[1])) -ne $info.Tiles[$t]) { [void]$out.Add($t) } }
    return ,$out
}

function Get-KnickPath($xp) { Join-Path $xp "Custom Scenery/$KnickDir" }

function Get-KnickInfo($xp) {
    # active, tree height and profile of a library generated by this tool
    $lt = Join-Path (Get-KnickPath $xp) 'library.txt'
    if (Test-Path -LiteralPath $lt) {
        foreach ($l in [IO.File]::ReadAllLines($lt, $Latin1)) {
            if ($l -match ('^' + [regex]::Escape($KnickMark) + '.*\|\s*height\s+([0-9.]+)\s+(\w+)')) {
                return [pscustomobject]@{ On = $true; H = [double]::Parse($Matches[1], $Inv); HP = $Matches[2] }
            }
        }
    }
    [pscustomobject]@{ On = $false; H = $null; HP = $null }
}

function Get-IniPath($xp) { Join-Path $xp 'Custom Scenery/scenery_packs.ini' }

function Read-Ini($xp) {
    $p = Get-IniPath $xp
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $raw = [IO.File]::ReadAllText($p, $Utf8)
    $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    [pscustomobject]@{ Lines = @($raw -split [regex]::Escape($nl)); NL = $nl }
}

function Write-Ini($xp, $lines, $nl) {
    # one backup per day in ForestDensityTweak, then write via a temp file
    $p = Get-IniPath $xp
    $bk = Join-Path (Get-TweakDir $xp) ('scenery_packs.ini.backup-' + (Get-Date -Format 'yyyyMMdd'))
    if ((Test-Path -LiteralPath $p) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $p -Destination $bk }
    Write-Bytes $p ($Utf8.GetBytes(($lines -join $nl)))
}

function Test-PackLine([string]$line, [string]$folder) {
    # true for the scenery_packs.ini line of exactly this Custom Scenery folder (enabled or disabled)
    if ($line -match '(?i)^SCENERY_PACK(?:_DISABLED)?\s+Custom Scenery/(.+?)/?\s*$') { return $Matches[1].ToLower() -eq $folder.ToLower() }
    return $false
}

function Set-PackPlace($xp, [string]$folder, [string]$rx, [string]$fallbackFolder) {
    # lists $folder directly above the first line matching $rx; $true if changed
    $ini = Read-Ini $xp
    if (-not $ini) { return $false }
    $mine = "SCENERY_PACK Custom Scenery/$folder/"
    $rest = @($ini.Lines | Where-Object { -not (Test-PackLine $_ $folder) })
    $i = -1
    for ($k = 0; $k -lt $rest.Count; $k++) { if ($rest[$k] -match $rx) { $i = $k; break } }
    if ($i -lt 0 -and $fallbackFolder) { for ($k = 0; $k -lt $rest.Count; $k++) { if (Test-PackLine $rest[$k] $fallbackFolder) { $i = $k; break } } }
    if ($i -lt 0) { for ($k = 0; $k -lt $rest.Count; $k++) { if ($rest[$k].StartsWith('SCENERY_PACK')) { $i = $k; break } } }
    if ($i -lt 0) { $i = $rest.Count }
    $new = @()
    if ($i -gt 0) { $new += $rest[0..($i - 1)] }
    $new += $mine
    if ($i -lt $rest.Count) { $new += $rest[$i..($rest.Count - 1)] }
    if (($new -join "`n") -eq ($ini.Lines -join "`n")) { return $false }
    Write-Ini $xp $new $ini.NL
    return $true
}
# the tweak library directly above the simHeaven libraries (free Vegetation Library or X-WORLD Pro Library)
function Set-KnickIniPlace($xp) { Set-PackPlace $xp $KnickDir '(?i)simheaven.*(vegetation.*librar|X-WORLD-Pro_Library)' $null }
# the hedge overlay above all simHeaven packs: their forest exclusions would hide it otherwise
function Set-ShIniPlace($xp) { Set-PackPlace $xp $ShDir '(?i)^SCENERY_PACK(_DISABLED)?\s+Custom Scenery/simHeaven_X-World(_|-Pro_(?!Library|Add-ons))' $KnickDir }

function Remove-KnickIni($xp) {
    $ini = Read-Ini $xp
    if (-not $ini -or -not @($ini.Lines | Where-Object { Test-PackLine $_ $KnickDir }).Count) { return }
    Write-Ini $xp @($ini.Lines | Where-Object { -not (Test-PackLine $_ $KnickDir) }) $ini.NL
}

function Write-Knicks($xp, [double]$h, [string]$hp, $built, [string]$choice = 'Knicks') {
    # creates or updates the tweak library for tree height $h / profile $hp. $built: tiles of the hedge overlay
    # (there the simHeaven hedges and tree rows are hidden, the overlay has them). $choice: 'Knicks' or 'enhanced'
    if ($null -eq $built) { $built = New-Object 'System.Collections.Generic.HashSet[string]' }
    $d = Get-KnickPath $xp
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    $tex = Join-Path $xp 'Resources/default scenery/1200 forests/textures'
    foreach ($name in $KnickTextures) {
        $src = $null
        foreach ($ext in '.dds', '.png') { $c = Join-Path $tex ($name + $ext); if (Test-Path -LiteralPath $c) { $src = $c; break } }
        if (-not $src) { throw "X-Plane default tree texture not found: $name (run the X-Plane installer 'Update')" }
        $dst = Join-Path $d (Split-Path -Leaf $src)
        if (-not (Test-Path -LiteralPath $dst) -or (Get-Item -LiteralPath $dst).Length -ne (Get-Item -LiteralPath $src).Length) {
            if ((Get-Free $d) -lt (Get-Item -LiteralPath $src).Length + $DiskMargin) { throw 'Not enough free disk space.' }
            Copy-Item -LiteralPath $src -Destination "$dst.tmp" -Force
            Move-Item -LiteralPath "$dst.tmp" -Destination $dst -Force
        }
    }
    $hb = if ($h -lt 1.0 -and $hp -eq 'realistic') { Rnd (1.0 - (1.0 - $h) * 0.5) 4 } else { $h }    # bushes: like shrubs
    foreach ($k in $KnickKinds) {
        foreach ($s in $KnickSeasons) {
            $out = @('A', '1200', 'FOREST', '', "$KnickMark $Version - do not edit, Restore original removes it",
                     "# $($k[1]), season $($s[0]), tree height factor $(Fmt $h) $hp", '',
                     'SHADER_2D', "`tTEXTURE $($s[1]).png", "`tSEASONAL $($s[2]).png", "`tTEXTURE_NORMAL 1`ttrees_bb1_NML.png",
                     "`tWEATHER $($s[3]).png", "`tBLEND_HASH 0.5", "`tSUPER_ROUGHNESS 1.0", "`tNORMAL_TRANSLUCENCY", '',
                     "LOD $($k[4])", 'SCALE_X 2048', 'SCALE_Y 4096', "SPACING $($k[2]) $($k[2])", "RANDOM $($k[3]) $($k[3])", '',
                     "#`ts`tt`tw`th`toff`tfreq`tmin`tmax`tquads`tlayer`tname")
            foreach ($r in $k[5]) {
                if ($r[0] -is [string] -and $r[0] -eq 'P') { $out += $r[1]; continue }               # perlin noise parameters
                if ($r[0] -is [string] -and $r[0] -eq 'G') { $out += "GROUP 0 $($r[1])"; continue }   # tree group with its share of the forest
                $f = if ($r[8] -eq 't') { $h } else { $hb }      # small trees in scrub scale like bushes
                $out += "TREE`t$($r[0])`t$($r[1])`t$($r[2])`t$($r[3])`t$($r[4])`t$($r[5])`t$(Fmt ([double]$r[6] * $f))`t$(Fmt ([double]$r[7] * $f))`t2`t0`t$($r[9])"
            }
            Write-Bytes (Join-Path $d "$($k[0])_$($s[0]).for") ([Text.Encoding]::ASCII.GetBytes(($out -join "`r`n") + "`r`n"))
        }
    }
    $blank = @('A', '1200', 'FOREST', '', "$KnickMark $Version - do not edit, Restore original removes it",
               '# empty forest: hides the simHeaven hedges and tree rows where the hedgerow map has them', '',
               'TEXTURE trees_bb1_ALB.png', 'LOD 1', 'SCALE_X 2048', 'SCALE_Y 4096', 'SPACING 10000 10000', 'RANDOM 0 0',
               "TREE`t224`t2848`t118`t124`t59`t100`t0.1`t0.1`t2`t0`tnone")
    Write-Bytes (Join-Path $d 'blank.for') ([Text.Encoding]::ASCII.GetBytes(($blank -join "`r`n") + "`r`n"))
    Write-Bytes (Join-Path $d 'blank.fac') ([Text.Encoding]::ASCII.GetBytes($BlankFac))
    $lib = @('A', '800', 'LIBRARY', '', ("$KnickMark $Version | height $(Fmt $h) $hp | choice $choice" + $(if ($built.Count) { ' | map' } else { '' })),
             '# Hedges: hedgebanks (Knicks) in the Knick areas, enhanced hedges elsewhere, for all four seasons.',
             "# Knick areas: $KnickArea.",
             '# simHeaven files are not changed. Restore original removes this folder.', '')
    foreach ($s in $KnickSeasons) {
        $lib += "EXPORT_SEASON $($s[0]) $ShVKnick knickmap_$($s[0]).for"
        $lib += "EXPORT_SEASON $($s[0]) $ShVRow treerow_$($s[0]).for"
        $lib += "EXPORT_SEASON $($s[0]) $HmVHedge hedge_$($s[0]).for"
    }
    $libTiles = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($choice -eq 'Knicks') { $libTiles.UnionWith($KnickTiles); $libTiles.ExceptWith($built) }
    if ($libTiles.Count) {
        $lib += @('', '# Knick areas without overlay tiles: free X-World hedges, tree rows and scrub become Knicks', 'REGION_DEFINE xp12_foresttweak_knicks_north')
        foreach ($r in (Get-TilesRects $libTiles)) { $lib += "REGION_RECT $r" }
        $lib += @('REGION xp12_foresttweak_knicks_north', '')
        foreach ($k in $KnickKinds) { if ($k[6]) { foreach ($s in $KnickSeasons) { $lib += "EXPORT_EXCLUDE_SEASON $($s[0]) $($k[6]) $($k[0])_$($s[0]).for" } } }
    }
    $bk = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($choice -eq 'Knicks') { $bk.UnionWith($built); $bk.IntersectWith($KnickTiles) }
    $other = New-Object 'System.Collections.Generic.HashSet[string]'; $other.UnionWith($built); $other.ExceptWith($bk)
    foreach ($g in @(@('xp12_foresttweak_overlay_knick', $bk, $true), @('xp12_foresttweak_overlay', $other, $false))) {
        if (-not $g[1].Count) { continue }
        $lib += @('', ('# tiles of the hedge overlay: its hedges' + $(if ($g[2]) { ' and tree rows' } else { '' }) + ' replace the simHeaven ones'), "REGION_DEFINE $($g[0])")
        foreach ($r in (Get-TilesRects $g[1])) { $lib += "REGION_RECT $r" }
        $lib += @("REGION $($g[0])", '')
        foreach ($vp in $ProHedgeFac) { $lib += "EXPORT_EXCLUDE $vp blank.fac" }
        foreach ($s in $KnickSeasons) {
            $vps = @($HedgeVPath) + $ProHedgeFor; if ($g[2]) { $vps += $RowVPath }
            foreach ($vp in $vps) { $lib += "EXPORT_EXCLUDE_SEASON $($s[0]) $vp blank.for" }
            if ($g[2]) { $lib += "EXPORT_EXCLUDE_SEASON $($s[0]) simheaven/forests/shrubs.for scrub_$($s[0]).for" }
        }
    }
    Write-Bytes (Join-Path $d 'library.txt') ([Text.Encoding]::ASCII.GetBytes(($lib -join "`r`n") + "`r`n"))
    $moved = Set-KnickIniPlace $xp
    TLog "knicks: library written (height $h $hp), scenery_packs.ini $(if ($moved) { 'updated' } else { 'ok' })"
}

function Remove-Knicks($xp) {
    $d = Get-KnickPath $xp
    if (Test-Path -LiteralPath $d) {
        $names = @('library.txt', 'blank.for', 'blank.fac')
        foreach ($k in $KnickKinds) { foreach ($s in $KnickSeasons) { $names += "$($k[0])_$($s[0]).for" } }
        foreach ($n in $KnickTextures) { $names += "$n.dds"; $names += "$n.png" }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File)) {
            if ($names -contains $f.Name -or $f.Name.EndsWith('.tmp') -or $f.Name.EndsWith('.fdt_tmp')) { Remove-Item -LiteralPath $f.FullName }
        }
        if (@(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) { Remove-Item -LiteralPath $d }
        else { Warn "  Folder Custom Scenery\$KnickDir has other files in it and was left in place (inactive)." }
    }
    Remove-KnickIni $xp
    TLog 'knicks: removed'
}

function Get-KnickLibVersion($xp) {
    $lt = Join-Path (Get-KnickPath $xp) 'library.txt'
    if (-not (Test-Path -LiteralPath $lt)) { return $null }
    foreach ($l in [IO.File]::ReadAllLines($lt, $Latin1)) { if ($l -match ('^' + [regex]::Escape($KnickMark) + '\s+(\S+)')) { return $Matches[1] } }
    return $null
}

function Get-HedgeChoice($xp, $overall) {
    # current hedge choice: 'default', 'enhanced' or 'Knicks'
    if ((Get-KnickInfo $xp).On) {
        $lt = Join-Path (Get-KnickPath $xp) 'library.txt'
        $txt = [IO.File]::ReadAllText($lt, $Latin1)
        if ($txt -match '\|\s*choice\s+(\w+)') { return $Matches[1] }
        return 'Knicks'
    }
    if ($overall) { return $overall }
    return 'default'
}

function Get-ShPack($xp) { Join-Path $xp "Custom Scenery/$ShDir" }
function Get-ShTileRel([int]$s, [int]$w) {
    $f = '{0}{1:00}{2}{3:000}' -f $(if ($s -lt 0) { '-' } else { '+' }), [Math]::Abs([Math]::Floor($s / 10) * 10), $(if ($w -lt 0) { '-' } else { '+' }), [Math]::Abs([Math]::Floor($w / 10) * 10)
    $n = '{0}{1:00}{2}{3:000}.dsf' -f $(if ($s -lt 0) { '-' } else { '+' }), [Math]::Abs($s), $(if ($w -lt 0) { '-' } else { '+' }), [Math]::Abs($w)
    "$f/$n"
}
function Test-ShInfo($xp) {
    $m = Join-Path (Get-ShPack $xp) 'hedgerow_map.txt'
    (Test-Path -LiteralPath $m) -and ([IO.File]::ReadAllText($m, $Latin1).StartsWith($KnickMark))
}

function Remove-ShMap($xp) {
    $d = Get-ShPack $xp
    if (Test-Path -LiteralPath $d) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Recurse)) {
            if ($f.Name.EndsWith('.dsf') -or $f.Name -eq 'ATTRIBUTION.txt' -or $f.Name -eq 'hedgerow_map.txt' -or $f.Name.EndsWith('.tmp') -or $f.Name.EndsWith('.fdt_tmp')) { Remove-Item -LiteralPath $f.FullName }
        }
        foreach ($sub in @(Get-ChildItem -LiteralPath $d -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending)) {
            if (@(Get-ChildItem -LiteralPath $sub.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $sub.FullName }
        }
        if (@(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) { Remove-Item -LiteralPath $d }
        else { Warn "  Folder Custom Scenery\$ShDir has other files in it and was left in place." }
    }
    $ini = Read-Ini $xp
    if ($ini -and @($ini.Lines | Where-Object { Test-PackLine $_ $ShDir }).Count) { Write-Ini $xp @($ini.Lines | Where-Object { -not (Test-PackLine $_ $ShDir) }) $ini.NL }
    TLog 'hedgerow map: removed'
}


# ---------------------------------------------------------------- [1] choose settings
function Read-Spacing([double]$current, [bool]$tweaked) {
    Write-Host '  Step 1/3  Tree spacing'
    Write-Host '  Lower = closer trees = denser forest.'
    Write-Host ''
    for ($i = 0; $i -lt 3; $i++) { Write-Host ('    [{0}] {1,-11} {2,-4}  {3}' -f ($i + 1), $Presets[$i][0], (Fmt $Presets[$i][1]), $Presets[$i][2]) }
    Write-Host "    [4] Custom      $(Fmt $MinFac) - 1.0"
    Write-Host ''
    $cur = $null
    for ($i = 0; $i -lt 3; $i++) { if ($Presets[$i][1] -eq $current) { $cur = "$($i + 1)" } }
    if (-not $tweaked) { $cur = '2'; $current = $DefaultFac }
    $hint = if ($cur) { "Enter = $cur" } else { "Enter = keep $(Fmt $current)" }
    while ($true) {
        $a = (Read-Host "  Choose ($hint)").Trim()
        if ($a -eq '') { return $current }
        if ($a -match '^[123]$') { return [double]$Presets[[int]$a - 1][1] }
        if ($a -eq '4') { return (Read-Value $MinFac $current 'tree spacing') }
        $v = Parse-Value $a $MinFac      # a value typed directly is fine too
        if ($null -ne $v) { return $v }
        Warn '  Please choose 1, 2, 3 or 4.'
    }
}

function Read-Height([double]$current, [bool]$tweaked) {
    Write-Host '  Step 2/3  Tree height'
    Write-Host '  Lower = smaller trees. Conifers shrink a bit less. 3D tree models included.'
    Write-Host ''
    for ($i = 0; $i -lt $HeightPresets.Count; $i++) { Write-Host ('    [{0}] {1,-16} {2,-4}' -f ($i + 1), $HeightPresets[$i][0], ([double]$HeightPresets[$i][1]).ToString('0.0', $Inv)) }
    $n = $HeightPresets.Count + 1
    Write-Host "    [$n] Custom           $(Fmt $MinHeight) - 1.0"
    Write-Host ''
    if (-not $tweaked) { $current = $DefaultHeight }
    $cur = $null
    for ($i = 0; $i -lt $HeightPresets.Count; $i++) { if ($HeightPresets[$i][1] -eq $current) { $cur = "$($i + 1)" } }
    $hint = if ($cur) { "Enter = $cur" } else { "Enter = keep $(Fmt $current)" }
    while ($true) {
        $a = (Read-Host "  Choose ($hint)").Trim()
        if ($a -eq '') { return $current }
        if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -lt $n) { return [double]$HeightPresets[[int]$a - 1][1] }
        if ($a -eq "$n") { return (Read-Value $MinHeight $current 'tree height') }
        $v = Parse-Value $a $MinHeight      # a value typed directly is fine too
        if ($null -ne $v) { return $v }
        Warn "  Please choose a number from 1 to $n."
    }
}

function Read-Hedges([string]$current) {
    Write-Host '  Step 3/3  Hedges'
    Write-Host '  How hedges and tree rows look. Official hedge maps add missing hedges.'
    Write-Host ''
    Write-Host '    [1] Original     as simHeaven made them'
    Write-Host '    [2] Enhanced     taller, greener hedges (4 - 5 m)'
    Write-Host '    [3] Hedgebanks   Northern Germany and Denmark: bushes on earth banks'
    Write-Host '        (Knicks)     with single hedgerow trees. Elsewhere: [2]'
    Write-Host ''
    $cur = if ($current -eq 'Knicks') { '3' } elseif ($current -eq 'enhanced') { '2' } else { '1' }
    while ($true) {
        $a = (Read-Host "  Choose (Enter = $cur)").Trim(); if ($a -eq '') { $a = $cur }
        if ($a -eq '1') { return 'default' } elseif ($a -eq '2') { return 'enhanced' } elseif ($a -eq '3') { return 'Knicks' }
        Warn '  Please choose 1, 2 or 3.'
    }
}

function Read-Countries($xp, $current) {
    $pro = Get-HmProTiles $xp
    $opts = @()
    foreach ($c in $CountryTable) { $t = Get-CountryTiles $c[0]; $t.IntersectWith($pro); if ($t.Count) { $opts += ,@($c[0], $c[1], $t.Count) } }
    Write-Host ''
    Write-Host '  Countries - X-WORLD Pro hedges are rebuilt here (Knick areas always, about 2 s per tile):'
    Write-Host ''
    for ($i = 0; $i -lt $opts.Count; $i++) { Write-Host ('    [{0}] {1,-12} {2,4} tiles' -f ($i + 1), $opts[$i][1], $opts[$i][2]) }
    Write-Host ('    [A] all X-WORLD Pro tiles on this computer  {0,4} tiles' -f $pro.Count)
    Write-Host ''
    $cur = if ($current -and @($current).Count) { @($current) } else { @('de', 'dk') }
    if ($cur -contains 'all') { $hint = 'A' }
    else {
        $hint = (@(for ($i = 0; $i -lt $opts.Count; $i++) { if ($cur -contains $opts[$i][0]) { "$($i + 1)" } }) -join ',')
        if (-not $hint) { $hint = 'none' }
    }
    while ($true) {
        $a = (Read-Host "  Choose, e.g. 1,2,5 (Enter = $hint)").Trim().ToLower()
        if ($a -eq '') { return $cur }
        if ($a -eq 'a') { return @('all') }
        $parts = @($a -split '[ ,;]+' | Where-Object { $_ })
        $ok = $parts.Count -gt 0
        foreach ($p in $parts) { if (-not ($p -match '^\d+$' -and [int]$p -ge 1 -and [int]$p -le $opts.Count)) { $ok = $false } }
        if ($ok) { return @($parts | ForEach-Object { [int]$_ } | Sort-Object -Unique | ForEach-Object { $opts[$_ - 1][0] }) }
        Warn "  Please type numbers from 1 to $($opts.Count) (e.g. 1,2) or A."
    }
}

function Confirm-FreeOff($xp, $det) {
    # free X-World and X-WORLD Pro both on for the same region -> offer to turn the free packs off
    if (-not $det.Both.Count) { return $det }
    $regions = $det.Both -join ', '
    Write-Host ''
    Warn "  simHeaven X-World (free) and X-WORLD Pro are both on for $regions."
    Warn '  This shows buildings, forests and roads twice.'
    Write-Host ''
    if (-not (Ask-Yes '  Turn off the free packs of these regions in scenery_packs.ini? (backup kept) [Y/n]')) { return $det }
    $ini = Read-Ini $xp
    $low = @($det.Both | ForEach-Object { $_.ToLower() })
    $new = @(foreach ($l in $ini.Lines) {
        if ($l -match '(?i)^SCENERY_PACK\s+(Custom Scenery/simHeaven_X-World_(.+?)-\d-[^/]+/?)\s*$' -and $low -contains $Matches[2].ToLower()) { "SCENERY_PACK_DISABLED $($Matches[1])" } else { $l }
    })
    Write-Ini $xp $new $ini.NL
    TLog "free X-World turned off for $regions"
    Write-Host "  Free X-World turned off for $regions." -ForegroundColor Green
    return (Get-HmDetect $xp)
}

function Invoke-ChooseSettings($xp, $targets) {
    if (Test-Blocked) { return }
    $wasOff = Test-SwitchedOff $xp
    Confirm-TweakActive $xp $targets
    # state read at the start (or by Status) is still valid when nothing was changed since then
    $st = $script:StCache
    if ($wasOff -or -not $st) { $st = Get-ForestState $xp $targets }
    $tweaked = $st.N -gt 0
    $ho = Get-HedgeOverview $xp
    $ki = Get-KnickInfo $xp
    $det = Confirm-FreeOff $xp (Get-HmDetect $xp)
    $hasSh = [bool]($ho.Files.Count -or $det.Pro.Count -or $det.Free.Count)
    $hchoice = if ($hasSh) { Get-HedgeChoice $xp $ho.Overall } else { 'default' }
    $info = Get-HmInfo $xp
    $curC = @(); if ($info) { $curC = @($info.Countries) }
    $hasGf = @($targets | Where-Object { (Rel $xp $_) -match '^Custom Scenery' }).Count -gt 0
    Write-Host ''
    Write-Host '  Nothing is changed until you confirm at the end.'
    Write-Host ''
    Write-Host ''
    $fac = Read-Spacing $st.X $tweaked
    Write-Host ''
    Write-Host ''
    $hf = Read-Height $st.H $tweaked
    $hp = if ($hf -lt 1.0) { 'realistic' } else { 'uniform' }
    Write-Host ''
    Write-Host ''
    $want = $hchoice; $wantC = $curC
    if ($hasSh) {
        $want = Read-Hedges $hchoice
        if ($det.Pro.Count -and $want -ne 'default') { $wantC = @(Read-Countries $xp $curC) }
    } else { Write-Host '  Step 3/3  Hedges   skipped - simHeaven X-World not installed' }
    # summary
    $same = (($fac -eq $st.X) -and ($hf -eq $st.H) -and ($hp -eq $st.HP)) -or (($fac -eq 1.0) -and ($hf -eq 1.0) -and ($st.X -eq 1.0) -and ($st.H -eq 1.0))
    $rebuild = $tweaked -and ((-not $same) -or $st.NOld -gt 0)       # restore first, then apply the new values
    $refresh = $tweaked -and $same -and $st.NOld -eq 0 -and $st.NOrig -gt 0
    $forestChange = $rebuild -or $refresh -or ((-not $tweaked) -and ($fac -ne 1.0 -or $hf -ne 1.0))
    $overlayOn = $want -ne 'default'
    if (-not $det.Pro.Count) { $wantC = @() }
    $changed = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($info -and $overlayOn) { $changed = Get-HmChanged $xp }
    # tiles the plan wants that are not built (or built ones it does not want), e.g. after an earlier version
    $planDiff = $false
    if ($info -and $overlayOn -and $info.Version -eq $Version -and $info.Choice -eq $want) {
        Write-Host '  Checking the hedge tiles ...'
        $plan0 = Get-HmWant $xp $want $wantC
        if ($plan0.Count -ne $info.Tiles.Count) { $planDiff = $true }
        else { foreach ($t in $plan0) { if (-not $info.Tiles.ContainsKey($t)) { $planDiff = $true; break } } }
    }
    $overlayChange = $overlayOn -and ((-not $info) -or $info.Version -ne $Version -or $info.Choice -ne $want -or ((@($info.Countries | Sort-Object) -join ' ') -ne (@($wantC | Sort-Object) -join ' ')) -or $changed.Count -gt 0 -or $planDiff)
    $libChange = $overlayOn -and ((-not $ki.On) -or $ki.H -ne $hf -or $ki.HP -ne $hp -or (Get-KnickLibVersion $xp) -ne $Version -or $hchoice -ne $want -or $overlayChange)
    $hedgeChange = $hasSh -and ($want -ne $hchoice -or $overlayChange -or $libChange)
    Write-Host ''
    Write-Host ''
    Write-Host '  Summary'
    Write-Host '  -------'
    $now = if ($tweaked) { Format-Forest $st.X $st.H $st.HP } else { 'original' }
    if ($refresh) { $why = if ($st.NReset) { 'reset by an update' } else { 'not tweaked yet' }; Write-Host "  Forests   $now  ->  apply to $($st.NOrig) files $why" }
    elseif ($tweaked -and $same -and $st.NOld) { Write-Host "  Forests   $now  ->  re-apply with the latest improvements" }
    elseif ($forestChange) { Write-Host "  Forests   $now  ->  $(Format-Forest $fac $hf $hp)" }
    else { Write-Host "  Forests   $now  (unchanged)" }
    if ($hasSh) {
        if ($want -ne $hchoice) { Write-Host "  Hedges    $($ChoiceNames[$hchoice])  ->  $($ChoiceNames[$want])" }
        elseif ($libChange -and $want -eq 'Knicks' -and $ki.On -and ($ki.H -ne $hf -or $ki.HP -ne $hp)) { Write-Host "  Hedges    $($ChoiceNames[$want])  ->  heights follow the new tree height" }
        else { Write-Host ("  Hedges    $($ChoiceNames[$want])" + $(if ($hedgeChange) { '  ->  updated' } else { '  (unchanged)' })) }
        if ($det.Pro.Count -and $overlayOn) {
            $names = if ($wantC -contains 'all') { 'all' } else { (@($CountryTable | Where-Object { $wantC -contains $_[0] } | ForEach-Object { $_[1] }) -join ', ') }
            if (-not $names) { $names = 'none' }
            Write-Host "  Countries $names (X-WORLD Pro)"
        }
    }
    Write-Host ''
    Write-Host '  What is changed'
    if ($forestChange) { Write-Host ('    {0,6} forest files      backups kept' -f $st.Files) }
    if ($hedgeChange -and $overlayOn) {
        $plan = Get-HmWant $xp $want $wantC
        if ((-not $info) -or $info.Version -ne $Version -or $info.Choice -ne $want) { $nNew = $plan.Count }
        else { $nNew = @($plan | Where-Object { -not $info.Tiles.ContainsKey($_) -or $changed.Contains($_) }).Count }
        Write-Host ('    {0,6} hedge tiles       {1} to build, about {2} min' -f $plan.Count, $nNew, [Math]::Max(1, [int][Math]::Floor($nNew * 2 / 60)))
        Write-Host '         1 tweak library     hedge types for all four seasons'
    }
    if ($hedgeChange -and $ho.Files.Count -and (($want -ne 'default') -ne ($ho.Overall -eq 'enhanced'))) { Write-Host ('    {0,6} free X-World hedge files' -f $ho.Files.Count) }
    if ($hedgeChange -and -not $overlayOn -and ($ki.On -or (Test-ShInfo $xp))) { Write-Host '         2 tweak folders     removed' }
    if (-not $forestChange -and -not $hedgeChange) { Write-Host '    nothing'; return }
    if ($forestChange -and $hf -lt 1.0) {
        $need = [long]((Get-Files $targets | Measure-Object Length -Sum).Sum * 0.35)
        $free = Get-Free $xp
        Write-Host ''
        Write-Host ("  Disk: about {0:N1} GB backups of the 3D tree models (free: {1:N1} GB)" -f ($need / 1GB), ($free / 1GB))
        if ($free -lt $need + 1GB) { Write-Host '  Not enough free disk space.' -ForegroundColor Red; return }
    }
    if ($forestChange) {
        Write-Host "  Time: $(Format-TimeRange (Get-Estimate $st $hf $rebuild)) for the forests (depends on your computer)"
        if ($hasGf -and $fac -lt 1.0) { Write-Host "  Global Forests v2: cropland extra x$(Fmt $CropFac), sparse forests extra x$(Fmt $SparseFac['25']) / x$(Fmt $SparseFac['50'])" }
    }
    Write-Host ''
    if (-not (Ask-Yes '  Apply now? [Y/n]')) { Write-Host '  Cancelled - nothing was changed.'; return }
    TLog "choose: $now -> spacing $fac height $hf $hp; hedges $hchoice -> $want; countries $($wantC -join ' ')"
    $ok = $true
    Write-Host ''
    if ($forestChange) {
        if ($rebuild) {
            Write-Host '  Restoring originals ...'
            if (-not (Invoke-Restore $xp $targets -Quiet)) { Write-Host '  Stopped before applying the new values.' -ForegroundColor Red; return }
        }
        if ($fac -ne 1.0 -or $hf -ne 1.0) { $ok = Invoke-ApplyValues $xp $targets $fac $hf $hp }
        else { Write-Host '  Forests are original again.' -ForegroundColor Green }
    }
    if ($hedgeChange -and $ok) {
        if ($ho.Files.Count) {
            if ($want -eq 'enhanced' -or $want -eq 'Knicks') { if ($ho.Overall -ne 'enhanced') { Apply-Hedges $xp $ho } }
            elseif ($ho.Overall -ne 'default') { Restore-Hedges $xp $ho }
        }
        if ($overlayOn) {
            if ($overlayChange) {
                $only = $null      # $null = build all tiles (a HashSet must not go through 'if' output, it would be unrolled)
                if ($info -and $info.Version -eq $Version -and $info.Choice -eq $want) { $only = $changed }
                $built = Build-HedgeOverlay $xp $want $wantC $only
            } else {
                $built = New-Object 'System.Collections.Generic.HashSet[string]'; foreach ($k in $info.Tiles.Keys) { [void]$built.Add($k) }
            }
            Write-Knicks $xp $hf $hp $built $want
            Write-Host "  Tweak library: Custom Scenery\$KnickDir" -ForegroundColor Green
            if (-not (Test-Path -LiteralPath (Get-IniPath $xp))) { Warn '  scenery_packs.ini not found - start X-Plane once, then run Check & repair.' }
        } elseif ($ki.On -or (Test-ShInfo $xp)) { Remove-ShMap $xp; Remove-Knicks $xp; Write-Host '  Hedge overlay and tweak library removed.' -ForegroundColor Green }
    }
    if ($ok) { Write-Host ''; Write-Host '  Done. Start X-Plane now.   [Q] Quit' -ForegroundColor Green }
}

# ---------------------------------------------------------------- [5] quick switch tweak <-> original
# Both versions of every tweaked file are kept side by side, so switching is only renaming:
#   tweak active   : file.for = tweak,     file.for.fdt_orig  = original (made at the first switch)
#   original active: file.for = original,  file.for.fdt_tweak = tweak
# The simHeaven hedges are set back / enhanced again (4 small files), the Knick library and the hedgerow
# map are switched off / on in scenery_packs.ini. X-Plane ignores the extra files.
$SideOrig = '.fdt_orig'; $SideTweak = '.fdt_tweak'; $SwitchFile = 'switched_off.json'

function Get-SwitchPath($xp) { Join-Path (Get-TweakDir $xp) $SwitchFile }
function Test-SwitchedOff($xp) { Test-Path -LiteralPath (Get-SwitchPath $xp) }
function Remove-Sides([string]$f) { foreach ($x in $SideOrig, $SideTweak) { if (Test-Path -LiteralPath ($f + $x)) { Remove-Item -LiteralPath ($f + $x) } } }
function Test-LoggedOriginal($fo, $e) { (Same $fo.Lines $e.o) -and ((-not (Has $e 'ot')) -or (Same $fo.TLines $e.ot)) }
function Move-Over([string]$from, [string]$to) { if (Test-Path -LiteralPath $to) { [IO.File]::Replace($from, $to, [NullString]::Value) } else { [IO.File]::Move($from, $to) } }

function Get-OriginalBytes($xp, [string]$f, [string]$rel, $e) {
    # the original file: from the 3D model backup (checked) or by putting the logged lines back
    if (Has $e 'mb') {
        $bp = Get-BackupPath $xp $rel
        try { $data = [FdtMesh14]::Gunzip($bp) } catch { return $null }
        if ((Has $e 'ms') -and [FdtMesh14]::Sha256($data) -ne $e.ms) { return $null }
        return ,$data
    }
    $fo = Read-For $f
    $newHead = Set-Seq $fo.Head $LineRx $e.o
    $newTail = if (Has $e 'ot') { Set-Seq $fo.Tail $TreeRx $e.ot } else { $fo.Tail }
    return ,(Join-For $fo $newHead $newTail)
}

function Set-PackEnabled($xp, [string]$folder, [bool]$on) {
    # switches one pack line on/off in scenery_packs.ini; $true if it was changed
    $ini = Read-Ini $xp
    if (-not $ini) { return $false }
    $new = @(foreach ($l in $ini.Lines) { if (Test-PackLine $l $folder) { $(if ($on) { 'SCENERY_PACK' } else { 'SCENERY_PACK_DISABLED' }) + " Custom Scenery/$folder/" } else { $l } })
    if (($new -join "`n") -eq ($ini.Lines -join "`n")) { return $false }
    Write-Ini $xp $new $ini.NL
    return $true
}

function Invoke-SwitchOff($xp, $targets) {
    # tweak -> original; $true if done
    $log = Read-Log (Get-LogPath $xp)
    $todo = @()
    foreach ($f in @(Get-Files $targets | Where-Object { $log.ContainsKey((Rel $xp $_.FullName)) })) {
        if ((Get-State (Read-For $f.FullName -Quick) $log[(Rel $xp $f.FullName)]) -eq 'tweaked') { $todo += $f } else { Remove-Sides $f.FullName }
    }
    $need = [long](($todo | Where-Object { -not (Test-Path -LiteralPath ($_.FullName + $SideOrig)) } | Measure-Object Length -Sum).Sum)
    if ($need -and (Get-Free $xp) -lt $need + $DiskMargin) { Write-Host ("  Not enough free disk space to keep both versions (needs about {0:N1} GB)." -f ($need / 1GB)) -ForegroundColor Red; return $false }
    if ($need) { Write-Host ("  First switch: keeping a copy of the original files ({0:N1} GB, only this time) ..." -f ($need / 1GB)) }
    $t0 = [DateTime]::Now; $p = New-Prog 'Switching to original' $todo.Count; $done = 0; $i = 0; $damaged = @()
    try {
        foreach ($f in $todo) {
            $i++; Step-Prog $p $i $i $todo.Count
            $full = $f.FullName; $rel = Rel $xp $full
            if (-not (Test-Path -LiteralPath ($full + $SideOrig))) {
                $data = Get-OriginalBytes $xp $full $rel $log[$rel]
                if ($null -eq $data) { $damaged += $rel; continue }   # stays tweaked; Check & repair tells more
                Write-Bytes ($full + $SideOrig) $data
            }
            Move-Over $full ($full + $SideTweak)
            Move-Over ($full + $SideOrig) $full
            $done++
        }
    } finally { End-Prog $p }
    $ho = Get-HedgeOverview $xp
    $hedges = $ho.Overall
    if ($ho.Files.Count -and $ho.Overall -eq 'enhanced') { Restore-Hedges $xp $ho }
    $packs = @(foreach ($d in $ShDir, $KnickDir) { if (Set-PackEnabled $xp $d $false) { $d } })
    $info = [ordered]@{ version = $Version; hedges = $hedges; packs = [string[]]$packs; files = $done }
    [IO.File]::WriteAllText((Get-SwitchPath $xp), ($info | ConvertTo-Json -Compress), $Utf8)
    TLog "switch: original ($done files, $($damaged.Count) damaged backups, hedges $hedges, packs off $($packs -join ' '), $(Took $t0))"
    Write-Host ("  Switched to ORIGINAL: $done forest files" + $(if ($hedges -eq 'enhanced') { ', simHeaven hedges default' } else { '' }) + $(if ($packs.Count) { ', Knicks off' } else { '' }) + "   ($(Took $t0))") -ForegroundColor Green
    if ($damaged.Count) { Warn "  $($damaged.Count) files stay tweaked (their 3D model backup is missing or damaged) - see Check & repair." }
    return $true
}

function Invoke-SwitchOn($xp, $targets, [switch]$Quiet) {
    # original -> tweak; $true if done
    $info = $null
    try { $info = [IO.File]::ReadAllText((Get-SwitchPath $xp), $Utf8) | ConvertFrom-Json } catch { }
    $log = Read-Log (Get-LogPath $xp)
    $t0 = [DateTime]::Now; $done = 0; $stale = 0; $i = 0
    $files = @(Get-Files $targets | Where-Object { $log.ContainsKey((Rel $xp $_.FullName)) })
    $p = New-Prog 'Switching to tweak' $files.Count
    try {
        foreach ($f in $files) {
            $i++; Step-Prog $p $i $i $files.Count
            $full = $f.FullName
            if (-not (Test-Path -LiteralPath ($full + $SideTweak))) { continue }
            if (Test-LoggedOriginal (Read-For $full -Quick) $log[(Rel $xp $full)]) {
                Move-Over $full ($full + $SideOrig)
                Move-Over ($full + $SideTweak) $full
                $done++
            } else { Remove-Item -LiteralPath ($full + $SideTweak); $stale++ }   # updated meanwhile -> tweak it again
        }
    } finally { End-Prog $p }
    if ($info -and $info.hedges -eq 'enhanced') {
        $ho = Get-HedgeOverview $xp
        if ($ho.Files.Count -and $ho.Overall -ne 'enhanced') { Apply-Hedges $xp $ho }
    }
    if ($info -and $info.packs) { foreach ($d in @($info.packs)) { [void](Set-PackEnabled $xp $d $true) } }
    Remove-Item -LiteralPath (Get-SwitchPath $xp)
    TLog "switch: tweak ($done files, $stale updated meanwhile, $(Took $t0))"
    if (-not $Quiet -or $stale) { Write-Host "  Switched to TWEAK: $done forest files   ($(Took $t0))" -ForegroundColor Green }
    if ($stale) { Warn "  $stale files were updated by X-Plane or Global Forests meanwhile - run Choose settings to tweak them again." }
    return $true
}

function Repair-Sides($xp, $targets) {
    # after an interrupted switch: puts every file back into the tweak state, drops outdated copies
    $log = Read-Log (Get-LogPath $xp); $fixed = 0
    foreach ($t in $targets) {
        foreach ($s in @(Get-ChildItem -LiteralPath $t -Recurse -File | Where-Object { $_.Name.EndsWith($SideOrig) -or $_.Name.EndsWith($SideTweak) })) {
            $full = $s.FullName
            if (-not (Test-Path -LiteralPath $full)) { continue }          # handled together with its partner
            $base = if ($full.EndsWith($SideOrig)) { $full.Substring(0, $full.Length - $SideOrig.Length) } else { $full.Substring(0, $full.Length - $SideTweak.Length) }
            $e = $log[(Rel $xp $base)]
            if (-not (Test-Path -LiteralPath $base)) {
                $src = if (Test-Path -LiteralPath ($base + $SideTweak)) { $base + $SideTweak } else { $full }
                Move-Over $src $base; $fixed++; continue
            }
            if (-not $e) { Remove-Sides $base; $fixed++; continue }
            if ((Test-Path -LiteralPath ($base + $SideTweak)) -and (Test-LoggedOriginal (Read-For $base -Quick) $e)) {
                Move-Over $base ($base + $SideOrig); Move-Over ($base + $SideTweak) $base; $fixed++
            } elseif ((Get-State (Read-For $base -Quick) $e) -ne 'tweaked') { Remove-Sides $base; $fixed++ }
            elseif (Test-Path -LiteralPath ($base + $SideTweak)) { Remove-Item -LiteralPath ($base + $SideTweak); $fixed++ }
        }
    }
    return $fixed
}

function Invoke-SwitchMenu($xp, $targets) {
    if (Test-Blocked) { return }
    if (Test-SwitchedOff $xp) {
        if (Ask-Yes '  Switch back to your tweak? [Y/n]') { [void](Invoke-SwitchOn $xp $targets); Write-Host '  Done! You can start X-Plane now.' -ForegroundColor Green }
        return
    }
    $st = Get-ForestState $xp $targets
    if (-not $st.N -and -not (Get-KnickInfo $xp).On) { Write-Host '  Nothing is tweaked - nothing to switch.'; return }
    Write-Host '  Switches to the original forests (and hedges/Knicks) without losing your tweak.'
    Write-Host '  [5] again switches back in a few seconds. The first time a copy of the originals is kept.'
    if (Ask-Yes '  Switch to original now? [Y/n]') { if (Invoke-SwitchOff $xp $targets) { Write-Host '  Done! You can start X-Plane now.' -ForegroundColor Green } }
}

function Confirm-TweakActive($xp, $targets) {
    # Choose settings, Restore and Check & repair work on the tweak: switch back first if needed
    if (Test-SwitchedOff $xp) { Write-Host '  The tweak is switched off - switching back first ...'; [void](Invoke-SwitchOn $xp $targets -Quiet) }
}

# ---------------------------------------------------------------- [2] restore, [3] status, [4] check & repair
function Invoke-RestoreAll($xp, $targets) {
    if (Test-Blocked) { return }
    Confirm-TweakActive $xp $targets
    if (-not (Ask-Yes '  Restore the original forests and hedges? [Y/n]')) { Write-Host '  Cancelled - nothing was changed.'; return }
    $ok = Invoke-Restore $xp $targets
    $ho = Get-HedgeOverview $xp
    if ($ho.Files.Count -and $ho.Overall -ne 'default') { Restore-Hedges $xp $ho }
    if ((Get-KnickInfo $xp).On -or (Test-ShInfo $xp)) { Remove-ShMap $xp; Remove-Knicks $xp; Write-Host '  Knicks removed.' -ForegroundColor Green }
    if ($ok) { Write-Host ''; Write-Host '  Done! You can start X-Plane now. Type Q and press Enter to close this window.' -ForegroundColor Green }
}

function Show-Status($xp, $targets) {
    if (Test-SwitchedOff $xp) {
        Write-Host ''
        Write-Host '  Switched to ORIGINAL with [5]: forests, hedges and Knicks are original right now.' -ForegroundColor Cyan
        Write-Host '  Your tweak is kept next to the files - [5] switches back in a few seconds.'
        return
    }
    $st = $script:StCache
    if (-not $st) { $st = Get-ForestState $xp $targets; $script:StCache = $st }
    $ho = Get-HedgeOverview $xp
    Write-Host ''
    Write-Host "  Forest files checked : $($st.Files)"
    Write-Host "  Tweaked              : $($st.N)" -ForegroundColor Green -NoNewline
    if ($st.N) { Write-Host "   ($(Format-Forest $st.X $st.H $st.HP))" -ForegroundColor Green } else { Write-Host '' }
    Write-Host ("  Original (tweakable) : $($st.NOrig)" + $(if ($st.N -and $st.NOrig) { '   -> run Choose settings to tweak them' } else { '' }))
    Write-Host "  Grass/shrubs (kept)  : $($st.NSkip)"
    if ($st.NOld) { Warn "  From an older version: $($st.NOld) files -> run Choose settings once for the latest improvements" }
    Write-Host "  simHeaven hedges     : $(Get-HedgeStatusText $ho)"
    $det = Get-HmDetect $xp
    $dl = @()
    if ($det.Pro.Count) { $dl += "X-WORLD Pro ($($det.Pro -join ', '))" }
    if ($det.Free.Count) { $dl += "X-World free ($($det.Free -join ', '))" }
    Write-Host ('  simHeaven            : ' + $(if ($dl.Count) { $dl -join ', ' } else { 'not found' }))
    if ($det.Both.Count) { Warn "  Free X-World and X-WORLD Pro are both on for $($det.Both -join ', ') - Choose settings can turn the free packs off" }
    if ((Get-KnickInfo $xp).On) {
        Write-Host "  Hedges               : $($ChoiceNames[(Get-HedgeChoice $xp $ho.Overall)])"
        $info = Get-HmInfo $xp
        if ($info) {
            $names = if ($info.Countries -contains 'all') { 'all' } else { (@($CountryTable | Where-Object { $info.Countries -contains $_[0] } | ForEach-Object { $_[1] }) -join ', ') }
            Write-Host ("  Hedge overlay        : $($info.Tiles.Count) tiles (Custom Scenery/$ShDir)" + $(if ($names) { ", X-WORLD Pro: $names" } else { '' }))
            Write-Host '                         official hedge maps: see DATA_LICENSES.txt'
        }
    }
    $other = @(Get-OtherForestAddons $xp)
    if ($other.Count) {
        Write-Host ''
        Warn '  Other scenery that may bring its own forests (not changed by this tool):'
        foreach ($o in ($other | Select-Object -First 8)) { Warn "    $o" }
        Warn '  Where it covers an area, its forests are shown instead of the tweaked ones.'
    }
    Write-Host ''
    Write-Host '  The visible effect is limited by the vegetation slider in X-Plane and by the forest data of'
    Write-Host '  the scenery: where the scenery has no forest areas, no trees are added.'
}

function Invoke-CheckRepair($xp, $targets) {
    if (Test-Blocked) { return }
    Confirm-TweakActive $xp $targets
    Write-Host '  Checking backups and log ...'
    $t0 = [DateTime]::Now
    $logPath = Get-LogPath $xp
    $log = Read-Log $logPath
    $tmp = Remove-TempFiles $xp $targets
    $sides = Repair-Sides $xp $targets
    $roots = @($targets | ForEach-Object { (Rel $xp $_) + $Sep })
    $gone = 0; $reset = 0; $bad = 0; $okGz = 0; $badFiles = @()
    $items = @($log.Keys | Where-Object { $k = $_; @($roots | Where-Object { $k.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count })
    $p = New-Prog 'Checking' $items.Count; $i = 0
    foreach ($rel in $items) {
        $i++; Step-Prog $p $i $i $items.Count
        $e = $log[$rel]; $f = Join-Path $xp $rel; $bp = Get-BackupPath $xp $rel
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
            $gone++; $log.Remove($rel); if (Test-Path -LiteralPath $bp) { Remove-Item -LiteralPath $bp }; continue
        }
        if ((Get-State (Read-For $f -Quick) $e) -ne 'tweaked') {
            $reset++; $log.Remove($rel); if (Test-Path -LiteralPath $bp) { Remove-Item -LiteralPath $bp }; continue   # reset by an update
        }
        if (Has $e 'mb') {
            $good = $false
            try {
                if (Test-Path -LiteralPath $bp) {
                    if (Has $e 'ms') { $good = ([FdtMesh14]::Sha256Gz($bp) -eq $e.ms) }
                    else { [void][FdtMesh14]::Gunzip($bp); $good = $true }      # 1.3 backup without checksum: test it reads to the end
                }
            } catch { $good = $false }
            if ($good) { $okGz++ } else { $bad++; $badFiles += $rel }
        }
    }
    End-Prog $p
    # backups that belong to no tweaked file
    $orphans = 0; $bk = Get-BackupRoot $xp
    if (Test-Path -LiteralPath $bk) {
        $bkFull = (Get-Item -LiteralPath $bk).FullName.TrimEnd('\', '/')
        foreach ($g in @(Get-ChildItem -LiteralPath $bk -Recurse -File)) {
            $r = $g.FullName.Substring($bkFull.Length).TrimStart('\', '/')
            if ($r.EndsWith('.gz')) { $r = $r.Substring(0, $r.Length - 3) }
            $e = $log[$r]
            if (-not (Has $e 'mb')) { Remove-Item -LiteralPath $g.FullName; $orphans++ }
        }
    }
    $empty = Remove-EmptyDirs $bk
    Write-Log $logPath $log.Values
    # hedges log
    $hl = Read-Log (Get-HedgeLogPath $xp)
    $hgone = @($hl.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $xp $_) -PathType Leaf) })
    foreach ($k in $hgone) { $hl.Remove($k) }
    if (Test-Path -LiteralPath (Get-HedgeLogPath $xp)) { Write-Log (Get-HedgeLogPath $xp) $hl.Values }
    Write-Host ''
    Write-Host "  3D model backups OK            : $okGz" -ForegroundColor Green
    Write-Host ("  Log lines of reset files       : $reset removed" + $(if ($reset) { '  (run Choose settings to tweak them again)' } else { '' }))
    Write-Host "  Log lines of missing files     : $($gone + $hgone.Count) removed"
    Write-Host "  Unused backups / temp files    : $orphans / $tmp removed"
    Write-Host "  Empty backup folders           : $empty removed"
    if ($sides) { Write-Host "  Quick switch copies            : $sides fixed or removed" }
    $ki = Get-KnickInfo $xp
    if ($ki.On) {
        # rebuild overlay tiles whose simHeaven source changed, rewrite the tweak library, fix scenery_packs.ini
        $info = Get-HmInfo $xp
        $choice = Get-HedgeChoice $xp $null
        $built = New-Object 'System.Collections.Generic.HashSet[string]'
        if ($info) {
            foreach ($t in $info.Tiles.Keys) { [void]$built.Add($t) }
            $ch = $null
            if ($info.Version -eq $Version) { $ch = Get-HmChanged $xp }
            if ($null -eq $ch -or $ch.Count) {
                Write-Host "  Hedge overlay                  : $(if ($null -eq $ch) { 'all' } else { $ch.Count }) tiles out of date - building again"
                $built = Build-HedgeOverlay $xp $choice $info.Countries $ch
            }
            [void](Set-ShIniPlace $xp)
            Write-Host '  Hedge overlay                  : checked, listed above simHeaven'
        }
        Write-Knicks $xp $ki.H $ki.HP $built $choice
        Write-Host '  Tweak library                  : checked, listed above the simHeaven libraries'
    }
    TLog "check: ok $okGz, reset $reset, gone $gone, orphans $orphans, tmp $tmp, empty dirs $empty, bad $bad ($(Took $t0))"
    if ($bad) {
        Write-Host ''
        Write-Host "  $bad backups are missing or damaged. These files stay tweaked (safe), but can't be" -ForegroundColor Red
        Write-Host '  restored exactly. Run the X-Plane installer (Update) or reinstall Global Forests v2,' -ForegroundColor Red
        Write-Host "  then run Check & repair again. First file: $($badFiles[0])" -ForegroundColor Red
        foreach ($r in $badFiles) { TLog "check: damaged backup $r" }
    } else { Write-Host '  Everything is fine.' -ForegroundColor Green }
}

# ---------------------------------------------------------------- main
$upd = Start-UpdateCheck
$t0Main = [DateTime]::Now
try {
    Write-Host ''
    Write-Host "  XP12 Forest Tweak $Version - Windows" -ForegroundColor Cyan
    Write-Host '  ------------------------------------------------------------'
    $xp = (Get-Item -LiteralPath (Find-XPlane @args)).FullName.TrimEnd('\', '/')
    $script:ToolLog = Join-Path (Get-TweakDir $xp) 'tool.log'
    $ver = Get-XPVersion $xp
    Write-Host ("  X-Plane : $xp" + $(if ($ver[1]) { "   ($($ver[1]))" } else { '' }))
    $gf = @(Find-GFv2 $xp)
    $targets = @(Get-Targets $xp $gf)
    TLog "start $Version (Windows, PowerShell $($PSVersionTable.PSVersion)), X-Plane $($ver[1]) at $xp, folders: $((@($targets | ForEach-Object { Rel $xp $_ })) -join ', ')"
    Write-Host "  Folders : $((@($targets | ForEach-Object { Rel $xp $_ })) -join ', ')"
    if (Test-XPRunning) { Warn '  X-Plane is running - please quit it before changing anything.' }
    $st = Get-ForestState $xp $targets
    $script:StCache = $st      # reused by Choose settings and Status until a menu action changes files
    $ho = Get-HedgeOverview $xp
    if (Test-SwitchedOff $xp) { Write-Host '  Status  : switched to ORIGINAL - your tweak is kept, [5] switches back' -ForegroundColor Cyan }
    else {
        Write-Host "  Status  : $(Get-StatusLine $st $(if ($ho.Overall -or (Get-KnickInfo $xp).On) { Get-HedgeChoice $xp $ho.Overall } else { $null }))"
        $det = Get-HmDetect $xp
        $dl = @()
        if ($det.Pro.Count) { $dl += "X-WORLD Pro ($($det.Pro -join ', '))" }
        if ($det.Free.Count) { $dl += "X-World free ($($det.Free -join ', '))" }
        if ($dl.Count) { Write-Host "  simHeaven: $($dl -join ', ')" }
    }
    Show-EnvHints $xp $targets $gf $ver[0] $ver[1]
    if ($upd) {
        try {
            $wait = [Math]::Max(0, 3000 - [int]([DateTime]::Now - $t0Main).TotalMilliseconds)
            if ($upd.Wait($wait)) {
                $tag = ($upd.Result | ConvertFrom-Json).tag_name
                if ($tag -and (Get-VTuple $tag) -gt (Get-VTuple $Version)) {
                    Write-Host "  Update  : version $($tag.TrimStart('v', 'V')) is available - github.com/$Repo/releases" -ForegroundColor Cyan
                }
            }
        } catch { }
    }
    while ($true) {
        Write-Host ''
        $sw = if (Test-SwitchedOff $xp) { '[5] Switch back to tweak' } else { '[5] Switch to original' }
        Write-Host "  [1] Choose settings   [2] Restore original   [3] Status   [4] Check & repair   $sw   [Q] Quit"
        $menuKey = (Read-Host '  Choice').Trim()
        switch -Regex ($menuKey) {
            '^1$'    { Invoke-ChooseSettings $xp $targets }
            '^2$'    { Invoke-RestoreAll $xp $targets }
            '^3$'    { Show-Status $xp $targets }
            '^4$'    { Invoke-CheckRepair $xp $targets }
            '^5$'    { Invoke-SwitchMenu $xp $targets }
            '^[qQ]$' { return }
        }
        if ($menuKey -match '^[1245]$') { $script:StCache = $null }      # files may have changed: read the state again next time
    }
} catch {
    Write-Host ''
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    TLog "ERROR: $($_.Exception.Message)"
    exit 1          # the .bat keeps the window open only after an error
}
