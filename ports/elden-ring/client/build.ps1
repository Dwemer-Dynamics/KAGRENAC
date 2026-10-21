# Builds the Elden Ring native client DLLs (x64 Release) outside the repository. Build only: it
# copies nothing into a game, runtime or me3 folder (see README, Runtime layout).
# Usage: powershell -ExecutionPolicy Bypass -File ports\elden-ring\client\build.ps1 -ControlConfig <file> [-BuildDir <folder>]
# -ControlConfig is the control config the package is built from (the example:
# ports\elden-ring\control\kagrenac_control.example.json); CMake compiles its map tile, hostile,
# bridge window and attack_enabled into the DLL and records its SHA-256 in the build folder.
param(
    [Parameter(Mandatory)] [string]$ControlConfig,
    [string]$BuildDir = (Join-Path $env:LOCALAPPDATA "DwemerDynamics\Kagrenac\elden-ring\client")
)
$ErrorActionPreference = "Stop"

$source = $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $source '..\..\..')).TrimEnd('\')

# A relative path resolves against the PowerShell location. Only a local drive folder below the
# root, outside the repository, with no junction or link on the way.
if (-not $BuildDir) { throw "BuildDir is empty" }
$full = [IO.Path]::GetFullPath([IO.Path]::Combine((Get-Location).ProviderPath, $BuildDir)).TrimEnd('\')
if ($full -notmatch '^[A-Za-z]:\\.') { throw "BuildDir $BuildDir must be a folder on a local drive, not a drive root or UNC path" }
$inside = { param($a, $b) $a -eq $b -or $a.StartsWith("$b\", [StringComparison]::OrdinalIgnoreCase) }
if ((& $inside $full $repoRoot) -or (& $inside $repoRoot $full)) { throw "BuildDir $BuildDir overlaps the repository $repoRoot" }
for ($p = $full; $p.Length -gt 3; $p = Split-Path -Parent $p) {
    $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "BuildDir $BuildDir goes through a junction or link at $p" }
}
$BuildDir = $full

# The control config: a file on a local drive, reached without a junction or link.
$config = [IO.Path]::GetFullPath([IO.Path]::Combine((Get-Location).ProviderPath, $ControlConfig))
if ($config -notmatch '^[A-Za-z]:\\.' -or -not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "ControlConfig $ControlConfig must be a file on a local drive" }
for ($p = $config; $p.Length -gt 3; $p = Split-Path -Parent $p) {
    $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "ControlConfig $ControlConfig goes through a junction or link at $p" }
}

$cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
$cmake = if ($cmakeCommand) { $cmakeCommand.Source } else { $null }
if (-not $cmake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $cmake = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' | Select-Object -First 1
    }
}
if (-not $cmake -or -not (Test-Path -LiteralPath $cmake)) {
    throw "CMake was not found. Install Visual Studio 2022 Desktop development with C++, including CMake tools."
}

& $cmake -S $source -B $BuildDir -G "Visual Studio 17 2022" -A x64 "-DKAGRENAC_ER_CONTROL_CONFIG=$($config.Replace('\', '/'))"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
& $cmake --build $BuildDir --config Release
if ($LASTEXITCODE -ne 0) { throw "Build failed" }
Write-Host "Built $(Join-Path $BuildDir 'Release\kagrenac_elden_ring.dll') from control config $config (compiled values: $(Join-Path $BuildDir 'kagrenac_er_control.json'))"
Write-Host "Test variant $(Join-Path $BuildDir 'Release\kagrenac_elden_ring_testhost.dll'): never put it in a profile."
