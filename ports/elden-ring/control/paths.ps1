# Shared helpers for the control tools (dot-sourced). Output folders must be new or empty,
# outside the repository and the game, and reached without any junction, symbolic link or
# name alias; the protected roots themselves must be reached the same way.

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..')).TrimEnd('\', '/')

function Refuse([string] $why) { Write-Host "refused: $why"; exit 1 }

# Relative paths resolve against the PowerShell location (what New-Item uses), not the
# process working directory.
# A drive root keeps its backslash: bare D: would mean the current folder on D:.
function Full([string] $p) {
    $abs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p)
    $f = [IO.Path]::GetFullPath($abs)
    if ($f -match '^[A-Za-z]:[\\/]$') { return $f.Substring(0, 2) + '\' }
    return $f.TrimEnd('\', '/')
}

function Under([string] $path, [string] $root) {
    $p = (Full $path).TrimEnd('\') + '\'; $r = (Full $root).TrimEnd('\') + '\'
    return $p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)
}

function Sha256([string] $file) {
    $s = [IO.File]::OpenRead($file)
    try { return -join ([Security.Cryptography.SHA256]::Create().ComputeHash($s) | ForEach-Object { $_.ToString('x2') }) }
    finally { $s.Dispose() }
}

# Absolute local drive path with each existing component spelled as it is on disk, so a DOS
# 8.3 alias (PROGRA~1) becomes the folder it names. Refuses what could still alias another
# folder: UNC and device paths, streams, trailing dots or spaces, and any ~digit component
# left after resolution. Subst and mapped drive letters are not detected.
function Resolve-LocalPath([string] $path) {
    # Windows drops trailing dots and spaces silently, so check the path as given.
    if ($path -match '^[\\/]{2}') { Refuse "$path is not a local drive path" }
    foreach ($leaf in ($path -split '[\\/]')) {
        if ($leaf -notin '', '.', '..' -and $leaf -match '[. ]$') { Refuse "path component '$leaf' in $path can alias another name" }
    }
    try { $full = Full $path } catch { Refuse "$path is not a usable local path" }
    if ($full -notmatch '^[A-Za-z]:(\\|$)') { Refuse "$path is not a local drive path" }
    $p = $full.Substring(0, 2) + '\'
    foreach ($leaf in ($full.Substring(2).Split('\') | Where-Object { $_ })) {
        if ($leaf -match '[:*?"<>|]' -or $leaf -match '[. ]$') { Refuse "path component '$leaf' in $path can alias another name" }
        $next = [IO.Path]::Combine($p, $leaf)
        if (Test-Path -LiteralPath $next) {
            try { $hits = @(([IO.DirectoryInfo] $p).GetFileSystemInfos($leaf)) } catch { Refuse "cannot list $p to resolve $leaf" }
            if ($hits.Count -ne 1) { Refuse "cannot resolve $next to one name on disk" }
            $leaf = $hits[0].Name
        }
        if ($leaf -match '~\d') { Refuse "path component '$leaf' in $path looks like a DOS 8.3 alias" }
        $p = [IO.Path]::Combine($p, $leaf)
    }
    if ($p.Length -eq 3) { return $p }
    return $p.TrimEnd('\')
}

# A junction or link anywhere on a path could point into the game or the repository, so
# every existing component must be a plain directory or file.
function Assert-NoLink([string] $path, [string] $what) {
    $p = $path
    while ($p) {
        if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Refuse "$what path component $p is a junction or link"
        }
        $p = [IO.Path]::GetDirectoryName($p)
    }
}

# Checked before anything is created: the output and every protected root resolve to long
# local names without links, and neither contains the other.
function Assert-OutDir([string] $dir, [string[]] $forbidden) {
    $out = Resolve-LocalPath $dir
    if ($out.Length -eq 3) { Refuse "output $dir is a drive root" }
    Assert-NoLink $out 'output'
    foreach ($r in $forbidden) {
        $root = Resolve-LocalPath $r
        Assert-NoLink $root 'protected root'
        if ((Under $out $root) -or (Under $root $out)) { Refuse "output $dir overlaps $root" }
    }
    if ((Test-Path -LiteralPath $out) -and (Get-ChildItem -LiteralPath $out -Force | Select-Object -First 1)) {
        Refuse "output $dir is not empty"
    }
}
