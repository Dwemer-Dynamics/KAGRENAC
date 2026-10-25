# Port recipes

One bounded recipe per port stage in [agent-playbook.md](../agent-playbook.md). Each maps to a
seam that already exists in this template and links to the canonical rule rather than
restating it. None of them adds a runtime feature, endpoint or protocol change.

Each recipe ends with two lines:

- **Check now**: what you can run today with the console client and a mock server. It may
  be "none (engine only)". Run it when the stage changed shared client or server code; it
  is never a step the first in-game prototype waits for.
- **Engine only**: what can be shown only in the game. Record it in
  [ENGINE_PACK.md](../engine-packs/ENGINE_PACK.md) with the statuses defined there.

The rules for threads, stale replies and actions are in [AGENTS.md](../../AGENTS.md), [client/AGENTS.md](../../client/AGENTS.md) and
[START_HERE, Cancellation and stale replies](../../START_HERE.md#10-cancellation-and-stale-replies).
Every recipe assumes them.

## Script engines and an external helper

Use this route when the game exposes entity/callback APIs but not safe HTTP or dynamic WAV
playback. First qualify the script API, I/O permissions and lifecycle from the installed
documentation ([Engine planning](../ENGINE_PLANNING.md)). A script sandbox may require the
user to enable a specific mod-menu setting. Never assume an edited setting persists.
Keep text entry, selection, replies and cancel inside the game; the helper is a background
implementation detail. Prefer game-side transport/audio when supported. A separate helper
window or desktop overlay is a last resort whose blocker and tradeoff must be explained
before adopting it, not the normal first-demo experience.

- The game script owns all entity reads, input, subtitles and action handlers, on documented
  callbacks. Capture a bounded awareness snapshot when the user sends a line; no model calls
  from a world update. Unknown values stay unavailable.
- A small external helper reuses `client/src/ai_client.cpp` and `config.cpp` for HTTP/cancel
  and optional voice. It never reads or writes game memory. Build it for the host independently
  of the game's bitness. Audio played by the helper is audible, not positional NPC audio.
- Use a bounded data-only mailbox or another qualified transport. Limit size, values and
  outstanding work; never evaluate Lua or model text received over it. Publish whole requests
  and reject partial/colliding records. Never put credentials in game scripts or mailbox files.
- Carry request, run/save, generation and NPC-instance identities through every step. Check
  them before display, actions and voice. A pause, death, player/NPC replacement, new save or
  cancel invalidates old work. Restore controls even when the player entity changes.
- Wait for the old server cancel before accepting a new turn for that NPC/session. Drop a
  stale turn with a matching error so the game releases its pending input state promptly.
- Play audio only while its matching subtitle/instance is still current. A heartbeat must
  work at low frame rates and stop when game updates stop. Check freshness with bounded clocks.
- The port provides `doctor`, `build`, `assemble`, `install`, `start`, `stop` (and optional
  `restart`) through its maintained route. Start helpers hidden with logs, one instance per
  runtime. Stop the specific helper gracefully; never kill unrelated processes. Do not launch
  the game automatically. Print full pair/configure and first-launch instructions.
- Use [generic build/runtime records](../PORT_BUILD_RECORDS.md) to gate action setup. Repeat
  build, pairing, install and start/stop to verify stable hashes and private config preservation.

**Check now:** existing shared-client checks if that code changed, parser/identity/cancel
probes appropriate to the port, build hashes, helper health and repeated lifecycle commands.
**Engine only:** actual script I/O, input focus, awareness, each action, pause/death/continue,
replacement and audible voice. Keep those distinct from successful mock/provider tests.

## Plugin lifecycle and shutdown

**Seam.** `TurnRuntime` (`client/src/turn_runtime.h`) owns the lifecycle: one mailbox, the
pending `request_id`, its captured `GameContext` and settings, two bounded worker pools,
cancels serialized per session and NPC, and `tick()`, which drains the mailbox on the game
thread. `runInteractive()` in `client/src/main.cpp` shows the glue. The console's `/npc`,
`/unload` and `/load` call `ConsoleGame` directly and are not part of `GameAdapter`.

- On load, read the config and create one `TurnRuntime` in the plugin entry point, then
  register a handler for each action the engine implements.
- On each main-thread tick, call `tick()`: it reaps finished workers, drains the mailbox,
  drops the pending reply or voice if `isSameNpc()` fails, then applies results.
- On unload or quit, call `shutdown()` on the game thread from the engine's unload hook,
  before the adapter goes away, then destroy the runtime there. The plugin owns it; never
  leave `shutdown()` or the destructor (both wait) to `DllMain` or a global or static
  destructor, where the wait can hang.
- Lifecycle lives in the plugin glue. `GameAdapter` gains no lifecycle methods.
- **Required on unload or quit:** clear the pending `request_id`, stop applying anything,
  and make sure no worker can call into the module after it unloads. The console waits
  for every worker before it exits (bounded per call by `timeout_seconds`, see
  [README, Limits](../../client/README.md#limits)). Whether a plugin may wait like that during unload,
  or must stop its threads another way, is an engine fact for ENGINE_PACK.md.
- **Optional:** a server cancel on quit, as `/quit` sends, only if ENGINE_PACK.md records
  that it can finish without blocking shutdown or outliving the module. Otherwise call
  `shutdown(message, false)`, which drops the pending turn locally without a cancel.
- **If no cancel is sent, or it fails** (cancels are best effort and never retried), the
  server may still finish the turn and save it to that session's history as `complete`.
  The player never saw that reply, but the NPC may refer to it later.

**Check now:** interactive `/unload`, `/load` and `/quit` with `mock_delay_seconds` 2 or
more (the matching rows in [README, Smoke checks](../../client/README.md#smoke-checks)).
**Engine only:** real load, unload and quit hooks; no callback after module unload; no
hang on exit.

## Typed dialogue

**Seam.** `TurnRuntime::submitTurn()`: `readContext()` on the game thread, a fresh
`newRequestId()`, `sendTurn()` on a worker, the result back through the mailbox, then
`tick()`, which checks the request ID and `isSameNpc()` before showing the reply and
running actions.

- Take the player's text from engine input. Read the context at send time, not later.
- If every worker is busy, a cancel for that NPC in that session is still out, or no
  cancel slot would stay free (one more is needed when replacing another NPC's pending
  turn), refuse with a message, as the console does. Do not queue.
- A failed turn is shown and never retried. Request and reply rules are in
  [PROTOCOL, POST turn.php](../../PROTOCOL.md#post-turnphp).

**Check now:** type a line in the interactive console; `--say "hello"`.
**Engine only:** the input UI, the subtitle in game, and the game thread never waiting on
HTTP.

## Actions

**Seam.** One handler per action registered with `TurnRuntime::setActionHandler()`, one
`GameAdapter` method and both allowlists; an allowlisted action without a handler is rejected. Follow [WAVE_ACTION.md](../../WAVE_ACTION.md) for
any new action. Do not copy its steps here.

- Implement `followPlayer()` with the engine's own follow behaviour and register it, or
  leave it out in a port without actions. The target is always the NPC the request was
  sent to.
- Add other actions only if authorized. Every action passes the gates in
  [Awareness and actions](#awareness-and-actions).

**Check now:** `--say "follow me"`; `--say "dance"` (the server rejects it); client
`"allowed_actions": []` (the client rejects `follow_player`). See
[START_HERE, Actions](../../START_HERE.md#9-actions-and-the-worked-extension).
**Engine only:** the NPC really follows.

## Awareness and actions

**Seam.** `readContext()` fills `GameContext.details` on the game thread at send time; it is
sent as `context` and reaches the model as quoted, untrusted data (`context_prompt()` in
`lib/llm.php`). The prompt offers only the server's `allowed_actions` (`actions_prompt()`),
and with none it tells the model it cannot act. Actions then pass both allowlists and one
registered handler each in `TurnRuntime`. The loop:

1. **Observe.** Send only what the game actually read, on a thread ENGINE_PACK.md records
   as safe for that read. The plan names each observation's source (a cited engine read)
   and its freshness limit. One the mod cannot read, or read longer ago than its limit, is
   sent as the value `unavailable`, never left out, guessed or filled with static text. One
   entry says where the observations came from and when; label that time as the request
   time unless the game captured the values then. Protocol 1 limits apply (10 entries,
   200 characters each).
2. **Offer capabilities.** An action is offered only with its name in both allowlists, its
   target (always the request's `npc.id`), the instance marker `isSameNpc()` checks, and
   written preconditions (for example "companion loaded and alive").
3. **Route.** An obvious command (a button, a key, or a fixed phrase the game itself matches)
   goes straight to its handler without a model call. Dialogue goes to the dialogue model,
   which may ask for an offered action with a tag. A bounded choice between offered options
   is the future JEV contract below. No model call runs from a game tick or frame callback:
   calls start only from player input or a bounded event, on a worker thread.
4. **Validate, then execute.** On the game thread: the reply is the current one,
   `isSameNpc()` passes, the target matches, and the preconditions hold on a fresh
   observation. Then the one explicit handler runs.
5. **Report the actual result.** `handled` in `result.php` means the handler ran, not that
   the outcome happened. Record an outcome (the companion is following) only from a later
   observation, and never let dialogue state it before then. Feeding that observed outcome
   back into dialogue is a new event type: a protocol change for server and client together.

**Gates, in order, for every handler and every observation.**

- **Cited mechanism.** ENGINE_PACK.md cites a mechanism that does exactly this read or
  action (SDK file, doc or the game's own data). No guessed address or hook.
- **Guarded local validation.** Implement and prototype the handler or reader behind that
  mechanism, off in shipped config, and check it locally (harness, test build, a private
  config). This step does not wait for in-game proof; requiring that first would be circular.
- **In-game verification.** Run it in the game against the engine pack's acceptance. Only
  then mark it Verified (in engine), add it to a shipped allowlist, or send it as available.

**Future JEV action choice (not implemented).** `decision.php` only picks the responding NPC
and stays free of actions ([AGENTS.md](../../AGENTS.md), Decisions); it is not extended for
this. A later contract may send JEV (`typesafe/jev-1.13`) the ids of the capabilities the
game offers right now plus "none", accept only one of those ids, and then validate and
execute it as in step 4. Use it only where a choice is ambiguous. It needs its own endpoint
or protocol addition, designed in the server, the client and PROTOCOL.md together; nothing
in this template provides it today.

**Check now:** with the server's `allowed_actions` `[]`, `--say "follow me"` lists
`follow_player` under rejected actions (the mock ignores the prompt). With a real provider
authorized, the dashboard **Send test** with an empty list should not claim any action.
**Engine only:** each observation's source and freshness, each handler's effect and the
observed result.

## Game events

**Seam.** `sendEvent()` with the four protocol types only
([PROTOCOL, POST event.php](../../PROTOCOL.md#post-eventphp)). The game decides when to send. The
server never triggers anything and has no queue.

- **Log only** (`respond: false`) makes no model call and does not move the NPC's
  generation. It needs only a rate bound.
- **Respond** (`respond: true`) is a normal turn and moves the generation, so it makes any
  pending turn for that NPC in that session stale. Never send a responding event while any
  turn is pending (the glue tracks one, so an event for another NPC would replace it), or
  while a cancel for that NPC in that session is still out. Drop the event and log that it
  was dropped. The console's
  `/react` does replace a pending turn, but only because the player typed it.
- A responding event that is sent becomes the pending turn. It is applied and cancelled
  exactly like a typed line.
- Bound automatic events: for example, a minimum interval per type and dropping events
  while workers are busy. These are port recommendations: record your values under "Port
  decisions" in ENGINE_PACK.md.
- A new event type is a protocol change for the server and the client together, so it is
  out of scope.

**Check now:** `--event`, `--react`, `/event` and `/react` (basic sending only).
**Engine only:** automatic triggers, rate bounds, drop-when-busy, drop-when-pending and
drop-while-cancelling.
The console sends no automatic events.

## Sessions, saves and branches

**Seam.** `TurnRuntime::setSession()`, called by `/session <id>` in `client/src/main.cpp`. A
client's settings are fixed when it is created, so switching session drops anything pending
and creates a new client with the new `session_id`.
Requests already out keep the client they started with.

- Set `session_id` per save at runtime, derived from a stable save identity and valid
  under the ID rule (1-64 characters of `A-Z a-z 0-9 _ . : -`). The shipped
  `demo-save-1` is only a demo default.
- On save load, new game or return to menu, do what `/session` does: drop the pending
  reply and cancel it with the **old** client (the old session), then switch. The cancel
  caveat from the lifecycle recipe applies.
- Branching saves have a trade-off and no free option:
  - A shared `session_id`: branches share and interleave one NPC history.
  - A new `session_id`: the branch starts with no history.
  - Either way, bios and facts are shared by every session.
- Protocol 1 has no checkpoint endpoint and no way to copy a session. Checkpoints are saved
  and restored by hand, one session at a time
  ([START_HERE, Checkpoints versus backups](../../START_HERE.md#7-checkpoints-versus-backups)).
  A game-driven save or restore would be a protocol change, so it is out of scope.

**Check now:** interactive `/session other-save` while a reply is pending; the checkpoint
commands in [README](../../client/README.md#npc-bios-knowledge-and-checkpoints).
**Engine only:** save, load and new-game hooks, and the save-to-session mapping.

## Voice (optional)

**Seam.** After `tick()` has shown the reply and run its actions, `speak()` runs on a worker
and writes a WAV. A later `tick()` calls `playVoice()` on the game thread only if that turn
was not cancelled or replaced, the session is unchanged and `isSameNpc()` still holds. The console's `playVoice()` only prints where
the WAV was saved. `listen()` turns a WAV into text before the turn.

- Only with voice authorized and services set up ([CONNECTORS, Voice](../../CONNECTORS.md#voice)).
  Text always comes first, and any voice failure keeps the subtitle or lets the player
  type.
- If the engine cannot play a WAV on an NPC, leave `playVoice()` as a message or log line
  and report voice output as Not tested.
- Report two separate results: **WAV saved** (the client wrote a valid file) and
  **audible on the NPC** (heard in game). Microphone capture to WAV is engine or OS work.

**Check now:** none without running voice services. With them authorized, the
[README voice examples](../../client/README.md#voice-examples) (evidence level 3).
**Engine only:** playback on the NPC and microphone capture.

## Diagnostics

**Seam.** The server's Logs page filtered by request ID
([START_HERE, Troubleshooting by request ID](../../START_HERE.md#troubleshooting-by-request-id)).
The console prints each request ID on its `Trace:`, `Event` or `Decision:` line, but keeps no
log; the plugin log is yours to add.

- Recommended minimum per request in the plugin log: request ID, endpoint, HTTP status or
  error code, and outcome (applied, ignored as stale, dropped because the NPC was gone,
  cancelled, failed). Timings are optional.
- A stale reply or `409 stale` is dropped without being applied, and its outcome is logged.
- Never log the token or audio. Do not log player text by default.
- Provider timing is optional evidence level 3: with authorization, time one real-mode
  turn and match server error-log lines by time.

**Check now:** only the [PROTOCOL curl example](../../PROTOCOL.md#try-it-with-curl) with an ID
you choose, then the Logs filter for that ID.
**Engine only:** the plugin log itself.

## Packaging

Two different packages. Never mix them up.

- **Licence obligations, both packages.** The licence (`LICENSE`, GPL-3.0-only), the
  source-offer duty for binaries and every notice to keep (listed in
  [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) and
  [client/THIRD_PARTY_NOTICES.md](../../client/THIRD_PARTY_NOTICES.md), with their texts
  under `LICENSES/`, `client/LICENSES/`, `ui/HERIKA-LICENSE` and `client/third_party/`) are set out once in
  [START_HERE, Packaging](../../START_HERE.md#packaging-licensing-and-private-data).
  Follow that section for every package; this list does not replace it.
- **Template or demo share.** Ship the renamed console program and `config.default.json`
  with the licence and notices above, labelled as a console simulation.
- **Engine port.** Ship only the plugin artifacts, at the locations in ENGINE_PACK.md's
  "Plugin file layout" row, with the licence and notices above and your own notice added.
  Put the default config at the recorded config location, and never ship a config with a
  token. Do not ship the console program, unless it is deliberately included and labelled
  as a diagnostic tool.
- **Server.** Package it as START_HERE describes. For a launcher install, change the
  manifest `id` before publishing; it cannot change after install. That install path needs
  your own public HTTPS repository; test an install from it before relying on it
  ([START_HERE, Launcher install](../../START_HERE.md#launcher-install-and-multiple-copies)).
- Packaging stays Not tested until the package is installed into a clean game install.

**Check now:** none (engine only). `client\scripts\build.ps1` shows only that the shared code
compiles.
**Engine only:** the package installs, loads and finds its config in a clean game install.
