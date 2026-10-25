#!/usr/bin/env bash
# Linux side of 'scripts/project.ps1 deploy'. project.ps1 runs it as root in the named
# DwemerDistro, from the Windows checkout, with an argument vector (never a shell string):
#   bash scripts/project-runtime.sh deploy <id> <commit> <bundle> <bundle-sha256> [<manual folder>]
# The manifest is read from <commit> inside the bundle. A new or Core-managed install goes
# through DwemerDistro Core (ddistro_custom_mod) only, fed from one private bare cache per
# project; an existing manual folder goes through scripts/update.sh of <commit>. It never
# registers or adopts a folder, never resets a checkout or rewrites a private config, never
# chmods recursively and prints no config, token or PHP output. When the web server cannot
# save a Core-managed install's config/config.php, it runs that commit's scripts/install.sh,
# which sets the config folder's, file's and lock's ownership and mode (contents kept), and
# also confirms the database and applies pending migrations. Core's install and update set
# the read-only ownership again, so a later deploy repairs it again.
# Exit codes: 0 deployed and verified; 1 refused or failed before the mod folder changed;
# 3 the mod folder changed but a later step or check failed (backup and recovery are printed).
set -euo pipefail

# DwemerDistro Core's layout and accounts.
WEB_ROOT=/var/www/html
STATE_ROOT=/var/lib/dwemerdistro-custom-mods
APP_USER=dwemer
APP_HOME=/home/dwemer
WEB_USER=www-data
ROOT_UID=0
CORE=ddistro_custom_mod
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
# Every listener that serves the project must answer 403 for all of these (Core web protection).
PROBES=(.git/HEAD .git/config client/CMakeLists.txt ports/ docs/getting-started.md config/
        config/config.php lib/app.php sql/001_init.sql scripts/migrate.php config.json .env
        ui/config.json client/config.json)
ZERO=0000000000000000000000000000000000000000
# A direct server folder, /var/www/html/<Name>Server (Core refuses reserved names).
DIRECT='[A-Z][A-Za-z0-9]{0,40}Server'
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '[%s] %s\n' "$1" "$2"; }
stage() { say STAGE "$1"; }

# Before the mod folder changes, a failure leaves it as it was (exit 1); after, exit 3.
changed=0
fail() {
    say FAIL "$1"
    if [ "$changed" = 1 ]; then recovery; exit 3; fi
    say INFO "The mod folder, its private config and database were not changed."
    exit 1
}

recovery() {
    if [ "$mode" = manual ]; then
        say INFO "Backup from scripts/update.sh: ${backup:-none}. Restore it by hand as SETUP.md section 6 describes; nothing is rolled back automatically."
    else
        say INFO "Core backup from before this deploy: ${backup:-none (Core made none in this run)}. Retry by running deploy again, or: sudo $CORE update $id --expect-commit $sha"
        say INFO "Code is never moved back automatically and database changes are not reversed; restore from the backup by hand if needed."
    fi
    if [ "$prepare" = 1 ]; then
        say INFO "scripts/install.sh may have changed the owner, group and mode of config/, config.php and config.php.lock (never their contents) and applied pending migrations. Run deploy again to finish, or: sudo bash $folder/scripts/install.sh"
    fi
}

# As dwemer with a clean environment: no user or system Git config, prompts or credentials.
as_app() {
    runuser -u "$APP_USER" -- env -i PATH="$PATH" HOME="$APP_HOME" LANG=C.UTF-8 GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false "$@"
}
appgit() { as_app git -c core.hooksPath=/dev/null -c credential.helper= -c protocol.file.allow=always "$@"; }

# Runs Core and shows only its [OK] and [FAIL] lines: its [INFO] lines can carry migration output.
core() {
    local status=0
    core_out="$("$CORE" "$@" 2>&1)" || status=$?
    printf '%s\n' "$core_out" | grep -E '^\[(OK|FAIL)\] [[:print:]]{1,300}$' || true
    return "$status"
}

# A real folder owned by dwemer that only dwemer can change.
owned_dir() {
    [ -d "$1" ] && [ ! -L "$1" ] && [ "$(stat -c %U -- "$1")" = "$APP_USER" ] &&
        [ $(( 8#$(stat -c %a -- "$1") & 8#022 )) -eq 0 ]
}

# id, default branch, allowed branches (space-separated), setup.config_path, health_path,
# server_folder (empty: the custom-mods/<id> layout).
manifest_fields() {
    appgit -C "$1" show "$2:dwemer-mod.json" | as_app python3 -c '
import json, sys
m = json.load(sys.stdin)
b = m.get("branches") or {}
d = b.get("default") or "main"
print(m["id"]); print(d); print(" ".join(b.get("allowed") or [d]))
print(m["setup"]["config_path"]); print(m["health_path"]); print(m.get("server_folder") or "")'
}

# Core's public, root-owned registry entry for the id: state, repository, local_source, folder,
# database, branch, commit and legacy_route (a moved install's old URL) into reg[]. Tombstones
# (state unregistered) are included.
read_registry() {
    local file=$STATE_ROOT/registry/$id.json
    [ -f "$file" ] && [ ! -L "$file" ] && [ "$(stat -c %u -- "$file")" = "$ROOT_UID" ] &&
        [ $(( 8#$(stat -c %a -- "$file") & 8#022 )) -eq 0 ] ||
        fail "Core's registry entry for $id is not a plain root-owned file."
    mapfile -t reg < <(python3 -c '
import json, sys
e = json.load(open(sys.argv[1], encoding="utf-8"))
for k in ("state", "repository", "local_source", "folder", "database", "branch", "commit", "legacy_route"):
    v = str(e.get(k, "")).lower() if k == "local_source" else str(e.get(k) or "")
    if not v.isprintable() or " " in v: sys.exit(1)
    print(v)' "$file" 2>/dev/null || true)
    [ "${#reg[@]}" -eq 8 ] || fail "Core's registry entry for $id is unreadable."
}

config_hash() { if [ -f "$1" ] && [ ! -L "$1" ]; then sha256sum < "$1" | cut -d' ' -f1; else echo none; fi; }

# A standard private config only returns settings. One that includes, evaluates or reads another
# file is not supported: Core's backup copies the file, not what it loads. Read as dwemer, never run.
standard_config() {
    as_app php -r '$code = @file_get_contents($argv[1]);
if ($code === false) exit(2);
foreach (token_get_all($code) as $t) {
    if (is_array($t) && (in_array($t[0], [T_INCLUDE, T_INCLUDE_ONCE, T_REQUIRE, T_REQUIRE_ONCE, T_EVAL], true)
        || (in_array($t[0], [T_STRING, T_NAME_FULLY_QUALIFIED], true)
            && in_array(strtolower(ltrim($t[1], "\\")), ["file_get_contents", "parse_ini_file", "getenv", "fopen", "file"], true)))) exit(1);
}' "$config" >/dev/null 2>&1
}

# What would stop a dashboard save, as the web server sees it (the deployed lib/config_writer.php).
# Prints one problem per line; nothing means saving works.
web_config_problems() {
    local out status=0
    out="$(runuser -u "$WEB_USER" -- env -i PATH="$PATH" LANG=C.UTF-8 php -d display_errors=0 -r '
require $argv[1] . "/lib/config_writer.php";
foreach (config_write_problems($argv[1] . "/config/config.php") as $p) echo $p, "\n";' "$folder" 2>/dev/null)" || status=$?
    printf '%s\n' "$out" | grep -E '^[[:print:]]{1,300}$' || true
    [ "$status" -eq 0 ] || echo "$WEB_USER could not run the config check in $folder/lib/config_writer.php."
}

# Runs this commit's scripts/install.sh when the web server cannot save the private config, and
# checks the contents and the lock file stay the same. Sets prepared to ok or repaired.
prepare_config() {
    local problems before lock out status=0
    problems="$(web_config_problems)"
    if [ -z "$problems" ]; then
        prepared=ok
        say OK "$WEB_USER can already save the private config from the dashboard; scripts/install.sh was not run."
        return
    fi
    printf '%s\n' "$problems" | sed 's/^/[INFO] Before: /'
    [ ! -L "$folder/config" ] && [ ! -L "$config" ] && [ ! -L "$config.lock" ] ||
        fail "config/, config.php or its lock is a symbolic link; it is not repaired."
    standard_config || fail "$config is not a standard config (it loads settings from elsewhere, or dwemer cannot read it); it is not repaired. Keep every setting in config/config.php itself, or repair it yourself."
    stage "Preparing config/ for dashboard saves with scripts/install.sh of $sha (owner, group and mode; it also confirms the database and applies pending migrations; contents kept)."
    before="$(config_hash "$config")"
    lock="$(stat -c %d:%i -- "$config.lock" 2>/dev/null || echo none)"
    prepare=1 changed=1
    out="$(env -i PATH="$PATH" LANG=C.UTF-8 bash "$folder/scripts/install.sh" 2>&1)" || status=$?
    # Only its own fixed lines; PHP and database errors can quote config or connection details.
    printf '%s\n' "$out" | grep -E '^(ERROR: |Keeping existing config|Database [a-z0-9_]{1,63} already exists|Created database |applied: |schema ready for )[[:print:]]{0,300}$' |
        sed 's/^/[INFO] install.sh: /' || true
    [ "$status" -eq 0 ] || fail "scripts/install.sh stopped (exit $status) while preparing config/."
    [ "$(config_hash "$config")" = "$before" ] || fail "The private config's contents changed while preparing config/."
    [ "$(stat -c %d:%i -- "$config.lock" 2>/dev/null || echo none)" = "$lock" ] || fail "The config lock file was replaced while preparing config/."
    problems="$(web_config_problems)"
    if [ -n "$problems" ]; then
        printf '%s\n' "$problems" | sed 's/^/[INFO] After: /'
        fail "$WEB_USER still cannot save the private config after scripts/install.sh."
    fi
    prepared=repaired
    say OK "Repaired: $WEB_USER can now save the private config from the dashboard (owner, group and mode changed; contents and lock kept)."
    say INFO "The launcher's Update and '$CORE update' set config/ read-only for $WEB_USER again; run deploy again after them."
}

# Imports the bundle into the project's private bare cache and moves its offered branches to
# the commit, fast-forward only and all at once; HEAD names the default branch for Core.
import_cache() {
    local dir=$APP_HOME part old b updates=""
    owned_dir "$dir" || fail "$dir must be a real folder owned by $APP_USER that only it can change."
    for part in .local share kagrenac "$id"; do
        dir=$dir/$part
        if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then as_app mkdir -m 700 -- "$dir"; fi
        owned_dir "$dir" || fail "$dir must be a real folder owned by $APP_USER that only it can change."
    done
    cache=$dir/source.git
    if [ ! -e "$cache" ] && [ ! -L "$cache" ]; then
        appgit init --quiet --bare "$cache"
        stage "Created the private source cache $cache."
    fi
    owned_dir "$cache" && [ -z "$(find "$cache" \( -type l -o ! -user "$APP_USER" -o -perm -0002 \) -print -quit)" ] &&
        [ "$(appgit -C "$cache" rev-parse --is-bare-repository 2>/dev/null)" = true ] ||
        fail "$cache is not a bare Git cache owned by $APP_USER without links. Nothing was repointed."
    appgit -C "$cache" fetch --quiet --no-tags --no-write-fetch-head "$tmp/source.bundle" "+HEAD:refs/kagrenac/incoming"
    [ "$(appgit -C "$cache" rev-parse --verify 'refs/kagrenac/incoming^{commit}')" = "$sha" ] ||
        fail "The cache did not receive commit $sha from the bundle."
    for b in $allowed; do
        old="$(appgit -C "$cache" rev-parse --quiet --verify "refs/heads/$b^{commit}" || true)"
        if [ -n "$old" ] && [ "$old" != "$sha" ]; then
            [ "$(manifest_fields "$cache" "$old" | head -n 1)" = "$id" ] ||
                fail "The cache's branch $b belongs to a different project. Nothing was repointed."
            appgit -C "$cache" merge-base --is-ancestor "$old" "$sha" ||
                fail "Commit $sha does not build on $old, deployed before from this project (unrelated or rewritten history). Nothing was repointed."
        fi
        updates+="update refs/heads/$b $sha ${old:-$ZERO}"$'\n'
    done
    printf '%s' "$updates" | appgit -C "$cache" update-ref --stdin
    appgit -C "$cache" symbolic-ref HEAD "refs/heads/$branch"
    appgit -C "$cache" update-ref -d refs/kagrenac/incoming
    stage "Source cache $cache offers $branch at $sha."
}

# Health 200 with ok true at the expected schema, and HTTP 403 for every probe, on each Apache
# listener that serves the route. Prints SERVING <ports> and fails if none or any probe fails.
check_http() {
    local ports
    ports="$(ss -Hltnp 2>/dev/null | awk '/"apache2"/ { n = split($4, a, ":"); print a[n] }' | sort -un | tr '\n' ' ')"
    as_app python3 - "$route" "$health_path" "$schema" "${PROBES[@]}" -- $ports <<'PY'
import json, sys, urllib.error, urllib.request
route, health, schema = sys.argv[1:4]
split = sys.argv.index("--")
probes, ports = sys.argv[4:split], sys.argv[split + 1:]
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None
opener = urllib.request.build_opener(NoRedirect, urllib.request.ProxyHandler({}))
def get(url):
    try:
        with opener.open(urllib.request.Request(url, headers={"User-Agent": "kagrenac-deploy"}), timeout=10) as r:
            return r.status, r.read(65536)
    except urllib.error.HTTPError as error: return error.code, b""
    except Exception: return 0, b""
serving, bad = [], 0
for port in ports:
    base = f"http://127.0.0.1:{port}{route}"
    status, body = get(f"{base}/{health}")
    codes = {probe: get(f"{base}/{probe}")[0] for probe in probes}
    if status != 200:
        # Not serving the route; it still must not serve any of these paths.
        exposed = [probe for probe, code in codes.items() if code == 200]
        for probe in exposed: print(f"[FAIL] {base}/{probe} answered HTTP 200 on a listener without this route's health.")
        bad += len(exposed)
        if not exposed: print(f"[INFO] Listener {port} does not serve {route} (health HTTP {status}); none of its source or config paths answered 200.")
        continue
    try: doc = json.loads(body)
    except ValueError: doc = None
    healthy = isinstance(doc, dict) and doc.get("ok") is True and (not schema or doc.get("schema") == schema)
    for probe, code in codes.items():
        if code != 403: print(f"[FAIL] {base}/{probe} answered HTTP {code}, not 403."); bad += 1
    denied = sum(code == 403 for code in codes.values())
    bad += 0 if healthy else 1
    print(f"[{'OK' if healthy and denied == len(probes) else 'FAIL'}] Listener {port}: health {'ok' if healthy else 'NOT ok:true'} at schema "
          f"{schema or '(any)'}, {denied} of {len(probes)} source and config paths denied (HTTP 403).")
    serving.append(port)
if not serving: print(f"[FAIL] No Apache listener serves {route} with ok health."); bad += 1
print("SERVING " + " ".join(serving))
sys.exit(1 if bad else 0)
PY
}

main() {
    [ "$(id -u)" -eq "$ROOT_UID" ] || { say FAIL "Run as root (project.ps1 deploy does this)."; exit 1; }
    [ "${1:-}" = deploy ] && [ $# -ge 5 ] && [ $# -le 6 ] || { say FAIL "Usage: project-runtime.sh deploy <id> <commit> <bundle> <bundle-sha256> [<manual folder>]"; exit 1; }
    id=$2 sha=$3 bundle=$4 bundle_hash=$5 manual=${6:-} mode="" backup="" previous="" cache=""
    tmp="" core_out="" prepare=0 prepared=unchecked folder=""
    umask 077
    cd /
    [[ $id =~ ^[a-z][a-z0-9-]{1,30}[a-z0-9]$ && $id != *--* ]] || fail "Unsupported project id."
    [[ $sha =~ ^[0-9a-f]{40}$ && $bundle_hash =~ ^[0-9a-f]{64}$ ]] || fail "Unsupported commit or bundle hash."
    [[ $bundle == /* && $bundle != */../* && -f $bundle && ! -L $bundle ]] || fail "The bundle is not a plain file."
    if [ -n "$manual" ]; then
        [[ $manual =~ ^$WEB_ROOT/(custom-mods/[A-Za-z0-9_-][A-Za-z0-9._-]*|ExampleServer|$DIRECT)$ ]] || fail "Unsupported manual folder."
    fi

    stage "Checking DwemerDistro Core and tools."
    command -v "$CORE" >/dev/null || fail "$CORE is missing; this is not DwemerDistro, or Core needs Update Distro from the launcher."
    local need help
    help="$("$CORE" --help 2>&1 || true)"
    for need in "setup-web --protect-project" "update <id> [--expect-commit" "--local-source"; do
        grep -qF -- "$need" <<< "$help" ||
            fail "DwemerDistro Core is too old for deploy (no '$need'). Run Update Distro from the DwemerDistro launcher, then deploy again. Core was not patched."
    done
    for need in git python3 sha256sum runuser ss; do
        command -v "$need" >/dev/null || fail "$need is missing in this distro."
    done
    # Read-only, before any cache, Core or folder change; deploy never installs packages. Its
    # [FAIL]/[INFO] lines (reasons, floors, update and restart steps) reach project.ps1's console.
    bash "$HERE/check-php-runtime-security.sh" ||
        fail "The distro's PHP runtime is not patched or could not be verified (reasons above). Update only its PHP packages, restart Apache, PHP-FPM and PHP workers, then deploy again."

    stage "Checking the bundle."
    tmp="$(as_app mktemp -d /tmp/kagrenac-deploy.XXXXXXXX)"
    [[ $tmp =~ ^/tmp/kagrenac-deploy\.[A-Za-z0-9]{8}$ ]] || fail "Could not create a private temporary folder."
    trap 'rm -rf -- "$tmp"' EXIT
    cp -- "$bundle" "$tmp/source.bundle"
    chown -- "$APP_USER:" "$tmp/source.bundle"
    [ "$(sha256sum < "$tmp/source.bundle" | cut -d' ' -f1)" = "$bundle_hash" ] || fail "The bundle changed on its way into WSL (SHA-256)."
    appgit init --quiet --bare "$tmp/scratch.git" &&
        appgit -C "$tmp/scratch.git" fetch --quiet --no-tags "$tmp/source.bundle" "+HEAD:refs/heads/deploy" >/dev/null 2>&1 ||
        fail "The bundle is not a readable Git bundle."
    [ "$(appgit -C "$tmp/scratch.git" rev-parse --verify 'refs/heads/deploy^{commit}')" = "$sha" ] || fail "The bundle's HEAD is not commit $sha."
    local fields
    mapfile -t fields < <(manifest_fields "$tmp/scratch.git" "$sha" 2>/dev/null || true)
    [ "${#fields[@]}" -eq 6 ] && [ "${fields[0]}" = "$id" ] || fail "dwemer-mod.json at $sha does not declare id $id."
    branch=${fields[1]} allowed=${fields[2]} config_path=${fields[3]} health_path=${fields[4]} server_folder=${fields[5]}
    [[ -z $server_folder || $server_folder =~ ^$DIRECT$ ]] || fail "Unsupported server_folder in dwemer-mod.json."
    [[ " $allowed " == *" $branch "* && $allowed =~ ^[A-Za-z0-9._/\ -]+$ && $config_path =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ &&
       $health_path =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ && "$config_path$health_path" != *..* ]] || fail "Unsupported branches or setup paths in dwemer-mod.json."
    ! appgit -C "$tmp/scratch.git" cat-file -e "$sha:$config_path" 2>/dev/null || fail "Commit $sha tracks the private config $config_path."
    schema="$(appgit -C "$tmp/scratch.git" ls-tree --name-only "$sha" sql/ | grep -E '^sql/[0-9]{3}_[A-Za-z0-9_]+\.sql$' | sort | tail -n 1 || true)"
    schema=${schema#sql/}
    schema=${schema%.sql}

    stage "Finding the install for $id."
    local reg=() folder database expected_folder=$WEB_ROOT/custom-mods/$id
    [ -z "$server_folder" ] || expected_folder=$WEB_ROOT/$server_folder
    if [ -e "$STATE_ROOT/registry/$id.json" ] || [ -L "$STATE_ROOT/registry/$id.json" ]; then read_registry; fi
    if [ -n "$manual" ]; then
        mode=manual folder=$manual
        [ "${#reg[@]}" -eq 0 ] || [ "${reg[3]}" != "$manual" ] ||
            fail "$manual belongs to Core's entry for $id (state ${reg[0]}); deploy without -WslServerPath so Core manages it."
    elif [ "${#reg[@]}" -eq 8 ]; then
        # Core's registered folder wins: custom-mods/<id>, or the direct root it installed or moved it to.
        folder=${reg[3]}
        case "${reg[0]}:${reg[2]}" in
            unregistered:true) mode=restore ;;
            unregistered:*) fail "Core's removed entry for $id came from ${reg[1]}, not this deploy cache; it is not adopted." ;;
            *:true) mode=local ;;
            *) mode=remote ;;
        esac
        [[ $folder == "$WEB_ROOT/custom-mods/$id" || $folder =~ ^$WEB_ROOT/$DIRECT$ ]] && [ "${reg[4]}" = "custom_${id//-/_}" ] &&
            [[ -z ${reg[7]} || ${reg[7]} == "/custom-mods/$id" ]] ||
            fail "Core's entry for $id names an unexpected folder, database or old URL."
        if [ "$folder" != "$expected_folder" ]; then
            say INFO "dwemer-mod.json names ${server_folder:-no server_folder}; Core keeps $id in $folder.$([ -z "$server_folder" ] || echo " To move it: sudo $CORE migrate-root $id --server-folder $server_folder")"
        fi
        if [ "$mode" != remote ]; then
            [ "${reg[1]}" = "$APP_HOME/.local/share/kagrenac/$id/source.git" ] ||
                fail "Core's entry for $id uses another local source; it is not repointed."
        fi
        [ "${reg[5]}" = "$branch" ] || fail "Core's entry for $id is on branch ${reg[5]}, not $branch (the manifest default); switch it back in the launcher first."
    else
        mode=new folder=$expected_folder
        if [ -e "$folder" ] || [ -L "$folder" ]; then
            fail "$folder exists but is not registered with Core. If it is your manual install, pass -WslServerPath $folder; it is never adopted."
        fi
        [ "$id" != example-server ] ||
            fail "dwemer-mod.json still has the template id example-server. Set your own project id there, commit, and deploy again."
    fi

    local route=${folder#"$WEB_ROOT"} protect="" config before_hash
    if [[ $route != /custom-mods/* && $route != /ExampleServer ]]; then
        grep -qF -- "--protect-root" <<< "$help" ||
            fail "DwemerDistro Core is too old for $folder (no 'setup-web --protect-root'). Run Update Distro from the DwemerDistro launcher, then deploy again."
    fi
    config=$folder/$config_path
    if [ "$mode" != new ]; then
        [ -d "$folder" ] && [ ! -L "$folder" ] && [ -d "$folder/.git" ] || fail "$folder is not a plain Git checkout."
        [ "$(stat -c %U -- "$folder")" = "$APP_USER" ] || fail "$folder is not owned by $APP_USER."
        previous="$(appgit -C "$folder" rev-parse --verify 'HEAD^{commit}')" || fail "Could not read the commit in $folder."
        [ "$(manifest_fields "$folder" HEAD 2>/dev/null | sed -n '1p;4p' | tr '\n' ' ')" = "$id $config_path " ] ||
            fail "$folder declares another project id or private config path."
        if [ "$previous" != "$sha" ]; then
            appgit -C "$tmp/scratch.git" cat-file -e "$previous^{commit}" 2>/dev/null &&
                appgit -C "$tmp/scratch.git" merge-base --is-ancestor "$previous" "$sha" ||
                fail "$folder is at $previous, which $sha does not build on (unrelated or rewritten history)."
        fi
    fi
    if [ "$mode" = manual ]; then
        [ -f "$config" ] && [ ! -L "$config" ] || fail "$folder has no private config at $config_path; run its scripts/install.sh first."
        runuser -u "$WEB_USER" -- test -x "$folder" && runuser -u "$WEB_USER" -- test -r "$config" ||
            fail "$WEB_USER cannot reach $config; repair it with that folder's scripts/install.sh first."
    fi
    if [ "$mode" = remote ] && [ "$previous" != "$sha" ]; then
        local published
        command -v timeout >/dev/null || fail "timeout (coreutils) is needed to check Core's remote for $id."
        published="$(as_app timeout -k 5 60 git -c core.hooksPath=/dev/null -c credential.helper= -c protocol.file.allow=always             ls-remote "${reg[1]}" "refs/heads/$branch" 2>/dev/null | cut -f1 || true)"
        [ "$published" = "$sha" ] ||
            fail "Core installed $id from ${reg[1]} (branch $branch), which does not publish $sha or did not answer within 60 seconds. Publish it there first; deploy does not repoint or adopt a remote install."
    fi
    before_hash="$(config_hash "$config")"
    if [ "$mode" != manual ]; then
        # Checked before Core backs up or changes anything.
        [ "$config_path" = config/config.php ] ||
            fail "Deploy prepares only the standard private config config/config.php, not $config_path; change setup.config_path in dwemer-mod.json."
        if [ "$before_hash" != none ]; then
            standard_config ||
                fail "$config is not a standard config (it loads settings from elsewhere, or dwemer cannot read it). Core's backup would not hold those settings; keep every setting in config/config.php itself, then deploy again."
        fi
    fi

    case "$route" in
        /custom-mods/KagrenacServer|/ExampleServer) say INFO "$route is covered by Core's built-in web protection." ;;
        /custom-mods/*)
            protect=${route#/custom-mods/}
            [[ $protect =~ ^[a-z][a-z0-9-]{1,30}[a-z0-9]$ && $protect != *--* ]] ||
                fail "Core cannot protect $folder (folder name is not a project id); add equivalent Apache rules yourself."
            stage "Protecting /custom-mods/$protect before any source is placed."
            core setup-web --protect-project "$protect" || fail "Core web protection for /custom-mods/$protect is not active."
            ;;
        *)
            protect=${route#/}
            stage "Protecting $route on every Apache listener before any source is placed."
            core setup-web --protect-root "$protect" || fail "Core web protection for $route is not active."
            ;;
    esac

    local action=updated status=0
    if [ "$previous" = "$sha" ] && { [ "$mode" = manual ] || [ "${reg[0]}" = ready ]; }; then
        action=already
        say OK "The code in $folder is already at commit $sha; it was not updated, backed up or migrated again."
    elif [ "$mode" = manual ]; then
        stage "Updating the manual install with its scripts/update.sh (backup, fast-forward, migrations)."
        local out
        out="$(umask 022 && bash "$HERE/update.sh" --app-dir "$folder" --bundle "$tmp/source.bundle" --commit "$sha" 2>&1)" || status=$?
        printf '%s\n' "$out" | grep -E '^(Refusing to update|Backup (written to|did not finish)|Already up to date|Update finished|Code updated to|The failed migration|Fix the cause|Or restore|Keep your changes|Move it aside)[[:print:]]{0,300}$' |
            sed 's/^/[INFO] /' || true
        backup="$(printf '%s\n' "$out" | sed -n 's/^Backup written to \(\/[[:graph:]]*\)$/\1/p' | tail -n 1)"
        [ "$status" -ne 3 ] || changed=1
        [ "$status" -eq 0 ] || fail "scripts/update.sh stopped (exit $status)."
        changed=1
    else
        [ "$mode" = remote ] || import_cache
        local head=$previous
        if [ "$mode" = new ] || [ "$mode" = restore ]; then
            stage "Installing through Core from $cache."
            core install --local-source "$cache" --expect-commit "$sha" || status=$?
            if [ "$mode" = new ] && [ -e "$folder" ]; then changed=1; fi
            [ "$status" -eq 0 ] || fail "Core install did not finish."
            changed=1
            [ "$mode" = new ] && action=installed || action=restored
            head="$(appgit -C "$folder" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" ||
                fail "Core installed $id but $folder has no readable commit."
            read_registry
        fi
        # Also retries a failed Core state at the same commit (backup, migrations, health).
        if [ "$head" != "$sha" ] || [ "${reg[0]}" != ready ]; then
            stage "Updating through Core to exactly $sha."
            core update "$id" --expect-commit "$sha" || status=$?
            backup="$(printf '%s\n' "$core_out" | sed -n "s|^\[OK\] Backup saved in \($STATE_ROOT/backups/$id/[0-9]*-[0-9]*\)\$|\1|p" | tail -n 1)"
            [ "$(appgit -C "$folder" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)" = "$head" ] || changed=1
            [ "$status" -eq 0 ] || fail "Core update did not finish."
            changed=1 action=updated
        fi
    fi

    stage "Verifying the deployed folder, permissions, config and web protection."
    [ "$(appgit -C "$folder" rev-parse --verify 'HEAD^{commit}')" = "$sha" ] || fail "$folder is not at $sha."
    [ -z "$(appgit -C "$folder" status --porcelain --untracked-files=no)" ] || fail "$folder has changes to tracked files."
    if [ "$mode" != manual ]; then
        read_registry
        [ "${reg[0]}" = ready ] && [ "${reg[6]}" = "$sha" ] || fail "Core does not report $id ready at $sha."
        database=${reg[4]}
        prepare_config
    else
        database="$(as_app php "$folder/scripts/database-name.php" 2>/dev/null || true)"
        [[ $database =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || fail "Could not read the manual install's database name."
    fi
    runuser -u "$WEB_USER" -- test -x "$folder" && runuser -u "$WEB_USER" -- test -r "$folder/$health_path" &&
        runuser -u "$WEB_USER" -- test -r "$config" || fail "$WEB_USER cannot read the deployed files or the private config."
    [ -f "$config" ] && [ ! -L "$config" ] && [ $(( 8#$(stat -c %a -- "$config") & 8#007 )) -eq 0 ] &&
        [[ " $APP_USER $WEB_USER " == *" $(stat -c %U -- "$config") "* && " $APP_USER $WEB_USER " == *" $(stat -c %G -- "$config") "* ]] ||
        fail "The private config is not a regular file limited to $APP_USER and $WEB_USER."
    if [ "$before_hash" != none ] && [ "$(config_hash "$config")" != "$before_hash" ]; then
        fail "The private config changed during deploy."
    fi
    [ "$before_hash" != none ] || say OK "The private config was created once with a new token (not shown)."
    local http serving
    http="$(check_http)" || { printf '%s\n' "$http" | grep -E '^\[(OK|INFO|FAIL)\] ' || true; fail "Web checks failed."; }
    printf '%s\n' "$http" | grep -E '^\[(OK|INFO|FAIL)\] ' || true
    serving="$(printf '%s\n' "$http" | sed -n 's/^SERVING //p')"
    if [ "$mode" != manual ] && [ -n "${reg[7]}" ]; then
        # A moved install's old URL is Core's alias to the same folder until its clients use $route.
        stage "Checking the old URL ${reg[7]} (Core's alias to $folder; $route is canonical)."
        http="$(route=${reg[7]} check_http)" || { printf '%s\n' "$http" | grep -E '^\[(OK|INFO|FAIL)\] ' || true; fail "Web checks of the old URL failed."; }
        printf '%s\n' "$http" | grep -E '^\[(OK|INFO|FAIL)\] ' || true
    fi
    local port=${serving%% *} p
    for p in $serving; do if [ "$p" -ge 19000 ] && [ "$p" -le 19999 ]; then port=$p; break; fi; done
    printf 'RESULT mode=%s action=%s id=%s commit=%s branch=%s folder=%s database=%s url=%s backup=%s previous=%s protected=%s config=%s\n' \
        "$mode" "$action" "$id" "$sha" "$branch" "$folder" "$database" "http://127.0.0.1:$port$route" \
        "${backup:-none}" "${previous:-none}" "${protect:-built-in}" "$prepared"
}

main "$@"
