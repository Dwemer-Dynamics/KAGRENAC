# Elden Ring native client reference (me3 DLL)

A reusable native client for one Elden Ring companion. Press **F8** in the game, type a line, get
the server's reply in a small box and, optionally, its voice. With the control package's mailbox
verified, a line can also ask the game to follow or hold. Attack is implemented and guarded
for one configured hostile, built only with the control config's `attack_enabled` true, and
**unavailable** until verified in the game
([acceptance](../../../docs/engine-packs/elden-ring.md#future-acceptance-for-hold-follow-and-attack)).
It uses the shared `client/src/ai_client` and `config` unchanged. It is a reference for this
port, not a universal or ready game SDK: one exact game build, one control package, one configured hostile.

The box is a **mod-owned Win32 window over the game**, not native game UI. Apart from the game
link below, the DLL reads no game memory, calls no game code, installs no hook and uses no
address from a symbol table.

## Status and evidence

- **Prior source (same logic, earlier names):** built `/W4 /WX`; 16 bridge fixture scenarios and
  65 loopback wire and provider checks passed outside the game. The user reported that it
  generally worked in the game (box, reply text, voice). Individual AI-requested actions were
  **not** explicitly qualified in the game.
- **This renamed DLL** (`kagrenac_elden_ring.dll`): built and tested only outside the game
  (2026-10-19): clean `/W4 /WX` build; exports only `kagrenac_init`; Dependent Load Flag `0x800`;
  the same 16 bridge fixtures and a loopback mock harness (including the identity checks and the
  shipping DLL refusing a host that is not `eldenring.exe`) passed. **Not loaded by me3 or the
  game yet.**
- **Live-candidate selection and build 2.7.2.0** (2026-10-20): the bridge now live-checks every
  beacon candidate and links only to exactly one live one, and takes the accepted game build
  from `../game-build.json`. Built `/W4 /WX` (shipping and test-host DLLs, clean); the bridge
  fixtures were not rerun on this source. **Not run in the game.**
- Unproven: that exactly one beacon candidate in game memory is live, how the game stores the flag
  bits, behaviour in exclusive fullscreen, and whether typing in the box reaches game controls.

## How it works

| Part | What the DLL does |
|---|---|
| Load | me3 calls `kagrenac_init` (`extern "C" bool()`) on its loader thread. It checks the host is `eldenring.exe`, pins the DLL, reads the config once, starts four detached threads and returns `true`. No exception crosses into me3. `DllMain` only records the module handle |
| UI thread | Message-only window plus the box, owned by the game window. F8 is polled every 50 ms, edge-triggered, only while a window of this process is in front (no global hotkey). Enter sends; **Esc** or the close button cancels the turn, drops any unsent order, asks for a safe hold and hides; **F8 only hides** (a follow order keeps going) |
| Network worker | One turn at a time: `turn.php`, show the **text first**, then `speak.php` (WAV checked: RIFF/WAVE, at most 20 MB, read into memory, file deleted). No confirmed answer (WinHTTP error, timeout, late reply) or an internal error requests a cancel under the same lock that frees the worker. Never retried |
| Cancel thread | Its own `AiClient`, `cancel.php` only; requests while one runs coalesce |
| Supersede | A new line, Esc or the 45 s line watchdog raises the generation; anything older is never shown or played. One replace-only slot waits until the old request has returned **and** its cancel finished |
| Bounds | `timeout_seconds` capped at 20 per WinHTTP phase; 45 s watchdog per line |
| Lifetime | Process lifetime only: pinned (`GET_MODULE_HANDLE_EX_FLAG_PIN`), no finalizer export (me3 has no finalizer call site at the cited pin), heap context never destroyed, nothing on process detach. A C++ exception never leaves a thread or window procedure |
| Log | `natives/kagrenac_elden_ring.log`, rewritten per launch; first line has the pid and local time. Ids, generations, timings, HTTP or WinHTTP codes only; never typed text, replies, names, the token, keys or the server URL |

## Game link and orders

The control package's mailbox event publishes state in the 96 event flags from the control
config's `bridge_flag_base` (the example: 1042369800-1042369895; layout:
`../control/kagrenac_control.js.in`). The bridge thread:

- runs only when `eldenring.exe` matches [`../game-build.json`](../game-build.json), which the
  build compiles in: today file 2.7.2.0, SHA-256
  `f9118fea2cfd8fa3901e8060bfadb1552cb2471771ded8a5b662c4e298ffb328`, PE timestamp
  `0x6aabf7e7`, SizeOfImage `0x05dfd600` (an in-game candidate, not a qualified build); any
  other build, 2.7.1.0 included, leaves the link off (`bridge: off, the game executable is not
  the recorded build`);
- scans only committed private read-write memory of its own process (bounded at 16 GB or 120 s
  per pass, retried with backoff up to 60 s) and keeps at most 16 distinct beacon candidates
  (address and bit order); more, a cap, or memory still of the scanned kind that cannot be read
  ends the pass with none trusted;
- checks **all** candidates together, read-only, within one 8 s budget: live means two
  consecutive heartbeat steps with shape and epoch unchanged and the sensors not mid-write; a
  candidate is ruled out only by a failed shape, epoch or step or no step for 4 s. It links only
  when **exactly one** is live (0, 2 or more, an unreadable candidate or one still undecided at
  8 s: no link, nothing written). The live one stays under the same checks until the last poll,
  and its real last heartbeat carries into the link, before the **arming challenge**. The log
  line gives raw candidates, live count and the reason, never addresses;
- reads with `ReadProcessMemory` and writes only its **one command byte** with
  `WriteProcessMemory` (a freed or protected page is a failed call, not a fault): written only
  while zero and not busy (busy barrier), with a nonce the answer must echo;
- ends the session on a load epoch change, companion loss, stopped heartbeat, stuck busy or
  mismatched answer; a queued order is re-checked against the current line generation and link
  session just before it is written.

Orders are requests: the box shows whether the game event accepted or refused one; acceptance
is not confirmed movement. An order with no answer in time is cancelled if still queued;
once written it may still run, so the box says only "outcome unconfirmed" and a safe hold is
requested if the link allows. Exact commands `/follow`, `/hold` and the guarded `/attack` (not
available yet, see above) skip the model. Any
other line goes to the model with only the actions offered right now; at most one order per
reply is sent, several conflicting ones none.

Observations sent as context: location (the player in the companion's map tile, the control
config's `companion_msb`, else `unavailable`), the companion's state, and the one configured
hostile (`hostile_entity`, by entity id only), loaded and alive and whether it is within
`bridge_hostile_near_m` of the player. Attack follows the control config's `attack_enabled`,
compiled into the DLL: with `false` (the example) `attack_hostile` is never offered and an attack
order (`/attack` or a model request) is refused before it is queued or written, even if
`allowed_actions` lists it. With `true` it is offered only while that hostile is loaded, alive and
near, and stays a guarded candidate: keep it out of both allowlists until it passes its in-game
acceptance. Inventory, combat, other actors and line of sight are `unavailable`.

## Config

A private `config.json`, never in the repository or a web root, read only from the runtime
folder (parent of `natives/`); there is no fallback location. Create it with `pair`, which
writes your server's real route and never overwrites an existing file:
`powershell -ExecutionPolicy Bypass -File scripts\project.ps1 pair -WslDistro <name> -OutFile <runtime>\config.json -AllowedActions follow_player,hold_position -NpcId <id> -NpcName "<name>" [-VoiceEnabled]`
([getting-started](../../../docs/getting-started.md#deploy-and-pair)), or start
from [config.example.json](config.example.json). `-NpcId`, `-NpcName` and `-VoiceEnabled`
shape only the new file, so nothing is edited after pairing. Same loader and fields as the
shared client, plus two optional native-only fields read once at startup:

| Field | Rule |
|---|---|
| `server_url`, `token`, `session_id`, `voice_enabled` | As the shared client. No file, no token or a bad `session_id`: "Not connected", nothing sent |
| `timeout_seconds` | Capped at 20 |
| `allowed_actions` | Only `follow_player`, `hold_position`, `attack_hostile`. **Absent or `[]`: no actions** (the server's own allowlist also applies). Do not add `attack_hostile` here or on the server until attack passes its [acceptance](../../../docs/engine-packs/elden-ring.md#future-acceptance-for-hold-follow-and-attack) |
| `npc_id` | Default `companion`. Protocol id rule (1-64 of `A-Z a-z 0-9 _ . : -`) |
| `npc_name` | Default `Companion`. 1-64 characters, no control characters, no space at either end |

A bad `npc_id` or `npc_name` leaves the client "Not connected" and names the field, never its
value. The identity is used in every request (`npc.id`, `npc.name`, `npc_id`) and in the box.
The DLL never reads the server's API keys.

## Build

```powershell
powershell -ExecutionPolicy Bypass -File ports\elden-ring\client\build.ps1 -ControlConfig <control config> [-BuildDir <folder>]
```

A mod normally builds it through `..\mod.ps1 build`, which uses this script with the same
`-ControlConfig` as the package. CMake reads the accepted game build from `../game-build.json`
and the companion map tile, hostile entity, near radius, bridge flag base and `attack_enabled`
from the control config (with the package build's ranges), and reconfigures when either changes;
the source does not compile without them. It writes what it compiled, with the config's SHA-256,
to `<build folder>\kagrenac_er_control.json`; the DLL logs the same hash at startup.

Visual Studio 2022 C++ with the Windows SDK, x64, C++17, `/W4 /WX`, static CRT. Links only
system `winhttp winmm user32 gdi32 bcrypt` with `/DEPENDENTLOADFLAG:0x800`, so those imports
load from System32, not a same-named DLL in the game folder. Default output:
`%LOCALAPPDATA%\DwemerDynamics\Kagrenac\elden-ring\client\Release`. A build folder overlapping
the repository, a drive root, a UNC or device path, or a path through a junction is refused.
**Build only:** it copies nothing into a runtime, game or me3 folder.

The same build makes `kagrenac_elden_ring_testhost.dll` for a temporary harness outside the
repository: it runs only in a process named `kagrenac_er_harness.exe`, skips the build gate,
has an 8 s line budget and one extra export, `kagrenac_test_show`. **Never put it in a profile.**

## Runtime layout and offline launch

```
<runtime>\                         outside the repository and any web root
  <id>.me3                         offline profile, own save <id>.sl2
  config.json                      private, created by pair
  natives\kagrenac_elden_ring.dll  the log appears here
  package\                         the built control package
  runtime.json                     what assemble wrote, with SHA-256
```

`ports\elden-ring\mod.ps1 assemble` writes this folder from one verified build
([Build a mod](../README.md#build-a-mod-from-this-reference)); it never writes `config.json`,
and the same build again changes nothing. By hand instead: copy only `kagrenac_elden_ring.dll`
into `natives\`, start the profile from `kagrenac_elden_ring.me3.example`, and **never overwrite
an existing `config.json`**. The profile uses `optional = false`, so a missing or failing DLL
stops the launch rather than starting the game without it.

Back up the save folder first, then (you, not this repository; assemble prints these with the
real paths):

```powershell
<me3>\bin\me3.exe profile show --file <runtime>\<id>.me3
<me3>\bin\me3.exe launch --game eldenring --exe "<Elden Ring>\Game\eldenring.exe" `
  -p <runtime>\<id>.me3 --online false --savefile <id>.sl2
```

When `<id>.sl2` does not exist yet, me3 creates it on first launch as a copy of
your existing save, so a fresh profile does not mean a new character. The save backup is
mandatory ([engine pack](../../../docs/engine-packs/elden-ring.md#offline-manual-gates-not-yet-run-need-the-user-to-launch)). Offline only, isolated save, no `start_online`, no
`disable_arxan`. Windowed or borderless is recommended. First checks: the log's first line has the running game's pid and this launch's
time, then `init: threads started`; the link line in the box reports ready before any order.
Windows ties an owned window's input to its owner's thread, so a stalled game thread (a loading
screen) may also stall typing; the game may also bind F8 (not checked).
