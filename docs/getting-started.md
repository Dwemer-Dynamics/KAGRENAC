# Getting started: from download to your first AI prototype

The one route for starting a mod with KAGRENAC AI Mod Maker. You talk with your coding agent;
the agent runs the commands, does the setup and writes things down in
[PROJECT.md](../PROJECT.md). Other pages are references the agent opens when a step needs
them; you do not have to read them first.

## The route

Use Codex or the coding agent the user chose. It handles planning, implementation, checks
and a separate review of the actual changes; no external coding-model setup is required.
Before game-port code, follow [Engine planning](ENGINE_PLANNING.md), with primary sources from
[the tool catalogue](research/MODDING_TOOLS.md). Keep the initial feature small and concrete.

1. **Download.** Clone your copy (GitHub's **Use this template**, a fork, or
   `git clone https://github.com/Dwemer-Dynamics/Kagrenac.git`), open your coding agent in it
   and paste the [first prompt](../README.md#first-prompt-for-your-coding-agent).
2. **Brief, in conversation.** The agent reuses what you already said and asks only for what
   is missing, in this order: the game, the starting feature (a new companion or an existing
   NPC, and what it should do), and the mod name. No forms. Working from the template itself,
   the agent then makes your mod its own project with `scripts\project.ps1 new`
   ([New project](#new-project)), which records that brief, and for a game with a reference
   port its plan, in the new copy's PROJECT.md, so nothing is asked twice. Every later step
   runs in that copy. Default to one repository; the optional
   [two-repository layout](#repository-layout) is a deliberate choice, not a required question.
3. **Gameplay design and integration plan, before any mod code is built.** From the
   conversation, the agent first fills PROJECT.md's short Gameplay design
   ([Gameplay design](GAMEPLAY_DESIGN.md)): the player's fantasy, the 2-3 minute loop they will
   see and hear, the interaction mode, and what decides and changes. It then fills the plan in
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
   test**, or runs `scripts\project.ps1 configure` with `-TestProviders`
   ([Configure](#configure-providers-voice-and-actions)): a real reply is the pass. You enter keys on the dashboard **API keys** page or in
   the private `config/config.php`, never in chat, logs or commits. Choosing a provider,
   setting its key privately and asking for the test authorizes that test only; no other
   paid call. For voice the agent checks PocketTTS is installed and running in the
   DwemerDistro launcher, enables it on the **Voice** page and presses **Speak**. The pass
   is you hearing it, on the dashboard or in the game; a generated WAV alone is not heard.
   The shipped config stays in mock mode.
6. **First real prototype.** The agent builds the thin slice from the plan in the game
   itself: the Gameplay design loop, with its automatic trigger when one was requested. Mock mode and the console client are developer checks for the server and shared
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

## Repository layout

**Default: one repository per mod.** The server lives at the root, with the game client or
plugin under `client/` or `ports/<engine>/`. Separate installed game files and a deployed
server are runtime copies, not separate source repositories. This is what `project.ps1 new`
creates and what the documented commands support today.

**Optional: separate client and server repositories.** Offer this when the user wants
independent maintenance or release schedules. Record the user's choice in PROJECT.md's
Decisions before creating the layout. Plan ownership of the shared protocol and client
transport, compatible versions, explicit source/build paths, server deployment and pairing.
Adapt and check the commands before claiming support; `new` has no two-repository switch.
Keep one repo unless the user chooses the alternative. Existing mods are not split by this
choice of instructions.

## Two copies of one repository

| Copy | Where | Job |
|---|---|---|
| Windows development copy | Any folder you own, for example `C:\dev\Kagrenac` | Edit, build, run `scripts\project.ps1` and your agent |
| WSL server copy | `/var/www/html/custom-mods/<id>` (made by `deploy` through Core), or an existing manual or launcher install | Run the server only |

They are separate copies; `deploy` updates the server copy from your committed HEAD. Never build the client, write its `config.json` or keep build
output in the server copy: it sits in Apache's web root.

## `scripts\project.ps1`

`powershell -ExecutionPolicy Bypass -File scripts\project.ps1 <new|doctor|setup|check|pair|configure|deploy>`
(the full option list is at the top of the script).

| Command | Does | Never |
|---|---|---|
| `new` | Makes a new mod from the template: an independent copy of the committed HEAD in a new folder, with its own id and name, brief, paths and stage states (below) | Writes into an existing folder, copies history, private config, databases, build output or logs, changes the template, or commits |
| `doctor` | Reports tools, WSL distros with their state, client builds, the client config (token shown only as set or missing), server health (`ok` and the `example-ai-server` identity) and, on a healthy server, whether `.git/`, `client/`, `docs/` and `ports/` are denied (only HTTP 403 counts; 200 or anything else is a problem). With `-WslDistro <name>`, and only if that distro is already running, it checks its `ddistro_custom_mod` tool, Apache, PostgreSQL and web protection. It says whether anything answers on local port 1234 (the `dwemerllm` default, [CONNECTORS.md](../CONNECTORS.md)) and at the PocketTTS default (8086), which is not a test, and ends with a readiness summary. In a native port's project (`-Engine <port>`, else the engine `new -Engine` wrote into its PROJECT.md Paths) it skips the console client build and config and points to the port's own route (Elden Ring: `ports\elden-ring\mod.ps1 doctor`, then `build`, `assemble` and `pair`); the console client stays an optional developer check. Exit 0 means no FAIL or UNVERIFIED line was detected; WARN, SKIP and not-checked items still need action, and exit 0 never means ready | Changes anything, or starts a distro |
| `setup` | Builds the client for x64 and x86 with `client\scripts\build.ps1` into `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>\client` for a project with its own id (the template: `%LOCALAPPDATA%\DwemerDynamics\KagrenacClient\build`; change with `-BuildRoot`, outside the repository); safe to repeat | Installs prerequisites, copies source into WSL, writes a client config |
| `check` | `php -l` on every server PHP file and `bash -n`, with local tools when present, then the client build (fails on compiler warnings) | Runs migrations or any other database operation |
| `pair` | Writes a new private client config from a server checkout (below) | Prints the token, overwrites a different config, writes an action the game side's build does not support |
| `configure` | Sets the install's dialogue provider, voice and server allowlist through the dashboard's own config writer, and with `-TestProviders` tests them once ([below](#configure-providers-voice-and-actions)) | Takes or prints a key, copies a token or database, retries a test, saves a text or audio file |
| `deploy` | Installs or updates your committed HEAD in the named distro (below) | Deploys uncommitted files, adopts or repoints an install, rewrites the private config |

### New project

```powershell
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 new -Destination C:\dev\MyMod -Id my-mod -Name "My Mod" `
  -Game "<game, version, tools>" -Feature "<starting feature>" [-Voice <text>] [-LlmProvider <name>] [-WslDistro <name>] [-Engine <port>] `
  [-InteractionMode manual|ambient|companion|operator]
```

- Runs only in the template (manifest id `example-server` at HEAD) and copies exactly its
  committed HEAD with `git archive`: no Git history, untracked or ignored files, private
  config, database, build output or logs. Uncommitted template changes are reported and left out.
- `-Destination` accepts either slash style and normalizes it before applying the same safety
  checks. It must be a new folder on a local fixed disk, in an existing parent reached
  without links, outside every Git checkout, web root (`htdocs`, `wwwroot`, `custom-mods` and
  the like) and `%LOCALAPPDATA%\DwemerDynamics`. An existing folder is refused, never merged.
- `-Id` (3-32 lowercase letters, digits and single hyphens) and `-Name` become the copy's
  `id`, `name` and `description` in `dwemer-mod.json`. An id that already has a deploy or
  build folder under `%LOCALAPPDATA%\DwemerDynamics\Kagrenac` is refused.
- The copy's PROJECT.md gets the brief you gave, its own build, runtime, deploy and server
  paths, and the stage states. `-Engine <port>` copies the reference plan from
  `ports/<port>/PLAN.md` as a starting plan and leaves stage 2 `in progress`: the agent checks
  each row against the starting feature, revises the rows that differ (none is verified in
  game) and then marks stage 2 done itself, while stages 3 to 5 go ahead without waiting. It
  also adds one stage row per reference action; brief text that holds
  a URL or looks like a key is refused.
- `-InteractionMode` (optional) prefills the primary mode in the copy's Gameplay design. It is
  planning text only and enables no feature, action, provider call or config. Pass it only
  when the user already named the mode; the agent records any mix and fills the other rows.
- An engine without a reference is also accepted: `new -Engine <name>` records its paths,
  creates a short `ports/<name>/PLAN.md` starter and leaves stage 2 not started. The agent
  qualifies it using [Engine planning](ENGINE_PLANNING.md), without inventing support.
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
- Checks, as `www-data`, that the dashboard can save `config/config.php`. If not (Core
  leaves `config/` readable but not writable by `www-data`), it runs that commit's
  `scripts/install.sh`, which sets the owner, group and mode of `config/`, the config and
  its lock to `www-data:dwemer`, `2770` and `660` (SETUP.md, Who can read what), and also
  confirms the database and applies pending migrations (normally none right after Core's
  update). Deploy checks that the config's contents (SHA-256) and the lock file stay the
  same, and checks saving again. The output and the deployment record say `config ok` or
  `config repaired`. Only the standard `config/config.php` is supported; one that loads
  settings from another file is refused before Core backs anything up.
- This repair does not last through Core: the launcher's **Update** and
  `ddistro_custom_mod update` set Core's read-only ownership again. Run
  `project.ps1 deploy -WslDistro <name>` again afterwards to repair it; `doctor -WslDistro
  <name>` reports when the dashboard cannot save.
- After the repair, change settings on the dashboard, or from an agent with `configure`
  ([below](#configure-providers-voice-and-actions)), which runs the existing `config_update()`
  in `lib/config_writer.php` as the config's owner `www-data`, never as `dwemer` (saving
  refuses a config it does not own).
- Running it again at the same commit reports the code as already deployed; when the config
  can already be saved it changes nothing (no Core update, backup, installer or migrations),
  so config and data are kept. A new commit is backed up and fast-forwarded; the private
  config's contents are never rewritten.

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

`-AllowedActions` sets only the client's list; pair cannot change the server. With
`-Build <port build folder>`, or when `-OutFile` sits in a runtime that `assemble`
wrote (its `runtime.json` names the build), every client action, including the default
`follow_player`, must be one that build supports; its records are checked as `configure`
checks them (below). A game client config (`-NpcId` or `-NpcName`) without a build record
allows only `follow_player`; a console client config is unchanged. The server returns only
names in its own `allowed_actions`, so set the same actions there with `configure`. An
action missing on either side is refused. With `-NpcId` or `-NpcName` the file is a game
client's config: leave it in the game runtime and check it with the port's launch steps and
its engine pack's acceptance, not `KagrenacClient.exe`.

### Configure providers, voice and actions

`pair` now defaults `-WslServerPath` to `/var/www/html/custom-mods/<id>` in a project with
its own id, like configure/deploy. The template still requires an explicit install path.
For a new port, use [schema-2 build/runtime records](PORT_BUILD_RECORDS.md); no shared CLI
edit is needed. Legacy Elden Ring records keep their specialized validation below.
For conversation-only work, set **both** lists explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 configure -WslDistro <name> -AllowedActions none
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 pair -WslDistro <name> -OutFile '<runtime>\config.json' -AllowedActions none
```

`none` creates an empty list and needs no build; omitting the option keeps the legacy
follow default. Pair never changes an existing private config's settings. Only use
`-Build` for recorded capabilities; a supported action still needs its own game test.

`configure -WslDistro <name>` (run with `powershell.exe`, not `pwsh`) changes the install's private `config/config.php` the way the
dashboard does: it runs that install's `scripts/configure_server.php` as `www-data`, which
saves through the existing `config_update()` in `lib/config_writer.php` (one lock, the latest
config read inside it, token, database and unknown settings kept, owner, group, mode and lock
file kept). The same request again writes nothing. It targets this project's own
`/var/www/html/custom-mods/<id>` (or `-WslServerPath <install>`, whose `dwemer-mod.json` must
have this project's id; in the template `-WslServerPath` is required). An install `www-data`
cannot save is refused with the same repair step doctor gives (run `deploy` again, or
`sudo bash <install>/scripts/install.sh` for a manual install); configure never changes
permissions itself. The install needs a deployed commit that has `scripts/configure_server.php`.
Nothing changes unless you name it; the shipped config stays in mock mode.

```powershell
# Recommended dialogue and voice; keeps the OpenRouter key already configured for openrouter:
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 configure -WslDistro <name> `
  -LlmProvider openrouter -LlmModel google/gemma-4-31b-it -Tts pockettts -TtsVoice alba
# A fresh copy: take only llm.api_key from another install's private openrouter config:
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 configure -WslDistro <name> `
  -LlmProvider openrouter -LlmModel google/gemma-4-31b-it `
  -ReuseProviderFrom /var/www/html/custom-mods/<other id>/config/config.php
# Server allowlist for a native build (Elden Ring), or for the console client:
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 configure -WslDistro <name> `
  -AllowedActions follow_player,hold_position -Build '<root>\elden-ring\builds\<time>'
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 configure -WslDistro <name> -AllowedActions follow_player -ConsoleClient
# One bounded test of what is saved (may cost money):
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 configure -WslDistro <name> -TestProviders
```

- `-LlmProvider openrouter|dwemerllm|mock` with `-LlmModel <model>` (not for mock) sets
  `llm.mode` and `llm.model`; other modes, URLs and timeouts stay on the dashboard **LLM**
  page. No key is ever an argument, typed in or printed. openrouter keeps the key only when
  `llm.mode` already is openrouter; otherwise it is refused unless you set the key on **API
  keys** with the LLM page in openrouter mode, or name with `-ReuseProviderFrom` another
  install's private config (no access for other users) whose `llm.mode` is openrouter. Only
  its `llm.api_key` is taken, read as `www-data` inside WSL with its output and errors
  discarded; its token, database, history and other settings are never copied. dwemerllm and
  mock leave `llm.api_key` as it is: neither sends it.
- `-Tts pockettts -TtsVoice <voice>` enables PocketTTS at `http://127.0.0.1:8086/v1/audio/speech`
  (model `pocket-tts`), only when something answers on port 8086; `-Tts off` turns voice off.
  `tts.api_key` and other voice settings stay; other providers are set on the **Voice** page.
- `-AllowedActions none` empties the server list. A nonempty `-AllowedActions a,b` replaces
  the server's `allowed_actions` with names the server knows
  (`follow_player`, `hold_position`, `attack_hostile`), and needs exactly one of:
  `-Build <port build folder>` with the [generic record](PORT_BUILD_RECORDS.md), or the
  existing Elden Ring record at `<root>\elden-ring\builds\<time>`, whose `build.json` must be this project's, for the
  accepted game build, with every recorded file unchanged (SHA-256), a `package.json` that
  agrees on the control config, `attack_enabled`, supported actions and package files, and a
  DLL carrying the control config's hash, and each action must be one it supports (with
  `attack_enabled` false, `attack_hostile` is refused); or `-ConsoleClient`, for
  `follow_player` only. Supported means a candidate: nothing is marked usable, and no other
  action is ever added.
- `-TestProviders` (after any changes; alone it only reads the config, so it also runs when
  `www-data` cannot save) refuses before calling anything when the mode is mock, voice is off,
  vector search (`embeddings.enabled`) or automatic memory (`memory.auto_notes`,
  `memory.auto_extract`) is on, or the default profile changes the mode or model. It prints
  the mode and model it tests, then makes one `turn.php` call (its own `provider-test-...` session, `offered_actions: []`)
  and one `speak.php` call with that reply, with no retry, fallback or NPC selection. It
  prints only HTTP status, time, reply shape and character count, and the WAV's format, size
  and SHA-256; never the text, a provider body, the token or the audio, and it saves no file.
  The pass needs a real reply whose event row records the configured mode, and a complete PCM
  or float WAV whose header values agree. `turn.php` records the test turn in that
  session like any turn. A generated WAV is not heard: voice is ready only once someone
  hears it on the **Voice** page or in game. Add `-ServerUrl` when Apache uses another port.

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
private config exists (without reading it); a stopped distro is reported and skipped. With
`-WslServerPath`, or in a project with its own id (its `/custom-mods/<id>` install), it also
checks as `www-data` whether the dashboard can save the private config, using that install's
`lib/config_writer.php` without reading the config; a FAIL there means run `deploy` again. In
the template (`example-server`) it guesses no install. The
opt-ins, `pair` and `deploy` may start the distro they name.

Doctor checks health and exposure at `-ServerUrl`, else the shared client config's
`server_url`, else `/custom-mods/KagrenacServer` on port 19000. For your own route, name it
explicitly, for example
`doctor -WslDistro <name> -ServerUrl http://127.0.0.1:19000/custom-mods/<id> -WslServerPath /var/www/html/custom-mods/<id>`.
