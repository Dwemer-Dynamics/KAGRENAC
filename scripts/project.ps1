# KAGRENAC AI Mod Maker developer wrapper for the Windows development copy. It only reuses the
# existing scripts: client\scripts\build.ps1 on Windows, and (explicit opt-in) the server's
# scripts/install.sh and scripts/smoke.sh inside an existing WSL server checkout.
# It installs no prerequisites, copies no source into WSL, resets no database, generates no
# client config and starts no background services. It never prints tokens or keys.
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\project.ps1 <doctor|setup|check> [options]
#   doctor  Report tools, WSL distros, client build, client config (no secrets) and server health
#           (ok and service identity only). On a healthy server, probe .git/ and the source
#           folders: only HTTP 403 counts as protected; 200 is exposed and any other status is
#           unverified, and both are problems. Changes nothing.
#   setup   Build the client (x64 and x86) outside the repository; repeat-safe. With
#           -RunServerInstaller -WslDistro <name> -WslServerPath <path>, also run the existing
#           scripts/install.sh in that WSL checkout (manual install folders only).
#   check   PHP lint of the server files and shell syntax with local tools, then the client
#           build. With -RunSmoke -WslDistro <name> -WslServerPath <path>, also run
#           scripts/smoke.sh there.
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("doctor", "setup", "check")]
    [string]$Command,
    [string]$BuildRoot = (Join-Path $env:LOCALAPPDATA "DwemerDynamics\KagrenacClient\build"),
    [string]$ServerUrl = "",
    [string]$WslDistro = "",
    [string]$WslServerPath = "",
    [switch]$RunServerInstaller,
    [switch]$RunSmoke,
    [switch]$SkipBuild
)
$ErrorActionPreference = "Stop"
$env:WSL_UTF8 = "1"

$repo = Split-Path -Parent $PSScriptRoot
$defaultUrl = "http://127.0.0.1:19000/custom-mods/KagrenacServer"
$serviceId = "example-ai-server"
$protectedSite = "/etc/apache2/sites-available/dwemerdistro-custom-mods.conf"
$failures = 0
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

# Only the known Kagrenac folders are covered by DwemerDistro Core's web protection.
function Test-WslServerPath([string]$path) {
    if ($path -cnotmatch '^/var/www/html/(custom-mods/[A-Za-z0-9_-][A-Za-z0-9._-]*|ExampleServer)$') {
        throw "Refusing WSL server path '$path': use an absolute folder directly under /var/www/html/custom-mods/ (or /var/www/html/ExampleServer), with no '..', links or trailing slash."
    }
}

function Test-ProtectedFolder([string]$path) {
    return $path -cmatch '^/var/www/html/(custom-mods/(KagrenacServer|example-server)|ExampleServer)$'
}

function Get-WslDistros {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $null }
    $names = @(Invoke-Native { & wsl.exe -l -q })
    if ($LASTEXITCODE -ne 0) { return ,@() }
    return ,@($names | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
}

function Require-WslTarget {
    if (-not $WslDistro -or -not $WslServerPath) {
        throw "This option needs both -WslDistro <name> and -WslServerPath <path to the existing server checkout>."
    }
    Test-WslServerPath $WslServerPath
    $distros = Get-WslDistros
    if ($null -eq $distros -or $distros -notcontains $WslDistro) {
        throw "WSL distro '$WslDistro' was not found. Run 'wsl -l -q' to list distros."
    }
    # The path is passed to sh as an argument, never interpolated; the pattern above allows no
    # spaces or shell characters, so $1 needs no quotes (Windows PowerShell mangles embedded quotes).
    Invoke-Native { & wsl.exe -d $WslDistro -e sh -c 'test -d $1 && ! test -L $1 && test -d $1/.git && test -f $1/dwemer-mod.json && test -f $1/scripts/install.sh' sh $WslServerPath } | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "No server checkout at $WslServerPath in $WslDistro (it must be an existing Git clone, not a link). This script never copies source into WSL; clone it there as SETUP.md describes."
    }
}

function Test-WebProtection {
    # -s: a missing site file means "not protected", not an error.
    $null = Invoke-Native { & wsl.exe -d $WslDistro -e grep -qsF "(client|ports|docs)" $protectedSite }
    return ($LASTEXITCODE -eq 0)
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

    $distros = Get-WslDistros
    if ($null -eq $distros) { Say "WARN" "wsl.exe not found; the server runs inside DwemerDistro WSL." }
    elseif ($distros.Count -eq 0) { Say "WARN" "No WSL distros listed; install and start DwemerDistro first." }
    else { Say "OK" ("WSL distros: " + ($distros -join ", ")) }

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
    if (Test-Path -LiteralPath (Join-Path $repo "client\config.json")) {
        Say "WARN" "client\config.json exists in the repository; keep the private config next to the built exe instead."
    }
    $url = $ServerUrl
    $configPath = Join-Path $BuildRoot "x64\Release\config.json"
    if (Test-Path -LiteralPath $configPath) {
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
    if ($health.Status -eq 0) {
        Say "WARN" "No answer from $url/health.php (refused, or nothing within 5 seconds). Start DwemerDistro, or pass -ServerUrl. Exposure was not checked."
    } elseif ($health.Status -ne 200) {
        Fail "$url/health.php answered HTTP $($health.Status), not 200 (redirects are not followed). Exposure was not checked."
    } elseif (-not ($h -is [System.Management.Automation.PSCustomObject] -and $h.ok -is [bool] -and $h.ok -and $h.service -is [string] -and $h.service -ceq $serviceId)) {
        Fail "$url/health.php is not KagrenacServer health JSON with ok true and service $serviceId. Exposure was not checked."
    } else {
        Say "OK" ("Server at {0}: ok=true, service={1}, schema={2}, server_version={3}, protocol={4}" -f $url, $serviceId, (Get-Printable $h.schema), (Get-Printable $h.server_version), (Get-Printable $h.protocol))
        Say "INFO" "Health shows only that this server answers; it does not check the LLM, voice services or any game."
        foreach ($probe in @(".git/HEAD", "client/CMakeLists.txt", "docs/getting-started.md", "ports/elden-ring/README.md")) {
            $status = (Get-HttpStatus "$url/$probe").Status
            if ($status -eq 403) { Say "OK" "$url/$probe is denied (HTTP 403)." }
            elseif ($status -eq 200) { Fail "$url/$probe is served (HTTP 200). Install DwemerDistro Core's web protection (SETUP.md) or add equivalent rules for this folder." }
            else {
                $script:failures++
                Say "UNVERIFIED" ("$url/$probe answered {0}; only HTTP 403 shows it is protected." -f $(if ($status -eq 0) { "with no status (no answer, or a redirect)" } else { "HTTP $status" }))
            }
        }
        Say "INFO" "Exposure was checked on this URL's listener only; check every other Apache port that serves /var/www/html too."
    }
    if ($WslDistro -and $WslServerPath) {
        Require-WslTarget
        Say "OK" "Server checkout found at $WslServerPath in $WslDistro."
        $null = Invoke-Native { & wsl.exe -d $WslDistro -e test -f "$WslServerPath/config/config.php" }
        if ($LASTEXITCODE -eq 0) { Say "OK" "Server private config exists (contents not read)." } else { Say "INFO" "No config/config.php yet; scripts/install.sh creates it." }
        if (Test-WebProtection) { Say "OK" "Core web protection rules are present in $protectedSite." }
        else { Say "WARN" "Core web protection rules are missing from $protectedSite; update DwemerDistro Core and run 'sudo ddistro_custom_mod setup-web' before installing or updating." }
        if (-not (Test-ProtectedFolder $WslServerPath)) { Say "WARN" "$WslServerPath is not a folder Core's web protection knows; add equivalent Apache rules for its .git/, client/, docs/ and ports/." }
    }
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
            if (-not (Test-ProtectedFolder $WslServerPath)) {
                throw "Refusing: $WslServerPath is not covered by DwemerDistro Core's web protection. Add equivalent Apache rules for its .git/, client/, docs/ and ports/, then run 'sudo bash scripts/install.sh' there yourself."
            }
            if (-not (Test-WebProtection)) {
                throw "Refusing: Core web protection rules are missing from $protectedSite. Update DwemerDistro Core and run 'sudo ddistro_custom_mod setup-web' first (SETUP.md, Before you install)."
            }
            Say "INFO" "Running the existing installer in $WslDistro`:$WslServerPath (keeps an existing config and database)."
            Invoke-Native { & wsl.exe -d $WslDistro -u root -e bash "$WslServerPath/scripts/install.sh" } | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) { Fail "scripts/install.sh failed (exit $LASTEXITCODE)." }
            else { $done.Add("Server installer in $WslDistro`:$WslServerPath") }
        } else {
            $manual.Add("Server install inside WSL: SETUP.md section 1 (or pass -RunServerInstaller -WslDistro <name> -WslServerPath <existing checkout>)")
        }
        $manual.Add("Core web protection before any server install or update: SETUP.md, Before you install")
        $manual.Add("Pairing: run scripts/pair_client.php in the WSL server copy (output outside the web root) and copy it next to KagrenacClient.exe as config.json; this script never writes client config")
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
}

if ($done.Count -gt 0) { Write-Host ""; Write-Host "Done by this script:"; $done | ForEach-Object { Write-Host "  - $_" } }
if ($manual.Count -gt 0) { Write-Host ""; Write-Host "Not done here (instructions only):"; $manual | ForEach-Object { Write-Host "  - $_" } }
if ($failures -gt 0) { Write-Host ""; Write-Host "$failures problem(s) found."; exit 1 }
exit 0
