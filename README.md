# KAGRENAC AI Mod Maker

<img src="ui/images/kagrenac.png" alt="KAGRENAC AI Mod Maker logo" width="64">

A template, with a coding agent workflow, for building your own AI NPC mod on DwemerDistro.
One repository holds both components:

- **KagrenacServer** (the repository root): a small PHP 8.2 + PostgreSQL server. A game sends
  what the player said to an NPC; the server answers with the NPC's reply and, at most, one
  allowlisted action (`follow_player` by default).
- **KagrenacClient** (`client/`): a Windows console "fake game" (C++17, x64 and x86) that
  shows the game side. It is not a plugin for any real game.

## What works today

| Area | Status | Details |
|---|---|---|
| Server (mock mode) | Working: turns, game events, history, NPC bios and facts, checkpoints, backups, cancellation and stale-reply protection, dashboard. Real LLM providers are code paths you configure and test yourself | [START_HERE.md](START_HERE.md#feature-and-status-checklist) |
| Console client | Builds for x64 and x86; talks to the server, shows replies as text, and simulates `follow_player` by printing a line | [client/README.md](client/README.md) |
| Voice | Optional and off by default. The server can call PocketTTS (text to speech) and Parakeet or faster-whisper (speech to text) once you install and enable them; the console saves reply WAVs and transcribes a WAV file you give it. No microphone capture and no playback | [CONNECTORS.md](CONNECTORS.md#voice) |
| Real game | **None verified.** An Elden Ring reference (a native me3 client plus an event-script control package for follow and hold) builds and passes fixture checks outside the game; it is not verified in game, and attack is unavailable until its target and handler are verified there | [ports/elden-ring/](ports/elden-ring/README.md) |
| Deploy and pair (Windows) | `scripts\project.ps1 deploy` installs or updates your committed HEAD through DwemerDistro Core; `pair` writes the private client config | [docs/getting-started.md](docs/getting-started.md#deploy-and-pair) |

## First prompt for your coding agent

Use Codex or your chosen coding agent directly: plan, implement, test, review the actual
changes in a separate pass, and fix findings. External delegation is optional. The
[game planning guide](docs/ENGINE_PLANNING.md) and [tool catalogue](docs/research/MODDING_TOOLS.md)
help the agent qualify a new game's mod infrastructure before building its port.

Clone your copy on Windows, open your coding agent in it and paste this, adding anything
you already know. You do not fill in any form first:

```text
Read AGENTS.md, PROJECT.md and docs/getting-started.md, and take me through that route.
Reuse what I already told you and ask only for what is missing (game, starting feature,
mod name). Write the gameplay design and integration plan in PROJECT.md before building
mod code; set up DwemerDistro, the LLM and voice meanwhile. You run the commands and
setup; never ask me for keys in chat.
```

## Get started

The route, from download to the first AI line in your game, is
[docs/getting-started.md](docs/getting-started.md). Your copy gets its own `id` and `name`
in `dwemer-mod.json`; `scripts\project.ps1 deploy -WslDistro <name>` then installs it inside
DwemerDistro WSL through Core, at `/custom-mods/<id>` with database `custom_<id>`. A manual
install ([SETUP.md](SETUP.md#1-install-the-server-inside-dwemerdistro)) or the launcher's
**Mods > Custom mods** ([LAUNCHER_CUSTOM_MOD.md](LAUNCHER_CUSTOM_MOD.md)) are separate
routes. 19000 is DwemerDistro's shared loopback port for custom PHP mods
(`CUSTOM_MODS_PORT`). A full engine port uses the staged prompt in
[docs/agent-playbook.md](docs/agent-playbook.md).

## Directory map

| Path | What |
|---|---|
| `*.php`, `lib/`, `sql/`, `config/`, `ui/` | KagrenacServer: endpoints, helpers, migrations, private config, dashboard |
| `scripts/` | Server scripts (`install.sh`, `update.sh`, `smoke.sh`, `migrate.php`, `pair_client.php`, ...), the Windows developer wrapper `project.ps1` and its WSL side `project-runtime.sh` |
| `dwemer-mod.json` | Manifest for the server (template id `example-server`; your copy sets its own) |
| `client/` | KagrenacClient source, CMake project and `scripts/build.ps1` |
| `docs/` | [Getting started](docs/getting-started.md), [agent playbook](docs/agent-playbook.md), [engine pack template](docs/engine-packs/ENGINE_PACK.md), [port recipes](docs/feature-recipes/PORT_RECIPES.md) |
| `ports/` | Per-engine work and evidence; `ports/elden-ring/` is a reference, not verified in game |
| `PROJECT.md` | Your project brief, integration plan, stage checklist and latest evidence |

`client/`, `docs/` and `ports/` are source only and are not meant to be served.

## Documentation

| Read | For |
|---|---|
| [docs/getting-started.md](docs/getting-started.md) | The route: brief, integration plan, DwemerDistro, LLM and voice tests, first prototype |
| [docs/GAMEPLAY_DESIGN.md](docs/GAMEPLAY_DESIGN.md) | Gameplay first: the player's loop, interaction modes, who decides, bounded automatic interactions, what exists today |
| [START_HERE.md](START_HERE.md) | Orientation, feature status, end-to-end walkthrough, troubleshooting by request ID, porting checklist |
| [SETUP.md](SETUP.md) | Install, web protection, pairing, LLM and voice setup, backups, updates, migrations, removal |
| [CONNECTORS.md](CONNECTORS.md) | Copyable LLM, voice, NPC selection, profile and memory settings |
| [PROTOCOL.md](PROTOCOL.md) | The request and reply contract (one copy, shared by server and client) |
| [UI_GUIDE.md](UI_GUIDE.md) | Dashboard pages and adding your own |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Server code layers, owners, dependency direction and compatibility functions |
| [LAUNCHER_CUSTOM_MOD.md](LAUNCHER_CUSTOM_MOD.md) | Launcher install, `main`/`dev` branches, publishing your own copy |
| [MAKE_IT_YOURS.md](MAKE_IT_YOURS.md), [WAVE_ACTION.md](WAVE_ACTION.md) | Renaming your copy; worked exercise for adding an action |
| [AGENTS.md](AGENTS.md), [client/AGENTS.md](client/AGENTS.md) | Rules for coding agents |

## Limits

- A template, not a product: no real game is supported until someone ports and tests the
  client in that game. The console's follow is a printed simulation.
- `deploy` needs a DwemerDistro Core with `setup-web --protect-project` and
  `update --expect-commit`, not yet in a public Core release; until a compatible Core is
  available, it stops with a clear message and changes nothing.
- Meant for one PC or a trusted local network. The dashboard has **no login**, there is
  **no rate limiting**, and the token travels over plain HTTP.
- The server copy sits inside Apache's web root. Private config and `lib/` files print
  nothing through PHP; Core's web protection denies `.git/`, `client/`, `docs/` and `ports/`
  only at the known install paths. Check your install as
  [START_HERE.md](START_HERE.md#deployment-and-exposure) describes.
- The model can only *ask* for allowlisted actions; the server and the game each check
  them, and nothing runs commands. Failed requests are never retried automatically.
- The smoke checks cover mock mode only; test real providers and voice services yourself.

## Licence

Copyright (C) 2026 Dwemer Dynamics. Licensed under the GNU General Public License,
version 3 only (`GPL-3.0-only`); see [LICENSE](LICENSE) and [client/LICENSE](client/LICENSE).
The dashboard presentation adapted from HerikaServer keeps its MIT notice, and the client's
JSON library keeps its MIT notice; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[client/THIRD_PARTY_NOTICES.md](client/THIRD_PARTY_NOTICES.md).
