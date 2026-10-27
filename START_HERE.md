# Start here

New project? Use [the guided setup](docs/getting-started.md) and keep its current state in
[PROJECT.md](PROJECT.md). This page is a reference map, not another setup route.

## Which document answers what

| Question | Reference |
|---|---|
| What should the mod do? | [Gameplay design](docs/GAMEPLAY_DESIGN.md) |
| Can this game support it? | [Engine planning](docs/ENGINE_PLANNING.md), [research leads](docs/research/MODDING_TOOLS.md) |
| How do I install and pair it? | [SETUP.md](SETUP.md), [guided commands](docs/getting-started.md#scriptsprojectps1) |
| How do I configure providers? | [CONNECTORS.md](CONNECTORS.md) |
| What goes over the wire? | [PROTOCOL.md](PROTOCOL.md) |
| Where should code live? | [Architecture](docs/ARCHITECTURE.md), [client core](client/README.md) |
| How do I add a feature? | [Port recipes](docs/feature-recipes/PORT_RECIPES.md), [worked action](WAVE_ACTION.md) |
| How does the dashboard work? | [UI_GUIDE.md](UI_GUIDE.md) |

## Before you start

Check [requirements and current compatibility](docs/getting-started.md#before-you-start).
The console is a developer tool. The mod's player-facing UI belongs in the game.

### Deployment and exposure

New generated projects install at `/var/www/html/<Name>Server`; Core's registry is the
source of truth for an existing path. Legacy `custom-mods/<id>` installs remain supported.
The server copy contains `client/`, `docs/` and `ports/` because it is one repository;
those are source only. Core's web protection must be present before source is installed.

Check HTTP **403** for private config, `.git/` and every source folder on every listener.
A 404, redirect or empty 200 is not that check. Never build or pair inside a web root.
See [web protection](SETUP.md#1-install-the-server-inside-dwemerdistro) and
[private data](SECURITY.md).

## Feature and status checklist

| Feature | Contract or implementation |
|---|---|
| Typed turn, optional responding game event | [Turns and events](PROTOCOL.md); both use `lib/turn.php` |
| History, bios and known facts | [Client examples](client/README.md#npc-bios-knowledge-and-checkpoints), [provider context](CONNECTORS.md) |
| Cancellation, session changes, stale replies | [Cancellation](#cancellation-and-stale-replies) |
| Action requests and outcome reports | [Actions](#actions-and-the-worked-extension) |
| Optional TTS/STT | [Voice](CONNECTORS.md#voice), [client voice examples](client/README.md#voice-examples) |
| Answering-NPC selection | [NPC selection](CONNECTORS.md#npc-selection-decision-optional); `decision.php` has no dialogue or actions |
| Optional profiles, memory and vector search | [CONNECTORS.md](CONNECTORS.md); not prerequisites for a basic mod |
| Real engine support | [Porting evidence](#porting-to-a-real-engine); no shipped live-game verification claimed |

## End-to-end walkthrough

Follow [guided setup](docs/getting-started.md) for a mod, or the
[client fast start](client/README.md#fast-start) for an explicitly requested console exercise.
The detailed install, pairing, provider, backup and update commands live in [SETUP.md](SETUP.md).
Do not make the player complete a console exercise before building their mod.

<a id="7-checkpoints-versus-backups"></a>

### Checkpoints versus backups

A checkpoint restores one session's dialogue and memory notes. A database/config backup is
for installation recovery. Neither replaces a game save. See
[protocol checkpoints](PROTOCOL.md) and [backup and update](SETUP.md#6-back-up-and-update).

<a id="9-actions-and-the-worked-extension"></a>

### Actions and the worked extension

The server returns only allowlisted action names; the client also needs its own allowlist
and a registered handler. Start with actions disabled until the port qualifies its handlers.
[WAVE_ACTION.md](WAVE_ACTION.md) is a developer exercise; it adds no real game capability.
Use [awareness and action gates](docs/feature-recipes/PORT_RECIPES.md#awareness-and-actions)
for the port and [result reports](PROTOCOL.md#optional-post-resultphp) for observations.

<a id="10-cancellation-and-stale-replies"></a>

### Cancellation and stale replies

Cancel on recipient unload, save/session change, replacement or shutdown. Apply a reply,
voice or action only to the same live NPC instance and session. No automatic failed-turn
retry. [TurnRuntime](client/README.md#adopting-turnruntime-in-a-port) supplies the shared
lifecycle; the port still owns native entity and input checks.

## Troubleshooting by request ID

Use a new `request_id` for each turn/event: 8-64 characters from `A-Z a-z 0-9 _ . : -`.
The client prints it; find it in the matching install's **Control Panel > Logs**, or
**Connector calls** for voice, decisions, embeddings and memory. Voice/decision IDs are
optional for older clients; the server generates one when omitted.

| Evidence | Meaning and next check |
|---|---|
| No Logs row | Inconclusive: wrong install/filter, early validation/auth/schema rejection, unsent request, retention, or failed logging. Inspect the client's HTTP status and `logged` field; connector-only requests are on Connector calls |
| `failed`, `llm_unavailable` | Check provider configuration and the Apache `example-ai [<id>]:` diagnostic; provider bodies are not logged |
| `duplicate_request` | The ID was reused within a day; use a fresh ID, without automatic resend |
| `cancelled` / `superseded` | Expected when cancelled, replaced or invalidated by restore |
| `complete` | Server finished. This does not prove the game received or displayed it |
| Client report `rejected` / `failed` | Check both action allowlists, target identity and registered handler |
| `game_event` complete | A log-only event was stored; it does not generate a reply |

`result.php` can return `404 unknown_request` after retention or for mismatched ids, and
`409 action_not_returned` / `already_reported` for invalid reports. See
[SETUP troubleshooting](SETUP.md#troubleshooting) before changing prompts.

### What Logs stores

`ex_events` intentionally stores player text, validated game context, cleaned replies and a
snapshot of retrieved bios/facts. Treat database exports as private conversations. Log
retention (`event_log_limit`) is separate from history and checkpoints. The connector audit
stores ids, provider, status and timing; diagnostic logs and connector audit must not store
keys, prompts, transcripts, audio or provider bodies. A client action report is untrusted;
`handled` means the handler ran, not that its intended game outcome happened.

## Versions and migrations

Server version, client version, protocol, baseline and database schema are separate.
Use [health](PROTOCOL.md), `lib/version.php`, `client/CMakeLists.txt` and `lib/app.php` for
current values. Migrations are additive and safe to repeat. A too-new database is refused;
there are no down migrations. See [migration and recovery details](SETUP.md#6-back-up-and-update).

## Server files

Endpoints are top-level PHP files. `lib/turn.php` coordinates domain services in `lib/`;
`sql/` owns migrations and `config/config.example.php` documents settings.
[Architecture](docs/ARCHITECTURE.md) explains ownership;
[PROTOCOL.md](PROTOCOL.md) specifies each endpoint; [UI_GUIDE.md](UI_GUIDE.md) covers the dashboard.

## Updating and private files

Deploy uses committed HEAD. `update.sh` backs up, refuses dirty/diverged checkouts and
fast-forwards from the install's upstream. A generated project is independent; future
template changes are reviewed and adapted deliberately. Neither route resets local work.
See [SETUP.md](SETUP.md#6-back-up-and-update) and [contribution hygiene](CONTRIBUTING.md).

## Launcher install and multiple copies

The launcher server route is separate from creating a new mod. The template keeps its
`example-server` identity for existing installations; generated mods get their own id,
named root and database. See [LAUNCHER_CUSTOM_MOD.md](LAUNCHER_CUSTOM_MOD.md).

## Packaging, licensing and private data

Ship reviewed source and intended plugin artifacts. Exclude credentials, paired configs,
logs, databases, backups, memory exports and voice samples unless explicitly intended and
safe to distribute. Keep licences and third-party notices; replace template branding with
your own. See [MAKE_IT_YOURS.md](MAKE_IT_YOURS.md), [CONTRIBUTING.md](CONTRIBUTING.md) and
[SECURITY.md](SECURITY.md).

## Porting to a real engine

Use [engine planning](docs/ENGINE_PLANNING.md), the [agent playbook](docs/agent-playbook.md)
and a copy of the [engine evidence record](docs/engine-packs/ENGINE_PACK.md).
Report these levels separately:

1. **Server/fixture:** mock protocol, migrations, validation and stale-result checks.
2. **Client build:** transport/runtime and the actual adapter's serialized request bytes.
3. **Provider:** configured LLM/TTS returned successfully; a WAV is not heard voice.
4. **In game:** native targeting, input capture/release, visible reply, requested heard
   voice, each action's observed outcome and normal-launch connection.

A scaffold, diagnostic hook, external chat window or working server is not level 4.
Leave each unresolved mechanism with its evidence and next bounded probe in PROJECT.md.
