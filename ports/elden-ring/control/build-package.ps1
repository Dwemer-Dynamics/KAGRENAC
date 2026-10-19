<#
.SYNOPSIS
  Builds the KAGRENAC Elden Ring companion control package from the user's own game files.

.DESCRIPTION
  Run with Windows PowerShell 5.1. Steps, each checked before the next:
    1. config: every value a finite number in range, no duplicates, no player id
    2. eldenring.exe SHA-256 equals the recorded build (a file check; the engine itself is
       not qualified by this)
    3. extract-inputs.ps1: common.emevd, aicommon.luabnd and the template's, companion's and
       hostile's tile MSBs and event files, read-only;
       then one `dotnet build` of erpack into the output folder (no build servers)
    4. erpack inspect on the user's MSBs and a copy of regulation.bin: the template and the
       hostile exist with the configured think row, NpcParam row, team and no talk script; the
       companion id does not exist yet; the action button row exists; the new think and
       NpcParam rows do not.
       erpack place then writes package/map/mapstudio/<companion_msb>.msb.dcx: the user's
       destination MSB plus one copy of the template under the companion id and name, with the
       control think row, the private NpcParam row and no backup animation (-1), beside
       the grace of the configured BonfireWarpParam row (read from the user's regulation and
       the Paramdex names), checked against that grace and its player part, and checked to be
       the original plus only that part and model
    5. DarkScript3 /cmd: decompile common (the control event id must be free), add the one
       control event and InitializeEvent(0, event_control, 0) to event 0, compile into the
       work folder. erpack merge-events then writes package/event/common.emevd.dcx from the
       user's original binary common, keeping its events, instructions, parameters and
       strings, appending only that event and that one start, and checking everything else
       is unchanged; the event id must also be free in the tiles' original event files, the
       event may set no team, and every character AI call must address the companion.
       DarkScript3 decompiles the merged file again as a last check.
    6. luac 5.0.3: compile the logic; erpack pack: add it to aicommon.luabnd and clone the
       think row (new logicId) and the NpcParam row (new teamType) into the regulation.bin
       copy, then re-read both; a last inspect qualifies the placed copy with that regulation
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
$template = Int 'template_entity' 1000000 4294967295
$hostile = Int 'hostile_entity' 1000000 4294967295
if (@($companion, $template, $hostile | Sort-Object -Unique).Count -ne 3) { Refuse 'companion_entity, template_entity and hostile_entity must all differ' }
$companionMsb = Tile 'companion_msb'
$templateMsb = Tile 'template_msb'
$hostileMsb = Tile 'hostile_msb'
# The companion is a new copy of the template, placed beside one grace in companion_msb.
$companionName = [string] $cfg.companion_name
if ($companionName -notmatch '^c\d{4}_\d{4}$') { Refuse 'companion_name must look like cNNNN_NNNN (the template model, then a new instance)' }
$graceRow = Int 'grace_bonfire_row' 1 2147483647
$graceName = [string] $cfg.grace_name
if (-not $graceName -or $graceName.Length -gt 100) { Refuse 'grace_name must be the row''s name from the Paramdex BonfireWarpParam names' }
$posCfg = @($cfg.companion_position)
if ($posCfg.Count -ne 3) { Refuse 'companion_position must be [x, y, z] in companion_msb''s coordinates' }
$companionPos = foreach ($v in $posCfg) {
    if ($null -eq $v -or $v -is [bool] -or -not ($v -is [ValueType])) { Refuse 'companion_position values must be numbers' }
    $d = [double] $v
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d) -or [Math]::Abs($d) -gt 1000) { Refuse "companion_position value $v outside -1000..1000" }
    $d
}
$originalAi = Int 'original_ai_id' 1 2147483647
$controlAi = Int 'control_ai_id' 1 2147483647
if ($originalAi -eq $controlAi) { Refuse 'control_ai_id must differ from original_ai_id' }
$originalNpc = Int 'original_npc_id' 1 2147483647
$controlNpc = Int 'control_npc_id' 1 2147483647
if ($originalNpc -eq $controlNpc) { Refuse 'control_npc_id must differ from original_npc_id' }
$originalTeam = Int 'original_team_type' 1 255
$controlTeam = Int 'control_team_type' 1 255
if ($controlTeam -eq $originalTeam) { Refuse 'control_team_type must differ from original_team_type' }
# The control team goes only into the companion's private NpcParam row, never into an event
# (the EMEDF Team Type enum lists neither 47 nor 48). Accepted: the raw teamType of the
# game's own spirit-summon NpcParam rows (Paramdex TEAM_TYPE 47 "Spirit Summon").
if ($controlTeam -ne 47) { Refuse 'control_team_type must be 47 (the teamType of the game''s spirit-summon NpcParam rows)' }
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
    ORIGINAL_NPC = $originalNpc; CONTROL_NPC = $controlNpc
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
$tiles = @($companionMsb, $templateMsb, $hostileMsb) | Sort-Object -Unique
$msbs = @($tiles | ForEach-Object { "/map/mapstudio/$_.msb.dcx" })
$mapEvents = @($tiles | ForEach-Object { "/event/$_.emevd.dcx" })
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
    foreach ($n in 'NpcThinkParam', 'NpcParam', 'ActionButtonParam', 'BonfireWarpParam') {
        [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry("ER/Defs/$n.xml"), (Join-Path $defs "$n.xml"))
    }
    $graceNames = Join-Path $work 'BonfireWarpParam.names.txt'
    [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry('ER/Names/BonfireWarpParam.txt'), $graceNames)
} finally { $zip.Dispose() }
$msbPaths = $msbs | ForEach-Object { Join-Path $vanilla $_.TrimStart('/') }
$code = Tool $erpack (@('inspect', '--oodle', $Oodle, '--regulation', $regCopy, '--paramdex', $defs, '--msb') + $msbPaths +
    @('--think', $controlAi, '--npc', $originalNpc, $controlNpc, '--buttons', $button)) (Join-Path $work 'inspect')
if ($code -ne 0) { Refuse "erpack inspect failed: $(Get-Content "$work\inspect.err" -Raw)" }
# Plain strings: Windows PowerShell 5.1 ConvertTo-Json also serializes the PSPath/PSDrive/
# PSProvider notes Get-Content attaches to each line, which grows without bound at -Depth 12.
$inspect = [IO.File]::ReadAllLines("$work\inspect.out")
function Part([string[]] $lines, [int64] $entity) {
    $l = @($lines | Where-Object { $_ -match " entity=$entity " })
    if ($l.Count -ne 1) { Refuse "entity $entity found $($l.Count) times in the MSBs" }
    return $l[0]
}
function Companion([string] $line, [string] $what, [int64] $npcId, [int64] $think, [int64] $team) {
    if ($line -notmatch " npc=$npcId " -or $line -notmatch " think=$think " -or $line -notmatch " team=$team " -or $line -notmatch ' talk=0 ') {
        Refuse "$what does not have NpcParam $npcId, think row $think and team $team, or has a talk script: $line"
    }
}
$t = Part $inspect $template; $h = Part $inspect $hostile
Companion $t 'template' $originalNpc $originalAi $originalTeam
if (@($inspect | Where-Object { $_ -match " entity=$companion " }).Count -ne 0) { Refuse "companion_entity $companion already exists in the MSBs" }
if ($h -notmatch " team=$hostileTeam " -or $h -match ' talk=[1-9]') { Refuse "hostile does not match hostile_team_type or has a talk script: $h" }
if (-not ($inspect -match "^think $controlAi exists=False$")) { Refuse "NpcThinkParam $controlAi already exists" }
if (-not ($inspect -match "^npc $originalNpc exists=True team=$originalTeam$")) { Refuse "NpcParam $originalNpc missing or not team $originalTeam" }
if (-not ($inspect -match "^npc $controlNpc exists=False team=$")) { Refuse "NpcParam $controlNpc already exists" }
if (-not ($inspect -match "^button $button regionType=")) { Refuse "ActionButtonParam $button not found" }

# The companion: one copy of the template in a new copy of companion_msb, beside the grace.
# Limits: 3 to 4 m from the grace, within 0.5 m of its height and of its player part, 2.5 m
# clear of characters, 2 m of assets, 1 m outside event regions; the id and name must be new
# in every extracted MSB and event file.
$pkgMap = Join-Path $pkg 'map\mapstudio'
New-Item -ItemType Directory -Force -Path $pkgMap | Out-Null
$placedMsb = Join-Path $pkgMap "$companionMsb.msb.dcx"
$code = Tool $erpack (@('place', '--oodle', $Oodle, '--template', (Join-Path $vanilla "map\mapstudio\$templateMsb.msb.dcx"),
    '--template-entity', $template, '--dest', (Join-Path $vanilla "map\mapstudio\$companionMsb.msb.dcx"),
    '--dest-events', (Join-Path $vanilla "event\$companionMsb.emevd.dcx"), '--out', $placedMsb,
    '--entity', $companion, '--name', $companionName, '--think', $controlAi, '--npc', $controlNpc, '--backup-anim', '-1',
    '--pos') + @($companionPos | ForEach-Object { $_.ToString('R', $inv) }) + @(
    '--regulation', $regCopy, '--paramdex', $defs, '--bonfire-names', $graceNames, '--bonfire-row', $graceRow, '--bonfire-name', $graceName,
    '--offset-min', '3', '--offset-max', '4', '--max-dy', '0.5', '--clear-chr', '2.5', '--clear-asset', '2', '--clear-region', '1',
    '--check-msb') + $msbPaths + @('--check-events', (Join-Path $vanilla 'event\common.emevd.dcx')) + @($mapEvents | ForEach-Object { Join-Path $vanilla $_.TrimStart('/') })) (Join-Path $work 'place')
if ($code -ne 0 -or -not (Test-Path -LiteralPath $placedMsb)) {
    Refuse "erpack place failed (exit $code): $(Get-Content "$work\place.out", "$work\place.err" -Raw)"
}
try { $place = Get-Content -LiteralPath "$work\place.out" -Raw | ConvertFrom-Json } catch { $place = $null }
if ($null -eq $place -or $place.ok -ne $true -or $place.original_entries_unchanged -ne $true -or $place.id_in_output -ne 1) {
    Refuse 'erpack place did not report a verified copy'
}
$steps.place = $place

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
    '--out', $emevdOut, '--oodle', $Oodle, '--expect-teams', '--expect-entity', $companion,
    '--check-events') + @($mapEvents | ForEach-Object { Join-Path $vanilla $_.TrimStart('/') })) (Join-Path $work 'merge')
if ($code -ne 0 -or -not (Test-Path -LiteralPath $emevdOut)) {
    Refuse "erpack merge-events failed (exit $code): $(Get-Content "$work\merge.out", "$work\merge.err" -Raw)"
}
try { $merge = Get-Content -LiteralPath "$work\merge.out" -Raw | ConvertFrom-Json } catch { $merge = $null }
if ($null -eq $merge) { Refuse 'erpack merge-events did not report its checks as JSON' }
if ($merge.ok -ne $true -or $merge.teams_ok -ne $true -or @($merge.team_commands).Count -ne 0 -or $merge.entity_ok -ne $true -or
        @($merge.event_id_checks).Count -ne $mapEvents.Count) {
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
    regulation = $regCopy; paramdex = $defs; think_source = $originalAi; think_new = $controlAi
    npc_source = $originalNpc; npc_new = $controlNpc; npc_team = $controlTeam; out_dir = $pkg
}
$specPath = Join-Path $work 'pack.json'
[IO.File]::WriteAllText($specPath, ($spec | ConvertTo-Json), $utf8)
$code = Tool $erpack @('pack', '--oodle', $Oodle, '--spec', $specPath) (Join-Path $work 'pack')
if ($code -ne 0) { Refuse "erpack pack failed: $(Get-Content "$work\pack.err" -Raw)" }
$steps.pack = Get-Content -LiteralPath "$work\pack.out" -Raw | ConvertFrom-Json

# Qualify the copy as the game would see it: the template's and the placed tile's MSBs with the
# packaged regulation.bin. The copy alone has the control think row (logic $logicId) and the
# private NpcParam row (team $controlTeam); the template keeps its own rows.
$code = Tool $erpack @('inspect', '--oodle', $Oodle, '--regulation', (Join-Path $pkg 'regulation.bin'), '--paramdex', $defs, '--msb',
    (Join-Path $vanilla "map\mapstudio\$templateMsb.msb.dcx"), $placedMsb, '--npc', $originalNpc, $controlNpc) (Join-Path $work 'inspect-placed')
if ($code -ne 0) { Refuse "erpack inspect of the placed MSB failed: $(Get-Content "$work\inspect-placed.err" -Raw)" }
$placedLines = [IO.File]::ReadAllLines("$work\inspect-placed.out")
$c = Part $placedLines $companion
Companion $c 'placed companion' $controlNpc $controlAi $controlTeam
if ($c -notmatch " logic=$logicId ") { Refuse "placed companion does not run logic $logicId`: $c" }
if ($c -notmatch "^$companionName ") { Refuse "placed companion is not named $companionName`: $c" }
if ((Part $placedLines $template) -ne $t) { Refuse 'template changed in the inspect of the placed MSB' }
if (-not ($placedLines -match "^npc $originalNpc exists=True team=$originalTeam$")) { Refuse "NpcParam $originalNpc changed in the package" }
$steps.ids = [ordered]@{ companion = $c; template = $t; hostile = $h; button = @($inspect -match "^button $button")[0] }

$outputs = [ordered]@{}
foreach ($f in 'event\common.emevd.dcx', 'script\aicommon.luabnd.dcx', 'regulation.bin', "map\mapstudio\$companionMsb.msb.dcx") {
    $outputs[$f.Replace('\', '/')] = Sha256 (Join-Path $pkg $f)
}
$manifest = [ordered]@{
    status = 'built from the user''s own files; not tested in game; nothing installed'
    game_exe_sha256 = $exeSha
    outputs = $outputs
    commands = [ordered]@{
        event = "DarkScript3 /cmd -decompile and -compile (work folder only); erpack merge-events --original <user common.emevd.dcx> --compiled <work build> --event $eventControl --out package/event/common.emevd.dcx --expect-teams (none) --expect-entity $companion --check-events <user's original $(($mapEvents -replace '^/event/') -join ' and ')>; DarkScript3 -decompile of the merged file"
        script_and_param = 'luac -s; erpack pack (aicommon.luabnd copy and regulation.bin copy, each re-read)'
        map = "erpack place --template <user $templateMsb.msb.dcx> --template-entity $template --dest <user $companionMsb.msb.dcx> --entity $companion --name $companionName --think $controlAi --npc $controlNpc --backup-anim -1 --bonfire-row $graceRow (re-read and compared with the original); erpack inspect of the placed MSB with the packaged regulation.bin"
    }
    source_preservation = [ordered]@{
        'event/common.emevd.dcx' = "the user's original binary common with its events, instructions, parameters and strings kept; only event $eventControl and one InitializeEvent(0, $eventControl, 0) in event 0 added, the rest checked unchanged by erpack merge-events (steps.emevd.merge)"
        'script/aicommon.luabnd.dcx' = "the user's original with one added logic file $logicName and its LUAINFO/LUAGNL names"
        'regulation.bin' = "a copy of the user's original with NpcThinkParam $controlAi cloned from $originalAi (only logicId changed) and NpcParam $controlNpc cloned from $originalNpc (only teamType changed, to $controlTeam); every other row, $originalAi and $originalNpc included, and every other file unchanged (steps.pack)"
        "map/mapstudio/$companionMsb.msb.dcx" = "the user's original with one enemy $companionName (entity $companion, a copy of $template from $templateMsb with think $controlAi, NpcParam $controlNpc and BackupEventAnimID -1) and its model entry if missing; with those removed it equals the original byte for byte, decompressed (steps.place)"
    }
    values = $values
    companion_copy = [ordered]@{
        template_entity = $template; template_msb = $templateMsb; companion_msb = $companionMsb; companion_name = $companionName
        companion_position = $companionPos; grace_bonfire_row = $graceRow; grace_name = $graceName
    }
    steps = $steps
    untested = @(
        "common event 0 starting control event $eventControl on every load or warp (constructor lifetime not confirmed)",
        "the copy loading friendly and holding: team $controlTeam from its private NpcParam row $controlNpc (the teamType of the game's spirit-summon rows) keeping it off the player and the player off it, and logic $logicId waiting with no request",
        "ActionButtonParam $button showing a prompt on a friendly character from an event, and one press passing only one wait",
        "IfElapsedSeconds($lease) in the attack wait counting from that wait, not from the event start",
        'GOAL_COMMON_ApproachTarget on TARGET_LOCALPLAYER following the player',
        "SetCharacterEventTarget setting TARGET_EVENT, and GOAL_COMMON_AttackTunableSpin with animation $attackAnim on it hitting the selected hostile",
        'the logic running without COMMON_EasySetup_Initial, and the soldier obeying follow, hold and attack',
        'a reload, warp, death or release returning the copy to a friendly hold',
        "the copy $companionName standing on the ground at $($companionPos -join ', ') in $companionMsb (height checked only against the grace asset and its player part, not against terrain collision)",
        "a team-$controlTeam copy within the grace's RegisterBonfire enemy deactivation distance ($($place.grace.register_bonfire.enemy_deactivation_distance) m) not blocking resting at the grace",
        "the game loading $companionMsb.msb.dcx from the package with the added part and model, and the copy without the template's BackupEventAnimID 704 starting in a normal standing pose"
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
