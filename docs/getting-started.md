# Getting started: from download to your first AI prototype

The one route for starting a mod with KAGRENAC AI Mod Maker. You talk with your coding agent;
the agent runs the commands, does the setup and writes things down in
[PROJECT.md](../PROJECT.md). Other pages are references the agent opens when a step needs
them; you do not have to read them first.

## The route

1. **Download.** Clone your copy (GitHub's **Use this template**, a fork, or
   `git clone https://github.com/Dwemer-Dynamics/Kagrenac.git`), open your coding agent in it
   and paste the [first prompt](../README.md#first-prompt-for-your-coding-agent).
2. **Brief, in conversation.** The agent reuses what you already said and asks only for what
   is missing, in this order: the game, the starting feature (a new companion or an existing
   NPC, and what it should do), and the mod name. No forms.
3. **Integration plan, before any mod code is built.** The agent fills the short plan in
   PROJECT.md: how the player's input reaches the mod, which NPC and how long it lives, how
   the HTTP call runs off the game thread and comes back to it, how the reply is shown and
   the voice played, which existing mechanism carries each action, saves, offline play and
   cancel, which facts are cited from the game's SDK or files and which are unknown, and
   what the first thin slice must show. For an unknown, the agent does bounded research: it
   says what it will look up and where, stops when it finds a citation or runs out of named
   sources, then gives you two or three concrete options with a recommendation. That is a
   short step, not a separate diagnostic stage, and the agent never invents an engine API.
   Steps 4 and 5 do not wait for it; only step 6 needs the plan with options chosen.
4. **DwemerDistro.** The agent runs `scripts\project.ps1 doctor -WslDistro <name>` for the
   one distro you use. If you have not named it and more than one distro is listed, the
   agent asks which one; doctor never probes the others. If DwemerDistro is missing, it
   walks you through the official installer. If it is there, the agent checks its runtime,
   Apache, PostgreSQL and web protection, then installs the server
   ([SETUP.md section 1](../SETUP.md#1-install-the-server-inside-dwemerdistro)) and pairs
   the client or mod with it ([SETUP.md section 3](../SETUP.md#3-connect-them)). Existing
   installs, configs and databases are kept; other distros are left alone.
5. **LLM and voice, tested for real.** The agent sets the LLM on the dashboard **LLM** page
   and presses **Send test**: a real reply is the pass. For voice it checks PocketTTS is
   installed and running in the DwemerDistro launcher (starting it there if it is not),
   enables it on the **Voice** page and presses **Speak**: you hearing it is the pass. You
   enter keys on the dashboard **API keys** page or in the private `config/config.php`,
   never in chat, logs or commits. Once you have chosen a provider, set its key privately
   and asked for the test, that is the permission for the test call; the agent makes no
   paid call just because you did not object.
6. **First real prototype.** The agent builds the thin slice from the plan in the game
   itself. Mock mode and the console client are developer checks for the server and shared
   code, not your demo, and no console exercise is required first.
7. **Expand.** One feature at a time: more actions, events, memory, speech to text. The
   [wave exercise](../WAVE_ACTION.md), memory and profiles come after the first AI line in
   game, never before it.

**Who does what.** The agent runs every command, does the service, dashboard and browser
work it has the tools for, writes the guides and records results. Only when a step is a
window it cannot drive does it give you the exact steps; it never hands you work it can do
itself. You answer missing facts, run installers that need your own consent or account,
enter keys privately, launch the game and say what you saw. Setup you already authorized
continues without asking again when it is routine and reversible; the agent asks only for a
missing provider, a key, or an install that needs your information. If one step is
blocked, the agent says what blocks it and the next action, and carries on with the steps
that do not depend on it.

**Going deeper.** A full engine port follows the staged prompt in
[agent-playbook.md](agent-playbook.md) and records engine evidence in
[engine-packs/ENGINE_PACK.md](engine-packs/ENGINE_PACK.md). Feature status:
[START_HERE.md](../START_HERE.md#feature-and-status-checklist).

## Two copies of one repository

| Copy | Where | Job |
|---|---|---|
| Windows development copy | Any folder you own, for example `C:\dev\Kagrenac` | Edit, build, run `scripts\project.ps1` and your agent |
| WSL server copy | `/var/www/html/custom-mods/KagrenacServer` (manual) or `/custom-mods/example-server` (launcher) | Run the server only |

They are separate clones. Never build the client, write its `config.json` or keep build
output in the server copy: it sits in Apache's web root.

## `scripts\project.ps1`

`powershell -ExecutionPolicy Bypass -File scripts\project.ps1 <doctor|setup|check>`

| Command | Does | Never |
|---|---|---|
| `doctor` | Reports tools, WSL distros with their state, client builds, the client config (token shown only as set or missing), server health (`ok` and the `example-ai-server` identity) and, on a healthy server, whether `.git/`, `client/`, `docs/` and `ports/` are denied (only HTTP 403 counts; 200 or anything else is a problem). With `-WslDistro <name>`, and only if that distro is already running, it checks its `ddistro_custom_mod` tool, Apache, PostgreSQL and web protection. It says whether anything answers on local port 1234 (the `dwemerllm` default, [CONNECTORS.md](../CONNECTORS.md)) and at the PocketTTS default (8086), which is not a test, and ends with a readiness summary. Exit 0 means no FAIL or UNVERIFIED line was detected; WARN, SKIP and not-checked items still need action, and exit 0 never means ready | Changes anything, or starts a distro |
| `setup` | Builds the client for x64 and x86 with `client\scripts\build.ps1` into `%LOCALAPPDATA%\DwemerDynamics\KagrenacClient\build` (change with `-BuildRoot`, outside the repository); safe to repeat | Installs prerequisites, copies source into WSL, writes a client config |
| `check` | `php -l` on every server PHP file and `bash -n`, with local tools when present, then the client build (fails on compiler warnings) | Runs migrations or any other database operation |

Explicit opt-ins, both against an **existing** WSL server checkout you name:

- `setup -RunServerInstaller -WslDistro <name> -WslServerPath /var/www/html/custom-mods/KagrenacServer`
  runs that checkout's existing `scripts/install.sh` as root (safe to repeat; it keeps the
  config and database). It refuses a missing or unsafe path, the launcher-managed
  `/custom-mods/example-server`, any folder Core's web protection does not cover, and a
  distro where that protection is not installed.
- `check -RunSmoke -WslDistro <name> -WslServerPath <checkout>` runs `scripts/smoke.sh`
  there as `dwemer` (add `-ServerUrl` if your port or route differs).

`doctor -WslDistro <name> -WslServerPath <checkout>` also checks that checkout and whether its
private config exists (without reading it); a stopped distro is reported and skipped. The
opt-ins above may start the distro they name.
