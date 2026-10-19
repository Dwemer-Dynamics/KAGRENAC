# Port recipes

One bounded recipe per port stage in [agent-playbook.md](../agent-playbook.md). Each maps to a
seam that already exists in this template and links to the canonical rule rather than
restating it. None of them adds a runtime feature, endpoint or protocol change.

Each recipe ends with two lines:

- **Check now**: what you can run today with the console client and a mock server. It may
  be "none (engine only)".
- **Engine only**: what can be shown only in the game. Record it in
  [ENGINE_PACK.md](../engine-packs/ENGINE_PACK.md) with the statuses defined there.

The rules for threads, stale replies and actions are in [AGENTS.md](../../AGENTS.md), [client/AGENTS.md](../../client/AGENTS.md) and
[START_HERE, Cancellation and stale replies](../../START_HERE.md#10-cancellation-and-stale-replies).
Every recipe assumes them.

## Plugin lifecycle and shutdown

**Seam.** `runInteractive()` in `client/src/main.cpp` is the model for plugin glue: one mailbox,
the pending `request_id`, its captured `GameContext` and client, two bounded worker pools,
and a loop body that drains the mailbox on the game thread. The console's `/npc`,
`/unload` and `/load` call `ConsoleGame` directly and are not part of `GameAdapter`.

- On load, read the config and create the client and mailbox in the plugin entry point.
- On each main-thread tick, do what one pass of the console loop does: reap finished
  workers, drain the mailbox, drop the pending reply if `isSameNpc()` fails, then apply
  results.
- Lifecycle lives in the plugin glue. `GameAdapter` gains no lifecycle methods.
- **Required on unload or quit:** clear the pending `request_id`, stop applying anything,
  and make sure no worker can call into the module after it unloads. The console waits
  for every worker before it exits (bounded per call by `timeout_seconds`, see
  [README, Limits](../../client/README.md#limits)). Whether a plugin may wait like that during unload,
  or must stop its threads another way, is an engine fact for ENGINE_PACK.md.
- **Optional:** a server cancel on quit, as `/quit` sends, only if ENGINE_PACK.md records
  that it can finish without blocking shutdown or outliving the module.
- **If no cancel is sent, or it fails** (cancels are best effort and never retried), the
  server may still finish the turn and save it to that session's history as `complete`.
  The player never saw that reply, but the NPC may refer to it later.

**Check now:** interactive `/unload`, `/load` and `/quit` with `mock_delay_seconds` 2 or
more (the matching rows in [README, Smoke checks](../../client/README.md#smoke-checks)).
**Engine only:** real load, unload and quit hooks; no callback after module unload; no
hang on exit.

## Typed dialogue

**Seam.** The console's plain-line path: `readContext()` on the game thread, a fresh
`newRequestId()`, `sendTurn()` on a worker, the result back through the mailbox, then
`handleResult()`, which checks the request ID and `isSameNpc()` before `applyResult()`.

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

**Seam.** One explicit branch per action in `applyResult()`, one `GameAdapter` method and
both allowlists. Follow [WAVE_ACTION.md](../../WAVE_ACTION.md) for
any new action. Do not copy its steps here.

- Implement `followPlayer()` with the engine's own follow behaviour. The target is always
  the NPC the request was sent to.
- Add other actions only if authorized.

**Check now:** `--say "follow me"`; `--say "dance"` (the server rejects it); client
`"allowed_actions": []` (the client rejects `follow_player`). See
[START_HERE, Actions](../../START_HERE.md#9-actions-and-the-worked-extension).
**Engine only:** the NPC really follows.

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

**Seam.** `/session <id>` in `client/src/main.cpp`. A client's settings are fixed when it is
created, so switching session means creating a new client with the new `session_id`.
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

**Seam.** `speak()` runs on the worker after the reply and writes a WAV. `applyResult()`
then calls `playVoice()` on the game thread. The console's `playVoice()` only prints where
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
