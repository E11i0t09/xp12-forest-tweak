<#
  XP12 Forest Tweak  -  Windows
  Version 1.4.0 (2026-10-26)   https://github.com/E11i0t09/xp12-forest-tweak

  Denser forests and optionally smaller trees for X-Plane 12 - for vanilla X-Plane,
  simHeaven X-World and Global Forests v2 (one tool for all; if Global Forests v2 is
  installed, it asks whether to include it).

  What it does
  - Tree spacing: SPACING and RANDOM in the forest files (.for) are multiplied by a factor
    (0.7 = about twice as many trees per area). The vegetation slider in X-Plane can
    never go above the density set there. RANDOM is scaled too, so the trees keep the
    same relative irregularity instead of clumping together.
  - Global Forests v2 "cropland" forests (field trees and hedgerows between fields) get
    an extra factor of 0.8 on top, so field edges are filled more evenly.
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
  - Optional: simHeaven hedges "default" or "enhanced" (hedges such as the Knicks in
    northern Germany about 4-5 m high and visible up to 8 km). Originals are logged in
    ForestDensityTweak\hedges.log.
  - Actions are written to ForestDensityTweak\tool.log (helpful for bug reports).

  After an X-Plane or Global Forests update the updated files are original again.
  Just run "Choose settings" once more and confirm: reset files are tweaked again.

  Performance: more trees cost GPU time. Start with 0.7, go to 0.8 if FPS drop too much,
  0.6 only on strong GPUs. Use at your own risk. Free community project - CC BY-NC-SA 4.0.
#>

$ErrorActionPreference = 'Stop'
$Version    = '1.4.0'
$TestedXP   = '12.4'          # X-Plane version the tool was tested with
$Repo       = 'E11i0t09/xp12-forest-tweak'
$Threshold  = 3.1             # files with a smaller tree spacing are grass/shrubs/hedges -> kept
$Presets    = @(@('Natural', 0.8, 'noticeably denser'), @('Dense', 0.7, 'about 2x trees, recommended'), @('Very dense', 0.6, 'about 2.8x trees, needs a strong GPU'))
$DefaultFac = 0.7             # preset [2]
$MinFac     = 0.4
$MinHeight  = 0.5             # lowest allowed height factor
$CropFac    = 0.8             # extra spacing factor for Global Forests v2 cropland forests
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
        -not ($low.StartsWith('simheaven') -or $low.StartsWith('global_forests') -or $low.StartsWith('global forests')) -and
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
    [IO.File]::Replace($tmp, $path, [NullString]::Value)   # atomic swap, never a half-written .for
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
    $xe = $x
    if ($x -lt 1.0 -and $rel.Replace('\', '/').ToLower().Contains('/cropland/')) { $xe = Rnd ($x * $CropFac) 4 }
    $he = $h
    if ($h -lt 1.0 -and $hp -eq 'realistic') { $he = Rnd (1.0 - (1.0 - $h) * (Get-HeightWeight $rel)) 4 }
    return @($xe, $he)
}

function Test-Outdated([string]$rel, $e) {
    # tweaked with values that differ from the 1.4 rules for its settings (e.g. cropland from 1.3)
    $want = Get-Effective $rel ([double]$e.x) (Get-H $e) (Get-HP $e)
    $xs = if (Has $e 'xe') { [double]$e.xe } else { [double]$e.x }
    $hs = if (Has $e 'he') { [double]$e.he } else { Get-H $e }
    ([Math]::Abs($want[0] - $xs) -gt 1e-9) -or ([Math]::Abs($want[1] - $hs) -gt 1e-9)
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
        elseif ($st.NOld) { $s += ' - run Choose settings once to apply the 1.4 improvements' }
    }
    if ($hstate) { $s += " | hedges $hstate" }
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
            if ($xe -lt 1.0) {
                $newHead = $LineRx.Replace($fo.Head, {
                    param($m)
                    $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value +
                    (Fmt ([double]::Parse($m.Groups[4].Value, $Inv) * $xe)) + $m.Groups[5].Value +
                    (Fmt ([double]::Parse($m.Groups[6].Value, $Inv) * $xe))
                })
            }
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

# ---------------------------------------------------------------- [1] choose settings
function Read-Spacing([double]$current, [bool]$tweaked) {
    Write-Host '  Step 1  Tree spacing (forest density)'
    Write-Host '          Lower spacing = closer trees = denser forest. 1.0 = original.'
    for ($i = 0; $i -lt 3; $i++) { Write-Host ('          [{0}] {1,-11} {2,-4}  {3}' -f ($i + 1), $Presets[$i][0], (Fmt $Presets[$i][1]), $Presets[$i][2]) }
    Write-Host '          [4] Custom      your own value from 0.4 to 1.0'
    $cur = $null
    for ($i = 0; $i -lt 3; $i++) { if ($Presets[$i][1] -eq $current) { $cur = "$($i + 1)" } }
    if (-not $tweaked) { $cur = '2'; $current = $DefaultFac }
    $hint = if ($cur) { "Enter = $cur" } else { "Enter = keep $(Fmt $current)" }
    while ($true) {
        $a = (Read-Host "  Choose 1-4 ($hint)").Trim()
        if ($a -eq '') { return $current }
        if ($a -match '^[123]$') { return [double]$Presets[[int]$a - 1][1] }
        if ($a -eq '4') { return (Read-Value $MinFac $current 'tree spacing') }
        $v = Parse-Value $a $MinFac      # a value typed directly is fine too
        if ($null -ne $v) { return $v }
        Warn '  Please choose 1, 2, 3 or 4.'
    }
}

function Read-Profile([double]$hf, [string]$current) {
    $ex = { param($w) Fmt (Rnd (1.0 - (1.0 - $hf) * $w) 4) }
    Write-Host '  Step 3  Height profile'
    Write-Host "          [1] uniform    every tree $(Fmt $hf)"
    Write-Host "          [2] realistic  broadleaf $(Fmt $hf), conifers $(& $ex 0.6), palms $(& $ex 0.8), shrubs/orchards $(& $ex 0.5)"
    Write-Host '                         (conifers are often the tallest trees in reality, so they shrink less)'
    $cur = if ($current -eq 'uniform') { '1' } else { '2' }
    while ($true) {
        $a = (Read-Host "  Choose 1-2 (Enter = $cur)").Trim(); if ($a -eq '') { $a = $cur }
        if ($a -eq '1') { return 'uniform' } elseif ($a -eq '2') { return 'realistic' }
        Warn '  Please choose 1 or 2.'
    }
}

function Invoke-ChooseSettings($xp, $targets) {
    if (Test-Blocked) { return }
    $st = Get-ForestState $xp $targets
    $tweaked = $st.N -gt 0
    $ho = Get-HedgeOverview $xp
    $hasGf = @($targets | Where-Object { (Rel $xp $_) -match '^Custom Scenery' }).Count -gt 0
    Write-Host ''
    Write-Host '  Nothing is changed until you confirm at the end.'
    Write-Host ''
    $fac = Read-Spacing $st.X $tweaked
    Write-Host ''
    Write-Host '  Step 2  Tree height'
    Write-Host "          1.0 = original, 0.8 = trees 20 % smaller (lowest $(Fmt $MinHeight)). Includes the 3D tree models."
    $hf = Read-Value $MinHeight $st.H 'tree height'
    $hp = 'uniform'
    if ($hf -lt 1.0) { Write-Host ''; $hp = Read-Profile $hf $(if ($st.H -lt 1.0) { $st.HP } else { 'realistic' }) }
    $want = $null
    if ($ho.Files.Count) {
        Write-Host ''
        Write-Host '  Step 4  simHeaven hedges (e.g. the Knicks in northern Germany)'
        Write-Host '          [1] default   2.2 - 2.8 m high, visible up to 4 km'
        Write-Host '          [2] enhanced  about 4 - 5 m high, visible up to 8 km'
        $cur = if ($ho.Overall -eq 'enhanced') { '2' } else { '1' }
        while (-not $want) {
            $a = (Read-Host "  Choose 1-2 (Enter = $cur)").Trim(); if ($a -eq '') { $a = $cur }
            if ($a -eq '1') { $want = 'default' } elseif ($a -eq '2') { $want = 'enhanced' }
        }
    }
    # summary
    $same = ($fac -eq $st.X) -and ($hf -eq $st.H) -and ($hp -eq $st.HP)
    $rebuild = $tweaked -and ((-not $same) -or $st.NOld -gt 0)       # restore first, then apply the new values
    $refresh = $tweaked -and $same -and $st.NOld -eq 0 -and $st.NOrig -gt 0
    $forestChange = $rebuild -or $refresh -or ((-not $tweaked) -and ($fac -ne 1.0 -or $hf -ne 1.0))
    $hedgeChange = $ho.Files.Count -and $want -ne $ho.Overall
    Write-Host ''
    Write-Host '  Summary'
    Write-Host '  -------'
    $now = if ($tweaked) { Format-Forest $st.X $st.H $st.HP } else { 'original' }
    if ($refresh) { $why = if ($st.NReset) { 'reset by an update' } else { 'not tweaked yet' }; Write-Host "  Forests : $now  ->  apply to $($st.NOrig) files $why" }
    elseif ($tweaked -and $same -and $st.NOld) { Write-Host "  Forests : $now  ->  re-apply with the 1.4 improvements" }
    elseif ($forestChange) { Write-Host "  Forests : $now  ->  $(Format-Forest $fac $hf $hp)" }
    else { Write-Host "  Forests : $now  (unchanged)" }
    if ($forestChange -and $hasGf -and $fac -lt 1.0) {
        Write-Host "            Global Forests v2 cropland (field trees, hedgerows): extra x$(Fmt $CropFac) -> spacing $(Fmt (Rnd ($fac * $CropFac) 4))"
    }
    if ($ho.Files.Count) {
        if ($hedgeChange) { Write-Host "  Hedges  : $($ho.Overall)  ->  $want" } else { Write-Host "  Hedges  : $($ho.Overall)  (unchanged)" }
    }
    if (-not $forestChange -and -not $hedgeChange) { Write-Host '  Nothing to change.'; return }
    if ($forestChange -and $hf -lt 1.0) {
        $need = [long]((Get-Files $targets | Measure-Object Length -Sum).Sum * 0.35)
        $free = Get-Free $xp
        Write-Host '  Smaller trees also scale the 3D tree models. A compressed backup of the originals is kept'
        Write-Host ("  for an exact restore: about {0:N1} GB (free on drive: {1:N1} GB)." -f ($need / 1GB), ($free / 1GB))
        if ($free -lt $need + 1GB) { Write-Host '  Not enough free disk space.' -ForegroundColor Red; return }
    }
    if ($forestChange) {
        Warn "  Estimated time: $(Format-TimeRange (Get-Estimate $st $hf $rebuild)) (depends on your computer)."
        Warn '  Please keep this window open.'
    }
    if (-not (Ask-Yes '  Apply these settings now? [Y/n]')) { Write-Host '  Cancelled - nothing was changed.'; return }
    TLog "choose: $now -> spacing $fac height $hf $hp; hedges $($ho.Overall) -> $want"
    if ($forestChange) {
        if ($rebuild) {
            Write-Host '  Restoring the original forests first ...'
            if (-not (Invoke-Restore $xp $targets -Quiet)) { Write-Host '  Stopped before applying the new values.' -ForegroundColor Red; return }
        }
        if ($fac -ne 1.0 -or $hf -ne 1.0) { [void](Invoke-ApplyValues $xp $targets $fac $hf $hp) }
        else { Write-Host '  Forests are original again.' -ForegroundColor Green }
    }
    if ($hedgeChange) { if ($want -eq 'enhanced') { Apply-Hedges $xp $ho } else { Restore-Hedges $xp $ho } }
    Write-Host ''
    Write-Host '  Done! You can start X-Plane now. Type Q and press Enter to close this window.' -ForegroundColor Green
}

# ---------------------------------------------------------------- [2] restore, [3] status, [4] check & repair
function Invoke-RestoreAll($xp, $targets) {
    if (Test-Blocked) { return }
    if (-not (Ask-Yes '  Restore the original forests and hedges? [Y/n]')) { Write-Host '  Cancelled - nothing was changed.'; return }
    $ok = Invoke-Restore $xp $targets
    $ho = Get-HedgeOverview $xp
    if ($ho.Files.Count -and $ho.Overall -ne 'default') { Restore-Hedges $xp $ho }
    if ($ok) { Write-Host ''; Write-Host '  Done! You can start X-Plane now. Type Q and press Enter to close this window.' -ForegroundColor Green }
}

function Show-Status($xp, $targets) {
    $st = Get-ForestState $xp $targets
    $ho = Get-HedgeOverview $xp
    Write-Host ''
    Write-Host "  Forest files checked : $($st.Files)"
    Write-Host "  Tweaked              : $($st.N)" -ForegroundColor Green -NoNewline
    if ($st.N) { Write-Host "   ($(Format-Forest $st.X $st.H $st.HP))" -ForegroundColor Green } else { Write-Host '' }
    Write-Host ("  Original (tweakable) : $($st.NOrig)" + $(if ($st.N -and $st.NOrig) { '   -> run Choose settings to tweak them' } else { '' }))
    Write-Host "  Grass/shrubs (kept)  : $($st.NSkip)"
    if ($st.NOld) { Warn "  From an older version: $($st.NOld) files -> run Choose settings once for the 1.4 improvements" }
    Write-Host "  simHeaven hedges     : $(Get-HedgeStatusText $ho)"
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
    Write-Host '  Checking backups and log ...'
    $t0 = [DateTime]::Now
    $logPath = Get-LogPath $xp
    $log = Read-Log $logPath
    $tmp = Remove-TempFiles $xp $targets
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
    $ho = Get-HedgeOverview $xp
    Write-Host "  Status  : $(Get-StatusLine $st $ho.Overall)"
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
        Write-Host '  [1] Choose settings   [2] Restore original   [3] Status   [4] Check & repair   [Q] Quit'
        switch -Regex ((Read-Host '  Choice').Trim()) {
            '^1$'    { Invoke-ChooseSettings $xp $targets }
            '^2$'    { Invoke-RestoreAll $xp $targets }
            '^3$'    { Show-Status $xp $targets }
            '^4$'    { Invoke-CheckRepair $xp $targets }
            '^[qQ]$' { return }
        }
    }
} catch {
    Write-Host ''
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    TLog "ERROR: $($_.Exception.Message)"
    exit 1          # the .bat keeps the window open only after an error
}
