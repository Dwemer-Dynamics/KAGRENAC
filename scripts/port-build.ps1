# Port build and runtime records for project.ps1 (schema 2, docs/PORT_BUILD_RECORDS.md).
# These are data, never scripts to execute; any other record is refused.

# Resolves a record's relative artifact without allowing aliases, links or path traversal.
function Get-PortArtifact([string]$root, [string]$relative) {
    if ($relative -cnotmatch '^[A-Za-z0-9_-][A-Za-z0-9_.-]*(/[A-Za-z0-9_-][A-Za-z0-9_.-]*)*\z' -or
        $relative -match '(^|/)\.\.?(/|$)' -or $relative -match '[. ]($|/)') {
        throw "Invalid port artifact path (use a relative slash-separated file name)."
    }
    $file = Join-Path $root $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Port artifact missing: $file" }
    Assert-NoReparse $file
    return $file
}

# Verifies a source-owned build's game pin, packaged handlers and every artifact before
# it can authorize any action. An unsigned local record is not proof of gameplay success.
function Get-GenericPortBuild([string]$dir) {
    if ($dir.Replace('/', '\') -cnotmatch '^[A-Za-z]:\\.') { throw '-Build must be an absolute local path.' }
    $full = [System.IO.Path]::GetFullPath($dir.Replace('/', '\')).TrimEnd('\')
    if ($full -cnotmatch '^[A-Za-z]:\\.' -or -not (Test-Path -LiteralPath $full -PathType Container)) {
        throw "-Build must name an existing local port build folder."
    }
    Assert-NoReparse $full
    $b = Read-JsonRecord (Join-Path $full 'build.json')
    if (-not (Test-ProjectId $workingId) -or $workingId -ceq 'example-server' -or -not $b -or
        $b.schema_version -isnot [int] -or $b.schema_version -ne 2 -or $b.kind -cne 'kagrenac-port-build' -or $b.id -cne $workingId -or
        $b.engine -isnot [string] -or $b.engine -cnotmatch '^[a-z0-9][a-z0-9-]{0,39}\z' -or
        $b.build -isnot [string] -or $b.build -cnotmatch '^\d{8}-\d{6}\z' -or (Split-Path -Leaf $full) -cne $b.build) {
        throw "Not a generic port build of this project (schema 2, id, engine and build folder must match); older or malformed records are not supported."
    }
    $pin = Join-Path $repo "ports\$($b.engine)\game-build.json"
    $game = Read-JsonRecord $pin
    if (-not $game -or $game.sha256 -isnot [string] -or $game.sha256 -cnotmatch '^[0-9a-f]{64}\z' -or
        $b.game_build_sha256 -cne (Get-FileSha256Hex $pin) -or $b.game.sha256 -cne $game.sha256) {
        throw "The port build's game pin is missing or stale; run its doctor and build again."
    }
    if ($b.source_commit -isnot [string] -or $b.source_commit -cnotmatch '^[0-9a-f]{40}\z' -or $b.source_dirty -isnot [bool]) {
        throw "The port build needs source_commit and source_dirty provenance."
    }
    if ($b.source_dirty) { Say 'WARN' 'This port build has uncommitted source changes; use a clean committed build for delivery.' }
    if ($b.supported_actions -isnot [array] -or $b.supported_actions.Count -gt 8 -or
        ($b.supported_actions.Count -gt 0 -and -not (Test-ActionNames @($b.supported_actions)))) {
        throw "supported_actions must be a list of up to eight different action names (an empty list is valid)."
    }
    if ($b.files -isnot [System.Management.Automation.PSCustomObject] -or
        $b.action_handlers -isnot [System.Management.Automation.PSCustomObject]) { throw 'Port files and action_handlers must be objects.' }
    $files = @($b.files.PSObject.Properties)
    if ($files.Count -lt 1 -or $files.Count -gt 128) { throw 'A port build must record 1-128 artifacts.' }
    $names = @($files | ForEach-Object { $_.Name })
    if (@($names | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique).Count -ne $names.Count) { throw 'Port artifacts must have unique Windows paths.' }
    foreach ($p in $files) {
        if ($p.Value -isnot [string] -or $p.Value -cnotmatch '^[0-9a-f]{64}\z') { throw 'A port artifact has no valid SHA-256.' }
        $file = Get-PortArtifact $full $p.Name
        if ((Get-FileSha256Hex $file) -cne $p.Value) { throw "Port artifact changed since the build: $file" }
    }
    if ($b.entrypoint -isnot [string] -or $names -cnotcontains $b.entrypoint) { throw 'The port entrypoint must name a recorded artifact.' }
    $handlers = @($b.action_handlers.PSObject.Properties)
    if ($handlers.Count -ne $b.supported_actions.Count) { throw 'Each supported action needs one packaged handler artifact.' }
    foreach ($h in $handlers) {
        if (@($b.supported_actions) -cnotcontains $h.Name -or $h.Value -isnot [string] -or $names -cnotcontains $h.Value) {
            throw 'An action handler must belong to supported_actions and name a recorded artifact.'
        }
    }
    return @{ Actions = @($b.supported_actions); DllSha = [string]$b.files.($b.entrypoint); Dir = $full; Engine = $b.engine; Record = $b }
}

# Verifies every staged runtime artifact against its own build. No path or command from
# these records is executed; the port owns installation and its human-launched game test.
function Get-GenericPortRuntime([string]$folder, $r) {
    if ($r.schema_version -isnot [int] -or $r.schema_version -ne 2 -or $r.kind -cne 'kagrenac-port-runtime' -or $r.id -cne $workingId -or
        $r.build_dir -isnot [string] -or $r.build_dir -cnotmatch '^[A-Za-z]:\\' -or
        $r.files -isnot [System.Management.Automation.PSCustomObject] -or
        $r.build_files -isnot [System.Management.Automation.PSCustomObject]) { throw 'Invalid generic port runtime record.' }
    $b = Get-GenericPortBuild $r.build_dir
    if ($r.engine -cne $b.Engine -or $r.build -cne $b.Record.build -or $r.game_build_sha256 -cne $b.Record.game_build_sha256) {
        throw 'The runtime and its build disagree on the engine, build or game pin.'
    }
    $files = @($r.files.PSObject.Properties)
    $map = @($r.build_files.PSObject.Properties)
    $buildNames = @($b.Record.files.PSObject.Properties | ForEach-Object { $_.Name })
    if ($files.Count -ne $buildNames.Count -or $map.Count -ne $files.Count -or
        @($map | ForEach-Object { $_.Value } | Select-Object -Unique).Count -ne $buildNames.Count) {
        throw 'The runtime must stage every build artifact exactly once.'
    }
    foreach ($p in $files) {
        $source = $r.build_files.($p.Name)
        if ($source -isnot [string] -or $buildNames -cnotcontains $source -or
            $p.Value -isnot [string] -or $p.Value -cne [string]$b.Record.files.($source)) { throw 'The runtime artifact mapping does not match its build.' }
        $file = Get-PortArtifact $folder $p.Name
        if ((Get-FileSha256Hex $file) -cne $p.Value) { throw "Runtime artifact changed: $file" }
    }
    return @{ Dir = $b.Dir; DllSha = $b.DllSha; Engine = $b.Engine }
}
