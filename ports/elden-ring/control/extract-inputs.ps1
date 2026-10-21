<#
.SYNOPSIS
  Copies a fixed allowlist of files out of the user's own ELDEN RING archives, headless.
  431000_battle.luabnd is only read for the attack call's argument shape and animation id;
  010000_logic.luabnd only as the layout (container, entry ids, flags, names) of a per-logic
  file; the map .emevd files only for their event ids and InitializeEvent targets.

.DESCRIPTION
  Original tool. Run with Windows PowerShell 5.1 (.NET Framework), because it calls the
  library code shipped inside the user's own UXM Selective Unpack 2.4.2 release:
  SoulsFormats.BHD5 (archive index and entry reader) and UXM's archive keys and RSA header
  decryption, through reflection. No UXM form, unpack routine or exe patcher is called.

  Reads only: the game's DataN/DLC .bhd/.bdt (read-only) and the UXM release. Writes only
  the allowlisted files into a new, empty -OutDir outside the repository and the game, plus
  extract.json with sizes and SHA-256. Refuses anything over 32 MB in total.

  Exit codes: 0 all files written, 1 refused or failed.
#>
param(
    [Parameter(Mandatory)] [string] $GameDir,
    [Parameter(Mandatory)] [string] $UxmExe,
    [Parameter(Mandatory)] [string] $OutDir,
    [string[]] $Files = @('/event/common.emevd.dcx', '/script/aicommon.luabnd.dcx',
        '/map/mapstudio/m60_42_36_00.msb.dcx', '/map/mapstudio/m60_42_37_00.msb.dcx',
        '/map/mapstudio/m60_43_36_00.msb.dcx')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'paths.ps1')

# Only these may ever be extracted; -Files can narrow the list, never widen it.
$Allow = @('/event/common.emevd.dcx', '/script/aicommon.luabnd.dcx',
    '/map/mapstudio/m60_42_36_00.msb.dcx', '/map/mapstudio/m60_42_37_00.msb.dcx',
    '/map/mapstudio/m60_43_36_00.msb.dcx', '/script/431000_battle.luabnd.dcx', '/script/010000_logic.luabnd.dcx',
    '/event/m60_42_36_00.emevd.dcx', '/event/m60_42_37_00.emevd.dcx', '/event/m60_43_36_00.emevd.dcx')
$MaxTotal = 32MB
$Archives = 'Data0', 'Data1', 'Data2', 'Data3', 'DLC'

if ($PSVersionTable.PSEdition -ne 'Desktop') { Refuse 'run with Windows PowerShell 5.1 (powershell.exe)' }
foreach ($f in $Files) { if ($f -notin $Allow) { Refuse "$f is not in the extraction allowlist" } }
if (-not (Test-Path -LiteralPath (Join-Path $GameDir 'eldenring.exe') -PathType Leaf)) { Refuse "no eldenring.exe in $GameDir" }
if (-not (Test-Path -LiteralPath $UxmExe -PathType Leaf)) { Refuse "missing $UxmExe" }
Assert-OutDir $OutDir @($GameDir, $RepoRoot)

# Load the libraries embedded in the UXM release (Costura stores them deflate-compressed).
$uxm = [Reflection.Assembly]::LoadFile((Full $UxmExe))
$loaded = @{}
foreach ($name in 'bouncycastle.crypto', 'soulsformats') {
    $s = $uxm.GetManifestResourceStream("costura.$name.dll.compressed")
    if (-not $s) { Refuse "UXM release has no embedded $name" }
    $ms = New-Object IO.MemoryStream
    $d = New-Object IO.Compression.DeflateStream($s, [IO.Compression.CompressionMode]::Decompress)
    $d.CopyTo($ms); $d.Dispose()
    $loaded[$name] = [Reflection.Assembly]::Load($ms.ToArray())
}
$resolver = [ResolveEventHandler] {
    param($sender, $e)
    $short = ($e.Name -split ',')[0].ToLowerInvariant()
    if ($loaded.ContainsKey($short)) { return $loaded[$short] }
    return $null
}
[AppDomain]::CurrentDomain.add_AssemblyResolve($resolver)

$sf = $loaded['soulsformats']
$bhd5 = $sf.GetType('SoulsFormats.BHD5', $true)
$gameEr = [Enum]::Parse($sf.GetType('SoulsFormats.BHD5+Game', $true), 'EldenRing')
$np = [Reflection.BindingFlags]'NonPublic,Public,Static'
$keys = $uxm.GetType('UXM.ArchiveKeys', $true).GetField('EldenRingKeys', $np).GetValue($null)
$decrypt = $uxm.GetType('UXM.CryptographyUtility', $true).GetMethod('DecryptRsa', $np)

# ELDEN RING archive path hash: lower-case path from the root, h = h * 133 + char, 64-bit.
function PathHash([string] $path) {
    [uint64] $h = 0
    foreach ($c in $path.ToLowerInvariant().Replace('\', '/').ToCharArray()) {
        $h = [uint64](([Numerics.BigInteger]$h * 133 + [int]$c) % [Numerics.BigInteger]::Pow(2, 64))
    }
    return $h
}
$wanted = @{}
foreach ($f in $Files) { $wanted[(PathHash $f)] = $f }

$found = @{}
foreach ($arc in $Archives) {
    $bhdPath = Join-Path $GameDir "$arc.bhd"
    $bdtPath = Join-Path $GameDir "$arc.bdt"
    if (-not (Test-Path -LiteralPath $bhdPath)) { continue }
    if (-not $keys.ContainsKey($arc)) { Refuse "UXM has no key for $arc" }
    $header = $decrypt.Invoke($null, [object[]] @([string] $bhdPath, [string] $keys[$arc]))
    $index = $bhd5.GetMethod('Read').Invoke($null, [object[]] @($header, $gameEr))
    foreach ($bucket in $index.Buckets) {
        foreach ($entry in $bucket) {
            if ($wanted.ContainsKey($entry.FileNameHash) -and -not $found.ContainsKey($entry.FileNameHash)) {
                $found[$entry.FileNameHash] = @{ archive = $arc; bdt = $bdtPath; entry = $entry }
            }
        }
    }
}
$missing = @($wanted.Keys | Where-Object { -not $found.ContainsKey($_) } | ForEach-Object { $wanted[$_] })
if ($missing.Count) { Refuse "not found in any archive: $($missing -join ', ')" }
$total = 0
foreach ($v in $found.Values) { $total += [int64] $v.entry.PaddedFileSize }
if ($total -gt $MaxTotal) { Refuse "allowlisted files total $total bytes, over $MaxTotal" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$report = [ordered]@{}
foreach ($h in $found.Keys) {
    $v = $found[$h]
    $fs = [IO.File]::Open($v.bdt, 'Open', 'Read', 'Read')
    try { $bytes = $v.entry.ReadFile($fs) } finally { $fs.Dispose() }
    $rel = $wanted[$h].TrimStart('/')
    $dest = Join-Path $OutDir $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    [IO.File]::WriteAllBytes($dest, $bytes)
    $report[$wanted[$h]] = [ordered]@{ archive = $v.archive; bytes = $bytes.Length; sha256 = (Sha256 $dest) }
    Write-Host "extracted $($wanted[$h]) from $($v.archive) ($($bytes.Length) bytes)"
}
[IO.File]::WriteAllText((Join-Path $OutDir 'extract.json'), ($report | ConvertTo-Json -Depth 3))
[AppDomain]::CurrentDomain.remove_AssemblyResolve($resolver)
exit 0
