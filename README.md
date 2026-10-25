# KAGRENAC AI Mod Maker

Building a mod to share? See [community publishing](docs/PUBLISHING.md) for one-repo
client/server releases, include/exclude rules, artwork and automatic installation.

<img src="ui/images/kagrenac.png" alt="KAGRENAC AI Mod Maker" width="128">

Build an AI mod with your coding agent: choose a game, design a useful gameplay loop,
prove the game's integration, then add dialogue, voice and supported actions.

One repository contains **KagrenacServer**, the PHP server and dashboard at the root,
and **KagrenacClient**, the shared Windows C++ client library and console example in
`client/`. Each mod gets its own source repository, server, database and private pairing.
The game-side integration is built for the game you choose.

## Get started

1. Clone this repository on Windows, or use GitHub's **Use this template**.
2. Open your coding agent in the checkout and paste the prompt below.
3. Follow [the guided setup](docs/getting-started.md). The agent runs the commands and
   records progress in [PROJECT.md](PROJECT.md); you supply private credentials and test
   the result in your game.

### First prompt for your coding agent

```text
Read AGENTS.md, PROJECT.md and docs/getting-started.md. Help me build an AI mod.
Reuse what I already told you; ask only for the missing game, starting feature and mod name.
Plan a meaningful gameplay loop and qualify the game's integration before writing port code.
Prepare the server and providers alongside that research. Use in-game text chat by default;
add voice if requested and speech input only if requested. Run the setup, implement, test,
review the actual changes, and fix findings. Keep keys out of chat and preserve existing work.
```

## Requirements

- Windows with Git and a coding agent of your choice. No separate coding model is required.
- [DwemerDistro](https://github.com/Dwemer-Dynamics/DwemerDistro) for the local PHP 8.2 and
  PostgreSQL server, with a **compatible Core**; check the limitation below before installing.
- The game's own mod tools or a qualified loader for its exact build. C++ ports and the
  console example need Visual Studio C++ tools; script or managed ports use their own tools.
- An LLM provider for real conversations. Recommended defaults are OpenRouter Gemma for
  dialogue, JEV for supported bounded decisions, and PocketTTS for requested voice.
  [Provider settings](CONNECTORS.md) give the exact model IDs and alternatives.

**Run Update Distro before your first deployment.** It fetches Core's current `main` and
installs the helpers needed by guided setup: `setup-web --protect-project`,
`setup-web --protect-root`, `update --expect-commit` and named `server_folder` support.
The older **v1.0.8 tag** lacks these capabilities, and a base image can ship older helpers.
The version label alone is not a compatibility test. Check the helper after updating. Deploy refuses an
incompatible Core before installing source; do not bypass that guard. See
[setup compatibility](docs/getting-started.md#before-you-start) for the checks and manual route.

## What works today

| Component | Included | Evidence boundary |
|---|---|---|
| Server | Turns, game events, NPC bios and knowledge, history, checkpoints, optional memory, dashboard and provider connectors | Mock-mode checks are repeatable; real providers need their own test |
| Shared C++ client | Async turns, cancellation, action handlers, text before voice, engine-free text-composer lifecycle | Builds for x64 and x86; the console simulates a game |
| Voice | PocketTTS and supported alternatives; optional transcription | Off by default. The console saves WAVs; each game port must implement playback and requested microphone input |
| Engine ports | An Elden Ring reference and a process for qualifying other engines | The shipped reference builds and passes fixtures; no live-game verification is claimed for this template |
| Install and pairing | Committed-source deploy, named server roots and private client config | Requires compatible Core; installing the server alone does not install a game plugin |

The model can request allowlisted actions. Both server and client validate them; the game
must provide a real handler and observe its outcome. A returned action is not proof it ran.
JEV's shipped `decision.php` contract selects an answering NPC from the candidates offered
by the game. Other decision systems need a planned, validated game-specific contract.

## How a mod is built

**Brief → gameplay design → game integration proof → first connected prototype → expansion.**

The first prototype should show the requested loop in game, with current game context,
a visible recipient, free typed chat, a reply and any requested voice or qualified action.
Automatic remarks must respond to meaningful observed events, yield to player input and
end cleanly. A probe, mocked conversation or external chat window is not that prototype.

After one-time installation and pairing, the mod loads and connects through the game's
normal mod loader. The player starts DwemerDistro and the game; no per-session transport
or provider-arming command. See [installed startup acceptance](docs/ENGINE_PLANNING.md#installed-startup-acceptance).

## Documentation

| Need | Read |
|---|---|
| Start or resume a mod | [Guided setup](docs/getting-started.md), [PROJECT.md](PROJECT.md) |
| Design the experience | [Gameplay design](docs/GAMEPLAY_DESIGN.md), [engine planning](docs/ENGINE_PLANNING.md) |
| Find a reference or diagnose a request | [START_HERE.md](START_HERE.md) |
| Install, pair, update or remove | [SETUP.md](SETUP.md), [launcher route](LAUNCHER_CUSTOM_MOD.md) |
| Configure models and voice | [CONNECTORS.md](CONNECTORS.md) |
| Implement the protocol | [PROTOCOL.md](PROTOCOL.md), [client guide](client/README.md), [architecture](docs/ARCHITECTURE.md) |
| Extend a port | [Agent playbook](docs/agent-playbook.md), [port recipes](docs/feature-recipes/PORT_RECIPES.md), [engine evidence record](docs/engine-packs/ENGINE_PACK.md) |
| Contribute or report a problem | [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) |

## Directory map

| Path | Purpose |
|---|---|
| `*.php`, `lib/`, `sql/`, `config/`, `ui/` | Server endpoints, services, migrations, private settings and dashboard |
| `client/` | Shared C++ client core and console example; [client rules](client/AGENTS.md) |
| `ports/` | Game-specific source, build routes and qualified capability records |
| `scripts/` | Setup, deployment, pairing, migrations, backup and smoke checks |
| `docs/` | Authoring guides and references |
| `dwemer-mod.json` | Server identity; generated projects get their own id and `<Name>Server` folder |
| `PROJECT.md` | One current project brief, plan, status and evidence record |

## Limits

- This is an authoring template. A server install or successful build does not establish
  live game support, visible UI, working actions or heard voice.
- Use one PC or a trusted network. The dashboard has no login, the API token travels over
  HTTP, and there is no rate limiting. [Exposure and private data](SECURITY.md) describes
  the deployment boundary.
- Builds, paired configs, credentials, backups and logs stay outside source and web roots.
  Core's protection must deny config, Git and source folders on every Apache listener.
- Keep existing installs compatible: the template id stays `example-server`. New projects
  use named server roots; older `custom-mods/<id>` routes remain supported.

## Licence

Copyright (C) 2026 Dwemer Dynamics. GNU General Public License version 3 only
(`GPL-3.0-only`): [LICENSE](LICENSE), [client/LICENSE](client/LICENSE).
Retain [third-party notices](THIRD_PARTY_NOTICES.md) and
[client notices](client/THIRD_PARTY_NOTICES.md). Replace the supplied branding with your
own artwork when making your own mod; see [MAKE_IT_YOURS.md](MAKE_IT_YOURS.md).
