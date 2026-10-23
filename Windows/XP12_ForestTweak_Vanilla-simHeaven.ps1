<#
  XP12 Forest Tweak  -  Vanilla / simHeaven edition
  Version 1.3.0 (2026-10-23)

  Denser forests and optionally smaller trees for X-Plane 12. Density: lowers the SPACING (tree distance) value
  in the forest definition files (.for). The vegetation slider in X-Plane can
  never exceed the density defined there, so this is the actual limit.

  Edition: Vanilla X-Plane 12 and simHeaven X-World.
  Folder changed: Resources\default scenery\1200 forests
  (simHeaven X-World links its forests to exactly these default files.)

  What it does
  - SPACING and RANDOM are multiplied by a factor (default 0.7 = ~2x trees per area).
    RANDOM is scaled too, so the trees keep the same relative irregularity instead
    of clumping together.
  - Files with SPACING <= 3.1 m (grass, shrubs, hedges) are left untouched.
  - Optional height factor (0.5 - 1.0): scales min and max height of every tree in
    the forest files, so trees get smaller and the height variation shrinks with
    them. 3D trees defined as TREE2 scale by themselves (nominal height is kept);
    the 3D models of TREE trees are drawn at their modelled size, so their
    vertices are scaled by the same factor. Before that, a compressed copy of the
    original file is stored in <X-Plane>\ForestDensityTweak\mesh_backup
    (about 30 % of the file size) for an exact restore.
  - Density only: just the header lines change, the 3D tree meshes are copied byte for byte.
  - Every original line is logged in <X-Plane>\ForestDensityTweak\backup.log
    (folder name kept from earlier versions so existing tweaks stay restorable),
    so "Restore" puts back the exact original values.
  - Both editions (Vanilla/simHeaven and Global Forests v2) share this log, so
    running both never scales the default forests twice.

  After an X-Plane or Global Forests update the updated files are original again.
  Just run "Choose settings" once more and confirm: reset files are tweaked again.

  Step 3 of "Choose settings": simHeaven hedges "default" or "enhanced" (hedges such as the Knicks in northern
  Germany about 4-5 m high and visible up to 8 km). Only the hedge files of the simHeaven
  X-World Vegetation Library are changed; originals are logged in ForestDensityTweak\hedges.log.

  Performance: more trees cost GPU time. Start with 0.7, go to 0.8 if FPS drop
  too much, 0.6 only on strong GPUs. Use at your own risk.
#>

$ErrorActionPreference = 'Stop'
$Edition    = 'Default'          # 'Default' or 'GFv2'
$Title      = 'Vanilla / simHeaven edition'
$Threshold  = 3.1
$DefaultFac = 0.7      # density factor default
$MinHeight  = 0.5      # lowest allowed height factor
$Inv        = [Globalization.CultureInfo]::InvariantCulture
$Latin1     = [Text.Encoding]::GetEncoding(28591)   # 1:1 byte <-> char, keeps files byte-exact
$LineRx     = [regex]'(?m)^([ \t]*)(SPACING|RANDOM)([ \t]+)([0-9]*\.?[0-9]+)([ \t]+)([0-9]*\.?[0-9]+)'
$HeaderEnd  = [regex]'(?m)^[ \t]*(TREE|TREE2|MESH|MESH_3D|GROUP)\b'
# TREE  <s> <t> <w> <h> <offset> <frequency> <min h> <max h> ...
# TREE2 <s1> <t1> <w> <h> <sw> <percent> <min_height> <max_height> <nominal_height> ...
$TreeRx     = [regex]'(?m)^([ \t]*TREE2?)((?:[ \t]+\S+){6})([ \t]+)([0-9]*\.?[0-9]+)([ \t]+)([0-9]*\.?[0-9]+)(?=[ \t\r\n]|$)'
$MeshDataRx = [regex]'(?m)^[ \t]*(VERTEX|IDX\d*)\b[^\n]*\n?'
$Sep        = [IO.Path]::DirectorySeparatorChar

function Fmt([double]$v) { $v.ToString('0.###', $Inv) }

# Fast helpers in C# (compiled once at start, no install needed):
#  - ScaleMeshes: multiplies x/y/z of the VERTEX lines of the given 3D meshes, everything else byte for byte
#  - Gzip / Gunzip: compressed backup of the original file before its 3D meshes are changed
if (-not ('FdtMesh' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.IO; using System.IO.Compression; using System.Collections.Generic; using System.Globalization; using System.Text;
public static class FdtMesh {
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
                    byte[] o = Encoding.ASCII.GetBytes((v * f).ToString("0.#######", inv));
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
        using (var fs = File.Create(path)) using (var gz = new GZipStream(fs, CompressionMode.Compress)) gz.Write(data, 0, data.Length);
    }
    public static byte[] Gunzip(string path) {
        using (var fs = File.OpenRead(path)) using (var gz = new GZipStream(fs, CompressionMode.Decompress)) using (var ms = new MemoryStream()) { gz.CopyTo(ms); return ms.ToArray(); }
    }
}
"@
}

# ---------------------------------------------------------------- X-Plane path
function Test-XP($p) { $p -and (Test-Path -LiteralPath (Join-Path $p 'X-Plane.exe')) -and (Test-Path -LiteralPath (Join-Path $p 'Resources/default scenery')) }

function Find-XPlane {
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
        $a = Read-Host "X-Plane 12 found at '$($cands[0])'. Use it? [Y/n]"
        if ($a -eq '' -or $a -match '^[yYjJ]') { return $cands[0] }
    } elseif ($cands.Count -gt 1) {
        Write-Host 'Several X-Plane 12 installations found:'
        for ($i = 0; $i -lt $cands.Count; $i++) { Write-Host "  [$($i+1)] $($cands[$i])" }
        $a = Read-Host 'Number (or Enter to type a path)'
        if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $cands.Count) { return $cands[[int]$a - 1] }
    }
    while ($true) {
        $p = (Read-Host 'Path to your X-Plane 12 folder (contains X-Plane.exe)').Trim('"', ' ').TrimEnd('\')
        if (Test-XP $p) { return $p }
        Write-Host '  -> X-Plane.exe / Resources\default scenery not found there.' -ForegroundColor Yellow
    }
}

function Get-Targets($xp) {
    $t = @()
    $def = Join-Path $xp 'Resources/default scenery/1200 forests'
    if (-not (Test-Path -LiteralPath $def)) { throw "Default forest folder not found: $def" }
    $t += (Get-Item -LiteralPath $def).FullName
    if ($Edition -eq 'GFv2') {
        $gf = @(Get-ChildItem -LiteralPath (Join-Path $xp 'Custom Scenery') -Directory |
                Where-Object { $_.Name -match '^Global[ _-]?Forests' -and $_.Name -match 'v2' })
        if ($gf.Count -eq 0) { throw "No 'Global_Forests_v2' folder found in Custom Scenery. Use the Vanilla/simHeaven edition instead." }
        $t += $gf | ForEach-Object { $_.FullName }
    }
    return $t
}

# ---------------------------------------------------------------- backup log
function Get-LogPath($xp) {
    $d = Join-Path $xp 'ForestDensityTweak'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    Join-Path $d 'backup.log'
}

function Read-Log($log) {
    $h = @{}
    if (Test-Path -LiteralPath $log) {
        foreach ($l in [IO.File]::ReadAllLines($log)) {
            if ($l.Trim()) { $e = $l | ConvertFrom-Json; $h[$e.f.Replace('/', $Sep).Replace('\', $Sep)] = $e }   # last entry per file wins; the macOS/Linux version writes '/'
        }
    }
    return $h
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

function Write-Bytes($path, [byte[]]$out) {
    $tmp = "$path.fdt_tmp"
    [IO.File]::WriteAllBytes($tmp, $out)
    [IO.File]::Replace($tmp, $path, [NullString]::Value)   # atomic swap, never a half-written .for
}

function Write-For($path, $fo, [string]$newHead, [string]$newTail, [byte[]]$newMid = $null) {
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
    Write-Bytes $path $out
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

function Get-BackupPath($xp, $rel) { Join-Path (Join-Path $xp 'ForestDensityTweak/mesh_backup') ($rel + '.gz') }

# replace the n-th regex match in $text with $list[n]
function Set-Seq([string]$text, $rx, $list) {
    $list = @($list); $parts = $rx.Matches($text); $sb = New-Object Text.StringBuilder; $pos = 0
    for ($j = 0; $j -lt $parts.Count -and $j -lt $list.Count; $j++) {
        [void]$sb.Append($text.Substring($pos, $parts[$j].Index - $pos)); [void]$sb.Append($list[$j]); $pos = $parts[$j].Index + $parts[$j].Length
    }
    [void]$sb.Append($text.Substring($pos)); $sb.ToString()
}

function Get-H($e) { if ($e -and $e.PSObject.Properties['h']) { [double]$e.h } else { 1.0 } }

function Get-MinSpacing([string]$head) {
    $v = @($LineRx.Matches($head) | Where-Object { $_.Groups[2].Value -eq 'SPACING' } |
           ForEach-Object { [Math]::Min([double]::Parse($_.Groups[4].Value, $Inv), [double]::Parse($_.Groups[6].Value, $Inv)) })
    if ($v.Count -eq 0) { return 0 }
    ($v | Measure-Object -Minimum).Minimum
}

function Same($a, $b) { ($a -join "`n") -eq ($b -join "`n") }

function Get-State($fo, $e) {
    if (-not $e) { return 'original' }
    $treesOk = (-not $e.PSObject.Properties['nt']) -or (Same $fo.TLines $e.nt)
    if ((Same $fo.Lines $e.n) -and $treesOk) { return 'tweaked' }
    return 'original'     # restored by an update (or changed by the author) -> treat as original
}

function Get-Files($targets) {
    foreach ($t in $targets) { Get-ChildItem -LiteralPath $t -Recurse -File -Filter '*.for' }
}

function Rel($xp, $full) { $full.Substring($xp.Length).TrimStart('\', '/') }

# ---------------------------------------------------------------- actions
function Show-Status($xp, $targets) {
    $log = Read-Log (Get-LogPath $xp)
    $c = @{ tweaked = 0; original = 0; skipped = 0 }; $fac = @{}
    $files = @(Get-Files $targets); $i = 0
    foreach ($f in $files) {
        $i++; if ($i % 50 -eq 0) { Write-Progress -Activity 'Checking' -Status "$i / $($files.Count)" -PercentComplete (100 * $i / $files.Count) }
        $fo = Read-For $f.FullName -Quick
        $e  = $log[(Rel $xp $f.FullName)]
        $s  = Get-State $fo $e
        if ($s -eq 'tweaked') { $c.tweaked++; $fac["density $($e.x), height $(Get-H $e)"] = 1 }
        else {
            if ((Get-MinSpacing $fo.Head) -le $Threshold) { $c.skipped++ }
            else { $c.original++ }
        }
    }
    Write-Progress -Activity 'Checking' -Completed
    Write-Host ''
    Write-Host "  Forest files checked : $($files.Count)"
    Write-Host "  Tweaked              : $($c.tweaked)" -ForegroundColor Green -NoNewline
    if ($fac.Count) { Write-Host "   ($($fac.Keys -join ' / '))" } else { Write-Host '' }
    Write-Host "  Original (tweakable) : $($c.original)"
    Write-Host "  Grass/shrubs (kept)  : $($c.skipped)"
    Write-Host "  simHeaven hedges     : $(Get-HedgeStatusText (Get-HedgeOverview $xp))"
    return $c
}

function Invoke-ApplyValues($xp, $targets, [double]$fac, [double]$hf) {
    $logPath = Get-LogPath $xp
    $log = Read-Log $logPath
    $files = @(Get-Files $targets)
    $sw = New-Object IO.StreamWriter($logPath, $true, (New-Object Text.UTF8Encoding($false)))
    $sw.AutoFlush = $true
    $done = 0; $already = 0; $skip = 0; $odd = 0; $i = 0; $meshCount = 0
    try {
        foreach ($f in $files) {
            $i++; if ($i % 25 -eq 0) { Write-Progress -Activity "Applying density $fac / height $hf" -Status "$i / $($files.Count)" -PercentComplete (100 * $i / $files.Count) }
            $rel = Rel $xp $f.FullName
            $fo  = Read-For $f.FullName -Quick
            if ((Get-State $fo $log[$rel]) -eq 'tweaked') { $already++; continue }
            if ((Get-MinSpacing $fo.Head) -le $Threshold) { $skip++; continue }
            $fo  = Read-For $f.FullName
            $newHead = $fo.Head; $newTail = $fo.Tail; $doTrees = $hf -lt 1.0
            if ($doTrees) {
                # safety: all TREE lines of the file must be in the tree list at the end
                $all = $TreeRx.Matches($Latin1.GetString($fo.Bytes)).Count
                if ($all -ne $fo.TLines.Count) { $doTrees = $false; $odd++ }
            }
            if ($fac -lt 1.0) {
                $newHead = $LineRx.Replace($fo.Head, {
                    param($m)
                    $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value +
                    (Fmt ([double]::Parse($m.Groups[4].Value, $Inv) * $fac)) + $m.Groups[5].Value +
                    (Fmt ([double]::Parse($m.Groups[6].Value, $Inv) * $fac))
                })
            }
            if ($doTrees) {
                # min and max height scaled alike -> the height variation shrinks with them
                $newTail = $TreeRx.Replace($fo.Tail, {
                    param($m)
                    $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value +
                    (Fmt ([double]::Parse($m.Groups[4].Value, $Inv) * $hf)) + $m.Groups[5].Value +
                    (Fmt ([double]::Parse($m.Groups[6].Value, $Inv) * $hf))
                })
            }
            $newMid = $null; $meshes = @()
            if ($doTrees) {
                $meshes = Get-TreeMeshes $fo.Tail
                if ($meshes.Count) { $newMid = [FdtMesh]::ScaleMeshes($fo.Bytes, [int]$fo.HeadLen, [int]$fo.TailStart, $meshes, $hf) }
            }
            if ($newHead -eq $fo.Head -and $newTail -eq $fo.Tail -and $null -eq $newMid) { $skip++; continue }
            $entry = [ordered]@{ f = $rel; x = $fac; h = $hf; o = [string[]]$fo.Lines; n = [string[]]@($LineRx.Matches($newHead) | ForEach-Object { $_.Value }) }
            if ($newTail -ne $fo.Tail) {
                $entry.ot = [string[]]$fo.TLines
                $entry.nt = [string[]]@($TreeRx.Matches($newTail) | ForEach-Object { $_.Value })
            }
            if ($null -ne $newMid) {
                # 3D meshes change -> keep a compressed copy of the original file for an exact restore
                [FdtMesh]::Gzip($fo.Bytes, (Get-BackupPath $xp $rel))
                $entry.mb = $true; $meshCount += $meshes.Count
            }
            # log first, then write: an interruption can never lead to double scaling
            $sw.WriteLine((New-Object PSObject -Property $entry | ConvertTo-Json -Compress))
            Write-For $f.FullName $fo $newHead $newTail $newMid
            $done++
        }
    } finally { $sw.Close(); Write-Progress -Activity 'Applying' -Completed }
    Write-Host ''
    Write-Host "  Tweaked now          : $done" -ForegroundColor Green
    Write-Host "  Already tweaked      : $already"
    Write-Host "  Grass/shrubs (kept)  : $skip"
    if ($meshCount) {
        $bk = Join-Path $xp 'ForestDensityTweak/mesh_backup'
        $mb = [Math]::Round(((Get-ChildItem -LiteralPath $bk -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB)
        Write-Host "  3D tree models scaled: $meshCount   (backup: $mb MB in ForestDensityTweak\mesh_backup)"
    }
    if ($odd) { Write-Host "  Unusual layout       : $odd (density changed, tree heights left as they are)" -ForegroundColor Yellow }
}

function Invoke-Restore($xp, $targets, [switch]$Quiet) {
    $logPath = Get-LogPath $xp
    $log = Read-Log $logPath
    if ($log.Count -eq 0) { if (-not $Quiet) { Write-Host '  Forests: nothing to restore (no backup log).' }; return }
    $files = @(Get-Files $targets); $done = 0; $i = 0
    foreach ($f in $files) {
        $i++; if ($i % 25 -eq 0) { Write-Progress -Activity 'Restoring' -Status "$i / $($files.Count)" -PercentComplete (100 * $i / $files.Count) }
        $rel = Rel $xp $f.FullName; $e = $log[$rel]
        if (-not $e) { continue }
        $fo = Read-For $f.FullName
        $bp = Get-BackupPath $xp $rel
        if ((Get-State $fo $e) -ne 'tweaked') {
            # file was reset by an update -> its backup is outdated
            if (Test-Path -LiteralPath $bp) { Remove-Item -LiteralPath $bp }
            $log.Remove($rel); continue
        }
        if ($e.PSObject.Properties['mb'] -and (Test-Path -LiteralPath $bp)) {
            Write-Bytes $f.FullName ([FdtMesh]::Gunzip($bp))
            Remove-Item -LiteralPath $bp
            $log.Remove($rel); $done++; continue
        }
        $newHead = Set-Seq $fo.Head $LineRx $e.o
        $newTail = if ($e.PSObject.Properties['ot']) { Set-Seq $fo.Tail $TreeRx $e.ot } else { $fo.Tail }
        Write-For $f.FullName $fo $newHead $newTail
        $log.Remove($rel); $done++
    }
    Write-Progress -Activity 'Restoring' -Completed
    # keep log entries of files outside this edition's folders (e.g. GFv2 when running the Default edition)
    $keep = @($log.Values | Where-Object { $p = Join-Path $xp $_.f; -not (@($targets | Where-Object { $p.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count) })
    [IO.File]::WriteAllLines($logPath, [string[]]@($keep | ForEach-Object { $_ | ConvertTo-Json -Compress }), (New-Object Text.UTF8Encoding($false)))
    if (-not $Quiet) { Write-Host ''; Write-Host "  Forests restored     : $done files" -ForegroundColor Green }
}

# ---------------------------------------------------------------- simHeaven hedges (step 3 of "Choose settings")
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

function Get-HedgeLogPath($xp) { Join-Path (Split-Path -Parent (Get-LogPath $xp)) 'hedges.log' }
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
    $sw = New-Object IO.StreamWriter((Get-HedgeLogPath $xp), $true, (New-Object Text.UTF8Encoding($false)))
    $sw.AutoFlush = $true; $done = 0
    try {
        foreach ($f in $o.Files) {
            $rel = Rel $xp $f; $text = [IO.File]::ReadAllText($f, $Latin1)
            if ((Get-HedgeState $text $o.Log[$rel]) -eq 'enhanced') { continue }
            if ($text -match '(?m)^[ \t]*MESH') { Write-Host "  Skipped (unexpected 3D content): $rel" -ForegroundColor Yellow; continue }
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
        }
    } finally { $sw.Close() }
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
    [IO.File]::WriteAllLines((Get-HedgeLogPath $xp), [string[]]@($o.Log.Values | ForEach-Object { $_ | ConvertTo-Json -Compress }), (New-Object Text.UTF8Encoding($false)))
    Write-Host "  simHeaven hedges back to default: $done files" -ForegroundColor Green
}

# ---------------------------------------------------------------- [1] choose settings
function Get-ForestState($xp, $targets) {
    # tweaked files, tweakable files still original, current density and height factor
    $log = Read-Log (Get-LogPath $xp)
    $n = 0; $nOrig = 0; $x = 1.0; $h = 1.0
    $files = @(Get-Files $targets); $i = 0
    foreach ($f in $files) {
        $i++; if ($i % 50 -eq 0) { Write-Progress -Activity 'Checking' -Status "$i / $($files.Count)" -PercentComplete (100 * $i / $files.Count) }
        $fo = Read-For $f.FullName -Quick
        $e  = $log[(Rel $xp $f.FullName)]
        if ((Get-State $fo $e) -eq 'tweaked') { $n++; $x = [double]$e.x; $h = Get-H $e }
        elseif ((Get-MinSpacing $fo.Head) -gt $Threshold) { $nOrig++ }
    }
    Write-Progress -Activity 'Checking' -Completed
    [pscustomobject]@{ N = $n; NOrig = $nOrig; X = $x; H = $h }
}

function Read-Value([string]$prompt, [double]$current, [double]$min) {
    while ($true) {
        $a = (Read-Host "$prompt (Enter = $(Fmt $current))").Trim()
        if ($a -eq '') { return $current }
        $v = 0.0
        if ([double]::TryParse($a.Replace(',', '.'), [Globalization.NumberStyles]::Float, $Inv, [ref]$v) -and $v -ge $min -and $v -le 1.0) { return $v }
        Write-Host "  Please enter a value from $(Fmt $min) to 1.0." -ForegroundColor Yellow
    }
}

function Format-Forest([double]$x, [double]$h) { if ($x -eq 1.0 -and $h -eq 1.0) { 'original' } else { "density $(Fmt $x), tree height $(Fmt $h)" } }

function Invoke-ChooseSettings($xp, $targets) {
    $st = Get-ForestState $xp $targets
    $ho = Get-HedgeOverview $xp
    $steps = if ($ho.Files.Count) { 3 } else { 2 }
    Write-Host ''
    Write-Host '  Nothing is changed until you confirm at the end.'
    Write-Host ''
    Write-Host "  Step 1/$steps  Density factor: 0.4 - 1.0. Lower = denser, 1 = original."
    Write-Host "               $DefaultFac = about twice as many trees (recommended)."
    $fac = Read-Value '  Density factor' $(if ($st.N) { $st.X } else { $DefaultFac }) 0.4
    Write-Host ''
    Write-Host "  Step 2/$steps  Tree height factor: $MinHeight - 1.0. Lower = smaller trees, 1 = original."
    Write-Host '               Scales all trees including the 3D models, e.g. 0.8 = 20 % smaller.'
    $hf = Read-Value '  Tree height factor' $st.H $MinHeight
    $want = $null
    if ($ho.Files.Count) {
        Write-Host ''
        Write-Host "  Step 3/$steps  simHeaven hedges (e.g. the Knicks in northern Germany):"
        Write-Host '               [1] default   2.2 - 2.8 m high, visible up to 4 km'
        Write-Host '               [2] enhanced  about 4 - 5 m high, visible up to 8 km'
        $cur = if ($ho.Overall -eq 'enhanced') { '2' } else { '1' }
        while (-not $want) {
            $a = (Read-Host "  Hedges [1/2] (Enter = $cur)").Trim(); if ($a -eq '') { $a = $cur }
            if ($a -eq '1') { $want = 'default' } elseif ($a -eq '2') { $want = 'enhanced' }
        }
    }
    # also re-apply unchanged values when an update has reset some files to original
    $refresh = $st.N -and $st.NOrig -and $fac -eq $st.X -and $hf -eq $st.H
    $forestChange = ($fac -ne $st.X) -or ($hf -ne $st.H) -or $refresh
    $hedgeChange = $ho.Files.Count -and $want -ne $ho.Overall
    Write-Host ''
    Write-Host '  Summary'
    Write-Host '  -------'
    if ($refresh) { Write-Host "  Forests : $(Format-Forest $st.X $st.H)  ->  re-apply to $($st.NOrig) files reset by an update" }
    elseif ($forestChange) { Write-Host "  Forests : $(Format-Forest $st.X $st.H)  ->  $(Format-Forest $fac $hf)" }
    else { Write-Host "  Forests : $(Format-Forest $st.X $st.H)  (unchanged)" }
    if ($ho.Files.Count) {
        if ($hedgeChange) { Write-Host "  Hedges  : $($ho.Overall)  ->  $want" } else { Write-Host "  Hedges  : $($ho.Overall)  (unchanged)" }
    }
    if (-not $forestChange -and -not $hedgeChange) { Write-Host '  Nothing to change.'; return }
    if ($forestChange -and $hf -lt 1.0) {
        $need  = [long]((@(Get-Files $targets) | Measure-Object Length -Sum).Sum * 0.35)
        $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($xp))
        Write-Host '  Smaller trees also scale the 3D tree models. A compressed backup of the originals is kept'
        Write-Host ("  for an exact restore: about {0:N1} GB (free on drive: {1:N1} GB)." -f ($need / 1GB), ($drive.AvailableFreeSpace / 1GB))
        if ($drive.AvailableFreeSpace -lt $need + 1GB) { Write-Host '  Not enough free disk space.' -ForegroundColor Yellow; return }
    }
    if ($forestChange) {
        Write-Host '  Depending on your PC this can take several minutes' -ForegroundColor Yellow
        Write-Host '  (longer with tree height and Global Forests v2). Please keep this window open.' -ForegroundColor Yellow
    }
    if ((Read-Host '  Apply these settings now? [Y/n]') -match '^[nN]') { Write-Host '  Cancelled - nothing was changed.'; return }
    if ($forestChange) {
        if ($st.N -and -not $refresh) { Write-Host '  Restoring the original forests first ...'; Invoke-Restore $xp $targets -Quiet }
        if ($fac -ne 1.0 -or $hf -ne 1.0) { Invoke-ApplyValues $xp $targets $fac $hf }
        else { Write-Host '  Forests are original again.' -ForegroundColor Green }
    }
    if ($hedgeChange) { if ($want -eq 'enhanced') { Apply-Hedges $xp $ho } else { Restore-Hedges $xp $ho } }
}

function Invoke-RestoreAll($xp, $targets) {
    Invoke-Restore $xp $targets
    $ho = Get-HedgeOverview $xp
    if ($ho.Files.Count -and $ho.Overall -ne 'default') { Restore-Hedges $xp $ho }
}

# ---------------------------------------------------------------- main
try {
    Write-Host ''
    Write-Host "  XP12 Forest Tweak 1.3.0 - $Title" -ForegroundColor Cyan
    Write-Host '  ------------------------------------------------------------'
    $xp = (Get-Item -LiteralPath (Find-XPlane)).FullName.TrimEnd('\', '/')
    $targets = Get-Targets $xp
    Write-Host "  X-Plane : $xp"
    foreach ($t in $targets) { Write-Host "  Folder  : $(Rel $xp $t)" }
    if (Get-Process -Name 'X-Plane' -ErrorAction SilentlyContinue) {
        Write-Host '  X-Plane is running - please close it first.' -ForegroundColor Yellow
    }
    [void](Show-Status $xp $targets)
    while ($true) {
        Write-Host ''
        Write-Host '  [1] Choose settings   [2] Restore original   [3] Status   [Q] Quit'
        switch -Regex (Read-Host '  Choice') {
            '^1$'    { Invoke-ChooseSettings $xp $targets }
            '^2$'    { Invoke-RestoreAll $xp $targets }
            '^3$'    { [void](Show-Status $xp $targets) }
            '^[qQ]$' { return }
        }
    }
} catch {
    Write-Host ''
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
