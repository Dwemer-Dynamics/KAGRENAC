# Architecture, version 2 (target)

Status (2026-11-20): planned, not implemented. The code today follows
[ARCHITECTURE.md](ARCHITECTURE.md). The order of work is in [MIGRATION_PLAN.md](MIGRATION_PLAN.md).

This page describes where each piece of the server and client belongs once the migration is
done, who owns what, and which way dependencies point. The wire contract is in the
[protocol 2 draft](design/PROTOCOL_V2.md); the game-specific boundary is in
[GAME_ADAPTER.md](GAME_ADAPTER.md).

## Server layers

| Layer | Folder | Owns | Never |
|---|---|---|---|
| Entry points | top-level `*.php`, `api/` | Method and token check, size limits, request validation, calling one manager, the reply | SQL, provider calls, prompt building, turn order |
| Managers | `managers/<Name>/` | One domain workflow each: dialogue, messages, context, prompts, actions, NPCs, sessions, memory, config, extensions | Read the raw request, write a reply, open sockets, talk to providers except through drivers |
| Drivers | `drivers/{llm,tts,stt,embeddings}/` | Provider requests and parsing behind one interface per kind; a wrapper chooses the driver from stored connector settings | Fall back silently to another provider; know about NPCs or prompts |
| Workers | `workers/<Name>/` | Bounded background jobs (memory summaries, embeddings, deferred extension events) | Run unbounded; hold a transaction across a model call |
| Extensions | `extensions/<id>/` | Optional features through declared hooks, routes, actions and their own `ext_<id>_*` tables | Change the session, the player identity or private game observations |
| Storage | `core/` | Entities and data-access classes; the only code that runs SQL; migrations | Depend on managers, drivers or the request |
| Helpers | `lib/` | Small generic helpers: logging, JSON replies, body reading, validation | Depend on any other layer |

Dependencies point down: entry points, then managers, then drivers and storage, then helpers.
Workers and extensions call managers. A manager may call another manager. Nothing calls
upward, and entry points never import workers or storage directly.

Make the rules a check, not only a sentence: a layering test fails on SQL outside `core/`,
provider HTTP outside `drivers/`, request globals inside managers, and an entry point longer
than a fixed limit. Large orchestration in a route file is the usual way a layered design
decays; the dialogue pipeline lives in `managers/Dialogue/` from the start.

## One dialogue turn

```text
game ──POST dialogue/request──▶ entry point ── validate, token, limits
                                    │
                                    ▼
                         Dialogue manager: admit in one transaction
                         (session check, supersede older pending lines,
                          resolve ids, store request, enqueue messages)
                                    │
game ◀──── 202 accepted ────────────┘   (no provider call yet)
                                    │
                         optional game RPC reads, short deadline
                         context + prompt ─▶ LLM driver (streaming)
                         each sentence ─▶ actions check ─▶ TTS driver
                         complete message ─▶ doorbell
                                    │
game ◀──── doorbell: message ready ─┘
game ──GET messages/{id}──▶ delivered once
game ──POST dialogue/spoken──▶ receipt (started, finished, interrupted, skipped)
```

- Admission is the only transaction on the request path. Provider calls run after it, with
  no lock held.
- A newer player line, a cancel or a save load moves the generation; lines from an older
  generation are never delivered.
- Text is published before voice. A TTS failure delivers the line without audio.
- Synchronous requests stay synchronous: transcription, health, settings and game events
  that need no reply.

## Messages and the doorbell

The message table is the source of truth; the doorbell only says "message N is ready".
If the doorbell is down the game can still fetch pending messages, and nothing in the
doorbell is trusted beyond the message id. The doorbell's process and ports are an open
decision (D1 in the migration plan); until it is settled, no mod starts a background service.

## Game RPC

The server may ask the game a question (inventory, nearby items, a position) over the same
socket. Each method is allowlisted on both sides and declares where it runs in the game (the
socket thread or the game thread). Calls have a deadline, a cap on calls in flight and typed
failures (not connected, timeout, unknown method, busy). Interactive code prefers data the
game already sent; RPC is for values that are cheap to read and needed now.

## Settings

One registry entry per setting: key, type, default, range, scopes and a short description.
Values resolve NPC, then profile, then global, then default, and the registry can explain
where a value came from. The dashboard reads the registry to draw forms. Secrets stay in
the API keys store, never in a setting or a profile.

## Extensions

An extension ships a manifest (id, version, supported extension API range, hooks,
permissions, settings) and its code. The host loads it only when one of its hooks fires,
runs each handler in isolation, logs slow handlers and disables an extension after repeated
failures. Hooks come in three kinds: filters (may change a payload), events (notified now)
and deferred events (stored and delivered at least once by a worker). Before any filter runs,
the host removes private game observations and capability flags from the request and checks
them again afterwards, so an extension cannot grant itself a capability.

## Workers

A worker run is bounded by units and seconds and then exits with a status (done, more
pending, idle, failed). It derives progress from data, locks each unit, writes its result
once under a guard and drops results if the save timeline changed while it ran. Model calls
happen between reading inputs and writing results, never inside a transaction.

## Client

| Part | Owns | Never |
|---|---|---|
| `GameAdapter` (per port) | Everything that touches the engine; see [GAME_ADAPTER.md](GAME_ADAPTER.md) | Network calls |
| `TurnRuntime` | Pending request, load epoch, doorbell subscription, fetch, receipts, cancels, action dispatch on the game thread, bounded shutdown | Engine calls from a worker thread |
| `AiClient` | Both protocol versions over WinHTTP (HTTP and WebSocket) | Game state |
| `RpcDispatcher` | Method table, thread affinity per method, calls in flight, deadlines | Methods the port did not register |

The client keeps C++17, the Windows SDK and the bundled JSON header, and builds for x64 and
x86.
