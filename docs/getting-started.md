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
   NPC, and what it should do), and the mod name. No forms. Working from the template itself,
   the agent then makes your mod its own project with `scripts\project.ps1 new`
   ([New project](#new-project)), which records that brief, and for a game with a reference
   port its plan, in the new copy's PROJECT.md, so nothing is asked twice. Every later step
   runs in that copy.
3. **Integration plan, before any mod code is built.** The agent fills the short plan in
   PROJECT.md: how the player's input reaches the mod, which NPC and how long it lives, how
   the HTTP call runs off the game thread and comes back to it, how the reply is shown and
   the voice played, which existing mechanism carries each action (its target, instance
   check and preconditions), what the mod can observe (each value's source and freshness;
   anything it cannot read is sent as `unavailable`), saves, offline play and cancel, which
   facts are cited from the game's SDK or files and which are unknown, and what the first
   thin slice must show. The mod stays one repository: the server at the root, the game
   side in `client/` or `ports/<engine>/`. For an unknown, the agent does bounded research: it
   says what it will look up and where, stops when it finds a citation or runs out of named
   sources, then gives you two or three concrete options with a recommendation. That is a
   short step, not a separate diagnostic stage, and the agent never invents an engine API.
   Steps 4 and 5 do not wait for it; only step 6 needs the plan with options chosen.
4. **DwemerDistro.** The agent runs `scripts\project.ps1 doctor -WslDistro <name>` for the
   one distro you use. If you have not named it and more than one distro is listed, the
   agent asks which one; doctor never probes the others. Doctor only diagnoses: it changes
   nothing, and a line about a service you did not choose (for example nothing answering on
   local port 1234 when you use OpenRouter) does not block anything. If DwemerDistro is
   missing, the agent walks you through the official installer. Then the agent:
   - gives your copy its own `id` and `name` in `dwemer-mod.json` (`new` does this; the
     template's `example-server` is refused for a new deploy), commits, and runs
     `scripts\project.ps1 deploy -WslDistro <name>` (see [Deploy](#deploy-and-pair) below);
   - pairs the game side with `scripts\project.ps1 pair` once the game-side folder exists
     (step 6), which writes the private client config itself. You never paste a key or copy
     the token by hand.
   Existing installs, configs and databases are kept; other distros are left alone. An
   existing manual install is supported separately ([SETUP.md section 1](../SETUP.md#1-install-the-server-inside-dwemerdistro)).
5. **LLM and voice, tested for real.** The agent reuses a provider you already configured.
   If you have not chosen, it recommends OpenRouter
   [`google/gemma-4-31b-it`](https://openrouter.ai/google/gemma-4-31b-it) for dialogue,
   OpenRouter [`typesafe/jev-1.13`](https://openrouter.ai/typesafe/jev-1.13) only for
   `decision.php` choices from a bounded list the game offers (never chat or actions), and
   PocketTTS for voice. It sets the LLM on the dashboard **LLM** page and presses **Send
   test**: a real reply is the pass. You enter keys on the dashboard **API keys** page or in
   the private `config/config.php`, never in chat, logs or commits. Choosing a provider,
   setting its key privately and asking for the test authorizes that test only; no other
   paid call. For voice the agent checks PocketTTS is installed and running in the
   DwemerDistro launcher, enables it on the **Voice** page and presses **Speak**. The pass
   is you hearing it, on the dashboard or in the game; a generated WAV alone is not heard.
   The shipped config stays in mock mode.
6. **First real prototype.** The agent builds the thin slice from the plan in the game
   itself. Mock mode and the console client are developer checks for the server and shared
   code, not your demo, and no console exercise is required first. For Elden Ring, the
   reference in [ports/elden-ring/](../ports/elden-ring/README.md) is reused rather than
   started over, through its maintained route
   ([Build a mod](../ports/elden-ring/README.md#build-a-mod-from-this-reference)): the agent
   runs `ports\elden-ring\mod.ps1 doctor` (read-only preflight: game build, tools, me3), then
   `build`, `assemble` and `pair` into the runtime folder, and records each in its own
   PROJECT.md row (6a build, 6b runtime and pairing). You back up your saves and launch the
   game yourself with the printed offline command; only what you then see and hear fills
   6c and each action row.
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
| WSL server copy | `/var/www/html/custom-mods/<id>` (made by `deploy` through Core), or an existing manual or launcher install | Run the server only |

They are separate copies; `deploy` updates the server copy from your committed HEAD. Never build the client, write its `config.json` or keep build
output in the server copy: it sits in Apache's web root.

## `scripts\project.ps1`

`powershell -ExecutionPolicy Bypass -File scripts\project.ps1 <new|doctor|setup|check|pair|deploy>`
(the full option list is at the top of the script).

| Command | Does | Never |
|---|---|---|
| `new` | Makes a new mod from the template: an independent copy of the committed HEAD in a new folder, with its own id and name, brief, paths and stage states (below) | Writes into an existing folder, copies history, private config, databases, build output or logs, changes the template, or commits |
| `doctor` | Reports tools, WSL distros with their state, client builds, the client config (token shown only as set or missing), server health (`ok` and the `example-ai-server` identity) and, on a healthy server, whether `.git/`, `client/`, `docs/` and `ports/` are denied (only HTTP 403 counts; 200 or anything else is a problem). With `-WslDistro <name>`, and only if that distro is already running, it checks its `ddistro_custom_mod` tool, Apache, PostgreSQL and web protection. It says whether anything answers on local port 1234 (the `dwemerllm` default, [CONNECTORS.md](../CONNECTORS.md)) and at the PocketTTS default (8086), which is not a test, and ends with a readiness summary. Exit 0 means no FAIL or UNVERIFIED line was detected; WARN, SKIP and not-checked items still need action, and exit 0 never means ready | Changes anything, or starts a distro |
| `setup` | Builds the client for x64 and x86 with `client\scripts\build.ps1` into `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>\client` for a project with its own id (the template: `%LOCALAPPDATA%\DwemerDynamics\KagrenacClient\build`; change with `-BuildRoot`, outside the repository); safe to repeat | Installs prerequisites, copies source into WSL, writes a client config |
| `check` | `php -l` on every server PHP file and `bash -n`, with local tools when present, then the client build (fails on compiler warnings) | Runs migrations or any other database operation |
| `pair` | Writes a new private client config from a server checkout (below) | Prints the token, overwrites a different config |
| `deploy` | Installs or updates your committed HEAD in the named distro (below) | Deploys uncommitted files, adopts or repoints an install, rewrites the private config |

### New project

```powershell
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 new -Destination C:\dev\MyMod -Id my-mod -Name "My Mod" `
  -Game "<game, version, tools>" -Feature "<starting feature>" [-Voice <text>] [-LlmProvider <name>] [-WslDistro <name>] [-Engine <port>]
```

- Runs only in the template (manifest id `example-server` at HEAD) and copies exactly its
  committed HEAD with `git archive`: no Git history, untracked or ignored files, private
  config, database, build output or logs. Uncommitted template changes are reported and left out.
- `-Destination` must be a new folder on a local fixed disk, in an existing parent reached
  without links, outside every Git checkout, web root (`htdocs`, `wwwroot`, `custom-mods` and
  the like) and `%LOCALAPPDATA%\DwemerDynamics`. An existing folder is refused, never merged.
- `-Id` (3-32 lowercase letters, digits and single hyphens) and `-Name` become the copy's
  `id`, `name` and `description` in `dwemer-mod.json`. An id that already has a deploy or
  build folder under `%LOCALAPPDATA%\DwemerDynamics\Kagrenac` is refused.
- The copy's PROJECT.md gets the brief you gave, its own build, runtime, deploy and server
  paths, and the stage states. `-Engine <port>` copies the reference plan from
  `ports/<port>/PLAN.md` as the chosen plan (revise the rows where your feature differs; it is
  not verified in game) and adds one stage row per reference action; brief text that holds
  a URL or looks like a key is refused.
- It runs `git init -b main` in the copy and commits nothing. Review the copy, then commit
  it yourself before its first deploy (deploy sends only committed HEAD), and run every
  later command from the copy:

  ```powershell
  git -C C:\dev\MyMod add -A
  git -C C:\dev\MyMod commit -m "Start My Mod from KAGRENAC AI Mod Maker"
  powershell -ExecutionPolicy Bypass -File C:\dev\MyMod\scripts\project.ps1 deploy -WslDistro <name>
  ```

### Deploy and pair

`deploy -WslDistro <name>` (run with `powershell.exe`, not `pwsh`):

- Refuses uncommitted or untracked files, then exports exactly HEAD as a Git bundle to the
  private folder `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\deploy\<id>`.
- Needs DwemerDistro Core with `setup-web --protect-project` and `update --expect-commit`.
  These are not yet in a public Core release, so **Update Distro** may not supply them yet.
  If Core lacks them, deploy stops without changing anything (its message suggests Update
  Distro, which helps only once a compatible Core is released); wait for that version, then
  deploy again.
- Protects `/custom-mods/<id>` with Core before any source is placed, then installs or
  fast-forwards through Core from a private cache in WSL, to exactly that commit. Core
  names the database `custom_<id>` (dashes become underscores).
- Checks the commit, `www-data` access, health and HTTP 403 for source and config paths,
  and writes a private deployment record (backup and retry steps) next to the bundle.
- Running it again at the same commit reports it as already deployed and changes nothing,
  so config and data are kept. A new commit is backed up and fast-forwarded; the private config is never rewritten.

`deploy -WslDistro <name> -WslServerPath <existing manual install>` updates that manual
install through its own `scripts/update.sh` instead. Deploy never adopts or repoints a
launcher or manual install it did not make.

`pair -WslDistro <name> -WslServerPath <checkout> -OutFile <full Windows path>` (optional
`-ServerUrl`, `-SessionId`, `-AllowedActions a,b`, and for a game client `-NpcId <id>`,
`-NpcName "<name>"`, `-VoiceEnabled`) runs that checkout's `scripts/pair_client.php` and
saves a new private client config. Put `-OutFile` outside every repository and web root, for
example the game-side runtime folder. If the file already exists with the same URL, token and
session it is kept byte for byte as "already paired" (the identity and voice options shape
only a new file); anything else is refused, never overwritten.

**What a backup holds.** Each deploy's Core backup, and `scripts/backup.sh` for a manual
install, take the database dump and the install's standard private `config/config.php`
(provider keys, token, voice and the other settings). Keep every private setting in that
file or on the dashboard: a `config/config.php` that only loads settings from a file
elsewhere is not supported, because the backup copies the file itself and not what it loads.
Game saves are not part of any server backup; back up `%APPDATA%\EldenRing` (or your game's
save folder) yourself before a modded launch.

Explicit opt-ins for an **existing** manual WSL server checkout you name:

- `setup -RunServerInstaller -WslDistro <name> -WslServerPath /var/www/html/custom-mods/KagrenacServer`
  runs that checkout's existing `scripts/install.sh` as root (safe to repeat; it keeps the
  config and database). It refuses a missing or unsafe path, the launcher-managed
  `/custom-mods/example-server`, any folder Core's web protection does not cover, and a
  distro where that protection is not installed.
- `check -RunSmoke -WslDistro <name> -WslServerPath <checkout>` runs `scripts/smoke.sh`
  there as `dwemer` (add `-ServerUrl` if your port or route differs).

`doctor -WslDistro <name> -WslServerPath <checkout>` also checks that checkout and whether its
private config exists (without reading it); a stopped distro is reported and skipped. The
opt-ins, `pair` and `deploy` may start the distro they name.

Doctor checks health and exposure at `-ServerUrl`, else the shared client config's
`server_url`, else `/custom-mods/KagrenacServer` on port 19000. For your own route, name it
explicitly, for example
`doctor -WslDistro <name> -ServerUrl http://127.0.0.1:19000/custom-mods/<id> -WslServerPath /var/www/html/custom-mods/<id>`.
