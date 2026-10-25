# Engine pack (generic evidence template)

Copy this file to `docs/engine-packs/<your-engine>.md` in your project and fill it in during
recon (stage 1 of [agent-playbook.md](../agent-playbook.md)). It records evidence. It is not a
workflow or a second checklist. The acceptance checklist is
[START_HERE, Porting to a real engine](../../START_HERE.md#porting-to-a-real-engine),
and the "Checklist" column below names its items by keyword. Rows marked "recon" are facts
the port needs that the checklist does not list on its own.

The template names no engine and claims support for none. Keep three things apart:

- **SDK facts**: what the engine's SDK or docs say, with a citation. Nothing is built yet.
- **Implemented**: code exists in your plugin. It says nothing about whether it works.
- **Verified (in engine)**: you ran it in the game and saw the result.

Write "Unknown" when the SDK does not say. Never fill a cell from memory or by analogy with
another engine.

## Status words

| Applies to | Allowed statuses |
|---|---|
| Anything behind `GameAdapter`, plugin glue, packaging | Not started; Implemented, untested; Verified (in engine); Not tested (say why) |
| Server code, shared client code (`ai_client`, `config`) | The above, plus Verified (console/mock) for checks you actually ran |

## SDK facts

| Item | Checklist | SDK fact | Citation (file, page or symbol) |
|---|---|---|---|
| Engine and version | recon | | |
| Plugin architecture: native, managed or script | recon | | |
| Plugin language, build tools, target architecture | correct architecture | | |
| Plugin file layout: artifact names and install locations | plugin package | | |
| Load, unload and quit hooks; can work run during unload? | plugin lifecycle | | |
| Main-thread tick or callback | main-thread tick | | |
| Worker threads or async HTTP; which HTTP facility | worker threads | | |
| Can a worker outlive the module? How to stop or join it | plugin lifecycle | | |
| Player name | stable NPC ID, names | | |
| Stable NPC ID (survives save and load) | stable NPC ID, names | | |
| NPC display name | stable NPC ID, names | | |
| NPC instance marker for `isSameNpc()` | `isSameNpc()` | | |
| Context sources (location, time of day, ...) | context entries | | |
| Live observation sources: what can be read, on which thread, how fresh | context entries | | |
| Text input from the player: native text field, open key, input mode that keeps keys from game controls, IME/paste | recon (dialogue) | | |
| Focus loss, pause, loading and death notifications (to release input capture) | recon (dialogue) | | |
| Subtitle or message display | subtitle display | | |
| NPC follow behaviour | one handler per action | | |
| Bridge from plugin code to the engine's action or script mechanism | one handler per action | | |
| Save, load and new-game hooks; a stable save identity | `session_id` per save; cancel on load | | |
| Hooks for the four event types, if any | events | | |
| Private config location (server URL, token) | private `config.json` | | |
| Plugin log facility and file location | client log | | |
| Optional: play a WAV on the NPC | optional voice | | |
| Optional, only if speech input was asked for: capture microphone to WAV (push-to-talk) | optional voice | | |

### Transport choice

The shared client code (`ai_client`, `config`) is blocking C++17 built on the platform HTTP
API this template targets. It fits a native plugin only if the SDK allows that language,
that API and blocking calls on threads the plugin owns. A managed or script plugin
implements [PROTOCOL.md](../../PROTOCOL.md) with its own HTTP facility and keeps the same rules
(request ID, stale check, `isSameNpc()` recheck, cancel in the sending session, allowlist,
no retries, main-thread apply).

| Choice | Reason, with citation |
|---|---|
| Reuse shared client code / reimplement the protocol | |

## Implementation and verification

| Item | Where (file, symbol) | Status | Evidence (what you ran, what you saw) |
|---|---|---|---|
| `GameAdapter` for the engine | | | |
| Plugin glue: load, tick drain, unload, quit | | | |
| In-game composer: "To: <recipient>", free typed text, Enter sends (`ChatInput`, `submitTurnTo`) | | | |
| Composer: game controls blocked while open; released on send, Esc, pause, loading, death, recipient unload, focus loss, quit; no leaked Enter/Esc | | | |
| Composer: recipient changed before Enter, so the send is refused and the draft kept | | | |
| Composer: refused send keeps the draft; a sent line that fails later returns to an empty draft for the same recipient and session (newer text kept); Enter resends; nothing resent automatically; no cooldown | | | |
| Typed dialogue to subtitle | | | |
| Observation snapshot: source, time, `unavailable` for unread values | | | |
| Readable self/player/location facts from qualified engine sources; no hidden/future knowledge | | | |
| Actual compiled adapter serialization and server round trip, including nested context | | | |
| Action capability gate: target, instance check, preconditions, observed result | | | |
| `follow_player` handler | | | |
| Other authorized actions | | | |
| Game events and their bounds | | | |
| `session_id` per save; cancel before switching | | | |
| NPC left while a reply was pending | | | |
| Server stopped: error shown, no crash or hang | | | |
| Optional voice: WAV saved | | | |
| Optional voice: audible on the NPC | | | |
| Optional speech input: mic open only while push-to-talk is held; transcript editable in the draft; nothing sent without Enter; WAV deleted; no transcript in logs | | | |
| Diagnostics log | | | |
| Package installed into a clean game install | | | |

## Shared code checks

Evidence levels 1 to 3 from START_HERE. Level 3 may stay "Not tested".

| Level | Command or step | Result | Date |
|---|---|---|---|
| 1. Server lint, migrations twice, smoke (mock) | | | |
| 2. Console smoke checks | | | |
| 3. Real provider calls, each on its own | | | |
| Build of the shared code for the target architecture | | | |

## Port decisions

Your choices, not template rules. Record each one with its reason.

| Decision | Choice and reason |
|---|---|
| Minimum interval per event type; events dropped when busy | |
| Session strategy for branching saves (shared or new `session_id`) | |
| Server cancel on quit or unload: sent, or skipped | |
| `session_id` derived from which save identity, and how | |
| Diagnostics log location and retention | |

## Open questions

| Question | Blocking which stage | Who decides |
|---|---|---|
| | | |
