# Architecture

How the server code is divided, who owns what and which way dependencies point, with a
short note on the client at the end. The contract with the game is
[PROTOCOL.md](../PROTOCOL.md); this page is only about the code.

## Layers

| Layer | Files | Owns | Never |
|---|---|---|---|
| Endpoints | `*.php` at the top level, `ui/*.php`, `scripts/*.php` | Method and token check, request validation, the reply or exit code, the audit row after the reply | Hold SQL or provider logic another endpoint also needs |
| Orchestration | `lib/turn.php` (`run_turn()`), `lib/memory.php` | Order of one turn: duplicate check, generation, profile, history, knowledge, model call, stale check, save, event log | Call a model inside a transaction |
| Domain services | `lib/dialogue_history.php` (`DialogueHistory`), `lib/speech.php` (`SpeechService`) | One concern each: the saved dialogue lines; the text-to-speech call | Read request input, check tokens, start transactions, take locks or send replies |
| Shared helpers | `lib/app.php` and the other `lib/*.php` function files | Config, replies, validation, database, HTTP, schema check | Depend on a service or an endpoint |
| Data catalogue | `lib/action_catalog.php` (`ActionCatalog`) | The known actions: names, prompt hints, target rules | Require another file, or read config, the request or the database |

Dependencies point down only: endpoints, then orchestration, then services, then helpers,
then the data-only `ActionCatalog`, which any layer may read (`lib/llm.php` builds
`actions_prompt()`, `extract_actions()` and `NPC_TARGET_ACTIONS` from it).
A service may use helpers (`db_query()`, `http_post()`, `app_log()`); `db_query()`'s
existing 500 reply on a database error is the one reply path a service inherits, and
`DialogueHistory::tryRecent()` exists for code that runs after the reply was sent.

## Owners

- **ActionCatalog** holds every action the server knows: its prompt hint and its target
  rule (today all act on the request's `npc.id`). `actions_prompt()`, `extract_actions()`
  and `project.ps1 configure` read it. Knowing an action never allows it: config
  `allowed_actions`, narrowed by the game's `offered_actions`, decides. A name the operator
  allowed that the catalog does not list is still offered as a bare tag and returned
  without args.
- **DialogueHistory** owns the `ex_turns` SQL of a turn: the newest lines and saving one
  exchange with trimming. The session lock, the generation `FOR UPDATE` check and the
  transaction stay in `run_turn()`, so the lock order (session lock, then rows) is visible
  in one place. Checkpoints and the dashboard History page still query `ex_turns` directly.
- **SpeechService** owns the provider request, the profile voice and the WAV check.
  `speak.php` keeps validation, the disabled answer and the audit row.

## Compatibility facades

Existing functions and constants keep their names, arguments and results and now delegate:
`actions_prompt()`, `extract_actions()`, `NPC_TARGET_ACTIONS`, `memory_history()`, and
`speak.php` itself. Keep them while anything calls them; new code may call the service.

## Adding code

- Plain PHP 8.2, explicit `require_once`, no autoloader. A library file only declares
  functions, constants or classes, so requesting it over HTTP prints nothing.
- Add a class only for one clear concern with more than one caller or a boundary worth
  naming; otherwise add a function. Small `final` classes, no base classes, containers or
  interfaces until two implementations exist.
- Moving code into a service must not change replies, errors, log lines, audit rows,
  validation, lock order or the generation check.

## Client (`client/src`)

| Part | Owns | Never |
|---|---|---|
| `GameAdapter` (per port) | Reading context, showing text, `isSameNpc()`, playing voice, the engine side of each action | Network calls |
| `TurnRuntime` (`turn_runtime`, one per port) | Bounded workers (four normal, two for cancels), the mailbox, the pending request id, NPC instance rechecks, cancels serialized per session and NPC, the settings snapshot each request keeps, registered action handlers, voice after text, result reports, bounded shutdown | Engine calls from a worker; running an action name without an allowlist entry and a registered handler |
| `AiClient`, `Config` | The protocol 1 wire format and settings, unchanged | Game state |
| `main.cpp` (console only) | Command line, console input and the console's simulated handlers | Lifecycle rules |

`ai_client`, `config` and `turn_runtime` are the `KagrenacClientCore` static library. The
console client uses it today; existing engine ports have not been moved to it, and using
it is no evidence of in-game behaviour.
