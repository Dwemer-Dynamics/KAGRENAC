# KAGRENAC AI Mod Maker developer wrapper for the Windows development copy. It reuses the
# existing scripts: client\scripts\build.ps1 on Windows, (explicit opt-in) the server's
# scripts/install.sh and scripts/smoke.sh inside an existing WSL server checkout, and for
# 'deploy' scripts/project-runtime.sh with DwemerDistro Core or a manual install's update.sh.
# It installs no prerequisites and resets no database. Only 'deploy' moves source into WSL (a
# Git bundle of the committed HEAD); client config is generated only through 'pair'. It starts
# no background services and never prints tokens or keys.
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\project.ps1 <new|doctor|setup|check|pair|configure|deploy> [options]
#   new     -Destination <full Windows path> -Id <id> -Name <name> [-Game <text>] [-Feature <text>]
#           [-Voice <text>] [-LlmProvider <name>] [-WslDistro <name>] [-Engine <port folder>]
#           [-InteractionMode manual|ambient|companion|operator] [-ServerFolder <Name>Server]
#           Start a new mod: copy exactly the committed HEAD of this template (git archive; no
#           Git history, untracked or ignored files, private config, database, build output or
#           logs) into a new folder outside every Git checkout and web root, set the copy's own
#           id, name and server_folder in dwemer-mod.json (default: -Name in CamelCase plus
#           Server, so Core installs it in /var/www/html/<Name>Server; the template's project_url
#           is left out), record the brief, paths and stage states in its
#           PROJECT.md (with -Engine, the plan from ports/<engine>/PLAN.md), and run 'git init'
#           there. It refuses an existing destination, an id already used by a deploy or build
#           folder, and any source that is not the template. It commits nothing and never
#           changes this checkout; review and commit the copy before its first deploy.
#           -InteractionMode only prefills the primary mode in PROJECT.md's Gameplay design
#           (planning text: it enables no feature, action, provider call or config).
#   doctor  Report tools, WSL distros and their state, client build, client config (no secrets)
#           and server health (ok and service identity only). On a healthy server, probe .git/
#           and the source folders: only HTTP 403 counts as protected; 200 is exposed and any
#           other status is unverified, and both are problems. With -WslDistro <name>, check
#           that one distro's DwemerDistro tool, Apache, PostgreSQL and web protection, only if
#           it is already running (it never starts a distro), and, for -WslServerPath or this
#           project's own install, whether www-data can save its private config
#           (the config is not read). For a native port's project (-Engine <port folder>, else
#           the engine 'new -Engine' wrote into its PROJECT.md Paths) it skips the console client
#           and points to that port's own route instead. Ends with a readiness summary;
#           the LLM and PocketTTS are only reported as answering or not, never as working.
#           Exit 0 means no FAIL or UNVERIFIED line was detected; WARN, SKIP and unchecked
#           items still need action, and it never means the AI is ready. Changes nothing.
#   setup   Build the client (x64 and x86) outside the repository; repeat-safe. With
#           -RunServerInstaller -WslDistro <name> -WslServerPath <path>, also run the existing
#           scripts/install.sh in that WSL checkout (manual install folders only).
#   check   PHP lint of the server files and shell syntax with local tools, then the client
#           build. With -RunSmoke -WslDistro <name> -WslServerPath <path>, also run
#           scripts/smoke.sh there.
#   pair    -WslDistro <name> [-WslServerPath <existing checkout>] -OutFile <full Windows path>
#           [-ServerUrl <base URL>] [-SessionId <id>] [-AllowedActions <name,...>]
#           [-NpcId <id>] [-NpcName <name>] [-VoiceEnabled]
#           Run that checkout's scripts/pair_client.php as dwemer (this may start the named
#           distro) into a private folder made for this run, read the file once over
#           \\wsl.localhost, and save it as a new private client config: the file is created
#           empty, limited to you, SYSTEM and Administrators (no inherited access) and checked
#           before the token is written, then compared with the source by SHA-256. The URL is
#           -ServerUrl, or port 19000 plus the checkout's route (pass -ServerUrl if Apache uses
#           another CUSTOM_MODS_PORT). An existing -OutFile is never overwritten: if it is private
#           and holds the same URL, token and session it is reported as already paired and kept
#           as it is; otherwise pair refuses. The token and file contents are never printed.
#           -NpcId, -NpcName (a game client's npc_id and npc_name) and -VoiceEnabled only shape
#           a new file; an existing one is kept byte for byte. With -Build <builds\<time> folder>,
#           or an assembled runtime.json beside -OutFile, every client action (default
#           follow_player) must be one that build supports (its build.json, package.json and DLL
#           checked as for configure); a game client config without a build record allows only
#           follow_player.
#   configure -WslDistro <name> [-WslServerPath <install>] [-LlmProvider openrouter|dwemerllm|mock
#           -LlmModel <model>] [-ReuseProviderFrom <private config.php in WSL>] [-Tts pockettts
#           -TtsVoice <voice> | -Tts off] [-AllowedActions <name,...> (-Build <builds\<time>
#           folder> | -ConsoleClient)] [-TestProviders] [-ServerUrl <base URL>]
#           Set the install's dialogue provider, voice and server allowlist through its
#           scripts/configure_server.php, run as www-data (this may start the named distro): the
#           existing config_update() saves, keeping token, database, unknown settings, owner,
#           group, mode and lock; the same request again writes nothing. -WslServerPath defaults
#           to this project's own install and must be that install. No key
#           is ever an argument or printed: openrouter keeps the key already configured for
#           openrouter, or takes only llm.api_key from the openrouter config named by
#           -ReuseProviderFrom. -Tts pockettts needs PocketTTS answering on 127.0.0.1:8086.
#           -AllowedActions replaces the server's list: with -Build only actions that verified
#           build supports (candidates, not qualified in game), with -ConsoleClient only
#           follow_player. -TestProviders then calls turn.php once (no actions offered, its own
#           test session; refused first when vector search, automatic memory or a default
#           profile's mode or model would change that) and speak.php once with that reply, no
#           retry, and prints only status,
#           timing, shape, length and the WAV's format, size and SHA-256.
#   deploy  -WslDistro <name> [-WslServerPath <existing manual install>] [-ServerUrl <base URL>]
#           Deploy the committed HEAD (the checkout must have no uncommitted or untracked files)
#           under the id in its dwemer-mod.json: a Git bundle of exactly HEAD goes to a private
#           folder (%LOCALAPPDATA%\DwemerDynamics\Kagrenac\deploy\<id>), then scripts/
#           project-runtime.sh runs as root in that distro. It needs DwemerDistro Core with
#           'setup-web --protect-project' and 'update --expect-commit' (a server_folder also needs
#           'setup-web --protect-root'; else: Update Distro), protects the install's route first,
#           and installs or updates only through Core from the
#           private cache /home/dwemer/.local/share/kagrenac/<id>/source.git, or for an existing
#           manual install through that folder's scripts/update.sh. It refuses the template id
#           example-server for a new install, never adopts, repoints or resets anything, and
#           never rewrites the private config. After deploy it checks the exact commit, www-data
#           access (a Core install's config/ that the dashboard cannot save is repaired by that
#           commit's scripts/install.sh, which also confirms the database and applies pending
#           migrations; Core's Update sets it read-only again, so deploy again after one),
#           health and HTTP 403 for source and config paths on every Apache listener
#           serving the route, then writes a private deployment record (with the backup and
#           retry steps) next to the bundle. The same commit again reports already deployed.
#           -ServerUrl only changes where Windows checks health (default: the route on the
#           custom mods listener that WSL verified).
#   -BuildRoot defaults to %LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>\client for a
#   project with its own id, and to %LOCALAPPDATA%\DwemerDynamics\KagrenacClient\build in the template.
#   New ports: -Engine accepts an engine without a reference plan and leaves planning open.
#   -Destination accepts either slash style. configure/pair -AllowedActions none explicitly
#   writes an empty list (no -Build needed). pair, configure, doctor and deploy find this project's
#   own install: the folder in Core's registry entry for its id (custom-mods/<id>, or the
#   /var/www/html/<Name>Server it was installed in or moved to with 'ddistro_custom_mod
#   migrate-root'), else the manifest's server_folder, else /var/www/html/custom-mods/<id>.
#   -Build and runtime.json records must use schema 2 (docs/PORT_BUILD_RECORDS.md); any other
#   record is refused (by pair before WSL is used; by configure before any server change, after
#   its registry read when -WslServerPath is omitted). Other server defaults and existing pairing stay unchanged.
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("new", "doctor", "setup", "check", "pair", "configure", "deploy", "package", "publish")]
    [string]$Command,
    [string]$BuildRoot = "",
    [string]$ClientDirectory = "",
    [string]$ReleaseVersion = "",
    [string]$ReleaseDirectory = "",
    [string]$ConfirmPublish = "",
    [string]$Destination = "",
    [string]$Id = "",
    [string]$Name = "",
    [string]$Game = "",
    [string]$Feature = "",
    [string]$Voice = "",
    [string]$LlmProvider = "",
    [string]$Engine = "",
    [string]$InteractionMode = "",
    [string]$ServerFolder = "",
    [string]$ServerUrl = "",
    [string]$WslDistro = "",
    [string]$WslServerPath = "",
    [string]$OutFile = "",
    [string]$SessionId = "",
    [string[]]$AllowedActions = @(),
    [string]$NpcId = "",
    [string]$NpcName = "",
    [switch]$VoiceEnabled,
    [string]$Build = "",
    [switch]$ConsoleClient,
    [string]$LlmModel = "",
    [string]$ReuseProviderFrom = "",
    [string]$Tts = "",
    [string]$TtsVoice = "",
    [switch]$TestProviders,
    [switch]$RunServerInstaller,
    [switch]$RunSmoke,
    [switch]$SkipBuild
)
$ErrorActionPreference = "Stop"
$env:WSL_UTF8 = "1"
. (Join-Path $PSScriptRoot 'port-build.ps1')

$repo = Split-Path -Parent $PSScriptRoot
$defaultUrl = "http://127.0.0.1:19000/custom-mods/KagrenacServer"
$serviceId = "example-ai-server"
$protectedSite = "/etc/apache2/sites-available/dwemerdistro-custom-mods.conf"
$failures = 0
$distroState = "not checked"
$distroRunning = $false
$serverState = "not checked"
$llmState = "not checked"
$ttsState = "not checked"
$done = New-Object System.Collections.Generic.List[string]
$manual = New-Object System.Collections.Generic.List[string]

function Say([string]$status, [string]$text) { Write-Host ("[{0}] {1}" -f $status, $text) }
function Fail([string]$text) { $script:failures++; Say "FAIL" $text }

# Runs a native command and passes its stdout and stderr on as text. Windows PowerShell 5.1
# turns redirected stderr into terminating errors under "Stop", so the preference is relaxed
# only for this call; callers check $LASTEXITCODE afterwards.
function Invoke-Native([scriptblock]$nativeCommand) {
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & $nativeCommand 2>&1 | ForEach-Object { "$_" } }
    finally { $ErrorActionPreference = $savedPreference }
}

# A server base URL: absolute http(s) with a host and no user info, query or fragment.
# Returns it without a trailing slash, or $null. Callers never print a rejected value.
function ConvertTo-BaseUrl([string]$raw) {
    if (-not $raw -or $raw -match '[\x00-\x20\x7f\\?#]' -or $raw -match '^[^/]*//[^/]*@') { return $null }
    $uri = $null
    if (-not [System.Uri]::TryCreate($raw, [System.UriKind]::Absolute, [ref]$uri)) { return $null }
    if ($uri.Scheme -ne "http" -and $uri.Scheme -ne "https") { return $null }
    if (-not $uri.Host -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { return $null }
    return $uri.AbsoluteUri.TrimEnd('/')
}

# Server text shown in the report: no control characters, at most 64 characters.
function Get-Printable($value) {
    $text = ([string]$value) -replace '[\x00-\x1f\x7f]', '?'
    if ($text.Length -gt 64) { $text = $text.Substring(0, 64) + "..." }
    return $text
}

# $value as one single-quoted PowerShell argument, so a printed command passes it literally ('$',
# '$(...)' and backticks stay text; every kind of single quote is doubled).
function ConvertTo-PsLiteral([string]$value) {
    return "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($value) + "'"
}

# A direct server folder Core accepts: <Letters/digits>Server, not an official or Kagrenac product name
# (the same rule as ddistro_custom_mod's validate_server_folder).
function Test-ServerFolder([string]$name) {
    $reserved = @("herika", "herikaserver", "chim", "stobe", "stobeserver", "dialectic", "dialecticserver", "reign", "reignserver",
        "lorkhan", "lorkhanserver", "dwemer", "dwemerdistro", "postgres", "template", "html", "admin", "root", "example", "kagrenac",
        "custom", "custommods")
    return ($name -cmatch '^[A-Z][A-Za-z0-9]{0,40}Server\z' -and $reserved -notcontains $name.Substring(0, $name.Length - 6).ToLowerInvariant())
}

# Folders DwemerDistro Core's web protection can cover: custom-mods/<folder>, the legacy
# ExampleServer, and a direct /var/www/html/<Name>Server root.
function Test-WslServerPath([string]$path) {
    $direct = $path -cmatch '^/var/www/html/([A-Za-z0-9]+)$' -and (Test-ServerFolder $Matches[1])
    if (-not $direct -and $path -cnotmatch '^/var/www/html/(custom-mods/[A-Za-z0-9_-][A-Za-z0-9._-]*|ExampleServer)$') {
        throw "Refusing WSL server path '$path': use an absolute folder directly under /var/www/html/custom-mods/, a /var/www/html/<Name>Server folder (or /var/www/html/ExampleServer), with no '..', links or trailing slash."
    }
}

# This project's install folder: the folder in Core's registry entry for its id when -WslDistro
# may be used (Core's registered location wins, legacy or moved), else the manifest's
# server_folder, else /var/www/html/custom-mods/<id>. "" in the template, which guesses no install.
function Get-OwnServerPath([bool]$readRegistry) {
    if (-not (Test-ProjectId $workingId) -or $workingId -ceq "example-server") { return "" }
    if ($readRegistry -and $WslDistro) {
        $lines = @(Invoke-Native { & wsl.exe -d $WslDistro -e cat "/var/lib/dwemerdistro-custom-mods/registry/$workingId.json" })
        if ($LASTEXITCODE -eq 0) {
            $entry = $null
            try { $entry = ($lines -join "`n") | ConvertFrom-Json } catch { }
            $folder = $(if ($entry -is [System.Management.Automation.PSCustomObject]) { [string]$entry.folder } else { "" })
            $direct = $folder -cmatch '^/var/www/html/([A-Za-z0-9]+)$' -and (Test-ServerFolder $Matches[1])
            if ([string]$entry.id -ceq $workingId -and ($direct -or $folder -ceq "/var/www/html/custom-mods/$workingId")) { return $folder }
            Say "WARN" "Core's registry entry for $workingId in $WslDistro names no usable folder, so the manifest's location is used."
        }
    }
    if ($workingFolder) { return "/var/www/html/$workingFolder" }
    return "/var/www/html/custom-mods/$workingId"
}

# Apache sections of a site file as @{ Type; Arg; Parent; Denied }, in file order. Denied is
# true only for a section whose every Require line is 'Require all denied'; a grant, another
# Require form or no Require leaves it false. Comments are skipped.
function Get-SiteSections([string[]]$lines) {
    $sections = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack
    foreach ($raw in $lines) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        if ($line -match '^<([A-Za-z]+)\s+"?([^">]*?)"?\s*>$') {
            $parent = if ($stack.Count -gt 0) { $stack.Peek() } else { $null }
            $section = @{ Type = $Matches[1]; Arg = $Matches[2]; Parent = $parent; Requires = 0; Denies = 0 }
            $null = $sections.Add($section)
            $stack.Push($section)
        } elseif ($line -match '^</[A-Za-z]+>$') {
            if ($stack.Count -gt 0) { $null = $stack.Pop() }
        } elseif ($line -match '^Require\b' -and $stack.Count -gt 0) {
            $section = $stack.Peek()
            $section.Requires++
            if ($line -cmatch '^Require\s+all\s+denied$') { $section.Denies++ }
        }
    }
    foreach ($section in $sections) { $section.Denied = ($section.Requires -gt 0 -and $section.Denies -eq $section.Requires) }
    return , $sections
}

# Apache regex sections match case-sensitively; an invalid pattern matches nothing.
function Test-SiteMatch([string]$pattern, [string]$value) {
    try { return [regex]::IsMatch($value, $pattern) } catch { return $false }
}

# Whether the last of $candidates that matches $value (and has Require lines) denies it, the way
# Apache's later sections override earlier ones. A plain Location matches by prefix.
function Test-LastDenies($candidates, [string]$value) {
    $denied = $false
    foreach ($section in $candidates) {
        if ($section.Requires -eq 0) { continue }
        $hit = if ($section.Type -ceq "Location") { $value.StartsWith($section.Arg, [System.StringComparison]::Ordinal) } else { Test-SiteMatch $section.Arg $value }
        if ($hit) { $denied = $section.Denied }
    }
    return $denied
}

# Whether the site text denies, for the server folder $path, everything Core's setup-web
# denies: .git, client/ports/docs/config/lib/sql/scripts as folders and URLs, and config.json
# and .env as files and URLs. Each probe must be denied by the last matching section, so old
# three-folder rules, rules for a similar name, and grants after the denials do not count.
function Test-SiteProtects([string[]]$lines, [string]$path) {
    $rel = $path.Substring("/var/www/html/".Length)
    $sections = Get-SiteSections $lines
    $dirs = @($sections | Where-Object { $_.Type -ceq "DirectoryMatch" -and $null -eq $_.Parent })
    $vhost = @($sections | Where-Object { $_.Type -ceq "VirtualHost" -and $null -eq $_.Parent })
    if ($vhost.Count -ne 1) { return $false }
    $locations = @($sections | Where-Object { ($_.Type -ceq "Location" -or $_.Type -ceq "LocationMatch") -and $_.Parent -eq $vhost[0] })
    foreach ($folder in @(".git", "client", "ports", "docs", "config", "lib", "sql", "scripts")) {
        if (-not (Test-LastDenies $dirs "$path/$folder")) { return $false }
        if (-not (Test-LastDenies $dirs "$path/$folder/sub")) { return $false }
        foreach ($url in @("/$rel/$folder", "/$rel/$folder/", "/$rel/$folder/x")) {
            if (-not (Test-LastDenies $locations $url)) { return $false }
        }
    }
    foreach ($file in @("config.json", ".env")) {
        $files = @($sections | Where-Object { $_.Type -ceq "FilesMatch" -and $null -ne $_.Parent -and $dirs -contains $_.Parent -and (Test-SiteMatch $_.Parent.Arg $path) })
        if (-not (Test-LastDenies $files $file)) { return $false }
        foreach ($url in @("/$rel/$file", "/$rel/sub/$file")) {
            if (-not (Test-LastDenies $locations $url)) { return $false }
        }
    }
    return $true
}

# The Core site file's lines, read once without root; $null when it is missing or unreadable.
function Get-ProtectedSite {
    if (-not $script:siteRead) {
        $script:siteRead = $true
        $script:siteLines = @(Invoke-Native { & wsl.exe -d $WslDistro -e cat $protectedSite })
        if ($LASTEXITCODE -ne 0) { $script:siteLines = $null }
    }
    return $script:siteLines
}

# Whether Core's generated rules protect $path (a fixed route or one named to setup-web).
function Test-ProtectedFolder([string]$path) {
    $lines = Get-ProtectedSite
    return ($null -ne $lines -and (Test-SiteProtects $lines $path))
}

# Distro names from 'wsl -l -q' (all) or 'wsl --list --running --quiet' (running): names
# only, so nothing depends on the Windows display language. Listing never starts a distro.
# Returns $null without wsl.exe, else @{ Code = exit code; Names = names, used only on 0 }.
function Get-WslNames([string[]]$listArgs) {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $null }
    $lines = @(Invoke-Native { & wsl.exe @listArgs })
    $code = $LASTEXITCODE
    return @{ Code = $code; Names = @($lines | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ }) }
}

function Require-WslTarget {
    if (-not $WslDistro -or -not $WslServerPath) {
        throw "This option needs both -WslDistro <name> and -WslServerPath <path to the existing server checkout>."
    }
    Test-WslServerPath $WslServerPath
    $distros = Get-WslNames @("-l", "-q")
    if ($null -eq $distros) { throw "wsl.exe not found, so WSL distro '$WslDistro' cannot be used." }
    if ($distros.Code -ne 0) { throw "Could not list WSL distros ('wsl -l -q' exit $($distros.Code)), so '$WslDistro' was not checked." }
    if ($distros.Names -notcontains $WslDistro) {
        throw "WSL distro '$WslDistro' was not found. Run 'wsl -l -q' to list distros."
    }
    # The path is passed to sh as an argument, never interpolated; the pattern above allows no
    # spaces or shell characters, so $1 needs no quotes (Windows PowerShell mangles embedded quotes).
    Invoke-Native { & wsl.exe -d $WslDistro -e sh -c 'test -d $1 && ! test -L $1 && test -d $1/.git && test -f $1/dwemer-mod.json && test -f $1/scripts/install.sh' sh $WslServerPath } | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "No server checkout at $WslServerPath in $WslDistro (it must be an existing Git clone, not a link). Put the committed project there with this script's 'deploy' or clone it as SETUP.md describes; this check copies and adopts nothing."
    }
}

# Whether Core's current rules are present, judged on its fixed KagrenacServer route; the
# -WslServerPath folder is checked separately. A missing site file means "not protected".
function Test-WebProtection {
    return (Test-ProtectedFolder "/var/www/html/custom-mods/KagrenacServer")
}

function Get-HttpStatus([string]$url) {
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0
        $body = $response.Content
        if ($body -is [byte[]]) { $body = [System.Text.Encoding]::UTF8.GetString($body) }
        return @{ Status = [int]$response.StatusCode; Body = [string]$body }
    } catch {
        $r = $_.Exception.Response
        if ($r) { return @{ Status = [int]$r.StatusCode; Body = "" } }
        return @{ Status = 0; Body = "" }
    }
}

function Test-BuildRoot {
    $full = [System.IO.Path]::GetFullPath($BuildRoot).TrimEnd('\')
    $repoFull = [System.IO.Path]::GetFullPath($repo).TrimEnd('\')
    if ($full -like "\\*" -or $full -eq $repoFull -or $full.StartsWith($repoFull + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing build folder '$full': build output must stay outside the repository and outside any WSL or network path."
    }
}

function Invoke-ClientBuild {
    Test-BuildRoot
    $build = Join-Path $repo "client\scripts\build.ps1"
    $output = @(Invoke-Native { & powershell -NoProfile -ExecutionPolicy Bypass -File $build -BuildRoot $BuildRoot } | ForEach-Object { Write-Host $_; $_ })
    $code = $LASTEXITCODE
    if ($code -ne 0) { Fail "Client build failed (client\scripts\build.ps1, exit $code)."; return }
    $warnings = @($output | Where-Object { "$_" -match ': warning [A-Z]+[0-9]+' }).Count
    if ($warnings -gt 0) { Fail "Client build reported $warnings warning line(s); the build must have no warnings." }
    else { Say "OK" "Client built for x64 and x86 in $BuildRoot (no warnings in files compiled this run)." }
    $script:done.Add("Client build (x64, x86) in $BuildRoot")
}

# The native port whose own route builds this project's game side: -Engine when given, else the
# engine 'new -Engine' wrote into this project's PROJECT.md Paths (projects\<id>\<engine>\<part>).
# "" for a project without one, which keeps the console client checks.
function Get-NativeEngine {
    if ($Engine) {
        if ($Engine -cnotmatch '^[a-z0-9][a-z0-9-]{0,39}\z' -or -not (Test-Path -LiteralPath (Join-Path $repo "ports\$Engine") -PathType Container)) {
            throw "-Engine must name an existing folder under ports/ (lowercase letters, digits and hyphens)."
        }
        return $Engine
    }
    if (-not (Test-ProjectId $workingId) -or $workingId -ceq "example-server") { return "" }
    $project = ""
    try { $project = [System.IO.File]::ReadAllText((Join-Path $repo "PROJECT.md")) } catch { }
    if ($project -cnotmatch ('\\projects\\' + [regex]::Escape($workingId) + '\\([a-z0-9][a-z0-9-]{0,39})\\<part>')) { return "" }
    $name = $Matches[1]
    if (-not (Test-Path -LiteralPath (Join-Path $repo "ports\$name") -PathType Container)) {
        Say "WARN" "PROJECT.md names the game-side port $name, but ports/$name is missing; pass -Engine <port folder> to name it."
        return ""
    }
    Say "INFO" "Game-side port $name, from this project's PROJECT.md Paths (pass -Engine <port folder> to name another)."
    return $name
}

# A native port builds, assembles and pairs its game side through its own route, so the console
# client is not part of it (KagrenacClient.exe stays an optional developer check).
function Show-NativeRoute([string]$name) {
    Say "INFO" "Game side: the native $name port. It needs no console client; KagrenacClient.exe, 'setup' and its config.json are optional developer checks and were not checked."
    if ($workingId -ceq "example-server") {
        Say "INFO" "This is the template: make the mod its own project first (project.ps1 new -Engine $name), then run its route from that copy."
    } elseif (Test-Path -LiteralPath (Join-Path $repo "ports\$name\mod.ps1") -PathType Leaf) {
        Say "INFO" "Next for the game side: powershell -ExecutionPolicy Bypass -File ports\$name\mod.ps1 doctor (options in ports/$name/README.md), then its build and pairing route (docs/PORT_BUILD_RECORDS.md)."
    } else {
        Say "WARN" "ports/$name has no maintained route (mod.ps1); qualify its PLAN.md using docs/ENGINE_PLANNING.md, then implement its build and pairing route."
    }
}

function Show-Doctor {
    Say "INFO" "Repository: $repo"
    foreach ($path in @("dwemer-mod.json", "PROTOCOL.md", "client\CMakeLists.txt", "client\scripts\build.ps1")) {
        if (-not (Test-Path -LiteralPath (Join-Path $repo $path))) { Fail "Missing $path; is this a KAGRENAC AI Mod Maker checkout?" }
    }
    foreach ($tool in @("git", "php", "cmake")) {
        $found = Get-Command $tool -ErrorAction SilentlyContinue
        if ($found) { Say "OK" "$tool found: $($found.Source)" } else { Say "INFO" "$tool not on PATH" }
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $vs = @(Invoke-Native { & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath })
        if ($LASTEXITCODE -ne 0) { Say "WARN" "vswhere.exe failed (exit $LASTEXITCODE); Visual Studio was not checked." }
        elseif ($vs.Count -gt 0 -and $vs[0]) { Say "OK" "Visual Studio with C++ tools: $($vs[0])" }
        else { Say "WARN" "Visual Studio found without the C++ tools; the client build needs 'Desktop development with C++'." }
    } elseif (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        Say "WARN" "No Visual Studio installer or CMake found; the client build needs Visual Studio 2022 with C++ tools."
    }
    $gitBash = Get-GitBash
    if ($gitBash) { Say "OK" "Git Bash found (for shell syntax checks): $gitBash" } else { Say "INFO" "Git Bash not found; check skips shell syntax." }

    Show-Distro
    # This project's own install (Core's registry when the distro is running, else the manifest).
    $ownPath = Get-OwnServerPath $script:distroRunning
    if ($ownPath) { $script:defaultUrl = "http://127.0.0.1:19000" + $ownPath.Substring("/var/www/html".Length) }

    $native = Get-NativeEngine
    if ($native) {
        Show-NativeRoute $native
    } else {
        foreach ($arch in @("x64", "x86")) {
            $exe = Join-Path $BuildRoot "$arch\Release\KagrenacClient.exe"
            if (Test-Path -LiteralPath $exe) {
                $version = @(Invoke-Native { & $exe --version })
                if ($LASTEXITCODE -eq 0 -and $version.Count -gt 0) { Say "OK" "Client $arch built: $(Get-Printable $version[0])" }
                else { Fail "Client $arch at $exe did not answer --version (exit $LASTEXITCODE)." }
            } else {
                Say "INFO" "Client $arch not built yet ($exe); run 'setup'."
            }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $repo "client\config.json")) {
        Say "WARN" "client\config.json exists in the repository; keep the private config outside it (next to the built exe, or in the game runtime)."
    }
    $url = $ServerUrl
    $configPath = Join-Path $BuildRoot "x64\Release\config.json"
    if ($native) {
        # A native port's private config lives in its game runtime; its own doctor reports it.
    } elseif (Test-Path -LiteralPath $configPath) {
        $config = $null
        try { $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json } catch { }
        if ($config -is [System.Management.Automation.PSCustomObject]) {
            $hasToken = [bool]($config.token -and ([string]$config.token).Length -gt 0)
            $configUrl = $null
            if ($config.server_url) { $configUrl = ConvertTo-BaseUrl ([string]$config.server_url) }
            $shownUrl = $(if (-not $config.server_url) { "(default)" } elseif ($configUrl) { $configUrl } else { "invalid (not shown)" })
            Say "INFO" ("Client config found: server_url {0}, token {1}" -f $shownUrl, $(if ($hasToken) { "set (not shown)" } else { "missing" }))
            if ($config.server_url -and -not $configUrl) { Fail "Client config server_url is not an http(s) base URL without credentials, query or fragment; pair the client again." }
            if (-not $url) { $url = $configUrl }
        } else {
            Fail "Client config $configPath is not a valid JSON object."
        }
    } else {
        Say "INFO" "No client config.json next to the x64 exe yet; pair it as SETUP.md section 3 describes."
    }
    if (-not $url) { $url = $defaultUrl }
    $health = Get-HttpStatus "$url/health.php"
    $h = $null
    if ($health.Status -eq 200) { try { $h = $health.Body | ConvertFrom-Json } catch { } }
    $script:serverState = "problem at $url (see above)"
    if ($health.Status -eq 0) {
        $script:serverState = "no answer at $url"
        Say "WARN" "No answer from $url/health.php (refused, or nothing within 5 seconds). Start DwemerDistro, or pass -ServerUrl. Exposure was not checked."
    } elseif ($health.Status -ne 200) {
        Fail "$url/health.php answered HTTP $($health.Status), not 200 (redirects are not followed). Exposure was not checked."
    } elseif (-not ($h -is [System.Management.Automation.PSCustomObject] -and $h.ok -is [bool] -and $h.ok -and $h.service -is [string] -and $h.service -ceq $serviceId)) {
        Fail "$url/health.php is not KagrenacServer health JSON with ok true and service $serviceId. Exposure was not checked."
    } else {
        Say "OK" ("Server at {0}: ok=true, service={1}, schema={2}, server_version={3}, protocol={4}" -f $url, $serviceId, (Get-Printable $h.schema), (Get-Printable $h.server_version), (Get-Printable $h.protocol))
        Say "INFO" "Health shows only that this server answers; it does not check the LLM, voice services or any game."
        $denied = 0
        $probes = @(".git/HEAD", "client/CMakeLists.txt", "docs/getting-started.md", "ports/README.md")
        foreach ($probe in $probes) {
            $status = (Get-HttpStatus "$url/$probe").Status
            if ($status -eq 403) { $denied++; Say "OK" "$url/$probe is denied (HTTP 403)." }
            elseif ($status -eq 200) { Fail "$url/$probe is served (HTTP 200). Install DwemerDistro Core's web protection (SETUP.md) or add equivalent rules for this folder." }
            else {
                $script:failures++
                Say "UNVERIFIED" ("$url/$probe answered {0}; only HTTP 403 shows it is protected." -f $(if ($status -eq 0) { "with no status (no answer, or a redirect)" } else { "HTTP $status" }))
            }
        }
        $script:serverState = "healthy at $url; " + $(if ($denied -eq $probes.Count) { "all $denied exposure probes denied (HTTP 403)" } else { "$($probes.Count - $denied) of $($probes.Count) exposure probes not denied (see above)" })
        Say "INFO" "Exposure was checked on this URL's listener only; check every other Apache port that serves /var/www/html too."
    }
    if ($WslDistro -and $WslServerPath) {
        if (-not $script:distroRunning) {
            Say "SKIP" "Server checkout $WslServerPath was not checked: $WslDistro is not confirmed running."
        } else {
            $found = $true
            try { Require-WslTarget } catch { $found = $false; Fail $_.Exception.Message }
            if ($found) {
                Say "OK" "Server checkout found at $WslServerPath in $WslDistro."
                $null = Invoke-Native { & wsl.exe -d $WslDistro -e test -f "$WslServerPath/config/config.php" }
                if ($LASTEXITCODE -eq 0) { Say "OK" "Server private config exists (contents not read)." } else { Say "INFO" "No config/config.php yet; scripts/install.sh creates it." }
                if (Test-ProtectedFolder $WslServerPath) { Say "OK" "$protectedSite has Core's full folder and file denials for $WslServerPath (rules read only; the HTTP 403 checks are the evidence)." }
                else { Say "WARN" "$protectedSite does not fully deny $WslServerPath's .git, client, ports, docs, config, lib, sql, scripts, config.json and .env; have Core's setup-web protect this route or add equivalent Apache rules." }
                Show-ConfigSaves $WslServerPath
            }
        }
    } elseif ($WslDistro -and (Test-ProjectId $workingId) -and $workingId -cne "example-server") {
        # This project's own install, found above; the template guesses no mod.
        if (-not $script:distroRunning) {
            Say "SKIP" "Dashboard saves in $ownPath were not checked: $WslDistro is not confirmed running."
        } else {
            $null = Invoke-Native { & wsl.exe -d $WslDistro -e test -d $ownPath }
            if ($LASTEXITCODE -ne 0) { Say "SKIP" "No install of $workingId at $ownPath in $WslDistro yet ('deploy' makes it); dashboard saves were not checked." }
            else { Show-ConfigSaves $ownPath }
        }
    }
    Show-AiServices
    Write-Host ""
    Write-Host "Readiness (exit 0 only means no FAIL or UNVERIFIED line above; WARN, SKIP and unchecked items still need action, and it never means the AI is ready):"
    Write-Host "  - DwemerDistro: $script:distroState"
    Write-Host "  - KagrenacServer: $script:serverState"
    if ($native) { Write-Host "  - Game side ($native): not checked by this doctor; its own route's doctor reports the game build, build, runtime and pairing." }
    Write-Host "  - LLM: not tested by doctor ($script:llmState). Ready only after the dashboard LLM page's Send test, or 'configure -TestProviders', returns a real reply."
    Write-Host "  - Voice (PocketTTS): not tested by doctor ($script:ttsState). Ready only after the dashboard Voice page's Speak is heard."
}

# Whether the dashboard can save the install's private config, judged as www-data by that
# install's own lib/config_writer.php. It only checks files, ownership and modes; the config is
# never read or loaded. Called only for a running distro; changes nothing.
function Show-ConfigSaves([string]$path) {
    $null = Invoke-Native { & wsl.exe -d $WslDistro -u www-data -e test -r "$path/lib/config_writer.php" }
    if ($LASTEXITCODE -ne 0) {
        $script:failures++
        Say "UNVERIFIED" "Dashboard saves in $path were not checked: www-data cannot read its lib/config_writer.php (an older install, or no access)."
        return
    }
    # No double quotes: Windows PowerShell 5.1 does not escape them for native arguments.
    $php = 'require $argv[1] . ''/lib/config_writer.php''; foreach (config_write_problems($argv[1] . ''/config/config.php'') as $p) echo $p, PHP_EOL;'
    $out = @(Invoke-Native { & wsl.exe -d $WslDistro -u www-data -e php -d display_errors=0 -d log_errors=0 -r $php $path })
    $code = $LASTEXITCODE
    $problems = @($out | Where-Object { $_ -cmatch '^[\x20-\x7e]{1,300}$' })
    if ($code -ne 0) {
        $script:failures++
        Say "UNVERIFIED" "Dashboard saves in $path were not checked: www-data could not run lib/config_writer.php (php exit $code)."
    } elseif ($problems.Count -ne @($out | Where-Object { "$_" -ne "" }).Count) {
        $script:failures++
        Say "UNVERIFIED" "Dashboard saves in $path were not checked: lib/config_writer.php printed output this script cannot safely show."
    } elseif ($problems.Count -eq 0) {
        Say "OK" "www-data can save $path/config/config.php from the dashboard (file checks only; contents not read)."
    } else {
        foreach ($p in $problems) { Say "INFO" "Dashboard save, as www-data: $p" }
        Fail "The dashboard cannot save $path/config/config.php. $(Get-ConfigRepairHint $path)"
    }
}

# How an install whose config www-data cannot save is repaired; never a chmod or chown by hand.
function Get-ConfigRepairHint([string]$path) {
    return "Run 'project.ps1 deploy -WslDistro $WslDistro' to repair it (also after the launcher's Update or 'ddistro_custom_mod update'); for a manual install run 'sudo bash $path/scripts/install.sh'."
}

# Reports the WSL distros with their state, and checks the one named by -WslDistro only when
# it is already running. Read-only; never starts, stops or installs anything.
function Show-Distro {
    $install = "Install DwemerDistro with its official installer, then start it from the DwemerDistro launcher; this script installs nothing."
    $all = Get-WslNames @("-l", "-q")
    if ($null -eq $all) { $script:distroState = "not installed (no WSL)"; Say "WARN" "wsl.exe not found, so DwemerDistro is not installed. $install"; return }
    if ($all.Code -ne 0) {
        $script:distroState = "unknown ('wsl -l -q' exit $($all.Code))"
        Say "WARN" "Could not list WSL distros ('wsl -l -q' exit $($all.Code)), so whether DwemerDistro is installed is unknown. If WSL has no distros yet: $install"
        return
    }
    if ($all.Names.Count -eq 0) { $script:distroState = "not installed (no WSL distros)"; Say "WARN" "No WSL distros listed, so DwemerDistro is not installed. $install"; return }
    $running = Get-WslNames @("--list", "--running", "--quiet")
    if ($running.Code -eq 0) {
        Say "OK" ("WSL distros: " + (($all.Names | ForEach-Object { "$_ ($(if ($running.Names -contains $_) { 'running' } else { 'not running' }))" }) -join ", "))
    } else {
        Say "OK" ("WSL distros: " + ($all.Names -join ", "))
        Say "WARN" "Could not list running WSL distros ('wsl --list --running --quiet' exit $($running.Code)); which are running is unknown."
    }
    if (-not $WslDistro) {
        $script:distroState = "not checked (name it with -WslDistro <name>)"
        Say "INFO" "Name your DwemerDistro with -WslDistro <name> to check its runtime. Doctor never starts a stopped distro."
        return
    }
    if ($all.Names -notcontains $WslDistro) {
        $script:distroState = "'$WslDistro' not found"
        Fail "WSL distro '$WslDistro' was not found. Check the name in the list above; if DwemerDistro is missing: $install"
        return
    }
    if ($running.Code -ne 0) {
        $script:distroState = "'$WslDistro' listed; running state unknown, runtime not checked"
        Say "WARN" "Whether $WslDistro is running is unknown, so its runtime and web protection were not checked; doctor does not start it."
        return
    }
    if ($running.Names -notcontains $WslDistro) {
        $script:distroState = "'$WslDistro' is not running; runtime not checked"
        Say "WARN" "$WslDistro is not running. Start DwemerDistro from its launcher; doctor did not start it, so its runtime and web protection were not checked."
        return
    }
    $script:distroRunning = $true
    Say "OK" "$WslDistro is running."
    $null = Invoke-Native { & wsl.exe -d $WslDistro -e sh -c 'command -v ddistro_custom_mod' }
    $core = ($LASTEXITCODE -eq 0)
    if ($core) { Say "OK" "DwemerDistro Core tool ddistro_custom_mod is present." }
    else { Say "WARN" "ddistro_custom_mod not found in $WslDistro; it may not be DwemerDistro, or Core needs Update Distro." }
    $down = @()
    $unchecked = @()
    foreach ($process in @("apache2", "postgres")) {
        $null = Invoke-Native { & wsl.exe -d $WslDistro -e pgrep -x $process }
        if ($LASTEXITCODE -eq 0) { Say "OK" "$process is running in $WslDistro." }
        elseif ($LASTEXITCODE -eq 1) { $down += $process; Say "WARN" "$process is not running in $WslDistro; start DwemerDistro's services from its launcher." }
        else { $unchecked += $process; Say "WARN" "Could not check $process in $WslDistro (pgrep exit $LASTEXITCODE); whether it runs is unknown." }
    }
    $protected = Test-WebProtection
    if ($protected) { Say "OK" "Core web protection rules are present in $protectedSite." }
    else { Say "WARN" "Core web protection rules are missing from $protectedSite; update DwemerDistro Core and run 'sudo ddistro_custom_mod setup-web' before installing or updating." }
    $gaps = @()
    if (-not $core) { $gaps += "Core tool missing" }
    if ($down.Count -gt 0) { $gaps += ("not running: " + ($down -join ", ")) }
    if ($unchecked.Count -gt 0) { $gaps += ("not checked: " + ($unchecked -join ", ")) }
    if (-not $protected) { $gaps += "web protection missing" }
    $script:distroState = "'$WslDistro' running" + $(if ($gaps.Count -gt 0) { "; " + ($gaps -join "; ") } else { "; Core tool, Apache, PostgreSQL and web protection present" })
}

# The default local LLM and PocketTTS addresses. Any HTTP status only shows that something
# answers there; it is not a model or speech test, so it is never reported as working.
function Get-AiServiceState([string]$label, [string]$serviceUrl) {
    $status = (Get-HttpStatus $serviceUrl).Status
    $state = $(if ($status -eq 0) { "nothing answers at $serviceUrl" } else { "something answers at $serviceUrl (HTTP $status)" })
    Say "INFO" "$label`: $state (answering is not the same as working)."
    return $state
}

function Show-AiServices {
    $script:llmState = Get-AiServiceState "Local port 1234 (the dwemerllm default in CONNECTORS.md)" "http://127.0.0.1:1234/"
    $script:ttsState = Get-AiServiceState "PocketTTS default" "http://127.0.0.1:8086/"
    Say "INFO" "A cloud LLM (OpenRouter, OpenAI), or a service at another address, is not checked here and needs nothing on port 1234; only the dashboard tests named below show readiness."
}

function Get-GitBash {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    # git.exe lives in <Git>\cmd, <Git>\bin or <Git>\mingw64\bin; never fall back to
    # System32\bash.exe (WSL).
    $root = Split-Path -Parent (Split-Path -Parent $git.Source)
    foreach ($candidate in @($root, (Split-Path -Parent $root))) {
        $bash = Join-Path $candidate "bin\bash.exe"
        if (Test-Path -LiteralPath $bash) { return $bash }
    }
    return $null
}

# Server PHP files only: never descends into .git/, client/, docs/ or ports/ at the root, or
# into dependency, build or linked folders anywhere.
function Get-ServerPhpFiles {
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $pending = New-Object System.Collections.Generic.Queue[System.IO.DirectoryInfo]
    $root = Get-Item -LiteralPath $repo
    $pending.Enqueue($root)
    while ($pending.Count -gt 0) {
        $dir = $pending.Dequeue()
        foreach ($item in $dir.GetFileSystemInfos()) {
            if ($item -is [System.IO.FileInfo]) {
                if ($item.Extension -eq ".php") { $files.Add($item) }
            } elseif (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
                      @("node_modules", "vendor", "build", "out", ".vs") -notcontains $item.Name -and
                      -not ($dir.FullName -eq $root.FullName -and @(".git", "client", "docs", "ports") -contains $item.Name)) {
                $pending.Enqueue($item)
            }
        }
    }
    return ,$files
}

function Invoke-StaticChecks {
    $php = Get-Command php -ErrorAction SilentlyContinue
    if ($php) {
        $files = Get-ServerPhpFiles
        $bad = 0
        foreach ($file in $files) {
            $out = @(Invoke-Native { & $php.Source -l $file.FullName })
            if ($LASTEXITCODE -ne 0) { $bad++; $out | ForEach-Object { Write-Host $_ } }
        }
        if ($bad -eq 0) { Say "OK" "php -l passed for $($files.Count) server files." } else { Fail "php -l failed for $bad file(s)." }
        $script:done.Add("PHP lint ($($files.Count) server files, local PHP)")
    } else {
        Say "SKIP" "PHP lint: php is not on PATH on Windows. Run the AGENTS.md lint inside the WSL server checkout."
        $script:manual.Add("PHP lint inside WSL")
    }
    $bash = Get-GitBash
    if ($bash) {
        $bad = 0
        $scripts = @(Get-ChildItem -Path (Join-Path $repo "scripts\*.sh") -File)
        foreach ($file in $scripts) {
            Invoke-Native { & $bash -n $file.FullName } | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { $bad++ }
        }
        if ($bad -eq 0) { Say "OK" "bash -n passed for $($scripts.Count) scripts." } else { Fail "bash -n failed for $bad script(s)." }
        $script:done.Add("Shell syntax ($($scripts.Count) scripts, Git Bash)")
    } else {
        Say "SKIP" "Shell syntax: Git Bash not found."
        $script:manual.Add("bash -n scripts/*.sh")
    }
}

function Get-RouteUrl {
    if ($ServerUrl) { return $ServerUrl }
    return "http://127.0.0.1:19000" + $WslServerPath.Substring("/var/www/html".Length)
}

# The client config destination: a full path on a local fixed disk, outside this repository
# and any other Git checkout, in an existing folder with no links or junctions above it. An
# existing entry there must be a plain file. Returns the full path.
function Resolve-PairOutFile {
    $refuse = "Refusing -OutFile: use a full local path such as C:\Users\<you>\KagrenacClient\config.json (drive letter and backslashes, with no '.', '..', stream, link or network path)."
    if ($OutFile -cnotmatch '^[A-Za-z]:\\[^\x00-\x1f"*/:<>?|]+\z') { throw $refuse }
    $full = [System.IO.Path]::GetFullPath($OutFile)
    if ($full -ne $OutFile -or $full.EndsWith('\')) { throw $refuse }
    $drive = New-Object System.IO.DriveInfo $full.Substring(0, 1)
    if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) { throw "Refusing -OutFile on $($drive.Name): only a local fixed disk is allowed, not a $($drive.DriveType) drive." }
    $repoFull = [System.IO.Path]::GetFullPath($repo).TrimEnd('\')
    if ($full.StartsWith($repoFull + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing -OutFile inside the repository; the token must stay outside source and web folders."
    }
    $parent = Split-Path -Parent $full
    if (-not [System.IO.Directory]::Exists($parent)) { throw "The folder $parent does not exist; create it first (pair creates no folders)." }
    for ($dir = New-Object System.IO.DirectoryInfo $parent; $dir; $dir = $dir.Parent) {
        if ($dir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Refusing -OutFile: $($dir.FullName) is a link or junction; choose a folder reached without one." }
        if (Test-Path -LiteralPath (Join-Path $dir.FullName ".git")) { throw "Refusing -OutFile inside the Git checkout $($dir.FullName); the token must stay outside source and web folders." }
    }
    # FileInfo.Attributes is -1 only when nothing is there; a dangling link still has attributes.
    $attributes = (New-Object System.IO.FileInfo $full).Attributes
    if ([int]$attributes -ne -1 -and ($attributes -band ([System.IO.FileAttributes]::Directory -bor [System.IO.FileAttributes]::ReparsePoint))) {
        throw "Refusing -OutFile: $full exists and is a folder or link, not a plain file. Nothing was changed."
    }
    return $full
}

# The only identities allowed on the client config: the current user, SYSTEM, Administrators.
function Get-PrivateSids {
    return @(@([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value, "S-1-5-18", "S-1-5-32-544") | Select-Object -Unique)
}

# Replaces only the DACL (never owner or audit, which would need SeSecurityPrivilege): no
# inherited entries, full control for exactly the private identities.
function Set-PrivateAcl([System.IO.FileInfo]$file) {
    $security = New-Object System.Security.AccessControl.FileSecurity
    $security.SetAccessRuleProtection($true, $false)
    foreach ($sid in Get-PrivateSids) {
        $identity = New-Object System.Security.Principal.SecurityIdentifier $sid
        $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($identity, "FullControl", "Allow")))
    }
    $file.SetAccessControl($security)
}

# True only for a protected DACL with one non-inherited Allow FullControl entry per private identity.
function Test-PrivateAcl([System.IO.FileInfo]$file) {
    $acl = $file.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    if (-not $acl.AreAccessRulesProtected) { return $false }
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    $sids = Get-PrivateSids
    if ($rules.Count -ne $sids.Count) { return $false }
    $seen = @()
    foreach ($rule in $rules) {
        if ($rule.IsInherited -or $rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or
            $rule.FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl) { return $false }
        $seen += $rule.IdentityReference.Value
    }
    return (@($sids | Where-Object { $seen -notcontains $_ }).Count -eq 0)
}

# A plain file of at most 64 KiB, read into memory. Callers never print the bytes.
function Read-SmallFile([string]$path) {
    if ((Get-Item -LiteralPath $path -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "$path is a link, not a plain file." }
    $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        if ($stream.Length -gt 65536) { throw "$path is larger than 64 KiB, so it is not a client config." }
        $bytes = New-Object byte[] $stream.Length
        $read = 0
        while ($read -lt $bytes.Length) {
            $n = $stream.Read($bytes, $read, $bytes.Length - $read)
            if ($n -le 0) { throw "$path changed while it was read." }
            $read += $n
        }
        return ,$bytes
    } finally { $stream.Dispose() }
}

# A JSON object from UTF-8 bytes, or $null. Parser errors are dropped unseen: they can quote the text.
function ConvertFrom-PairJson([byte[]]$bytes) {
    $value = $null
    try { $value = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) | ConvertFrom-Json } catch { return $null }
    if ($value -is [System.Management.Automation.PSCustomObject]) { return $value }
    return $null
}

# 1-8 different action names (case-sensitive) of 1-40 characters A-Z a-z 0-9 _, as in PROTOCOL.md.
function Test-ActionNames([object[]]$names) {
    if ($names.Count -lt 1 -or $names.Count -gt 8) { return $false }
    $unique = New-Object System.Collections.Generic.HashSet[string]
    foreach ($name in $names) {
        if (-not ($name -is [string] -and $name -cmatch '^[A-Za-z0-9_]{1,40}\z' -and $unique.Add($name))) { return $false }
    }
    return $true
}

function Get-Sha256([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.Convert]::ToBase64String($sha.ComputeHash($bytes)) } finally { $sha.Dispose() }
}

# Creates $path (it must not exist) empty, makes and checks it private, and only then writes
# $bytes and compares the copy by SHA-256. On any failure the file this call created is deleted.
function Write-PrivateFile([string]$path, [byte[]]$bytes) {
    $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $ok = $false
    try {
        $file = New-Object System.IO.FileInfo $path
        Set-PrivateAcl $file
        if (-not (Test-PrivateAcl $file)) { throw "$path could not be limited to you, SYSTEM and Administrators; it was removed and nothing was written." }
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $stream.Position = 0
        $copy = New-Object byte[] $bytes.Length
        $read = 0
        while ($read -lt $copy.Length) {
            $n = $stream.Read($copy, $read, $copy.Length - $read)
            if ($n -le 0) { break }
            $read += $n
        }
        $same = ($read -eq $bytes.Length -and $stream.Length -eq $bytes.Length -and (Get-Sha256 $copy) -ceq (Get-Sha256 $bytes))
        [System.Array]::Clear($copy, 0, $copy.Length)
        if (-not $same) { throw "The copy at $path did not match the source (SHA-256); it was removed." }
        $ok = $true
    } finally {
        $stream.Dispose()
        if (-not $ok) { [System.IO.File]::Delete($path) }
    }
}

# SHA-256 of a file as lowercase hex, the form build.json and runtime.json record.
function Get-FileSha256Hex([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($path)
    try { return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) } finally { $stream.Dispose(); $sha.Dispose() }
}

# Throws unless $path and every folder above it are reached without a junction or link.
function Assert-NoReparse([string]$path) {
    for ($item = Get-Item -LiteralPath $path -Force; $item; $item = $(if ($item -is [System.IO.DirectoryInfo]) { $item.Parent } else { $item.Directory })) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Refusing $path`: $($item.FullName) is a link or junction." }
    }
}

# A JSON object from a record file of at most 1 MiB reached without links, or $null.
function Read-JsonRecord([string]$path) {
    $file = New-Object System.IO.FileInfo $path
    if (-not $file.Exists -or $file.Length -gt 1048576) { return $null }
    Assert-NoReparse $path
    return ConvertFrom-PairJson ([System.IO.File]::ReadAllBytes($path))
}

# Throws unless every name in $actions is one the build supports; warns for the guarded attack.
function Assert-BuildActions($record, [string[]]$actions, [string]$list) {
    $unsupported = @($actions | Where-Object { $record.Actions -cnotcontains $_ })
    if ($unsupported.Count) {
        throw ("Refusing $list $($unsupported -join ','): build $(Split-Path -Leaf $record.Dir) supports only $($record.Actions -join ', ')" +
            ". Nothing was changed.")
    }
    Say "INFO" "Build $(Split-Path -Leaf $record.Dir) supports $($actions -join ', ') (its records and files checked; candidates, none qualified in game)."
    if ($actions -ccontains "attack_hostile") {
        Say "WARN" "attack_hostile is a candidate, not qualified gameplay behavior. Follow this port's target and acceptance checks before using it."
    }
}

# The build an assembled runtime came from: the schema-2 runtime.json beside $configPath
# (docs/PORT_BUILD_RECORDS.md), checked against this project, its build and every staged
# artifact. $null when there is none; any other record is refused.
function Get-RuntimeBuild([string]$configPath) {
    $folder = Split-Path -Parent $configPath
    $record = Join-Path $folder "runtime.json"
    if ([int](New-Object System.IO.FileInfo $record).Attributes -eq -1) { return $null }
    $r = Read-JsonRecord $record
    if (-not $r -or $r.schema_version -isnot [int] -or $r.schema_version -ne 2) {
        throw "$record is not a schema-2 port runtime record (docs/PORT_BUILD_RECORDS.md); malformed and older records are not supported. Nothing was changed; pass -Build, or stage the runtime again with this project's port route."
    }
    return Get-GenericPortRuntime $folder $r
}

# The client actions pair may write: with -Build or an assembled runtime.json beside -OutFile,
# only those that build supports; a game client config without either, follow_player only; a
# console client config, any valid names as before.
function Assert-PairActions([string[]]$actions, [string]$outPath) {
    $requested = @(if ($AllowedActions.Count -gt 0) { $actions } else { "follow_player" })
    $runtime = Get-RuntimeBuild $outPath
    if ($Build -or $runtime) {
        $record = Get-GenericPortBuild $(if ($Build) { $Build } else { $runtime.Dir })
        if ($runtime -and ($record.DllSha -cne $runtime.DllSha -or [System.IO.Path]::GetFullPath($runtime.Dir).TrimEnd('\') -ne $record.Dir)) {
            throw "The runtime beside $outPath was not assembled from $($record.Dir) (its entrypoint differs). Nothing was changed; pass the build it was assembled from, or assemble again."
        }
        Assert-BuildActions $record $requested "-AllowedActions"
    } elseif ($NpcId -or $NpcName) {
        $unsupported = @($requested | Where-Object { $_ -cne "follow_player" })
        if ($unsupported.Count) {
            throw "Refusing -AllowedActions $($unsupported -join ','): a game client config allows more than follow_player only with -Build <build folder>, or an assembled runtime.json beside -OutFile, whose records support it. Nothing was changed."
        }
    }
}

# configure: see the usage at the top. Everything on Windows is checked before WSL is used.
function Invoke-Configure {
    if ($PSVersionTable.PSEdition -ne "Desktop") { throw "configure reads build records the way Windows PowerShell 5.1 does (pwsh reads their numbers differently); run it with powershell.exe, not pwsh." }
    if ($WslDistro -cnotmatch '^[A-Za-z0-9._-]{1,64}\z') { throw "configure needs -WslDistro <name> made of A-Z a-z 0-9 . _ -" }
    $own = (Test-ProjectId $workingId) -and $workingId -cne "example-server"
    if (-not $WslServerPath) {
        if (-not $own) { throw "In the template, name the install with -WslServerPath <path>; configure guesses no install." }
        $script:WslServerPath = Get-OwnServerPath $true
    }
    Test-WslServerPath $WslServerPath
    if ($LlmProvider -and @("openrouter", "dwemerllm", "mock") -cnotcontains $LlmProvider) {
        throw "configure -LlmProvider must be openrouter, dwemerllm or mock; set other modes on the dashboard LLM page."
    }
    if ($LlmProvider -and $LlmProvider -cne "mock" -and $LlmModel -cnotmatch '^[A-Za-z0-9_.:/@+-]{1,200}\z') {
        throw "-LlmProvider $LlmProvider needs -LlmModel <model> of at most 200 letters, digits and _ . : / @ + - (recommended for openrouter: google/gemma-4-31b-it)."
    }
    if ($LlmModel -and $LlmProvider -cne "openrouter" -and $LlmProvider -cne "dwemerllm") { throw "-LlmModel goes with -LlmProvider openrouter or dwemerllm." }
    if ($ReuseProviderFrom) {
        if ($LlmProvider -cne "openrouter") { throw "-ReuseProviderFrom goes only with -LlmProvider openrouter; a key is never reused for another provider." }
        if ($ReuseProviderFrom.Length -gt 300 -or $ReuseProviderFrom -cnotmatch '^(/[A-Za-z0-9_.-]+)+\.php\z' -or $ReuseProviderFrom -match '/\.\.?(/|$)') {
            throw "-ReuseProviderFrom must be the absolute Linux path of another install's private config, such as /var/www/html/<Other>Server/config/config.php or /var/www/html/custom-mods/<other id>/config/config.php."
        }
        if ($ReuseProviderFrom -ceq "$WslServerPath/config/config.php") { throw "-ReuseProviderFrom names this install's own config; leave it out to keep the key already configured." }
    }
    if ($Tts -and @("pockettts", "off") -cnotcontains $Tts) { throw "-Tts must be pockettts or off; set other voice providers on the dashboard Voice page." }
    if (($Tts -ceq "pockettts") -ne [bool]$TtsVoice -or ($TtsVoice -and $TtsVoice -cnotmatch '^[A-Za-z0-9_.:/@+-]{1,64}\z')) {
        throw "-Tts pockettts needs -TtsVoice <voice> of at most 64 letters, digits and _ . : / @ + - (for example alba), and -TtsVoice needs it."
    }
    $actions = @()
    if ($AllowedActions.Count -gt 0) {
        $actions = @(if (($AllowedActions -join ',') -cne 'none') { ($AllowedActions -join ',').Split(',') })
        if ($actions.Count -gt 0 -and -not (Test-ActionNames $actions)) { throw "-AllowedActions must be 'none' or 1-8 different action names." }
        if (($actions.Count -gt 0 -and [bool]$Build -eq [bool]$ConsoleClient) -or ($Build -and $ConsoleClient)) {
            throw "-AllowedActions needs exactly one of -Build <build folder> (a verified native build of this project) or -ConsoleClient (the console client, whose one handler is follow_player)."
        }
        if ($ConsoleClient) {
            $unsupported = @($actions | Where-Object { $_ -cne "follow_player" })
            if ($unsupported.Count) { throw "Refusing -AllowedActions $($unsupported -join ','): the console client handles only follow_player (client/src/main.cpp). Nothing was changed." }
        } elseif ($Build) {
            Assert-BuildActions (Get-GenericPortBuild $Build) $actions "-AllowedActions"
        }
    } elseif ($Build -or $ConsoleClient) {
        throw "-Build and -ConsoleClient only go with -AllowedActions."
    }
    if (-not $LlmProvider -and -not $Tts -and $AllowedActions.Count -eq 0 -and -not $TestProviders) {
        throw "configure needs -LlmProvider, -Tts, -AllowedActions or -TestProviders (usage at the top of scripts\project.ps1)."
    }
    # Voice is enabled only for a PocketTTS that answers; answering is still not a speech test.
    if ($Tts -ceq "pockettts" -and (Get-AiServiceState "PocketTTS default" "http://127.0.0.1:8086/") -like "nothing answers*") {
        throw "Voice was not enabled: nothing answers at http://127.0.0.1:8086/. Start PocketTTS from the DwemerDistro launcher first. Nothing was changed."
    }
    if ($LlmProvider -ceq "dwemerllm" -and (Get-AiServiceState "DwemerDistro LLM Studio" "http://127.0.0.1:1234/") -like "nothing answers*") {
        Say "WARN" "Nothing answers on port 1234 yet; dwemerllm replies fail until LLM Studio runs with a model loaded."
    }

    Require-WslTarget
    $helper = "$WslServerPath/scripts/configure_server.php"
    $null = Invoke-Native { & wsl.exe -d $WslDistro -u www-data -e test -r $helper }
    if ($LASTEXITCODE -ne 0) { throw "$helper is missing in $WslDistro or www-data cannot read it; deploy a commit that has it first. Nothing was changed." }
    $phpArgs = @("-d", "display_errors=0", "-d", "log_errors=0", $helper)
    if (Test-ProjectId $workingId) { $phpArgs += @("--expect-id", $workingId) }
    if ($LlmProvider) { $phpArgs += @("--llm-mode", $LlmProvider) }
    if ($LlmModel) { $phpArgs += @("--llm-model", $LlmModel) }
    if ($ReuseProviderFrom) { $phpArgs += @("--reuse-llm-key-from", $ReuseProviderFrom) }
    if ($Tts) { $phpArgs += @("--tts", $Tts) }
    if ($TtsVoice) { $phpArgs += @("--tts-voice", $TtsVoice) }
    if ($AllowedActions.Count -gt 0) { $phpArgs += @("--allowed-actions", $(if ($actions.Count) { $actions -join ',' } else { 'none' })) }
    if ($TestProviders) { $phpArgs += @("--test-providers", "--base-url", (Get-RouteUrl)) }
    Say "INFO" ("Configuring $WslServerPath in $WslDistro as www-data (this may start the distro)" + $(if ($TestProviders) { ", then one provider test (a paid provider may charge for it)." } else { "." }))
    $result = $null
    $hidden = 0
    # Only the helper's own status lines are shown; anything else could quote private values.
    Invoke-Native { & wsl.exe -d $WslDistro -u www-data -e php @phpArgs } | ForEach-Object {
        if ($_ -cmatch '^\[(OK|INFO|WARN|FAIL)\] ([\x20-\x7e]{1,600})$') { Say $Matches[1] $Matches[2] }
        elseif ($_ -cmatch '^RESULT config=(saved|unchanged) test=(run|skipped)$') { $result = $_ }
        elseif ("$_" -ne "") { $hidden++ }
    }
    $code = $LASTEXITCODE
    if ($hidden -gt 0) { Say "INFO" "$hidden other output line(s) were not shown; they may quote private values." }
    if ($code -eq 2) { Fail "www-data cannot save $WslServerPath/config/config.php, so nothing was changed. $(Get-ConfigRepairHint $WslServerPath)"; return }
    if (-not $result -or ($code -ne 0 -and $code -ne 3)) { Fail "scripts/configure_server.php stopped (exit $code) before confirming the settings; see the lines above. Nothing was saved."; return }
    $state = $(if ($result -cmatch 'config=saved') { "saved" } else { "unchanged" })
    if ($code -eq 3) {
        Fail "The provider test did not pass (see above). The settings are $state as reported; a test is never retried automatically."
    }
    $script:done.Add("configure $WslDistro`:$WslServerPath (settings $state$(if ($TestProviders) { "; provider test $(if ($code -eq 0) { 'passed: reply and WAV generated' } else { 'failed' })" }))")
    if ($TestProviders) { $script:manual.Add("Voice is ready only once someone hears it: dashboard Voice page Speak, or in game. A generated WAV is not heard.") }
    if ($actions.Count -gt 0) {
        $script:manual.Add("The client's own allowlist comes from pair -AllowedActions; each action is usable only after its own in-game check (PROJECT.md 6d rows).")
    }
}

# pair: see the usage at the top. Validates everything on Windows before touching WSL.
function Invoke-Pair {
    if ($PSVersionTable.PSEdition -ne "Desktop") { throw "pair uses the Windows PowerShell file permission API; run it with powershell.exe, not pwsh." }
    $outPath = Resolve-PairOutFile
    if ($SessionId -and $SessionId -cnotmatch '^[A-Za-z0-9_.:-]{1,64}\z') { throw "-SessionId must be 1-64 characters of A-Z a-z 0-9 _ . : -" }
    # -AllowedActions a,b arrives as one string through -File and as a list otherwise.
    $actions = @()
    if ($AllowedActions.Count -gt 0) {
        $actions = @(if (($AllowedActions -join ',') -cne 'none') { ($AllowedActions -join ',').Split(',') })
        if ($actions.Count -gt 0 -and -not (Test-ActionNames $actions)) { throw "-AllowedActions must be 'none' or 1-8 different action names." }
    }
    if ($NpcId -and $NpcId -cnotmatch '^[A-Za-z0-9_.:-]{1,64}\z') { throw "-NpcId must be 1-64 characters of A-Z a-z 0-9 _ . : -" }
    if ($NpcName -and ($NpcName -cnotmatch '^[^\x00-\x1f\x7f]{1,64}\z' -or $NpcName.Trim(' ') -cne $NpcName)) { throw "-NpcName must be 1-64 characters without control characters or a space at either end." }
    if ($WslDistro -cnotmatch '^[A-Za-z0-9._-]{1,64}\z') { throw "pair needs -WslDistro <name> made of A-Z a-z 0-9 . _ - (it is also used in the \\wsl.localhost path)." }
    $existing = [int](New-Object System.IO.FileInfo $outPath).Attributes -ne -1
    if ($existing -and -not (Test-PrivateAcl (New-Object System.IO.FileInfo $outPath))) {
        throw "$outPath already exists and is not private to you, SYSTEM and Administrators. Nothing was changed; choose a new -OutFile, or delete that file yourself if it is not needed."
    }
    Assert-PairActions $actions $outPath
    if (-not $WslServerPath -and (Test-ProjectId $workingId) -and $workingId -cne 'example-server') {
        $script:WslServerPath = Get-OwnServerPath $true
    }
    Require-WslTarget
    $null = Invoke-Native { & wsl.exe -d $WslDistro -e test -f "$WslServerPath/scripts/pair_client.php" }
    if ($LASTEXITCODE -ne 0) { throw "$WslServerPath/scripts/pair_client.php is missing in $WslDistro; update that checkout first." }
    $url = Get-RouteUrl

    # A new 0700 folder owned by dwemer under the sticky /tmp, as pair_client.php requires.
    $made = @(Invoke-Native { & wsl.exe -d $WslDistro -u dwemer -e mktemp -d /tmp/kagrenac-pair.XXXXXXXX })
    if ($LASTEXITCODE -ne 0 -or $made.Count -ne 1 -or $made[0] -cnotmatch '^/tmp/kagrenac-pair\.[A-Za-z0-9]{8}$') {
        throw "Could not create a private temporary folder as dwemer in $WslDistro (mktemp exit $LASTEXITCODE)."
    }
    $folder = $made[0]
    $source = $null
    $sourcePath = $null
    try {
        $phpArgs = @("$WslServerPath/scripts/pair_client.php", "--out", "$folder/client.json", "--base-url", $url)
        if ($SessionId) { $phpArgs += @("--session-id", $SessionId) }
        if ($AllowedActions.Count -gt 0) { $phpArgs += @("--allowed-actions", $(if ($actions.Count) { $actions -join ',' } else { 'none' })) }
        if ($NpcId) { $phpArgs += @("--npc-id", $NpcId) }
        if ($NpcName) { $phpArgs += @("--npc-name", $NpcName) }
        if ($VoiceEnabled) { $phpArgs += @("--voice-enabled", "true") }
        $output = @(Invoke-Native { & wsl.exe -d $WslDistro -u dwemer -e php @phpArgs })
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            # pair_client.php's own refusals only; PHP errors can quote config lines, so they stay hidden.
            $output | Where-Object { $_ -cmatch '^pair_client: [\x20-\x7e]{1,400}$' } | ForEach-Object { Say "INFO" $_ }
            throw "scripts/pair_client.php failed (exit $code); any other output is not shown because it may contain private values. Nothing was written on Windows."
        }
        foreach ($root in @("\\wsl.localhost\$WslDistro", "\\wsl$\$WslDistro")) {
            $candidate = $root + $folder.Replace("/", "\") + "\client.json"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $sourcePath = $candidate; break }
        }
        if (-not $sourcePath) { throw "The new file in $WslDistro`:$folder could not be reached over \\wsl.localhost; nothing was written on Windows." }
        $source = Read-SmallFile $sourcePath
        $config = ConvertFrom-PairJson $source
        $expectedActions = @(if ($AllowedActions.Count -gt 0) { $actions } else { 'follow_player' })
        $valid = $config -and $config.server_url -is [string] -and $config.server_url -ceq $url -and
            $config.token -is [string] -and $config.token.Length -ge 16 -and
            $config.session_id -is [string] -and $(if ($SessionId) { $config.session_id -ceq $SessionId } else { $config.session_id -cmatch '^[A-Za-z0-9_.:-]{1,64}\z' }) -and
            $config.timeout_seconds -is [int] -and $config.voice_enabled -is [bool] -and $config.voice_enabled -eq [bool]$VoiceEnabled -and
            $config.allowed_actions -is [array] -and
            ($config.allowed_actions.Count -eq 0 -or (Test-ActionNames @($config.allowed_actions))) -and
            (($config.allowed_actions -join ',') -ceq ($expectedActions -join ',')) -and
            $(if ($NpcId) { $config.npc_id -is [string] -and $config.npc_id -ceq $NpcId } else { $null -eq $config.npc_id }) -and
            $(if ($NpcName) { $config.npc_name -is [string] -and $config.npc_name -ceq $NpcName } else { $null -eq $config.npc_name })
        if (-not $valid) { throw "scripts/pair_client.php wrote a file that is not the expected client config (contents not shown); nothing was written on Windows." }

        if ($existing) {
            $old = $null
            $oldBytes = Read-SmallFile $outPath
            try { $old = ConvertFrom-PairJson $oldBytes } finally { [System.Array]::Clear($oldBytes, 0, $oldBytes.Length) }
            if (-not $old) { throw "$outPath already exists and is not a JSON client config (contents not shown). Nothing was changed; choose a new -OutFile, or move that file away yourself." }
            $differ = @(foreach ($name in @("server_url", "token", "session_id")) { if (-not ($old.$name -is [string] -and $old.$name -ceq $config.$name)) { $name } })
            if ($differ.Count -gt 0) {
                throw ("$outPath already holds a different pairing (different {0}; values not shown). Nothing was changed; choose a new -OutFile, or move that file away yourself and pair again." -f ($differ -join ", "))
            }
            Say "OK" "Already paired: $outPath is private and has this server's URL ($url), token and session $($config.session_id). Its voice, timeout and action settings were kept; nothing was written."
            $ignored = @(foreach ($given in @(@("-AllowedActions", ($AllowedActions.Count -gt 0)), @("-NpcId", [bool]$NpcId), @("-NpcName", [bool]$NpcName), @("-VoiceEnabled", [bool]$VoiceEnabled))) { if ($given[1]) { $given[0] } })
            if ($ignored.Count -gt 0) { Say "INFO" "$($ignored -join ', ') only shape a new file and were not applied; the existing file was kept byte for byte." }
            $script:done.Add("Pairing checked: $outPath already paired with $url")
            return
        }

        Write-PrivateFile $outPath $source
        $again = Read-SmallFile $sourcePath
        try { $same = (Get-Sha256 $again) -ceq (Get-Sha256 $source) } finally { [System.Array]::Clear($again, 0, $again.Length) }
        if (-not $same) { [System.IO.File]::Delete($outPath); throw "The source in WSL changed during the copy; $outPath was removed. Run pair again." }
        Say "OK" "Paired: wrote $outPath for $url, session $($config.session_id) (private to you, SYSTEM and Administrators; contents not shown)."
        if ($NpcId -or $NpcName) {
            Say "INFO" "It holds this server's token. Leave it in the game runtime where it was written; check it with your port's launch steps and its engine pack's acceptance (ports/<engine>/README.md), not KagrenacClient.exe."
        } else {
            Say "INFO" "It holds this server's token. Keep it next to KagrenacClient.exe as config.json, then run: KagrenacClient.exe --health"
        }
        $actionArg = $(if ($config.allowed_actions.Count) { $config.allowed_actions -join ',' } else { 'none' })
        Say "INFO" "pair sets only the client's allowed_actions. Set the server to match with 'project.ps1 configure -WslDistro $WslDistro -AllowedActions $actionArg'. Nonempty lists need -Build <build folder> or -ConsoleClient (follow_player only); none needs neither."
        $script:done.Add("Private client config $outPath paired with $url")
    } finally {
        if ($source) { [System.Array]::Clear($source, 0, $source.Length) }
        # Remove only this run's file (a regular mode-0600 file) and then its folder if empty.
        $null = Invoke-Native { & wsl.exe -d $WslDistro -u dwemer -e sh -c 'test -f $1/client.json && ! test -L $1/client.json && test $(stat -c %a $1/client.json) = 600 && rm -- $1/client.json; rmdir -- $1' sh $folder }
        if ($LASTEXITCODE -ne 0) { Say "WARN" "Could not remove the temporary folder $folder in $WslDistro; delete it there yourself (it may hold the token)." }
    }
}

# A manifest id Core accepts: 3-32 lowercase letters, digits and single hyphens.
function Test-ProjectId([string]$value) {
    return ($value -cmatch '^[a-z][a-z0-9-]{1,30}[a-z0-9]\z' -and -not $value.Contains("--"))
}

# Git in this checkout; returns the output lines and throws on failure.
function Invoke-RepoGit([string[]]$gitArgs) {
    $out = @(Invoke-Native { & git -C $repo @gitArgs })
    if ($LASTEXITCODE -ne 0) { throw "git $($gitArgs[0]) failed in $repo (exit $LASTEXITCODE)." }
    return ,$out
}

# The deploy folder for one project: private (you, SYSTEM, Administrators; protected and
# inherited by everything created inside) before anything is written, outside this repository
# and reached without links. An existing folder must already be private.
function Get-DeployDir([string]$id) {
    if ($env:LOCALAPPDATA -cnotmatch '^[A-Za-z]:\\') { throw "LOCALAPPDATA is not a local folder, so the private deploy folder cannot be made." }
    $base = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "DwemerDynamics\Kagrenac\deploy"))
    if ($base.StartsWith([System.IO.Path]::GetFullPath($repo).TrimEnd('\') + "\", [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing a deploy folder inside the repository." }
    $null = [System.IO.Directory]::CreateDirectory($base)
    for ($dir = New-Object System.IO.DirectoryInfo $base; $dir; $dir = $dir.Parent) {
        if ($dir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Refusing the deploy folder: $($dir.FullName) is a link or junction." }
    }
    $path = Join-Path $base $id
    $info = New-Object System.IO.DirectoryInfo $path
    if ([int]$info.Attributes -eq -1) {
        $security = New-Object System.Security.AccessControl.DirectorySecurity
        $security.SetAccessRuleProtection($true, $false)
        foreach ($sid in Get-PrivateSids) {
            $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule((New-Object System.Security.Principal.SecurityIdentifier $sid), "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")))
        }
        $null = [System.IO.Directory]::CreateDirectory($path, $security)
        $info.Refresh()
    }
    $isPrivate = $info.Exists -and -not ($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    if ($isPrivate) {
        $acl = $info.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        $sids = Get-PrivateSids
        $isPrivate = $acl.AreAccessRulesProtected -and $rules.Count -eq $sids.Count -and
            @($rules | Where-Object { -not $_.IsInherited -and $_.AccessControlType -eq "Allow" -and $_.FileSystemRights -eq "FullControl" -and
                $_.InheritanceFlags -eq "ContainerInherit, ObjectInherit" -and $_.PropagationFlags -eq "None" -and $sids -contains $_.IdentityReference.Value } |
                ForEach-Object { $_.IdentityReference.Value } | Select-Object -Unique).Count -eq $sids.Count
    }
    if (-not $isPrivate) { throw "$path is not a private folder (only you, SYSTEM and Administrators, not a link). Nothing was exported; fix or remove it yourself." }
    return $path
}

# Throws unless the file is a valid bundle whose only ref is HEAD at exactly $head.
function Test-Bundle([string]$file, [string]$head) {
    $heads = @(Invoke-Native { & git -C $repo bundle list-heads $file })
    $listed = $LASTEXITCODE
    $null = Invoke-Native { & git -C $repo bundle verify --quiet $file }
    if ($listed -ne 0 -or $LASTEXITCODE -ne 0 -or $heads.Count -ne 1 -or $heads[0] -cne "$head HEAD") {
        throw "$file is not a complete bundle of exactly $head. Nothing was deployed; move that file away yourself if it is not needed."
    }
}

# One bundle per commit: written under a new name, checked, made private, then renamed (never
# over an existing file). An existing bundle for the commit is checked and reused.
function Export-Bundle([string]$dir, [string]$id, [string]$head) {
    $bundle = Join-Path $dir "$id-$head.bundle"
    if ([int](New-Object System.IO.FileInfo $bundle).Attributes -eq -1) {
        $partial = Join-Path $dir ("partial-{0}.bundle" -f [System.Guid]::NewGuid().ToString("N"))
        try {
            $null = Invoke-Native { & git -C $repo bundle create --quiet $partial HEAD }
            if ($LASTEXITCODE -ne 0) { throw "git bundle create failed (exit $LASTEXITCODE); nothing was deployed." }
            Test-Bundle $partial $head
            Set-PrivateAcl (New-Object System.IO.FileInfo $partial)
            [System.IO.File]::Move($partial, $bundle)
        } finally {
            if ([System.IO.File]::Exists($partial)) { [System.IO.File]::Delete($partial) }
        }
        Say "OK" "Exported commit $head to $bundle."
    } else {
        Say "INFO" "Reusing the bundle for this commit: $bundle"
    }
    $file = New-Object System.IO.FileInfo $bundle
    if (($file.Attributes -band ([System.IO.FileAttributes]::Directory -bor [System.IO.FileAttributes]::ReparsePoint)) -or -not (Test-PrivateAcl $file)) {
        throw "$bundle is not a private plain file. Nothing was deployed; move it away yourself."
    }
    Test-Bundle $bundle $head
    return $bundle
}

function ConvertTo-WslPath([string]$path) {
    $out = @(Invoke-Native { & wsl.exe -d $WslDistro -u root --exec wslpath -u $path })
    if ($LASTEXITCODE -ne 0 -or $out.Count -ne 1 -or $out[0] -cnotmatch '^/[^\x00-\x1f]+$') {
        throw "Could not translate $path into a path inside $WslDistro (wslpath exit $LASTEXITCODE). Nothing was deployed."
    }
    return $out[0]
}

# Creates the record (never over an existing file), then reads it back and checks the fields
# that identify the deployment before success is reported.
function Write-DeployRecord([string]$path, [System.Collections.Specialized.OrderedDictionary]$fields) {
    Write-PrivateFile $path ((New-Object System.Text.UTF8Encoding($false)).GetBytes(($fields | ConvertTo-Json -Depth 3)))
    $saved = ConvertFrom-PairJson (Read-SmallFile $path)
    foreach ($name in @("id", "commit", "mode", "folder", "database")) {
        if (-not $saved -or -not ($saved.$name -is [string]) -or $saved.$name -cne $fields[$name]) {
            throw "The deployment record $path did not read back as written ($name). The deploy itself finished; do not rely on that record."
        }
    }
}

# deploy: see the usage at the top. Everything on Windows is checked before WSL is used.
function Invoke-Deploy {
    if ($PSVersionTable.PSEdition -ne "Desktop") { throw "deploy uses the Windows PowerShell permission API; run it with powershell.exe, not pwsh." }
    if ($WslDistro -cnotmatch '^[A-Za-z0-9._-]{1,64}\z') { throw "deploy needs -WslDistro <name> made of A-Z a-z 0-9 . _ -" }
    if ($WslServerPath) { Test-WslServerPath $WslServerPath }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not on PATH." }

    $head = (Invoke-RepoGit @("rev-parse", "--verify", "HEAD^{commit}"))[0]
    if ($head -cnotmatch '^[0-9a-f]{40}\z') { throw "Could not read the committed HEAD." }
    $pending = Invoke-RepoGit @("status", "--porcelain", "--untracked-files=all")
    if ($pending.Count -gt 0) {
        throw ("Refusing: {0} uncommitted or untracked path(s), for example '{1}'. deploy sends only the committed HEAD; commit, ignore or move them yourself first. Nothing was exported." -f $pending.Count, (Get-Printable $pending[0]))
    }
    # WSL runs these from this checkout, so they must be the committed bytes (LF, unchanged).
    foreach ($file in @("scripts/project-runtime.sh", "scripts/update.sh", "scripts/check-php-runtime-security.sh")) {
        $blob = (Invoke-RepoGit @("rev-parse", "$($head):$file"))[0]
        if ((Invoke-RepoGit @("hash-object", "--no-filters", "--", $file))[0] -cne $blob) {
            throw "$file on disk is not byte-identical to commit $head (line endings or a hidden local change); scripts must be checked out with LF as .gitattributes says. Nothing was exported."
        }
    }
    $manifest = $null
    try { $manifest = (Invoke-RepoGit @("show", "$($head):dwemer-mod.json")) -join "`n" | ConvertFrom-Json } catch { }
    $id = $(if ($manifest -is [System.Management.Automation.PSCustomObject]) { [string]$manifest.id } else { "" })
    if (-not (Test-ProjectId $id)) { throw "dwemer-mod.json at $head has no valid id (3-32 lowercase letters, digits, single hyphens)." }
    $healthPath = [string]$manifest.health_path
    if ($healthPath -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9._/-]{0,199}\z' -or $healthPath.Contains("..")) { throw "dwemer-mod.json at $head has no valid health_path." }
    $headFolder = [string]$manifest.server_folder
    if ($headFolder -and -not (Test-ServerFolder $headFolder)) { throw "dwemer-mod.json at $head has an invalid server_folder (<Name>Server, letters and digits, not a product name)." }

    $exportDir = Get-DeployDir $id
    $bundle = Export-Bundle $exportDir $id $head
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($bundle)
    try { $bundleHash = -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) } finally { $stream.Dispose(); $sha.Dispose() }

    $distros = Get-WslNames @("-l", "-q")
    if ($null -eq $distros -or $distros.Code -ne 0 -or $distros.Names -notcontains $WslDistro) {
        throw "WSL distro '$WslDistro' was not found (run 'wsl -l -q'). The bundle was kept in $exportDir; nothing was deployed."
    }
    # Where WSL must report the install: Core's registered folder, else the manifest's location.
    $own = Get-OwnServerPath $true
    $folder = $(if ($WslServerPath) { $WslServerPath } elseif ($own) { $own } elseif ($headFolder) { "/var/www/html/$headFolder" } else { "/var/www/html/custom-mods/$id" })
    $wslArgs = @("-d", $WslDistro, "-u", "root", "--exec", "bash", (ConvertTo-WslPath (Join-Path $repo "scripts\project-runtime.sh")),
        "deploy", $id, $head, (ConvertTo-WslPath $bundle), $bundleHash)
    if ($WslServerPath) { $wslArgs += $WslServerPath }
    Say "INFO" "Deploying $id at $head to $folder in $WslDistro (runs as root; this may start the distro)."
    $result = $null
    Invoke-Native { & wsl.exe @wslArgs } | ForEach-Object {
        if ($_ -cmatch '^\[(STAGE|OK|INFO|WARN|FAIL)\] ([\x20-\x7e]{1,400})$') { Say $Matches[1] $Matches[2] }
        elseif ($_ -cmatch '^RESULT( [a-z]+=[\x21-\x7e]+){12}$') { $result = $_ }
    }
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $state = $(if ($code -eq 3) { "changed the mod but did not finish; use the backup and recovery lines above" } else { "stopped before the mod changed" })
        throw "Deploy in $WslDistro $state (exit $code). No deployment record was written."
    }
    $r = @{}
    if ($result) { foreach ($pair in $result.Split(" ") | Select-Object -Skip 1) { $kv = $pair.Split("=", 2); $r[$kv[0]] = $kv[1] } }
    $mode = [string]$r["mode"]
    if ($r["id"] -cne $id -or $r["commit"] -cne $head -or $r["folder"] -cne $folder -or $mode -cnotmatch '^(new|restore|local|remote|manual)\z' -or
        [string]$r["config"] -cnotmatch $(if ($mode -eq "manual") { '^unchecked\z' } else { '^(ok|repaired)\z' }) -or
        ($mode -ne "manual" -and $r["database"] -cne ("custom_" + $id.Replace("-", "_"))) -or [string]$r["database"] -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}\z') {
        throw "WSL did not confirm exactly $id at $head in $folder. No deployment record was written; run doctor and deploy again."
    }

    $checkUrl = $(if ($ServerUrl) { $ServerUrl } else { ConvertTo-BaseUrl $r["url"] })
    $health = Get-HttpStatus "$checkUrl/$healthPath"
    $h = $null
    if ($health.Status -eq 200) { try { $h = $health.Body | ConvertFrom-Json } catch { } }
    $reachable = $h -is [System.Management.Automation.PSCustomObject] -and $h.ok -is [bool] -and $h.ok
    $recovery = @(
        $(if ($mode -eq "manual") { "Backup from scripts/update.sh: $($r['backup']). Restore it by hand as SETUP.md section 6 describes." }
          else { "Core backup from before this deploy: $($r['backup']) (private config and database dump, root only)." }),
        $(if ($mode -eq "manual") { "Retry: run project.ps1 deploy again with the same -WslServerPath." }
          else { "Retry or finish: wsl -d $WslDistro -u root --exec ddistro_custom_mod update $id --expect-commit $head" }),
        "Code is never moved back automatically and database changes are never reversed; the previous commit was $($r['previous'])."
    )
    $recordPath = Join-Path $exportDir ("deployment-{0}-{1}.json" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ"), $head.Substring(0, 12))
    Write-DeployRecord $recordPath ([ordered]@{
        schema_version = 1; id = $id; commit = $head; branch = $r["branch"]; mode = $mode; action = $r["action"]
        distro = $WslDistro; folder = $r["folder"]; database = $r["database"]; url = $checkUrl; reachable_from_windows = [bool]$reachable
        previous_commit = $r["previous"]; protected = $r["protected"]; backup = $r["backup"]; config_permissions = $r["config"]
        bundle = $bundle; bundle_sha256 = $bundleHash; deployed_at = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); recovery = $recovery
    })
    $recovery | ForEach-Object { Say "INFO" $_ }
    if (-not $reachable) {
        Fail "Deployed in $WslDistro, but $checkUrl/$healthPath did not answer ok from Windows (HTTP $($health.Status)); pass -ServerUrl if Windows reaches it elsewhere. Record: $recordPath"
        return
    }
    $what = $(if ($r["action"] -eq "already") { "Code already at commit" } else { "Deployed ($($r['action']), $mode)" })
    $prep = $(if ($r["config"] -eq "repaired") { "; config permissions repaired by scripts/install.sh" } else { "" })
    Say "OK" "$what $head for $id in $WslDistro`:$($r['folder'])$prep, healthy at $checkUrl. Record: $recordPath"
    $script:done.Add("Deploy of $id at $head to $WslDistro ($mode, $($r['action']), config $($r['config'])); record $recordPath")
}

# Text recorded in a new project's PROJECT.md: one line of at most 200 characters with no table
# separator, URL or anything shaped like a key. A rejected value is never printed.
function Test-BriefText([string]$label, [string]$value) {
    if (-not $value) { return }
    if ($value.Length -gt 200 -or $value -match '[\x00-\x1f\x7f|]' -or $value.Trim() -cne $value -or $value -match '://' -or
        $value -match '\b(sk|pk|rk|or)-[A-Za-z0-9_-]{12,}' -or $value -match '[A-Za-z0-9+/_=-]{32,}') {
        throw "-$label must be one line of at most 200 characters, without '|', control characters, URLs or anything that looks like a key (value not shown)."
    }
}

# The new project's folder: a full path on a local fixed disk that does not exist yet, in an
# existing parent reached without links, outside every Git checkout, web root and the private
# output folders. Returns the full path.
function Resolve-NewDestination {
    $Destination = $Destination.Replace('/', '\')
    $refuse = "Refusing -Destination: use a full local path such as C:\dev\MyMod (drive letter and backslashes, with no '.', '..', '~1' alias, stream, link or network path)."
    if ($Destination -cnotmatch '^[A-Za-z]:\\[^\x00-\x1f"*/:<>?|]+\z' -or $Destination -match '~\d') { throw $refuse }
    $full = [System.IO.Path]::GetFullPath($Destination)
    if ($full -cne $Destination -or $full.EndsWith('\')) { throw $refuse }
    $drive = New-Object System.IO.DriveInfo $full.Substring(0, 1)
    if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) { throw "Refusing -Destination on $($drive.Name): only a local fixed disk is allowed, not a $($drive.DriveType) drive." }
    if ([int](New-Object System.IO.DirectoryInfo $full).Attributes -ne -1) { throw "Refusing -Destination: $full already exists. new never writes into an existing folder; choose a new one." }
    foreach ($part in $full.Substring(3).Split('\')) {
        if (@("htdocs", "wwwroot", "www", "public_html", "inetpub", "custom-mods") -contains $part.ToLowerInvariant()) { throw "Refusing -Destination under '$part': the source copy stays outside every web root." }
    }
    $outputs = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "DwemerDynamics")).TrimEnd('\')
    if ($full.StartsWith($outputs + "\", [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing -Destination inside $outputs, which holds builds, deploy bundles and private configs." }
    $parent = Split-Path -Parent $full
    if (-not [System.IO.Directory]::Exists($parent)) { throw "The folder $parent does not exist; create it first (new creates only the project folder)." }
    for ($dir = New-Object System.IO.DirectoryInfo $parent; $dir; $dir = $dir.Parent) {
        if ($dir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Refusing -Destination: $($dir.FullName) is a link or junction; choose a folder reached without one." }
        if (Test-Path -LiteralPath (Join-Path $dir.FullName ".git")) { throw "Refusing -Destination inside the Git checkout $($dir.FullName); each mod is its own repository." }
    }
    return $full
}

# The default server folder for -Name: its letters and digits as CamelCase words, plus Server
# ("Farnham's Echo" -> FarnhamsEchoServer). Test-ServerFolder decides whether it is usable.
function ConvertTo-ServerFolder([string]$name) {
    $words = @(($name -creplace "['\u2019]", "") -split '[^A-Za-z0-9]+' | Where-Object { $_ })
    $base = -join ($words | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })
    if ($base -cmatch 'Server\z') { $base = $base.Substring(0, $base.Length - 6) }
    return "${base}Server"
}

# $text with the one occurrence of $old replaced by $new; throws when $old is missing or repeated.
function Set-Once([string]$text, [string]$old, [string]$new, [string]$file) {
    $at = $text.IndexOf($old, [System.StringComparison]::Ordinal)
    if ($at -lt 0 -or $text.IndexOf($old, $at + 1, [System.StringComparison]::Ordinal) -ge 0) {
        throw "The template's $file does not have exactly one '$old'; new stopped before writing it."
    }
    return $text.Substring(0, $at) + $new + $text.Substring($at + $old.Length)
}

# A stage row of PROJECT.md given its state and latest evidence; the row must still be blank.
function Set-Stage([string]$text, [string]$stage, [string]$state, [string]$evidence) {
    $lines = $text.Split("`n")
    $hits = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith("| $stage ") -and $lines[$i].EndsWith("| not started | |")) { $i } })
    if ($hits.Count -ne 1) { throw "The template's PROJECT.md has no single blank stage row '$stage'; new stopped before writing it." }
    $line = $lines[$hits[0]]
    $lines[$hits[0]] = $line.Substring(0, $line.Length - "| not started | |".Length) + "| $state |" + $(if ($evidence) { " $evidence |" } else { " |" })
    return $lines -join "`n"
}

# The reference plan in ports/<engine>/PLAN.md at $head: its action names, and its plan rows with
# links rewritten from the port folder to the repository root.
function Get-EnginePlan([string]$head) {
    $lines = @()
    $null = Invoke-Native { & git -C $repo cat-file -e "$($head):ports/$Engine/PLAN.md" 2>$null }
    if ($LASTEXITCODE -ne 0) { return $null }
    $lines = Invoke-RepoGit @("show", "$($head):ports/$Engine/PLAN.md")
    $base = New-Object System.Uri "http://repo/ports/$Engine/"
    $rows = New-Object System.Collections.Generic.List[string]
    $actions = @()
    $inTable = $false
    foreach ($line in $lines) {
        if ($line -cmatch '^Actions: ([A-Za-z0-9_, ]+)$') { $actions = @($Matches[1].Split(",") | ForEach-Object { $_.Trim() }) }
        if ($line -ceq "| Part | Plan | Fact (citation) or Unknown |") { $inTable = $true; continue }
        if (-not $inTable -or $line -ceq "|---|---|---|") { continue }
        if (-not $line.StartsWith("| ")) { $inTable = $false; continue }
        $rows.Add([regex]::Replace($line, '\]\(([^)#:]+)(#[^)]*)?\)', {
            param($m)
            $target = New-Object System.Uri ($base, $m.Groups[1].Value)
            "](" + $target.AbsolutePath.TrimStart('/') + $m.Groups[2].Value + ")"
        }))
    }
    if ($actions.Count -gt 0 -and -not (Test-ActionNames $actions)) { throw "ports/$Engine/PLAN.md has an invalid Actions line." }
    return @{ Rows = $rows; Actions = $actions }
}

# new: see the usage at the top. Everything is checked before the destination is created.
function Invoke-New {
    if (-not $Destination -or -not $Id -or -not $Name) { throw "new needs -Destination <full Windows path>, -Id <id> and -Name <name>." }
    if (-not (Test-ProjectId $Id) -or $Id -ceq "example-server") { throw "-Id must be the new mod's own id: 3-32 lowercase letters, digits and single hyphens, not example-server." }
    if ($Name -cnotmatch '^[^\x00-\x1f\x7f"\\|<>`]{1,64}\z' -or $Name.Trim() -cne $Name) { throw "-Name must be 1-64 characters without control characters, quotes, backslashes, backticks, '|', '<' or '>', and no space at either end." }
    foreach ($field in @(@("Game", $Game), @("Feature", $Feature), @("Voice", $Voice), @("LlmProvider", $LlmProvider))) { Test-BriefText $field[0] $field[1] }
    if ($WslDistro -and $WslDistro -cnotmatch '^[A-Za-z0-9._-]{1,64}\z') { throw "-WslDistro must be made of A-Z a-z 0-9 . _ -" }
    if ($Engine -and $Engine -cnotmatch '^[a-z0-9][a-z0-9-]{0,39}\z') { throw "-Engine must be a port folder name for ports/: 1-40 lowercase letters, digits and hyphens, such as my-engine." }
    # The direct /var/www/html folder Core installs this mod in; Core still refuses one that exists.
    $folderName = $(if ($ServerFolder) { $ServerFolder } else { ConvertTo-ServerFolder $Name })
    if (-not (Test-ServerFolder $folderName)) {
        throw "Server folder '$(Get-Printable $folderName)' is not usable: pass -ServerFolder <Name>Server (7-47 ASCII letters or digits, a capital first letter, ending in Server, not a product name such as HerikaServer or KagrenacServer)."
    }
    if ($InteractionMode -and @("manual", "ambient", "companion", "operator") -cnotcontains $InteractionMode) {
        throw "-InteractionMode must be manual, ambient, companion or operator (the primary mode; the agent records any mix in PROJECT.md)."
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not on PATH." }
    $tarExe = Join-Path $env:SystemRoot "System32\tar.exe"
    if (-not (Test-Path -LiteralPath $tarExe -PathType Leaf)) { throw "$tarExe (part of Windows 10 and later) is missing; new uses it to unpack the copy." }

    $head = (Invoke-RepoGit @("rev-parse", "--verify", "HEAD^{commit}"))[0]
    if ($head -cnotmatch '^[0-9a-f]{40}\z') { throw "Could not read the committed HEAD." }
    $template = $null
    try { $template = (Invoke-RepoGit @("show", "$($head):dwemer-mod.json")) -join "`n" | ConvertFrom-Json } catch { }
    if (-not ($template -is [System.Management.Automation.PSCustomObject] -and [string]$template.id -ceq "example-server")) {
        throw "new copies only the template (manifest id example-server at HEAD); this checkout is already a project of its own."
    }
    if ($Name -ceq [string]$template.name) { throw "-Name must be the new mod's own name, not the template's." }
    $plan = $(if ($Engine) { Get-EnginePlan $head } else { $null })
    $dest = Resolve-NewDestination
    foreach ($used in @("deploy\$Id", "projects\$Id")) {
        $path = Join-Path $env:LOCALAPPDATA "DwemerDynamics\Kagrenac\$used"
        if ([int](New-Object System.IO.DirectoryInfo $path).Attributes -ne -1) { throw "Refusing -Id ${Id}: $path already exists, so another project has used that id. Choose another id." }
    }

    # Only plain tracked files at HEAD are copied, and none that is private, a database, a log or output.
    $tracked = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Invoke-RepoGit @("-c", "core.quotePath=false", "ls-tree", "-r", "--full-tree", "HEAD"))) {
        if ($line -cnotmatch '^(100644|100755) blob [0-9a-f]{40}\t([^"\t]+)$') { throw "HEAD tracks an entry new does not copy (a link, submodule or quoted name): '$(Get-Printable $line)'. Nothing was created." }
        $path = $Matches[2]
        if ($path -cmatch '(^|/)(config/config\.php|config\.json|\.env)$|\.(log|sqlite3?|db|dump|bundle|pem|key|pfx|p12)$|(^|/)(\.git|build|out|node_modules|vendor)/') {
            throw "HEAD tracks '$(Get-Printable $path)', which looks private or generated; remove it from the template first. Nothing was created."
        }
        $tracked.Add($path)
    }
    $pending = Invoke-RepoGit @("status", "--porcelain", "--untracked-files=all")
    if ($pending.Count -gt 0) { Say "WARN" "$($pending.Count) uncommitted or untracked path(s) in this checkout are not copied; new copies only commit $head." }

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("kagrenac-new-" + [System.Guid]::NewGuid().ToString("N"))
    $null = [System.IO.Directory]::CreateDirectory($temp)
    $tar = Join-Path $temp "source.tar"
    try {
        $null = Invoke-Native { & git -C $repo archive --format=tar -o $tar HEAD }
        if ($LASTEXITCODE -ne 0) { throw "git archive failed (exit $LASTEXITCODE). Nothing was created." }
        $entries = @(Invoke-Native { & $tarExe -tf $tar })
        if ($LASTEXITCODE -ne 0) { throw "tar could not list the archive (exit $LASTEXITCODE). Nothing was created." }
        $files = @($entries | Where-Object { -not $_.EndsWith("/") } | Sort-Object -CaseSensitive)
        $expected = @($tracked | Sort-Object -CaseSensitive)
        if ($files.Count -ne $expected.Count -or @(Compare-Object -CaseSensitive $files $expected).Count -gt 0) {
            throw "The archive of $head does not hold exactly its $($expected.Count) tracked files. Nothing was created."
        }
        if ([int](New-Object System.IO.DirectoryInfo $dest).Attributes -ne -1) { throw "Refusing -Destination: $dest appeared while new was checking. Nothing was written there." }
        $null = [System.IO.Directory]::CreateDirectory($dest)
        $null = Invoke-Native { & $tarExe -xf $tar -C $dest }
        $unpacked = @(Get-ChildItem -LiteralPath $dest -Recurse -File -Force).Count
        if ($LASTEXITCODE -ne 0 -or $unpacked -ne $expected.Count) {
            throw "Unpacking into $dest failed (tar exit $LASTEXITCODE, $unpacked of $($expected.Count) files). new does not delete folders; remove $dest yourself and run new again."
        }
    } finally {
        if ([System.IO.File]::Exists($tar)) { [System.IO.File]::Delete($tar) }
        [System.IO.Directory]::Delete($temp)
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $date = (Get-Date).ToString("yyyy-MM-dd")
    $short = $head.Substring(0, 12)
    try {
        $manifestPath = Join-Path $dest "dwemer-mod.json"
        $text = [System.IO.File]::ReadAllText($manifestPath, $utf8)
        $text = Set-Once $text '"id": "example-server"' "`"id`": `"$Id`"" "dwemer-mod.json"
        $text = Set-Once $text "`"name`": `"$($template.name)`"" "`"name`": `"$Name`"" "dwemer-mod.json"
        $text = Set-Once $text "`"description`": `"$($template.description)`"" "`"description`": `"$Name, an AI mod made with KAGRENAC AI Mod Maker.`"" "dwemer-mod.json"
        $eol = $(if ($text.Contains("`r`n")) { "`r`n" } else { "`n" })
        $text = Set-Once $text "`"id`": `"$Id`",$eol" "`"id`": `"$Id`",$eol  `"server_folder`": `"$folderName`",$eol" "dwemer-mod.json"
        # The template's own page is not this mod's; project_url is optional and added once the mod has one.
        $text = Set-Once $text "  `"project_url`": `"$($template.project_url)`",$eol" "" "dwemer-mod.json"
        [System.IO.File]::WriteAllText($manifestPath, $text, $utf8)
        $saved = [System.IO.File]::ReadAllText($manifestPath, $utf8) | ConvertFrom-Json
        if ([string]$saved.id -cne $Id -or [string]$saved.name -cne $Name -or [string]$saved.server_folder -cne $folderName -or $null -ne $saved.project_url) {
            throw "dwemer-mod.json did not read back with id $Id, name $Name, server_folder $folderName and no project_url."
        }

        $projectPath = Join-Path $dest "PROJECT.md"
        $text = [System.IO.File]::ReadAllText($projectPath, $utf8)
        $brief = [ordered]@{
            "Game, version and modding tools" = $Game
            "Starting feature (new companion or existing NPC, and what it does)" = $Feature
            "Mod name" = $Name
            "Project id and name in ``dwemer-mod.json`` (own values, set before deploy)" = "``$Id``, $Name"
            "Voice (none, or PocketTTS replies; speech input only if asked: Parakeet push-to-talk into the editable draft)" = $Voice
            "LLM provider (name only)" = $LlmProvider
            "DwemerDistro (the one WSL distro name)" = $WslDistro
        }
        foreach ($question in $brief.Keys) {
            if ($brief[$question]) { $text = Set-Once $text "| $question | |" "| $question | $($brief[$question]) |" "PROJECT.md" }
        }
        # Planning text only: the mode enables nothing; the agent fills the other Gameplay design rows.
        if ($InteractionMode) {
            $mode = @{
                manual = "manual: the player starts each exchange"
                ambient = "ambient/social: automatic and bounded; one NPC remarks on a fixed game event (event.php respond true, trigger and cooldown owned by the port), or NPCs talk among themselves if the brief asks for that (needs the planned participant contract)"
                companion = "companion: the player talks and gives orders, plus bounded reactions to game events"
                operator = "operator: the player asks for reports and gives orders, or a fixed game event prompts a bounded report (event.php respond true)"
            }[$InteractionMode]
            $label = "Interaction mode (manual, ambient/social, companion or operator; a mix is fine)"
            $text = Set-Once $text "| $label | |" "| $label | $mode (primary, from project.ps1 new; the agent records any mix) |" "PROJECT.md"
        }
        $missing = @(foreach ($field in @(@("game", $Game), @("starting feature", $Feature))) { if (-not $field[1]) { $field[0] } })
        $text = Set-Stage $text "1." $(if ($missing.Count -eq 0) { "done" } else { "in progress: " + ($missing -join " and ") + " missing" }) "$date, source: brief given to project.ps1 new"
        if ($plan) {
            foreach ($row in $plan.Rows) {
                $part = $row.Substring(2, $row.IndexOf(" | ", 2) - 2)
                $text = Set-Once $text "| $part | | |" $row "PROJECT.md"
            }
            if ($text.Contains(" | | |`n")) { throw "ports/$Engine/PLAN.md does not fill every plan row of the template's PROJECT.md." }
            # A copied reference plan is only a starting point: the agent checks each row against the
            # starting feature and marks the stage done itself. Stages 3 to 5 do not wait for it.
            $text = Set-Stage $text "2." "in progress: reference plan copied, not yet checked against the starting feature; the agent fills the Gameplay design, revises each plan row that differs, then marks this done" "$date, source: reference plan from ports/$Engine/PLAN.md, not checked against this brief or verified in game"
        } elseif ($Engine) {
            $text = Set-Stage $text '2.' 'not started: survey the installed game and qualify the integration before mod code' "$date, source: no reference plan for $Engine; follow docs/ENGINE_PLANNING.md"
            $port = Join-Path $dest "ports\$Engine"
            [void][System.IO.Directory]::CreateDirectory($port)
            [System.IO.File]::WriteAllText((Join-Path $port 'PLAN.md'),
                "# $Engine integration plan`n`nNo reference plan ships for this engine. Start with [Engine planning](../../docs/ENGINE_PLANNING.md).`n`nRecord the installed build, loader, documented hooks, save/offline strategy, selected architecture, unknowns and first acceptance test here. No game support or action is qualified yet.`n", $utf8)
        }
        $text = Set-Stage $text "3." "in progress: own id set; commit, then deploy" ""
        if ($Voice -match '^(none|no|not wanted)$') { $text = Set-Stage $text "5." "not wanted" "$date, source: brief" }
        if ($plan -and $plan.Actions.Count -gt 0) {
            $row = "| 6d. Action ``<name>`` (one row per action) | in-game: that action's own check; a broad `"it works`" does not count | not started | |"
            $text = Set-Once $text $row (($plan.Actions | ForEach-Object { $row.Replace("``<name>`` (one row per action)", "``$_``") }) -join "`n") "PROJECT.md"
        }
        $text = Set-Once $text ("Everything built or private stays outside this repository and every web root. ``<id>`` is the`n" +
            "id in ``dwemer-mod.json``; the template itself keeps the client build in`n" +
            "``%LOCALAPPDATA%\DwemerDynamics\KagrenacClient\build``.") "Everything built or private stays outside this repository and every web root." "PROJECT.md"
        $text = Set-Once $text "database ``custom_<id>`` with ``-`` as ``_``" "database ``custom_$($Id.Replace('-', '_'))``" "PROJECT.md"
        $text = Set-Once $text "``/var/www/html/<server_folder>`` (``server_folder`` in ``dwemer-mod.json``; a copy without it: ``/var/www/html/custom-mods/<id>``; Core's registry entry is what counts)" "``/var/www/html/$folderName`` (``server_folder`` in ``dwemer-mod.json``)" "PROJECT.md"
        $start = $text.IndexOf("`n## Paths`n", [System.StringComparison]::Ordinal)
        $end = $text.IndexOf("`n## Decisions`n", [System.StringComparison]::Ordinal)
        if ($start -lt 0 -or $end -lt $start) { throw "The template's PROJECT.md has no Paths section before Decisions." }
        $paths = $text.Substring($start, $end - $start).Replace("<id>", $Id)
        if ($Engine) { $paths = $paths.Replace("<engine>", $Engine) }
        $text = $text.Substring(0, $start) + $paths + $text.Substring($end)
        $text = Set-Once $text "| Date | Decision | Reason |`n|---|---|---|`n" ("| Date | Decision | Reason |`n|---|---|---|`n" +
            "| $date | Started from KAGRENAC AI Mod Maker commit $short with ``project.ps1 new`` | An independent copy with its own id; the template is unchanged |`n") "PROJECT.md"
        $text = $text.TrimEnd("`n") + "`n| $date | source | ``project.ps1 new`` from template commit $short | $($expected.Count) files copied; id ``$Id`` and name set; Git initialised, nothing committed |`n"
        [System.IO.File]::WriteAllText($projectPath, $text, $utf8)
    } catch {
        throw "$($_.Exception.Message) The copy at $dest is incomplete; new does not delete folders, so remove it yourself and run new again."
    }

    $null = Invoke-Native { & git init --quiet -b main $dest }
    if ($LASTEXITCODE -ne 0) { throw "git init failed in $dest (exit $LASTEXITCODE); the files are there, run 'git init -b main' in it yourself." }
    Say "OK" "Created $Name ($Id) at $dest from template commit $short`: $($expected.Count) files, its own manifest id, name and server folder $folderName, Git initialised, nothing committed."
    Say "INFO" "Its first deploy installs it at /var/www/html/$folderName (http://127.0.0.1:19000/$folderName/), database custom_$($Id.Replace('-', '_'))."
    Say "INFO" "$dest\PROJECT.md holds the brief$(if ($plan) { ", the $Engine reference plan" }), the paths for this id and the stage states; this checkout was not changed."
    $script:done.Add("New project $Id at $dest (from $short)")
    $script:manual.Add("Agent: review the independent copy and commit it before deploy, within the user's existing authorization: git -C $(ConvertTo-PsLiteral $dest) add -A; git -C $(ConvertTo-PsLiteral $dest) commit -m $(ConvertTo-PsLiteral "Start $Name from KAGRENAC AI Mod Maker $short")")
    $script:manual.Add("Agent: fill the Gameplay design rows in the copy's PROJECT.md from the conversation (docs/GAMEPLAY_DESIGN.md) before engine-port code; server and provider setup does not wait for it")
    $script:manual.Add("Work from the copy from now on, for example: powershell -ExecutionPolicy Bypass -File $(ConvertTo-PsLiteral "$dest\scripts\project.ps1") deploy -WslDistro <name>")
    $script:manual.Add("Add project_url (an https URL) to the copy's dwemer-mod.json once the mod has its own public repository; it is optional and left out until then")
}

# A project with its own id builds the client into its own folder; the template keeps the shared one.
$workingId = ""
try { $workingId = [string](Get-Content -Raw -LiteralPath (Join-Path $repo "dwemer-mod.json") | ConvertFrom-Json).id } catch { }
# This project's direct server folder, if its manifest names one.
$workingFolder = ""
try { $workingFolder = [string](Get-Content -Raw -LiteralPath (Join-Path $repo "dwemer-mod.json") | ConvertFrom-Json).server_folder } catch { }
if ($workingFolder -and -not (Test-ServerFolder $workingFolder)) { Say "WARN" "dwemer-mod.json has an unusable server_folder; Core will refuse it."; $workingFolder = "" }
# A project with its own id serves its own route; the template keeps KagrenacServer.
if ((Test-ProjectId $workingId) -and $workingId -cne "example-server") { $defaultUrl = "http://127.0.0.1:19000" + (Get-OwnServerPath $false).Substring("/var/www/html".Length) }
if (-not $BuildRoot) {
    $BuildRoot = $(if ((Test-ProjectId $workingId) -and $workingId -cne "example-server") { Join-Path $env:LOCALAPPDATA "DwemerDynamics\Kagrenac\projects\$workingId\client" }
        else { Join-Path $env:LOCALAPPDATA "DwemerDynamics\KagrenacClient\build" })
}

# Validate an explicit -ServerUrl once, before anything prints or uses it.
if ($ServerUrl) {
    $validUrl = ConvertTo-BaseUrl $ServerUrl
    if (-not $validUrl) {
        Fail "-ServerUrl must be an http(s) base URL without credentials, query or fragment (value not shown)."
        exit 1
    }
    $ServerUrl = $validUrl
}

switch ($Command) {
    "package" {
        if (-not $ClientDirectory -or -not $ReleaseVersion -or -not $ReleaseDirectory) {
            throw "package needs -ClientDirectory <build output> -ReleaseVersion <tag> -ReleaseDirectory <new folder>."
        }
        $python = Get-Command py -ErrorAction SilentlyContinue
        if ($python) { & $python.Source -3 (Join-Path $PSScriptRoot 'publish.py') package --repo $repo --client-dir $ClientDirectory --version $ReleaseVersion --output $ReleaseDirectory }
        else { & python3 (Join-Path $PSScriptRoot 'publish.py') package --repo $repo --client-dir $ClientDirectory --version $ReleaseVersion --output $ReleaseDirectory }
        exit $LASTEXITCODE
    }
    "publish" {
        if (-not $ReleaseDirectory -or -not $ConfirmPublish) { throw "Review the package, then publish with -ReleaseDirectory <folder> -ConfirmPublish <owner/repo>." }
        $python = Get-Command py -ErrorAction SilentlyContinue
        if ($python) { & $python.Source -3 (Join-Path $PSScriptRoot 'publish.py') publish --output $ReleaseDirectory --confirm-publish $ConfirmPublish }
        else { & python3 (Join-Path $PSScriptRoot 'publish.py') publish --output $ReleaseDirectory --confirm-publish $ConfirmPublish }
        exit $LASTEXITCODE
    }
    "new" {
        Invoke-New
    }
    "doctor" {
        Show-Doctor
    }
    "setup" {
        if ($SkipBuild) { Say "SKIP" "Client build (-SkipBuild)." } else { Invoke-ClientBuild }
        if ($RunServerInstaller) {
            Require-WslTarget
            if ($WslServerPath -ceq "/var/www/html/custom-mods/example-server") {
                throw "Refusing: /custom-mods/example-server is managed by the DwemerDistro launcher, which never runs scripts/install.sh. Use the launcher's Update instead."
            }
            if (-not (Test-WebProtection)) {
                throw "Refusing: Core web protection rules are missing from $protectedSite. Update DwemerDistro Core and run 'sudo ddistro_custom_mod setup-web' first (SETUP.md, Before you install)."
            }
            if (-not (Test-ProtectedFolder $WslServerPath)) {
                throw "Refusing: $WslServerPath is not fully covered by DwemerDistro Core's web protection in $protectedSite. Have Core's setup-web protect this route (or add equivalent Apache rules for its .git, client, ports, docs, config, lib, sql, scripts, config.json and .env), then run 'sudo bash scripts/install.sh' there yourself."
            }
            Say "INFO" "Running the existing installer in $WslDistro`:$WslServerPath (keeps an existing config and database)."
            Invoke-Native { & wsl.exe -d $WslDistro -u root -e bash "$WslServerPath/scripts/install.sh" } | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { Fail "scripts/install.sh failed (exit $LASTEXITCODE)." }
            else { $done.Add("Server installer in $WslDistro`:$WslServerPath") }
        } else {
            $manual.Add("Server install inside WSL: SETUP.md section 1 (or pass -RunServerInstaller -WslDistro <name> -WslServerPath <existing checkout>)")
        }
        $manual.Add("Core web protection before any server install or update: SETUP.md, Before you install")
        $manual.Add("Pairing: SETUP.md section 3, Connect them (run scripts/pair_client.php in the WSL server copy, output outside the web root, and copy it next to KagrenacClient.exe as config.json), or run this script's 'pair'; setup never writes client config")
    }
    "check" {
        Invoke-StaticChecks
        if ($SkipBuild) { Say "SKIP" "Client build (-SkipBuild)." } else { Invoke-ClientBuild }
        if ($RunSmoke) {
            Require-WslTarget
            $url = Get-RouteUrl
            Say "INFO" "Running scripts/smoke.sh against $url as dwemer (mock mode expected)."
            Invoke-Native { & wsl.exe -d $WslDistro -u dwemer -e bash "$WslServerPath/scripts/smoke.sh" $url } | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { Fail "scripts/smoke.sh failed (exit $LASTEXITCODE)." } else { $done.Add("Server smoke checks against $url") }
        } else {
            $manual.Add("Server smoke checks: pass -RunSmoke -WslDistro <name> -WslServerPath <checkout>, or run 'bash scripts/smoke.sh' in WSL")
        }
        $manual.Add("Migrations twice (php scripts/migrate.php) in WSL; this script runs no database operations")
        $manual.Add("Console smoke checks: client/README.md, Smoke checks")
    }
    "pair" {
        Invoke-Pair
    }
    "configure" {
        Invoke-Configure
    }
    "deploy" {
        Invoke-Deploy
    }
}

if ($done.Count -gt 0) { Write-Host ""; Write-Host "Done by this script:"; $done | ForEach-Object { Write-Host "  - $_" } }
if ($manual.Count -gt 0) { Write-Host ""; Write-Host "Not done here (instructions only):"; $manual | ForEach-Object { Write-Host "  - $_" } }
if ($failures -gt 0) { Write-Host ""; Write-Host "$failures problem(s) found."; exit 1 }
exit 0
