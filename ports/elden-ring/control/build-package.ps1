<#
.SYNOPSIS
  Builds the KAGRENAC Elden Ring companion control package from the user's own game files.

.DESCRIPTION
  Run with Windows PowerShell 5.1. Steps, each checked before the next:
    1. config: every value a finite number in range, no duplicates, no player id
    2. eldenring.exe SHA-256 equals the recorded build (a file check; the engine itself is
       not qualified by this)
    3. extract-inputs.ps1: common.emevd, aicommon.luabnd and the two tiles' MSBs and event
       files, read-only;
       then one `dotnet build` of erpack into the output folder (no build servers)
    4. erpack inspect on the user's MSBs and a copy of regulation.bin: the companion and the
       hostile exist with the configured think row, team and no talk script; the action
       button row exists; the new think row does not
    5. DarkScript3 /cmd: decompile common (the control event id must be free), add the one
       control event and InitializeEvent(0, event_control, 0) to event 0, compile into the
       work folder. erpack merge-events then writes package/event/common.emevd.dcx from the
       user's original binary common, keeping its events, instructions, parameters and
       strings, appending only that event and that one start, and checking everything else
       is unchanged; the event id must also be free in both tiles' original event files and
       every SetCharacterTeamType must target the companion. DarkScript3 decompiles the
       merged file again as a last check.
    6. luac 5.0.3: compile the logic; erpack pack: add it to aicommon.luabnd and clone the
       think row into the regulation.bin copy, then re-read both
  Every tool but the console `dotnet build` runs hidden; each has its own timeout and checked exit code; only the process the
  script started is stopped on a timeout. DOTNET_ROLL_FORWARD=Major, DOTNET_ReadyToRun=0
  and the game folder on PATH are set for erpack and DarkScript3 only; this session's
  environment is not changed.
  Writes only into a new, empty -OutDir outside the repository and the game, reached
  without junctions or 8.3 aliases. Never writes to the game folder, saves or me3.
  Exit codes: 0 package built (not tested in game), 1 refused or a step failed.
#>
param(
    [Parameter(Mandatory)] [string] $Config,
    [Parameter(Mandatory)] [string] $GameDir,
    [Parameter(Mandatory)] [string] $Tools,
    [Parameter(Mandatory)] [string] $OutDir
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'paths.ps1')

# The build the engine notes were written against (docs/engine-packs/elden-ring.md).
$RecordedExeSha256 = '1a3547101327f65d0c76da2f9190ac0aa66871ea42bae2aecc61e11a8b597891'
$PlayerEntity = 10000

$DarkScript = Join-Path $Tools 'darkscript\DarkScript3.exe'
$Emedf = Join-Path $Tools 'darkscript\er-common.emedf.json'
$Luac = Join-Path $Tools 'lua50-msvc\luac.exe'
$Uxm = Join-Path $Tools 'uxm\UXM Selective Unpack 2.4.2.0\UXM Selective Unpack.exe'
$Paramdex = Join-Path $Tools 'witchy\Assets\Paramdex.zip'
$SoulsLib = Join-Path $Tools 'witchy-lib'
$Oodle = Join-Path $GameDir 'oo2core_6_win64.dll'
# The witchy-lib files are the ones erpack.csproj references.
$SoulsFiles = 'SoulsFormats.dll', 'ZstdNet.dll', 'DrSwizzler.dll', 'libzstd.dll' | ForEach-Object { Join-Path $SoulsLib $_ }
foreach ($f in @($Config, $DarkScript, $Emedf, $Luac, $Uxm, $Paramdex) + $SoulsFiles + @(
        (Join-Path $GameDir 'eldenring.exe'), (Join-Path $GameDir 'regulation.bin'), $Oodle)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Refuse "missing input $f" }
}

# 1. Config.
$cfg = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
function Num([string] $name, [double] $min, [double] $max) {
    $v = $cfg.$name
    if ($null -eq $v -or $v -is [bool] -or -not ($v -is [ValueType])) { Refuse "$name must be a number" }
    $d = [double] $v
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d) -or $d -lt $min -or $d -gt $max) { Refuse "$name=$v outside $min..$max" }
    return $d
}
function Int([string] $name, [double] $min, [double] $max) {
    $d = Num $name $min $max
    if ($d -ne [Math]::Floor($d)) { Refuse "$name must be an integer" }
    return [int64] $d
}
function Tile([string] $name) {
    $v = [string] $cfg.$name
    if ($v -notin 'm60_42_36_00', 'm60_42_37_00', 'm60_43_36_00') { Refuse "$name must be one of the extracted MSBs" }
    return $v
}
$companion = Int 'companion_entity' 1000000 4294967295
$hostile = Int 'hostile_entity' 1000000 4294967295
if ($companion -eq $hostile) { Refuse 'companion_entity and hostile_entity are the same' }
$companionMsb = Tile 'companion_msb'
$hostileMsb = Tile 'hostile_msb'
$originalAi = Int 'original_ai_id' 1 2147483647
$controlAi = Int 'control_ai_id' 1 2147483647
if ($originalAi -eq $controlAi) { Refuse 'control_ai_id must differ from original_ai_id' }
$originalTeam = Int 'original_team_type' 1 255
$controlTeam = Int 'control_team_type' 1 255
$hostileTeam = Int 'hostile_team_type' 1 255
if ($hostileTeam -in $originalTeam, $controlTeam) { Refuse 'hostile_team_type must differ from original_team_type and control_team_type' }
$logicId = Int 'logic_id' 1 2147483647
# One flagless event; where it waits is the control state.
$eventControl = Int 'event_control' 1000000 4294967295
$commands = [ordered]@{}
foreach ($c in 'command_hold', 'command_follow', 'command_attack') { $commands[$c] = Int $c 1 2147483647 }
if (@($commands.Values | Sort-Object -Unique).Count -ne 3) { Refuse 'command ids must be distinct' }
$button = Int 'action_button_param' 1 2147483647
$followMin = Num 'follow_min' 0.5 30
$followMax = Num 'follow_max' 1 50
if ($followMin -ge $followMax) { Refuse 'follow_min must be below follow_max' }
$reach = Num 'attack_reach' 0.5 20
$lease = Int 'attack_lease_seconds' 5 600
# Attack animations proven per battle goal: an id is accepted only where the NPC's own
# vanilla battle goal requests it (431000_battle.luabnd, ComboAttackTunableSpin 3000).
$ProvenAttacks = @{ 43111100 = @(3000) }
$attackAnim = Int 'attack_animation' 0 2147483647
if (-not $ProvenAttacks.ContainsKey([int] $originalAi)) { Refuse "no attack animation is proven for think row $originalAi" }
if ($attackAnim -notin $ProvenAttacks[[int] $originalAi]) { Refuse "attack_animation $attackAnim is not proven for think row $originalAi" }

$inv = [Globalization.CultureInfo]::InvariantCulture
$logicName = "kagrenac$logicId"
$values = [ordered]@{
    COMPANION = $companion; HOSTILE = $hostile; ORIGINAL_AI = $originalAi; CONTROL_AI = $controlAi
    ORIGINAL_TEAM = $originalTeam; CONTROL_TEAM = $controlTeam; HOSTILE_TEAM = $hostileTeam
    LOGIC_ID = $logicId; LOGIC_NAME = $logicName; E_CONTROL = $eventControl
    BUTTON_PARAM = $button; CMD_HOLD = $commands.command_hold; CMD_FOLLOW = $commands.command_follow
    CMD_ATTACK = $commands.command_attack; ATTACK_LEASE = $lease; ATTACK_ANIM = $attackAnim
    FOLLOW_MIN = $followMin.ToString('0.0##', $inv); FOLLOW_MAX = $followMax.ToString('0.0##', $inv)
    ATTACK_REACH = $reach.ToString('0.0##', $inv)
}
if ($values.Values -contains $PlayerEntity) { Refuse 'no configured id may be the player entity 10000' }

# 2. Game build (file identity only).
$exeSha = Sha256 (Join-Path $GameDir 'eldenring.exe')
if ($exeSha -ne $RecordedExeSha256) { Refuse "eldenring.exe SHA-256 $exeSha is not the recorded build" }

# Output folders, checked before anything is created; from here on the resolved long path.
Assert-OutDir $OutDir @($RepoRoot, (Split-Path (Full $GameDir) -Parent))
$OutDir = Resolve-LocalPath $OutDir
$work = Join-Path $OutDir 'work'
$pkg = Join-Path $OutDir 'package'
New-Item -ItemType Directory -Force -Path $work, $pkg | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$steps = [ordered]@{}

# One argument quoted for the Windows command line (backslashes before a quote doubled).
function Quote([string] $a) {
    if ($a -and $a -notmatch '[\s"]') { return $a }
    return '"' + [regex]::Replace([regex]::Replace($a, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

# Runs one tool hidden in the work folder and waits for that process only, up to $timeoutSec;
# on a timeout only that process is stopped. Output goes to $log.out/.err, or with -Console
# straight to this console. $set and $unset change the child's environment only.
function Run([string] $exe, [string[]] $argv, [string] $log, [int] $timeoutSec = 300,
        [hashtable] $set = @{}, [string[]] $unset = @(), [switch] $Console) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = @($argv | ForEach-Object { Quote $_ }) -join ' '
    $psi.WorkingDirectory = $work
    $psi.UseShellExecute = $false
    foreach ($k in $unset) { $psi.EnvironmentVariables.Remove($k) }
    foreach ($k in $set.Keys) { $psi.EnvironmentVariables[$k] = [string] $set[$k] }
    if (-not $Console) {
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.StandardOutputEncoding = $utf8
        $psi.RedirectStandardError = $true; $psi.StandardErrorEncoding = $utf8
    }
    $name = Split-Path $exe -Leaf
    $p = [Diagnostics.Process]::Start($psi)
    try {
        if (-not $Console) { $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync() }
        if (-not $p.WaitForExit($timeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            [void] $p.WaitForExit(10000)
            Refuse "$name $($argv[0]) did not finish within $timeoutSec s; stopped its process $($p.Id)"
        }
        if (-not $Console) {
            if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]] @($out, $err), 30000)) {
                Refuse "$name $($argv[0]) exited but its output did not close"
            }
            [IO.File]::WriteAllText("$log.out", $out.Result, $utf8)
            [IO.File]::WriteAllText("$log.err", $err.Result, $utf8)
        }
        return $p.ExitCode
    } finally { $p.Dispose() }
}
# DarkScript3 targets .NET 6 and runs on the installed runtime; both tools need the game's
# Oodle for DCX_KRAK. The ReadyToRun code in the bundled SoulsFormats fails fast on load,
# so the runtime uses its IL. Set on those child processes only.
$ToolEnv = @{ DOTNET_ROLL_FORWARD = 'Major'; DOTNET_ReadyToRun = '0'; PATH = "$env:PATH;$((Full $GameDir))" }
function Tool([string] $exe, [string[]] $argv, [string] $log) { Run $exe $argv $log 300 $ToolEnv }

# 3. Extract the allowlisted inputs.
$vanilla = Join-Path $work 'vanilla'
$msbs = @("/map/mapstudio/$companionMsb.msb.dcx", "/map/mapstudio/$hostileMsb.msb.dcx") | Sort-Object -Unique
$mapEvents = @("/event/$companionMsb.emevd.dcx", "/event/$hostileMsb.emevd.dcx") | Sort-Object -Unique
& (Join-Path $PSScriptRoot 'extract-inputs.ps1') `
    -GameDir $GameDir -UxmExe $Uxm -OutDir $vanilla -Files (@('/event/common.emevd.dcx', '/script/aicommon.luabnd.dcx') + $msbs + $mapEvents)
if ($LASTEXITCODE -ne 0) { Refuse 'extract-inputs.ps1 failed' }
$steps.extract = Get-Content -LiteralPath (Join-Path $vanilla 'extract.json') -Raw | ConvertFrom-Json

# erpack, built once outside the repository against the user's SoulsFormats, with no build
# servers or reused nodes left behind and none of the runtime DOTNET_* settings of the caller.
$dotnet = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $dotnet) { Refuse 'dotnet SDK not found on PATH' }
$keepDotnet = '^DOTNET_(ROOT|CLI_HOME$|CLI_TELEMETRY_OPTOUT$|NOLOGO$|SKIP_FIRST_TIME_EXPERIENCE$)'
$runtimeVars = @([Environment]::GetEnvironmentVariables().Keys | Where-Object { $_ -match '^(DOTNET_|COMPlus_)' -and $_ -notmatch $keepDotnet })
$erpackOut = Join-Path $work 'erpack'
$code = Run $dotnet.Source @('build', (Join-Path $PSScriptRoot 'erpack\erpack.csproj'), '-nologo', '--disable-build-servers',
    '-nodeReuse:false', '-p:UseSharedCompilation=false', "-p:KgOut=$erpackOut", "-p:SoulsLib=$SoulsLib") '' 600 @{} $runtimeVars -Console
$erpack = Join-Path $erpackOut 'bin\erpack.exe'
if ($code -ne 0 -or -not (Test-Path -LiteralPath $erpack)) { Refuse "erpack build failed (exit $code)" }

# 4. Check the configured ids against the user's own MSBs and params.
$regCopy = Join-Path $work 'regulation.bin.original'
Copy-Item -LiteralPath (Join-Path $GameDir 'regulation.bin') -Destination $regCopy
$defs = Join-Path $work 'paramdex'
[void][Reflection.Assembly]::Load('System.IO.Compression.FileSystem, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
$zip = [IO.Compression.ZipFile]::OpenRead($Paramdex)
try {
    New-Item -ItemType Directory -Force -Path $defs | Out-Null
    foreach ($n in 'NpcThinkParam', 'NpcParam', 'ActionButtonParam') {
        [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry("ER/Defs/$n.xml"), (Join-Path $defs "$n.xml"))
    }
} finally { $zip.Dispose() }
$msbPaths = $msbs | ForEach-Object { Join-Path $vanilla $_.TrimStart('/') }
$code = Tool $erpack (@('inspect', '--oodle', $Oodle, '--regulation', $regCopy, '--paramdex', $defs, '--msb') + $msbPaths +
    @('--think', $controlAi, '--buttons', $button)) (Join-Path $work 'inspect')
if ($code -ne 0) { Refuse "erpack inspect failed: $(Get-Content "$work\inspect.err" -Raw)" }
# Plain strings: Windows PowerShell 5.1 ConvertTo-Json also serializes the PSPath/PSDrive/
# PSProvider notes Get-Content attaches to each line, which grows without bound at -Depth 12.
$inspect = [IO.File]::ReadAllLines("$work\inspect.out")
function Part([int64] $entity) {
    $l = @($inspect | Where-Object { $_ -match " entity=$entity " })
    if ($l.Count -ne 1) { Refuse "entity $entity found $($l.Count) times in the MSBs" }
    return $l[0]
}
$c = Part $companion; $h = Part $hostile
if ($c -notmatch " think=$originalAi " -or $c -notmatch " team=$originalTeam " -or $c -notmatch ' talk=0 ') {
    Refuse "companion does not match original_ai_id/original_team_type or has a talk script: $c"
}
if ($h -notmatch " team=$hostileTeam " -or $h -match ' talk=[1-9]') { Refuse "hostile does not match hostile_team_type or has a talk script: $h" }
if (-not ($inspect -match "^think $controlAi exists=False$")) { Refuse "NpcThinkParam $controlAi already exists" }
if (-not ($inspect -match "^button $button regionType=")) { Refuse "ActionButtonParam $button not found" }
$steps.ids = [ordered]@{ companion = $c; hostile = $h; button = @($inspect -match "^button $button")[0] }

function Render([string] $template) {
    $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot $template) -Raw
    foreach ($k in $values.Keys) { $text = $text.Replace("@$k@", [string] $values[$k]) }
    $left = [regex]::Match($text, '@[A-Z_]+@')
    if ($left.Success) { Refuse "unfilled placeholder $($left.Value) in $template" }
    return $text
}

# 5. Event script: EMEDF names and argument counts, then DarkScript3 compile and round trip.
$eventsJs = Render 'kagrenac_control.js.in'
$emedfData = Get-Content -LiteralPath $Emedf -Raw | ConvertFrom-Json
$known = @{}
foreach ($cls in $emedfData.main_classes) {
    foreach ($ins in $cls.instrs) {
        # DarkScript3 3.6.3 naming: punctuation dropped, then each word capitalised and the
        # rest lower-cased, except its acronym list and SpEffect. The compiler has the last word.
        $name = ((($ins.name -replace '[^\w\s]', '') -split ' ') | Where-Object { $_ } | ForEach-Object {
            if ($_.ToUpperInvariant() -in 'AI', 'HP', 'SE', 'SP', 'SFX', 'FFX', 'NPC', 'BGM', 'PS5', 'FE', 'ESD') { $_.ToUpperInvariant() }
            elseif ($_ -ceq 'SpEffect') { $_ }
            else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant() }
        }) -join ''
        $known[$name] = @{ id = "$($cls.index)[$($ins.index)]"; args = @($ins.args).Count }
    }
}
$used = [ordered]@{}
foreach ($line in $eventsJs -split "`n") {
    $m = [regex]::Match($line, '^\s{4}([A-Z]\w*)\((.*)\);\s*$')
    if (-not $m.Success -or $m.Groups[1].Value -like 'Label*') { continue }
    $name = $m.Groups[1].Value
    $argc = if ($m.Groups[2].Value.Trim()) { ($m.Groups[2].Value -split ',').Count } else { 0 }
    if (-not $known.ContainsKey($name)) { Refuse "event instruction $name is not in $Emedf" }
    if (($name -eq 'InitializeEvent' -and $argc -lt 2) -or ($name -ne 'InitializeEvent' -and $argc -ne $known[$name].args)) {
        Refuse "$name has $argc arguments, EMEDF $($known[$name].id) has $($known[$name].args)"
    }
    $used[$name] = $known[$name].id
}

$vanillaEmevd = Join-Path $vanilla 'event\common.emevd.dcx'
$dsIn = Join-Path $work 'ds-decompiled'
# DarkScript3 reads a whole folder; give it common only, not the map event files.
$dsSource = Join-Path $work 'ds-source'
New-Item -ItemType Directory -Force -Path $dsSource | Out-Null
Copy-Item -LiteralPath $vanillaEmevd -Destination $dsSource
$code = Tool $DarkScript @('/cmd', '-decompile', '-game', 'er', '-indir', $dsSource, '-outdir', $dsIn) (Join-Path $work 'ds-decompile')
$commonJs = Join-Path $dsIn 'common.emevd.dcx.js'
if ($code -ne 0 -or -not (Test-Path -LiteralPath $commonJs)) { Refuse "DarkScript3 decompile failed (exit $code)" }
$common = Get-Content -LiteralPath $commonJs -Raw
if ([regex]::IsMatch($common, "\bEvent\(\s*$eventControl\s*,")) { Refuse "event id $eventControl already exists in common" }
$eventHeader = '(?m)^\$?Event\(\s*\d+\s*,'
$ctor = [regex]::Matches($common, '(?m)^\$?Event\(\s*0\s*,[^\r\n]*\{[ \t]*\r?$')
if ($ctor.Count -ne 1) { Refuse "expected exactly one event 0 header in common, found $($ctor.Count)" }
$at = $ctor[0].Index + $ctor[0].Length
$patched = $common.Substring(0, $at) + "`n    InitializeEvent(0, $eventControl, 0);" +
    $common.Substring($at).TrimEnd() + "`n`n" + $eventsJs
$dsPatched = Join-Path $work 'ds-patched'
New-Item -ItemType Directory -Force -Path $dsPatched | Out-Null
[IO.File]::WriteAllText((Join-Path $dsPatched 'common.emevd.dcx.js'), $patched, $utf8)
# The DarkScript3 build stays in the work folder; only the merged file goes to the package.
$dsCompiled = Join-Path $work 'ds-compiled'
$code = Tool $DarkScript @('/cmd', '-compile', '-game', 'er', '-indir', $dsPatched, '-outdir', $dsCompiled) (Join-Path $work 'ds-compile')
$compiled = Join-Path $dsCompiled 'common.emevd.dcx'
if ($code -ne 0 -or -not (Test-Path -LiteralPath $compiled)) {
    Refuse "DarkScript3 compile failed (exit $code): $(Get-Content "$work\ds-compile.out", "$work\ds-compile.err" -Raw)"
}
# erpack merge-events: the user's original binary common plus only the new event and its one
# start in event 0, everything else checked unchanged; it reports its checks as JSON.
$pkgEvent = Join-Path $pkg 'event'
New-Item -ItemType Directory -Force -Path $pkgEvent | Out-Null
$emevdOut = Join-Path $pkgEvent 'common.emevd.dcx'
$code = Tool $erpack (@('merge-events', '--original', $vanillaEmevd, '--compiled', $compiled, '--event', $eventControl,
    '--out', $emevdOut, '--oodle', $Oodle, '--expect-teams', $originalTeam, $controlTeam, '--expect-entity', $companion,
    '--check-events') + @($mapEvents | ForEach-Object { Join-Path $vanilla $_.TrimStart('/') })) (Join-Path $work 'merge')
if ($code -ne 0 -or -not (Test-Path -LiteralPath $emevdOut)) {
    Refuse "erpack merge-events failed (exit $code): $(Get-Content "$work\merge.out", "$work\merge.err" -Raw)"
}
try { $merge = Get-Content -LiteralPath "$work\merge.out" -Raw | ConvertFrom-Json } catch { $merge = $null }
if ($null -eq $merge) { Refuse 'erpack merge-events did not report its checks as JSON' }
if ($merge.ok -ne $true -or $merge.teams_ok -ne $true -or $merge.entity_ok -ne $true -or @($merge.event_id_checks).Count -ne $mapEvents.Count) {
    Refuse "erpack merge-events reported ok=$($merge.ok) teams_ok=$($merge.teams_ok) entity_ok=$($merge.entity_ok)"
}
# Last check on the file actually packaged: DarkScript3 reads it back with the control event,
# its event 0 start and exactly one more event than the original.
$dsCheck = Join-Path $work 'ds-roundtrip'
$code = Tool $DarkScript @('/cmd', '-decompile', '-game', 'er', '-indir', $pkgEvent, '-outdir', $dsCheck) (Join-Path $work 'ds-roundtrip')
$roundJs = Join-Path $dsCheck 'common.emevd.dcx.js'
if ($code -ne 0 -or -not (Test-Path -LiteralPath $roundJs)) { Refuse "DarkScript3 round-trip decompile failed (exit $code)" }
$round = Get-Content -LiteralPath $roundJs -Raw
if (-not [regex]::IsMatch($round, "\bEvent\(\s*$eventControl\s*,")) { Refuse "event $eventControl missing after the merge round trip" }
if (-not [regex]::IsMatch($round, "InitializeEvent\(0,\s*$eventControl\b")) { Refuse 'control event start missing after the merge round trip' }
$eventsBefore = [regex]::Matches($common, $eventHeader).Count
$eventsAfter = [regex]::Matches($round, $eventHeader).Count
if ($eventsAfter -ne $eventsBefore + 1) { Refuse "merged common has $eventsAfter events, expected $($eventsBefore + 1)" }
$steps.emevd = [ordered]@{
    instructions = $used
    source_sha256 = (Sha256 $vanillaEmevd); compiled_sha256 = (Sha256 $compiled)
    bytes = (Get-Item -LiteralPath $emevdOut).Length; sha256 = (Sha256 $emevdOut)
    merge = $merge
    round_trip = "DarkScript3 reads the merged file: event $eventControl and its event 0 start present, $eventsBefore events before, $eventsAfter after"
}

# 6. Lua logic, aicommon.luabnd and the regulation.bin copy.
$luaDir = Join-Path $work 'lua'
New-Item -ItemType Directory -Force -Path $luaDir | Out-Null
$luaSrc = Join-Path $luaDir "${logicName}_logic.lua"
$luaBin = Join-Path $luaDir "${logicName}_logic.luac"
[IO.File]::WriteAllText($luaSrc, (Render 'kagrenac_companion.lua.in'), $utf8)
$code = Run $Luac @('-s', '-o', $luaBin, $luaSrc) (Join-Path $work 'luac') 60
if ($code -ne 0 -or -not (Test-Path -LiteralPath $luaBin)) { Refuse "luac failed: $(Get-Content "$work\luac.err" -Raw)" }
$spec = [ordered]@{
    luabnd = (Join-Path $vanilla 'script\aicommon.luabnd.dcx'); lua_bytecode = $luaBin; lua_file = "${logicName}_logic.lua"
    logic_id = $logicId; logic_name = $logicName; globals = @("${logicName}_Logic", "${logicName}_Interupt")
    regulation = $regCopy; paramdex = $defs; think_source = $originalAi; think_new = $controlAi; out_dir = $pkg
}
$specPath = Join-Path $work 'pack.json'
[IO.File]::WriteAllText($specPath, ($spec | ConvertTo-Json), $utf8)
$code = Tool $erpack @('pack', '--oodle', $Oodle, '--spec', $specPath) (Join-Path $work 'pack')
if ($code -ne 0) { Refuse "erpack pack failed: $(Get-Content "$work\pack.err" -Raw)" }
$steps.pack = Get-Content -LiteralPath "$work\pack.out" -Raw | ConvertFrom-Json

$outputs = [ordered]@{}
foreach ($f in 'event\common.emevd.dcx', 'script\aicommon.luabnd.dcx', 'regulation.bin') {
    $outputs[$f.Replace('\', '/')] = Sha256 (Join-Path $pkg $f)
}
$manifest = [ordered]@{
    status = 'built from the user''s own files; not tested in game; nothing installed'
    game_exe_sha256 = $exeSha
    outputs = $outputs
    commands = [ordered]@{
        event = "DarkScript3 /cmd -decompile and -compile (work folder only); erpack merge-events --original <user common.emevd.dcx> --compiled <work build> --event $eventControl --out package/event/common.emevd.dcx --expect-teams $originalTeam $controlTeam --expect-entity $companion --check-events <user's original $(($mapEvents -replace '^/event/') -join ' and ')>; DarkScript3 -decompile of the merged file"
        script_and_param = 'luac -s; erpack pack (aicommon.luabnd copy and regulation.bin copy, each re-read)'
    }
    source_preservation = [ordered]@{
        'event/common.emevd.dcx' = "the user's original binary common with its events, instructions, parameters and strings kept; only event $eventControl and one InitializeEvent(0, $eventControl, 0) in event 0 added, the rest checked unchanged by erpack merge-events (steps.emevd.merge)"
        'script/aicommon.luabnd.dcx' = "the user's original with one added logic file $logicName and its LUAINFO/LUAGNL names"
        'regulation.bin' = "a copy of the user's original with NpcThinkParam $controlAi cloned from $originalAi"
    }
    values = $values
    steps = $steps
    untested = @(
        "common event 0 starting control event $eventControl on every load or warp (constructor lifetime not confirmed)",
        'a reload or warp while controlled: the event restarts at idle without a restore, so the game must rebuild the companion with its original AI and team',
        "ActionButtonParam $button showing a prompt on a character from an event, and one press passing only one wait",
        "IfElapsedSeconds($lease) in the attack wait counting from that wait, not from the event start",
        "control team $controlTeam (raw NpcParam team, seen on spirit-summon rows) being accepted by SetCharacterTeamType and keeping the soldier off the player",
        "GOAL_COMMON_AttackTunableSpin with animation $attackAnim on TARGET_EVENT hitting the selected hostile",
        'the logic running and the soldier obeying follow, hold and attack'
    )
    attack_evidence = [ordered]@{
        asset = '/script/431000_battle.luabnd.dcx (Data0, 5952 bytes, sha256 c1295e3a21536027e751651ba565d2985ae07dd721ca4e79bc3f9320cbf8500b)'
        entry = '431000_battle.lua (sha256 81f4a857a44f1dd6a44e8ae06ba5bcbcfd5f4fe9789121b978155c86793941cf)'
        call_site = 'AddSubGoal(GOAL_COMMON_ComboAttackTunableSpin, 5, 3000, TARGET_ENE_0, 2.5, ...)'
        top_goal_shape = 'aicommon AddTopGoal(GOAL_COMMON_AttackTunableSpin, 10, anim, TARGET_ENE_0, 9999, 0, 180, 0, 0)'
        attack_animation = $attackAnim
    }
}
[IO.File]::WriteAllText((Join-Path $OutDir 'package.json'), ($manifest | ConvertTo-Json -Depth 12), $utf8)
Write-Host "built $pkg (not tested in game)"
exit 0
