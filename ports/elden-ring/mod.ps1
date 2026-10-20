<#
.SYNOPSIS
  The Elden Ring route for a mod made from this template: doctor (read-only preflight), build
  (native client and control package) and assemble (an offline me3 runtime folder).

.DESCRIPTION
  Run with Windows PowerShell 5.1 from the mod's own copy (scripts\project.ps1 new). It wraps
  client\build.ps1 and control\build-package.ps1; it installs, downloads and launches nothing,
  and never writes to the game folder, me3, a save or the private config.json.

  doctor    -GameDir <...\ELDEN RING\Game> [-Tools <tools>] [-Me3 <me3.exe>] [-Root <folder>]
            Reads only. Compares eldenring.exe with game-build.json (file version, size, PE
            timestamp, SizeOfImage, SHA-256), checks the game inputs, the tools, dotnet, CMake
            and me3, and reports the build and runtime folders. Ends with one readiness line per
            part; none of them is an in-game result.
  build     -GameDir <...> [-Tools <tools>] [-Root <folder>] [-ControlConfig <file>]
            Refuses unless eldenring.exe is the build in game-build.json. Builds the native client
            into <Root>\elden-ring\client and the control package into a new
            <Root>\elden-ring\builds\<time>\control, copies the DLL beside it and records both,
            with their SHA-256, in that folder's build.json.
  assemble  [-Root <folder>] [-Build <builds\<time> folder>] [-GameDir <...>] [-Me3 <me3.exe>] [-Replace]
            Refuses while eldenring.exe runs and, with -GameDir, unless the installed eldenring.exe
            is still the build in game-build.json (without it, warns to run doctor before launching).
            Copies one verified build (default: the newest) into <Root>\runtime with an offline me3
            profile <id>.me3 that uses its own save <id>.sl2. The same build again changes
            nothing. A runtime assembled from another build is refused unless -Replace, which
            first moves the files assembly wrote (only if they are unchanged) into
            runtime\superseded\<time>; config.json and logs stay where they are. Prints the pair,
            profile check and launch commands; you launch the game yourself.

  -Root defaults to %LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id> (<id> from dwemer-mod.json);
  pass one on another disk for the large extraction and work folders. It must be a local folder
  outside this repository, every Git checkout and web root, the game, the tools, me3 and
  %APPDATA%\EldenRing, and nothing it writes or moves may go through a junction or link.
  -Tools defaults to %LOCALAPPDATA%\DwemerDynamics\Kagrenac\elden-ring\control\tools, -Me3 to
  <Tools>\me3\bin\me3.exe, -ControlConfig to control\kagrenac_control.example.json.
  Exit codes: 0 done (doctor: no FAIL line), 1 refused or failed.
#>
param(
    [Parameter(Position = 0, Mandatory)] [ValidateSet('doctor', 'build', 'assemble')] [string] $Command,
    [string] $GameDir = '',
    [string] $Tools = (Join-Path $env:LOCALAPPDATA 'DwemerDynamics\Kagrenac\elden-ring\control\tools'),
    [string] $Me3 = '',
    [string] $Root = '',
    [string] $ControlConfig = '',
    [string] $Build = '',
    [switch] $Replace
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'control\paths.ps1')

$failures = 0
function Say([string] $status, [string] $text) { Write-Host ("[{0}] {1}" -f $status, $text) }
function Fail([string] $text) { $script:failures++; Say 'FAIL' $text }
$utf8 = New-Object Text.UTF8Encoding($false)

if ($PSVersionTable.PSEdition -ne 'Desktop') { Refuse 'run with Windows PowerShell 5.1 (powershell.exe), as the package build needs' }

# The project: its own id and name, never the template's.
try { $manifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'dwemer-mod.json') -Raw | ConvertFrom-Json } catch { $manifest = $null }
$id = [string] $manifest.id
$name = [string] $manifest.name
if ($id -cnotmatch '^[a-z][a-z0-9-]{1,30}[a-z0-9]$' -or $id.Contains('--')) { Refuse 'dwemer-mod.json has no valid id' }
if ($id -ceq 'example-server') { Refuse 'this is the template; make your mod its own project first (scripts\project.ps1 new -Engine elden-ring) and run this there' }

# The one accepted game build (also read by the package build and the native client build).
$game = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'game-build.json') -Raw | ConvertFrom-Json
if ([string] $game.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [string] $game.file_version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
    [string] $game.pe_timestamp -cnotmatch '^0x[0-9a-f]{8}$' -or [string] $game.size_of_image -cnotmatch '^0x[0-9a-f]{8}$') {
    Refuse 'game-build.json is not a valid build record'
}

$rootGiven = [bool] $Root
$toolsGiven = $PSBoundParameters.ContainsKey('Tools')
$me3Given = [bool] $Me3
if (-not $Root) { $Root = Join-Path $env:LOCALAPPDATA "DwemerDynamics\Kagrenac\projects\$id" }
if (-not $Me3) { $Me3 = Join-Path $Tools 'me3\bin\me3.exe' }
if (-not $ControlConfig) { $ControlConfig = Join-Path $PSScriptRoot 'control\kagrenac_control.example.json' }
$toolFiles = [ordered]@{
    'DarkScript3 3.6.3' = 'darkscript\DarkScript3.exe'; 'EMEDF' = 'darkscript\er-common.emedf.json'; 'Lua 5.0.3 luac' = 'lua50-msvc\luac.exe'
    'UXM Selective Unpack 2.4.2.0' = 'uxm\UXM Selective Unpack 2.4.2.0\UXM Selective Unpack.exe'; 'Paramdex (WitchyBND 3.0.1)' = 'witchy\Assets\Paramdex.zip'
    'SoulsFormats' = 'witchy-lib\SoulsFormats.dll'; 'ZstdNet' = 'witchy-lib\ZstdNet.dll'; 'DrSwizzler' = 'witchy-lib\DrSwizzler.dll'; 'libzstd' = 'witchy-lib\libzstd.dll'
}
$profileName = "$id.me3"
$saveName = "$id.sl2"
$dllName = 'kagrenac_elden_ring.dll'

# Native output on the console, its exit code in $LASTEXITCODE; stderr is shown, never an error.
function Native([scriptblock] $run) {
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $run 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $saved }
}

# eldenring.exe compared with game-build.json. Returns @{ Ok; Lines }; reads the file only.
function Test-GameBuild([string] $dir) {
    $exe = Join-Path $dir 'eldenring.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return @{ Ok = $false; Lines = @("no eldenring.exe in $dir") } }
    $lines = @()
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
    $version = "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart).$($info.FilePrivatePart)"
    $length = (Get-Item -LiteralPath $exe).Length
    $s = [IO.File]::OpenRead($exe)
    try {
        $head = New-Object byte[] 4096
        [void] $s.Read($head, 0, $head.Length)
        $pe = [BitConverter]::ToInt32($head, 0x3C)
        $ok = $pe -gt 0 -and $pe -lt 4000 -and [BitConverter]::ToUInt32($head, $pe) -eq 0x4550
        $stamp = if ($ok) { '0x{0:x8}' -f [BitConverter]::ToUInt32($head, $pe + 8) } else { 'unreadable' }
        $image = if ($ok) { '0x{0:x8}' -f [BitConverter]::ToUInt32($head, $pe + 24 + 56) } else { 'unreadable' }
    } finally { $s.Dispose() }
    $sha = Sha256 $exe
    foreach ($c in @(@('file version', $version, [string] $game.file_version), @('bytes', [string] $length, [string] $game.bytes),
            @('PE timestamp', $stamp, [string] $game.pe_timestamp), @('SizeOfImage', $image, [string] $game.size_of_image), @('SHA-256', $sha, [string] $game.sha256))) {
        if ($c[1] -cne $c[2]) { $lines += "$($c[0]) $($c[1]), expected $($c[2])" }
    }
    return @{ Ok = ($lines.Count -eq 0); Lines = $lines; Version = $version; Sha = $sha }
}

# The -Root, -Tools and -Me3 arguments this run was given, for the next command it prints.
function Get-RouteArgs([string] $out) {
    $a = ''
    if ($rootGiven) { $a += ' -Root "' + $out + '"' }
    if ($toolsGiven) { $a += ' -Tools "' + (Full $Tools) + '"' }
    if ($me3Given) { $a += ' -Me3 "' + (Full $Me3) + '"' }
    return $a
}

# CMake as client\build.ps1 finds it: on PATH, else the one in Visual Studio's C++ tools.
function Find-CMake {
    $c = Get-Command cmake -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    $found = @(Native { & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' }) | Select-Object -First 1
    if ($found -and (Test-Path -LiteralPath $found -PathType Leaf)) { return $found }
    return $null
}

# A folder this route may write: local, without links, outside the repository, every Git checkout
# and web root, the game (its whole install folder), the tools, me3 and the save folder.
# Returns the resolved path.
function Resolve-OutputRoot {
    $out = Resolve-LocalPath $Root
    if ($out.Length -eq 3) { Refuse "-Root $Root is a drive root" }
    Assert-NoLink $out '-Root'
    $protected = @($RepoRoot, $Tools, (Join-Path $env:APPDATA 'EldenRing'))
    # me3's own installation: <me3>\bin\me3.exe, else the folder holding me3.exe; never a drive root.
    $me3Home = Split-Path (Full $Me3) -Parent
    if ((Split-Path $me3Home -Leaf) -eq 'bin') { $me3Home = Split-Path $me3Home -Parent }
    if ($me3Home.Length -gt 3) { $protected += $me3Home }
    if ($GameDir) { $protected += (Split-Path (Full $GameDir) -Parent) }
    foreach ($r in $protected) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        $p = Resolve-LocalPath $r
        if ((Under $out $p) -or (Under $p $out)) { Refuse "-Root $out overlaps $p" }
    }
    foreach ($part in $out.Substring(3).Split('\')) {
        if (@('htdocs', 'wwwroot', 'www', 'public_html', 'inetpub', 'custom-mods') -contains $part.ToLowerInvariant()) { Refuse "-Root is under '$part'; outputs stay outside every web root" }
    }
    for ($d = $out; $d.Length -gt 3; $d = Split-Path $d -Parent) {
        if (Test-Path -LiteralPath (Join-Path $d '.git')) { Refuse "-Root is inside the Git checkout $d; outputs stay outside every source folder" }
    }
    return $out
}

# <Root>\elden-ring belongs to this project: new, empty, or marked with this id.
function Assert-PortFolder([string] $dir, [switch] $Create) {
    $marker = Join-Path $dir 'project.json'
    Assert-NoLink $marker 'output'
    if (Test-Path -LiteralPath $marker) {
        try { $m = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json } catch { $m = $null }
        if ([string] $m.id -cne $id) { Refuse "$dir belongs to another project ($marker); choose another -Root" }
        return
    }
    if ((Test-Path -LiteralPath $dir) -and (Get-ChildItem -LiteralPath $dir -Force | Select-Object -First 1)) {
        Refuse "$dir already holds files that this route did not write; choose another -Root"
    }
    if ($Create) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        New-File $marker ((([ordered]@{ id = $id; name = $name; note = 'Build folders of this mod, written by ports\elden-ring\mod.ps1' }) | ConvertTo-Json) + "`n")
    }
}

# A new file (never over an existing one) with this text.
function New-File([string] $path, [string] $text) {
    $bytes = $utf8.GetBytes($text)
    $s = New-Object IO.FileStream($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
}

# Whether a file's DACL is protected and allows only you, SYSTEM and Administrators (as pair makes it).
function Test-Private([string] $path) {
    $acl = (New-Object IO.FileInfo $path).GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
    $sids = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544') | Select-Object -Unique
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    return $acl.AreAccessRulesProtected -and $rules.Count -eq $sids.Count -and
        @($rules | Where-Object { -not $_.IsInherited -and $_.AccessControlType -eq 'Allow' -and $sids -contains $_.IdentityReference.Value }).Count -eq $sids.Count
}

# The builds of this project, newest first, each a folder <yyyyMMdd-HHmmss> with build.json.
function Get-Builds([string] $port) {
    $dir = Join-Path $port 'builds'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -Directory | Where-Object { $_.Name -match '^\d{8}-\d{6}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'build.json')) } |
        Sort-Object Name -Descending)
}

# The relative paths a record lists, each with a SHA-256, no way out of its folder and no Windows
# device name; refuses an empty or malformed list. $exact are the names it must list and
# $prefix/* the rest; any other name is refused.
function Get-RecordedFiles($files, [string] $record, [string[]] $exact, [string] $prefix) {
    $props = @(if ($files -is [Management.Automation.PSCustomObject]) { $files.PSObject.Properties })
    if (-not $props.Count) { Refuse "$record lists no files" }
    foreach ($p in $props) {
        if ($p.Name -cnotmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$' -or $p.Name -match '(^|/)\.\.?(/|$)' -or [string] $p.Value -cnotmatch '^[0-9a-f]{64}$' -or
            $p.Name -match '(^|/)(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.[^/]*)?(/|$)' -or $p.Name -match '[. ]$|[. ]/') {
            Refuse "$record has an invalid entry"
        }
        if ($exact -cnotcontains $p.Name -and -not $p.Name.StartsWith("$prefix/", [StringComparison]::Ordinal)) { Refuse "$record lists $($p.Name), which is not one of its files" }
    }
    $names = @($props | ForEach-Object { $_.Name })
    foreach ($e in $exact) { if ($names -cnotcontains $e) { Refuse "$record does not list $e" } }
    if (-not @($names | Where-Object { $_.StartsWith("$prefix/", [StringComparison]::Ordinal) }).Count) { Refuse "$record lists no $prefix files" }
    return $names
}

# A build's record with every recorded file checked by SHA-256 (reached without links); refuses on
# any difference.
function Read-Build([string] $dir) {
    Assert-NoLink (Join-Path $dir 'build.json') 'build'
    try { $b = Get-Content -LiteralPath (Join-Path $dir 'build.json') -Raw | ConvertFrom-Json } catch { Refuse "$dir\build.json is not readable JSON" }
    if ($b.schema_version -ne 1 -or [string] $b.id -cne $id) { Refuse "$dir\build.json is not a build of $id" }
    $null = Get-RecordedFiles $b.files "$dir\build.json" @("natives/$dllName", 'control/package.json') 'control/package'
    foreach ($p in $b.files.PSObject.Properties) {
        $f = Join-Path $dir $p.Name.Replace('/', '\')
        Assert-NoLink $f 'build'
        if (-not (Test-Path -LiteralPath $f -PathType Leaf) -or (Sha256 $f) -cne [string] $p.Value) { Refuse "$f is missing or changed since the build; build again" }
    }
    return $b
}

function Invoke-Doctor {
    Say 'INFO' "Project $name ($id); repository $RepoRoot"
    $readyGame = 'not checked (pass -GameDir)'
    if ($GameDir) {
        $g = Test-GameBuild $GameDir
        if ($g.Ok) {
            Say 'OK' "eldenring.exe is the accepted build: file $($game.file_version), Steam build $($game.steam_build), SHA-256 $($game.sha256) (an in-game candidate, not qualified)."
            $readyGame = "accepted build $($game.file_version)"
        } else {
            Fail "eldenring.exe is not the build in game-build.json ($($g.Lines -join '; ')). The package build refuses it and the client's game link stays off. Do not edit game-build.json to match: a new game build needs its own read of the file and a rebuild of both parts."
            $readyGame = 'unknown build: blocked'
        }
        foreach ($f in 'regulation.bin', 'oo2core_6_win64.dll', 'Data0.bhd', 'Data0.bdt') {
            if (-not (Test-Path -LiteralPath (Join-Path $GameDir $f) -PathType Leaf)) { Fail "missing game file $f in $GameDir" }
        }
    }
    $failuresBefore = $script:failures
    $missing = @($toolFiles.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Tools $toolFiles[$_]) -PathType Leaf) })
    if ($missing.Count) { Fail "tools root $Tools lacks: $($missing -join ', ') (control\README.md, Tools)" } else { Say 'OK' "Tools present in $Tools." }
    $sdks = @()
    if (Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue) { $sdks = @(Native { & dotnet --list-sdks }) }
    if (-not $sdks) { Fail 'no .NET SDK found (dotnet --list-sdks); the package build compiles erpack with it' }
    elseif (-not ($sdks -match '^(\d+)\.' | Where-Object { [int] ($_ -replace '\..*$', '') -ge 10 })) { Say 'WARN' ".NET SDKs: $($sdks -join '; '). The package build was verified with the .NET 10 SDK." }
    else { Say 'OK' ".NET SDKs: $($sdks -join '; ')" }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs = @(if (Test-Path -LiteralPath $vswhere) { Native { & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath } })
    if ($vs.Count -and $vs[0]) { Say 'OK' "Visual Studio with C++ tools: $($vs[0])" } else { Fail 'Visual Studio 2022 with Desktop development with C++ (and CMake tools) not found; the native client needs it' }
    $cmake = Find-CMake
    if ($cmake) { Say 'OK' "CMake: $cmake (as client\build.ps1 finds it)" }
    else { Fail 'CMake not found on PATH or in Visual Studio; add "C++ CMake tools for Windows" to Desktop development with C++ in the Visual Studio Installer (client\build.ps1 needs it)' }
    $readyTools = if ($script:failures -gt $failuresBefore) { 'incomplete (see FAIL lines)' } else { 'present' }
    $readyMe3 = 'not found'
    if (Test-Path -LiteralPath $Me3 -PathType Leaf) {
        $v = (@(Native { & $Me3 --version }) -join ' ')
        $readyMe3 = "$v at $Me3"
        if ($v -notmatch '\b0\.13\.0\b') { Say 'WARN' "me3 reports '$v'; the profile follows the me3 v0.13.0 schema." } else { Say 'OK' "me3: $readyMe3" }
    } else { Say 'WARN' "me3 not found at $Me3 (pass -Me3); it is only needed for the launch you run yourself." }

    $out = Resolve-OutputRoot
    $port = Join-Path $out 'elden-ring'
    Assert-PortFolder $port
    Say 'OK' "Output root $out is outside the repository, Git checkouts, web roots$(if ($GameDir) { ', the game' }), the tools, me3 and the save folder."
    $builds = Get-Builds $port
    $readyBuild = 'none yet (run build)'
    if ($builds.Count) {
        $b = Get-Content -LiteralPath (Join-Path $builds[0].FullName 'build.json') -Raw | ConvertFrom-Json
        $readyBuild = "$($builds[0].Name) for $($b.game.file_version), attack $(if ($b.attack_enabled) { 'built (guarded, unavailable)' } else { 'left out' })"
        if ([string] $b.game.sha256 -cne [string] $game.sha256) { Say 'WARN' "the newest build $($builds[0].Name) is for another game build; build again"; $readyBuild += ' (stale)' }
    }
    $rt = Join-Path $out 'runtime'
    $readyRuntime = 'not assembled (run assemble)'
    $readyPair = 'no config.json yet (run pair after assemble)'
    if (Test-Path -LiteralPath (Join-Path $rt 'runtime.json')) {
        $r = Get-Content -LiteralPath (Join-Path $rt 'runtime.json') -Raw | ConvertFrom-Json
        $readyRuntime = "assembled from build $($r.build) at $rt"
    }
    $cfg = Join-Path $rt 'config.json'
    if (Test-Path -LiteralPath $cfg -PathType Leaf) {
        $readyPair = if (Test-Private $cfg) { 'config.json present and private (contents not read)' } else { 'config.json present but NOT private to you, SYSTEM and Administrators' }
    }
    $saves = @(Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'EldenRing') -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $saveName) -PathType Leaf })
    Write-Host ''
    Write-Host 'Readiness (doctor reads only; no line is an in-game result):'
    Write-Host "  - Game build: $readyGame"
    Write-Host "  - Tools and compilers: $readyTools"
    Write-Host "  - me3: $readyMe3"
    Write-Host "  - Build: $readyBuild"
    Write-Host "  - Runtime: $readyRuntime"
    Write-Host "  - Pairing: $readyPair"
    Write-Host "  - Isolated save ${saveName}: $(if ($saves.Count) { 'exists (the game was launched with this profile before)' } else { 'not created yet; me3 creates it from an existing save on first launch, so back up first' })"
    Write-Host '  - Server, LLM and voice: scripts\project.ps1 doctor -WslDistro <name> and the dashboard tests'
    Write-Host '  - In game: not verified; each action needs its own in-game check'
}

function Invoke-Build {
    if (-not $GameDir) { Refuse 'build needs -GameDir <...\ELDEN RING\Game>' }
    $g = Test-GameBuild $GameDir
    if (-not $g.Ok) { Refuse "eldenring.exe is not the build in game-build.json ($($g.Lines -join '; ')); run doctor" }
    $missing = @($toolFiles.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Tools $toolFiles[$_]) -PathType Leaf) })
    if ($missing.Count) { Refuse "tools root $Tools lacks: $($missing -join ', ')" }
    if (-not (Test-Path -LiteralPath $ControlConfig -PathType Leaf)) { Refuse "no control config at $ControlConfig" }
    if (-not (Find-CMake)) { Refuse 'CMake not found on PATH or in Visual Studio; run doctor' }
    $config = Resolve-LocalPath $ControlConfig
    $out = Resolve-OutputRoot
    $port = Join-Path $out 'elden-ring'
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $dir = Join-Path $port "builds\$stamp"
    foreach ($w in @("natives\$dllName", 'build.json', 'control')) { Assert-NoLink (Join-Path $dir $w) 'output' }
    Assert-NoLink (Join-Path $port "client\Release\$dllName") 'output'
    Assert-PortFolder $port -Create
    if (Test-Path -LiteralPath $dir) { Refuse "$dir already exists; run build again in a second" }
    New-Item -ItemType Directory -Force -Path (Join-Path $port 'builds') | Out-Null
    [void] [IO.Directory]::CreateDirectory($dir)
    $ps = Join-Path $PSHOME 'powershell.exe'

    Say 'INFO' "Native client: client\build.ps1 into $port\client"
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'client\build.ps1') -BuildDir (Join-Path $port 'client') | Out-Host
    if ($LASTEXITCODE -ne 0) { Refuse "the native client build failed (exit $LASTEXITCODE); $dir holds no build" }
    $dll = Join-Path $port "client\Release\$dllName"
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { Refuse "the native client build left no $dll" }

    Say 'INFO' "Control package: control\build-package.ps1 into $dir\control (several minutes)"
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'control\build-package.ps1') -Config $config -GameDir $GameDir -Tools $Tools -OutDir (Join-Path $dir 'control') | Out-Host
    if ($LASTEXITCODE -ne 0) { Refuse "the control package build failed (exit $LASTEXITCODE); $dir is incomplete and is never assembled" }
    $packageJson = Join-Path $dir 'control\package.json'
    try { $pkg = Get-Content -LiteralPath $packageJson -Raw | ConvertFrom-Json } catch { Refuse "$packageJson is not readable" }
    if ([string] $pkg.game_exe_sha256 -cne [string] $game.sha256 -or $pkg.attack_enabled -isnot [bool]) { Refuse "$packageJson does not record the accepted game build and attack_enabled" }

    $natives = Join-Path $dir 'natives'
    Assert-NoLink $dll 'client build'
    Assert-NoLink (Join-Path $natives $dllName) 'output'
    [void] [IO.Directory]::CreateDirectory($natives)
    [IO.File]::Copy($dll, (Join-Path $natives $dllName), $false)
    $files = [ordered]@{ "natives/$dllName" = (Sha256 (Join-Path $natives $dllName)); 'control/package.json' = (Sha256 $packageJson) }
    foreach ($p in $pkg.outputs.PSObject.Properties) {
        $f = Join-Path $dir ('control\package\' + $p.Name.Replace('/', '\'))
        Assert-NoLink $f 'output'
        if ((Sha256 $f) -cne [string] $p.Value) { Refuse "$f does not match package.json" }
        $files["control/package/$($p.Name)"] = [string] $p.Value
    }
    $commit = @(Native { & git -C $RepoRoot rev-parse --verify -q 'HEAD^{commit}' })
    $commit = if ($LASTEXITCODE -eq 0 -and $commit.Count -eq 1) { $commit[0] } else { 'none (nothing committed yet)' }
    $dirty = @(Native { & git -C $RepoRoot status --porcelain --untracked-files=all }).Count
    Assert-NoLink (Join-Path $dir 'build.json') 'output'
    New-File (Join-Path $dir 'build.json') ((([ordered]@{
        schema_version = 1; id = $id; name = $name; built_at = (Get-Date).ToString('s')
        status = 'built from your own game files; not loaded by me3 or the game; nothing installed'
        source = [ordered]@{ commit = $commit; uncommitted_paths = $dirty }
        game = [ordered]@{ file_version = $g.Version; sha256 = $g.Sha }
        control_config = [ordered]@{ path = $config; sha256 = (Sha256 $config) }
        attack_enabled = $pkg.attack_enabled
        files = $files
    }) | ConvertTo-Json -Depth 4) + "`n")
    Say 'OK' "Built $stamp in $dir for $($g.Version): $dllName and the control package (attack $(if ($pkg.attack_enabled) { 'built, guarded, still unavailable' } else { 'left out' })); not loaded by me3 or the game."
    if ($dirty) { Say 'WARN' "$dirty uncommitted path(s) in the source at build time; build.json records it." }
    Say 'INFO' ('Next: powershell -ExecutionPolicy Bypass -File ports\elden-ring\mod.ps1 assemble' + (Get-RouteArgs $out) + ' -GameDir "' + (Full $GameDir) + '"')
}

# The text of the offline me3 profile (me3 v0.13.0 schema, schemas/mod-profile.json).
function Get-Profile([string] $stamp) {
    return @(
        "# $id`: me3 v0.13.0 profile written by ports\elden-ring\mod.ps1 assemble from build $stamp.",
        '# Offline only: no start_online. Anti-tamper is left alone: no disable_arxan.',
        "# Isolated save: me3 creates $saveName as a copy of an existing save on first launch, so back",
        '# up the save folder first. optional = false: a missing or failing DLL stops the launch.',
        'profileVersion = "v1"', "savefile = `"$saveName`"", '', '[[supports]]', 'game = "eldenring"', '',
        '[[package]]', "id = `"$id-control`"", 'path = "package"', '',
        '[[natives]]', "path = 'natives/$dllName'", 'optional = false', 'initializer = { function = "kagrenac_init" }', ''
    ) -join "`n"
}

function Invoke-Assemble {
    # A running game (or me3 holding it) may have the runtime files open; nothing is touched then.
    $running = @(Get-Process -Name eldenring -ErrorAction SilentlyContinue)
    if ($running.Count) { Refuse "Elden Ring is running (process $($running[0].Id)); close the game first. Nothing was written" }
    $gameChecked = $false
    if ($GameDir) {
        $g = Test-GameBuild $GameDir
        if (-not $g.Ok) { Refuse "the installed eldenring.exe is no longer the build in game-build.json ($($g.Lines -join '; ')); nothing was written. A build's package is made from the game files it read, so do not launch it on this game: run doctor" }
        $gameChecked = $true
    }
    $out = Resolve-OutputRoot
    $port = Join-Path $out 'elden-ring'
    Assert-PortFolder $port
    if ($Build) {
        $dir = Resolve-LocalPath $Build
        if (-not (Under $dir (Join-Path $port 'builds')) -or (Split-Path $dir -Parent) -ne (Join-Path $port 'builds')) { Refuse "-Build must be one folder in $port\builds" }
    } else {
        $builds = Get-Builds $port
        if (-not $builds.Count) { Refuse "no build in $port\builds; run build first" }
        $dir = $builds[0].FullName
    }
    $stamp = Split-Path $dir -Leaf
    $b = Read-Build $dir
    if ([string] $b.game.sha256 -cne [string] $game.sha256) { Refuse "build $stamp is for game file $($b.game.file_version), not the accepted $($game.file_version); build again" }

    # What assembly writes: runtime path -> source path in the build.
    $copies = [ordered]@{ "natives/$dllName" = "natives/$dllName" }
    foreach ($p in $b.files.PSObject.Properties) {
        if ($p.Name -like 'control/package/*') { $copies[$p.Name.Substring('control/'.Length)] = $p.Name }
    }
    $profileText = Get-Profile $stamp
    $rt = Join-Path $out 'runtime'
    $record = Join-Path $rt 'runtime.json'
    # Every path assembly may read, move or write is reached without a junction or link: each
    # file's own components are checked, so no tree is scanned.
    Assert-NoLink $record 'runtime'
    foreach ($rel in @($copies.Keys) + $profileName) { Assert-NoLink (Join-Path $rt $rel.Replace('/', '\')) 'runtime' }
    if (Test-Path -LiteralPath $record) {
        try { $old = Get-Content -LiteralPath $record -Raw | ConvertFrom-Json } catch { Refuse "$record is not readable; move the runtime away yourself" }
        if ($old.schema_version -ne 1 -or [string] $old.id -cne $id) { Refuse "$rt is not a runtime of $id; choose another -Root" }
        $oldNames = Get-RecordedFiles $old.files $record @("natives/$dllName", $profileName) 'package'
        $changed = @(foreach ($p in $old.files.PSObject.Properties) {
            $f = Join-Path $rt $p.Name.Replace('/', '\')
            Assert-NoLink $f 'runtime'
            if (-not (Test-Path -LiteralPath $f -PathType Leaf) -or (Sha256 $f) -cne [string] $p.Value) { $p.Name }
        })
        if ($changed.Count) { Refuse "$rt was changed since it was assembled ($($changed -join ', ')); nothing was written. Move the runtime away yourself, or restore those files" }
        if ([string] $old.build -ceq $stamp) {
            Say 'OK' "Already assembled from build $stamp in $rt; every assembled file matches, nothing was written."
        } elseif (-not $Replace) {
            Refuse "$rt was assembled from build $($old.build), not $stamp. Nothing was written; pass -Replace to move its assembled files into runtime\superseded and assemble $stamp (config.json is kept)"
        } else {
            $aside = Join-Path $rt ('superseded\' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
            if (Test-Path -LiteralPath $aside) { Refuse "$aside already exists; run assemble again in a second" }
            $moves = @($oldNames) + 'runtime.json'
            foreach ($rel in $moves) { Assert-NoLink (Join-Path $aside $rel.Replace('/', '\')) 'runtime' }
            foreach ($rel in $moves) {
                $from = Join-Path $rt $rel.Replace('/', '\')
                $to = Join-Path $aside $rel.Replace('/', '\')
                Assert-NoLink $from 'runtime'
                Assert-NoLink $to 'runtime'
                [void] [IO.Directory]::CreateDirectory((Split-Path $to -Parent))
                [IO.File]::Move($from, $to)
            }
            Say 'INFO' "Moved the files assembled from build $($old.build) into $aside (nothing deleted)."
        }
    } elseif (Test-Path -LiteralPath $rt) {
        $other = @(Get-ChildItem -LiteralPath $rt -Force | Where-Object { -not ($_.Name -ceq 'config.json' -and -not $_.PSIsContainer) })
        if ($other.Count) { Refuse "$rt holds files this route did not assemble ($($other[0].Name)); nothing was written. Choose another -Root" }
    }
    if (-not (Test-Path -LiteralPath $record)) {
        $written = [ordered]@{}
        foreach ($rel in $copies.Keys) {
            $to = Join-Path $rt $rel.Replace('/', '\')
            Assert-NoLink $to 'runtime'
            [void] [IO.Directory]::CreateDirectory((Split-Path $to -Parent))
            [IO.File]::Copy((Join-Path $dir $copies[$rel].Replace('/', '\')), $to, $false)
            $written[$rel] = Sha256 $to
            if ($written[$rel] -cne [string] $b.files.($copies[$rel])) { Refuse "$to did not copy intact; move the runtime away and assemble again" }
        }
        Assert-NoLink (Join-Path $rt $profileName) 'runtime'
        New-File (Join-Path $rt $profileName) $profileText
        $written[$profileName] = Sha256 (Join-Path $rt $profileName)
        Assert-NoLink $record 'runtime'
        New-File $record ((([ordered]@{
            schema_version = 1; id = $id; build = $stamp; build_dir = $dir; assembled_at = (Get-Date).ToString('s')
            note = 'Files written by mod.ps1 assemble. config.json (pair) and the DLL log are not part of it.'
            files = $written
        }) | ConvertTo-Json -Depth 3) + "`n")
        Say 'OK' "Assembled build $stamp into $rt`: natives\$dllName, package\ ($($copies.Count - 1) files) and $profileName (offline, save $saveName). Nothing was launched."
    }

    $cfg = Join-Path $rt 'config.json'
    $exe = if ($GameDir) { Join-Path (Full $GameDir) 'eldenring.exe' } else { '<...\ELDEN RING\Game>\eldenring.exe' }
    Write-Host ''
    if (Test-Path -LiteralPath $cfg -PathType Leaf) {
        Say 'OK' "config.json is present and was not touched$(if (-not (Test-Private $cfg)) { ' (WARNING: not private to you, SYSTEM and Administrators)' })."
    } else {
        Say 'INFO' 'Pair next (creates the private config.json; follow and hold only, attack stays out):'
        Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\project.ps1 pair -WslDistro <name> -WslServerPath /var/www/html/custom-mods/$id -OutFile `"$cfg`" -AllowedActions follow_player,hold_position -NpcId <companion id> -NpcName `"<companion name>`" [-VoiceEnabled]"
    }
    Say 'INFO' 'Before the first launch, back up the whole save folder %APPDATA%\EldenRing yourself (copy it somewhere outside it).'
    if ($gameChecked) { Say 'OK' "The installed eldenring.exe is still the build $stamp was made for ($($game.file_version))." }
    else {
        Say 'WARN' 'The installed game was NOT checked (no -GameDir). If Steam updated it since the build, this package does not match it. Right before launching, run:'
        Write-Host ('  powershell -ExecutionPolicy Bypass -File ports\elden-ring\mod.ps1 doctor' + (Get-RouteArgs $out) + ' -GameDir "<...\ELDEN RING\Game>"')
    }
    Say 'INFO' 'Check the profile, then launch it yourself, offline, with the game closed first:'
    Write-Host "  & `"$(Full $Me3)`" profile show --file `"$rt\$profileName`""
    Write-Host "  & `"$(Full $Me3)`" launch --game eldenring --exe `"$exe`" -p `"$rt\$profileName`" --online false --savefile $saveName"
}

switch ($Command) {
    'doctor' { Invoke-Doctor }
    'build' { Invoke-Build }
    'assemble' { Invoke-Assemble }
}
if ($failures) { Write-Host ''; Write-Host "$failures problem(s) found."; exit 1 }
exit 0
