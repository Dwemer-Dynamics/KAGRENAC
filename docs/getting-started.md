# Getting started (developer cold start)

The shortest path from nothing to a working mock server and console client with
KAGRENAC AI Mod Maker. Each step links to the canonical detail; this page does not repeat it.

## 1. What you need

| Where | What | Detail |
|---|---|---|
| Windows | DwemerDistro installed and started (WSL, Apache on the shared custom mods port 19000, PostgreSQL, PHP 8.2) | [SETUP.md, Requirements](../SETUP.md#requirements) |
| Windows | Git, and Visual Studio 2022 with "Desktop development with C++" | [SETUP.md, Requirements](../SETUP.md#requirements) |
| DwemerDistro | A Core version with the custom mod web protection | [SETUP.md, Before you install](../SETUP.md#before-you-install-web-protection) |
| Optional | An LLM provider, PocketTTS and Parakeet | [CONNECTORS.md](../CONNECTORS.md) |

Nothing here installs these for you.

## 2. Two copies of one repository

| Copy | Where | Job |
|---|---|---|
| Windows development copy | Any folder you own, for example `C:\dev\Kagrenac` | Edit, build the client, run `scripts\project.ps1` and your agent |
| WSL server copy | `/var/www/html/custom-mods/KagrenacServer` (manual) or `/custom-mods/example-server` (launcher) | Run the server only |

They are separate clones. Never build the client, write its `config.json` or keep build
output in the server copy: it sits in Apache's web root.

## 3. Windows development copy

```powershell
git clone https://github.com/Dwemer-Dynamics/Kagrenac.git
cd Kagrenac
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 doctor
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 setup
```

| Command | Does | Never |
|---|---|---|
| `doctor` | Reports tools, WSL distros, client builds, the client config (token shown only as set or missing) and server health (`ok` and the `example-ai-server` identity only; not model, voice or game readiness). On a healthy server it probes `.git/`, `client/`, `docs/` and `ports/` on that URL: only HTTP 403 counts as protected; 200 is exposed, and any other status or no answer is unverified. Both count as problems | Changes anything |
| `setup` | Builds the client for x64 and x86 with `client\scripts\build.ps1` into `%LOCALAPPDATA%\DwemerDynamics\KagrenacClient\build` (change with `-BuildRoot`, which must be outside the repository); safe to repeat. Lists the remaining manual steps | Installs prerequisites, copies source into WSL, writes a client config |
| `check` | `php -l` on every server PHP file (root, `lib/`, `scripts/`, `config/`, `ui/`; not `client/`, `docs/` or `ports/`) and `bash -n`, with local tools when present, then the client build (fails on compiler warnings in files compiled that run) | Runs migrations or any other database operation |

Explicit opt-ins, both against an **existing** WSL server checkout you name:

- `setup -RunServerInstaller -WslDistro <name> -WslServerPath /var/www/html/custom-mods/KagrenacServer`
  runs that checkout's existing `scripts/install.sh` as root (safe to repeat; it keeps the
  config and database). It refuses a missing or unsafe path, the launcher-managed
  `/custom-mods/example-server`, any folder Core's web protection does not cover, and a
  distro where that protection is not installed.
- `check -RunSmoke -WslDistro <name> -WslServerPath <checkout>` runs `scripts/smoke.sh`
  there as `dwemer` (add `-ServerUrl` if your port or route differs).

`doctor -WslDistro <name> -WslServerPath <checkout>` also checks that checkout, whether its
private config exists (without reading it) and whether the protection rules are present.
Naming a distro may start it.

## 4. WSL server copy

Install Core's web protection first ([SETUP.md, Before you install](../SETUP.md#before-you-install-web-protection)),
then follow [SETUP.md section 1](../SETUP.md#1-install-the-server-inside-dwemerdistro)
(or the launcher, [LAUNCHER_CUSTOM_MOD.md](../LAUNCHER_CUSTOM_MOD.md)). In short, as `dwemer`
after **Update Distro**:

```bash
sudo ddistro_custom_mod setup-web
grep -qF '(client|ports|docs)' /etc/apache2/sites-available/dwemerdistro-custom-mods.conf && echo protected
# Continue only if it printed "protected".
sudo install -d -o dwemer -g dwemer /var/www/html/custom-mods/KagrenacServer
git clone https://github.com/Dwemer-Dynamics/Kagrenac.git /var/www/html/custom-mods/KagrenacServer
cd /var/www/html/custom-mods/KagrenacServer
sudo bash scripts/install.sh
bash scripts/smoke.sh
```

Then check exposure as [START_HERE.md](../START_HERE.md#deployment-and-exposure) describes.
Updates use `sudo bash scripts/update.sh` in this copy, from your pushed branch
([SETUP.md section 6](../SETUP.md#6-back-up-and-update)).

## 5. Pair and talk

Pair as [SETUP.md section 3](../SETUP.md#3-connect-them) describes: `pair_client.php` writes a
private file outside the web root; copy it next to `KagrenacClient.exe` as `config.json`.
Then:

```text
KagrenacClient.exe --health
KagrenacClient.exe --say "Follow me"
```

The full walkthrough is [START_HERE.md](../START_HERE.md#end-to-end-walkthrough).

## 6. Start your own mod

1. Give your agent the first prompt in
   [README.md](../README.md#first-prompt-for-your-coding-agent); it fills in
   [PROJECT.md](../PROJECT.md) from your conversation and asks only for what is missing.
2. Qualify your engine with a copy of [engine-packs/ENGINE_PACK.md](engine-packs/ENGINE_PACK.md).
3. Port in stages with [agent-playbook.md](agent-playbook.md) and
   [feature-recipes/PORT_RECIPES.md](feature-recipes/PORT_RECIPES.md).
4. Rename your copy with [MAKE_IT_YOURS.md](../MAKE_IT_YOURS.md).
