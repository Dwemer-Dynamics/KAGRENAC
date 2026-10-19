# KAGRENAC AI Mod Maker

<img src="ui/images/kagrenac.png" alt="KAGRENAC AI Mod Maker logo" width="64">

A template, with a coding agent workflow, for building your own AI NPC mod on DwemerDistro.
One repository holds both components:

- **KagrenacServer** (the repository root): a small PHP 8.2 + PostgreSQL server. A game sends
  what the player said to an NPC; the server answers with the NPC's reply and, at most, one
  safe action (`follow_player`).
- **KagrenacClient** (`client/`): a Windows console "fake game" (C++17, x64 and x86) that
  shows the game side. It is not a plugin for any real game.

## What works today

| Area | Status | Details |
|---|---|---|
| Server (mock mode) | Working: turns, game events, history, NPC bios and facts, checkpoints, backups, cancellation and stale-reply protection, dashboard. Real LLM providers are code paths you configure and test yourself | [START_HERE.md](START_HERE.md#feature-and-status-checklist) |
| Console client | Builds for x64 and x86; talks to the server, shows replies as text, and simulates `follow_player` by printing a line | [client/README.md](client/README.md) |
| Voice | Optional and off by default. The server can call PocketTTS (text to speech) and Parakeet or faster-whisper (speech to text) once you install and enable them; the console saves reply WAVs and transcribes a WAV file you give it. No microphone capture and no playback | [CONNECTORS.md](CONNECTORS.md#voice) |
| Real game | **None.** No game is supported until someone ports the client and tests it in that game. `ports/` holds evidence records only | [docs/agent-playbook.md](docs/agent-playbook.md) |

## First prompt for your coding agent

Paste this, adding what you already know (game, voice, actions, what you allow it to do);
you do not need to fill in [PROJECT.md](PROJECT.md) first:

```text
Read AGENTS.md and PROJECT.md in this repository. Fill in PROJECT.md from this
conversation and my earlier instructions; ask me only for facts still missing for the
next step, and do not ask me to confirm what I already said. Inspect what this repository
and my engine can actually do today, and qualify the engine with
docs/engine-packs/ENGINE_PACK.md before promising any game feature; never invent engine
APIs. Then run: powershell -ExecutionPolicy Bypass -File scripts\project.ps1 doctor, and
report what it found.
```

For a full engine port, use the staged prompt in [docs/agent-playbook.md](docs/agent-playbook.md).

## Get started

Clone once on Windows as your development copy (edit, build the client, run checks):

```powershell
git clone https://github.com/Dwemer-Dynamics/Kagrenac.git
cd Kagrenac
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 doctor
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 setup    # builds the client outside the repository
```

The server runs from a **separate clone inside DwemerDistro WSL**, in Apache's web root.
Install DwemerDistro Core's custom mod web protection first
([SETUP.md, Before you install](SETUP.md#before-you-install-web-protection)), then either:

- **Launcher:** **Mods > Custom mods > Add custom mod**, paste
  `https://github.com/Dwemer-Dynamics/Kagrenac` ([LAUNCHER_CUSTOM_MOD.md](LAUNCHER_CUSTOM_MOD.md)).
  It installs at `/custom-mods/example-server`.
- **Manually**, in the DwemerDistro WSL shell as `dwemer`, after **Update Distro**:

  ```bash
  sudo ddistro_custom_mod setup-web   # protection and the shared custom mods port
  grep -qF '(client|ports|docs)' /etc/apache2/sites-available/dwemerdistro-custom-mods.conf && echo protected
  # Continue only if it printed "protected".
  sudo install -d -o dwemer -g dwemer /var/www/html/custom-mods/KagrenacServer
  git clone https://github.com/Dwemer-Dynamics/Kagrenac.git /var/www/html/custom-mods/KagrenacServer
  cd /var/www/html/custom-mods/KagrenacServer
  sudo bash scripts/install.sh
  curl http://127.0.0.1:19000/custom-mods/KagrenacServer/health.php
  bash scripts/smoke.sh
  ```

Never build the client or write its `config.json` inside the server copy. Pair the client as
[SETUP.md](SETUP.md#3-connect-them) describes. The dashboard is at
`http://127.0.0.1:19000/custom-mods/KagrenacServer/`. 19000 is DwemerDistro's shared loopback
port for custom PHP mods (`CUSTOM_MODS_PORT`); official server ports such as 8081 are unchanged.
The full developer cold start is [docs/getting-started.md](docs/getting-started.md).

## Directory map

| Path | What |
|---|---|
| `*.php`, `lib/`, `sql/`, `config/`, `ui/` | KagrenacServer: endpoints, helpers, migrations, private config, dashboard |
| `scripts/` | Server scripts (`install.sh`, `update.sh`, `smoke.sh`, `migrate.php`, `pair_client.php`, ...) and the Windows developer wrapper `project.ps1` |
| `dwemer-mod.json` | Launcher manifest for the server (id `example-server`) |
| `client/` | KagrenacClient source, CMake project and `scripts/build.ps1` |
| `docs/` | [Getting started](docs/getting-started.md), [agent playbook](docs/agent-playbook.md), [engine pack template](docs/engine-packs/ENGINE_PACK.md), [port recipes](docs/feature-recipes/PORT_RECIPES.md) |
| `ports/` | Per-engine evidence records; no port is implemented |
| `PROJECT.md` | Your project brief, decisions, acceptance and evidence |

`client/`, `docs/` and `ports/` are source only and are not meant to be served.

## Documentation

| Read | For |
|---|---|
| [START_HERE.md](START_HERE.md) | Orientation, feature status, end-to-end walkthrough, troubleshooting by request ID, porting checklist |
| [SETUP.md](SETUP.md) | Install, web protection, pairing, LLM and voice setup, backups, updates, migrations, removal |
| [CONNECTORS.md](CONNECTORS.md) | Copyable LLM, voice, NPC selection, profile and memory settings |
| [PROTOCOL.md](PROTOCOL.md) | The request and reply contract (one copy, shared by server and client) |
| [UI_GUIDE.md](UI_GUIDE.md) | Dashboard pages and adding your own |
| [LAUNCHER_CUSTOM_MOD.md](LAUNCHER_CUSTOM_MOD.md) | Launcher install, `main`/`dev` branches, publishing your own copy |
| [MAKE_IT_YOURS.md](MAKE_IT_YOURS.md), [WAVE_ACTION.md](WAVE_ACTION.md) | Renaming your copy; worked exercise for adding an action |
| [AGENTS.md](AGENTS.md), [client/AGENTS.md](client/AGENTS.md) | Rules for coding agents |

## Limits

- A template, not a product: no real game is supported until someone ports and tests the
  client in that game. The console's follow is a printed simulation.
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
