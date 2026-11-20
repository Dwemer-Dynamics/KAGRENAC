# Architecture v2 migration plan

Status (2026-11-20): planned. Nothing in this file is implemented. The current code, its rules
in [AGENTS.md](../AGENTS.md) and [PROTOCOL.md](../PROTOCOL.md) version 1 stay authoritative
until a phase below is marked `done` with evidence.

This plan moves KagrenacServer and KagrenacClient from the small synchronous template
([ARCHITECTURE.md](ARCHITECTURE.md)) to the layered, asynchronous design in
[ARCHITECTURE_V2.md](ARCHITECTURE_V2.md). The design follows patterns Dwemer Dynamics uses in
its larger AI mods. Those are a design reference only: no code is copied from them, and
every part here is written and tested from this repository's own code.

## Goals

- Replies stream line by line, with voice for each line, instead of one blocking turn.
- The server can ask the game for live data (game RPC) within a short deadline.
- Game-specific identity, prompts, voices and lore sit behind adapters, not in the core.
- New features arrive as extensions or managers, not as new top-level endpoint files.
- Every existing protocol 1 mod keeps working until its author chooses to move.

## What does not change

| Kept | Why |
|---|---|
| Bearer token on every endpoint except health, and private pairing | Everything from the game is untrusted; the server is reachable on a local port |
| One contract file for each protocol version, with field rules and error codes | Client and server authors need one copy to implement against |
| `health.php` capabilities and schema checks | Clients and Core detect what a server supports before using it |
| PROJECT.md stages, engine planning and evidence kinds | A built server is not a verified game integration |
| Stale-reply protection: one current generation per session and NPC | Cancel, new input and checkpoint restore must drop old work |
| No model call inside a transaction, no automatic retry | Retries repeat replies and actions |
| Optional features off by default and failing cleanly | Text works without voice, memory or extensions |
| The `ui/*.php` dashboard | A new UI framework is a separate project |

## Phases

Each phase is one or more focused pull requests. A phase is `done` only when its
acceptance passes; record the evidence in the phase table at the end.

### P0. Documents and decisions

- This plan, [ARCHITECTURE_V2.md](ARCHITECTURE_V2.md), [GAME_ADAPTER.md](GAME_ADAPTER.md) and
  the [protocol 2 draft](design/PROTOCOL_V2.md).
- Resolve the open decisions below that block P2.

Acceptance: the documents are reviewed; each open decision has an owner and an answer or a
dated next step.

### P1. Server layers, protocol 1 unchanged

Move existing code into the v2 layers without changing any reply, error, log line, audit
row, lock order or the generation check.

| From | To |
|---|---|
| `lib/app.php` database helpers, `ex_*` SQL in `lib/*.php` | `core/` storage: one entity class and one data-access class per table; only `core/` runs SQL |
| `lib/turn.php` `run_turn()` | `managers/Dialogue/`: the turn pipeline |
| `lib/dialogue_history.php`, `lib/knowledge.php`, `lib/memory.php`, `lib/profiles.php`, `lib/checkpoint.php`, `lib/events.php` | one manager each |
| `lib/action_catalog.php` | `managers/Actions/`, still data-only for the catalogue |
| `lib/llm.php`, `lib/speech.php`, `listen.php` provider code, `lib/embeddings.php` | `drivers/llm`, `drivers/tts`, `drivers/stt`, `drivers/embeddings`: one interface, one wrapper and one class per provider |
| Settings read from `config/config.php` arrays | `managers/Config/`: one registry entry per setting (type, default, range, scopes) with global, profile and NPC overrides |
| Top-level `*.php` endpoints | stay as thin entry points that validate, call one manager and reply |

Old function names stay as compatibility facades while anything calls them.

Acceptance: the [AGENTS.md checks](../AGENTS.md#checks-before-finishing) pass, including
`migrate.php` twice and `smoke.sh` in mock mode with byte-identical replies; a layering check
(script or test) fails on SQL outside `core/`, provider HTTP outside `drivers/` and manager
code reading the request.

### P2. Asynchronous dialogue (protocol 2)

- A durable message table: each reply line is a message with a lifecycle
  (pending, completed, delivered, cancelled, expired).
- `POST dialogue/request` validates, admits the turn and answers `202` before any provider
  call. The same request then runs the turn and publishes lines as the model streams them.
- A doorbell (WebSocket) tells the game a message is ready; the game fetches it once over
  HTTP. The doorbell carries no dialogue text.
- A spoken receipt reports when a line started, finished, was interrupted or skipped.
- Cancel by NPC, request or conversation chain.
- `turn.php` and `event.php` (protocol 1) become synchronous facades over the same pipeline,
  so protocol 1 clients see no change.

Acceptance: protocol 1 smoke unchanged; a protocol 2 fixture shows first-line delivery before
the model finishes, cancel dropping pending lines, a stale line never delivered, and the
doorbell absent (server down, port blocked) leaving protocol 1 and the game playable.

### P3. Game RPC, capabilities and identity

- Game RPC over the same socket: the server asks, the game answers within a deadline;
  methods are allowlisted on both sides and each declares the thread it runs on.
- Capability flags in each request say which actions and features the game can run now.
  Actions are bound to the offer that made them possible (request, NPC, session, lifetime).
- An identity resolver the port supplies turns game ids into stable server character ids.
- A load epoch: each save load starts a new session; work from an older session is dropped.

Acceptance: fixtures for RPC timeout, unknown method, disconnected game, stale session and
an action returned outside its offer; none of them blocks a reply.

### P4. Extension host and bounded workers

- Extensions: a manifest with an API version, declared hooks and permissions, lazy loading,
  per-handler error isolation and automatic disable after repeated failures. Private game
  observations are removed before extension filters run and checked again afterwards.
- Workers: bounded runs (units and seconds), progress derived from data, results written
  once under a guard, LLM calls outside transactions, results dropped if the save timeline
  changed meanwhile. Memory summaries and embeddings move here from the turn path.

Acceptance: an example extension and an example worker with fixtures; a failing extension
never changes a core reply.

### P5. Client core v2 and port guides

- `KagrenacClientCore` gains the doorbell, fetch, spoken receipt, RPC dispatcher and load
  epoch, using WinHTTP's WebSocket support so it stays dependency-free and builds for x64 and
  x86.
- The console example runs both protocols.
- [PORT_RECIPES](feature-recipes/PORT_RECIPES.md), [ENGINE_PLANNING](ENGINE_PLANNING.md) and
  the PROJECT.md integration plan gain rows for the socket, RPC methods and the identity
  resolver.

Acceptance: both builds pass; the console shows streamed lines, cancel and an RPC answer
against a mock-mode server. This is not evidence for any real game.

## Open decisions

| # | Decision | Options | Blocks | Owner | State |
|---|---|---|---|---|---|
| D1 | Who owns the doorbell process and its ports | one shared Core service that routes by server id; or one process per mod with ports allocated by Core | P2 | DwemerDistro Core | open |
| D2 | Minimum PHP version | stay on 8.2; or require the version Core ships after Update Distro | P1 | Core | open: confirm the public base image |
| D3 | Dependencies | stay dependency-free (own small storage layer); or allow a vetted Composer set installed by Core before migrations | P1 | maintainers | open |
| D4 | Long-running worker process | on-demand bounded runs started by the dashboard or a turn's deferred step; or a supervisor owned by Core | P4 | Core | open |
| D5 | Protocol 1 retirement | keep indefinitely as a facade; or deprecate after a dated notice | after P2 | maintainers | open |

Until D1 and D4 are decided, the rule in [AGENTS.md](../AGENTS.md) against default services,
watchers and project-written launchers stands.

## Progress

| Phase | State | Latest evidence (date, kind) |
|---|---|---|
| P0 | in progress | 2026-11-20, source: documents drafted |
| P1 | not started | |
| P2 | not started | |
| P3 | not started | |
| P4 | not started | |
| P5 | not started | |
