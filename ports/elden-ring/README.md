# Elden Ring port: reusable reference, not verified in game

A reference for building an Elden Ring AI companion with KAGRENAC. Reuse and adapt it rather
than starting over; it is tied to one game build, one companion and one fixed hostile.

| Folder | What | Status |
|---|---|---|
| [client/](client/README.md) | Native me3 DLL: F8 text box, server turn, reply text, optional PocketTTS voice, and orders to the control package through a guarded event-flag mailbox | Built `/W4 /WX` and bridge fixtures passed outside the game; not loaded by me3 or the game |
| [control/](control/README.md) | Event-script and AI-logic package built from the user's own game files: one companion copy that holds and follows | Full package build verified; not verified in game |
| `probe/` | Native diagnostic DLL and offline build inspector | Inspector verified offline; DLL not loaded by me3; it controls no actor |
| [PLAN.md](PLAN.md) | The integration plan for a companion built on this reference; `scripts\project.ps1 new -Engine elden-ring` copies it into the new project | Each row cited; nothing verified in game |
| `mod.ps1` | The maintained route for a mod: `doctor`, `build`, `assemble` ([below](#build-a-mod-from-this-reference)) | Doctor run on the installed game and tools; assemble exercised on a test build; full build not yet run through it |
| `game-build.json` | The one accepted `eldenring.exe` (2.7.2.0), read by `mod.ps1`, the package build and the client's game link | Identity read from the installed file, 2026-10-20; not qualified in game |

**Follow and hold** are the reference actions. Each is a request that the game event may
accept or refuse; neither is verified in game yet. **Attack is unavailable:** a new mod's
control config leaves it out of the package (`attack_enabled` false). The guarded attack
path for one fixed hostile can still be built, but no target or handler is verified in the
game, so do not put `attack_hostile` in either allowlist or describe it as working until its
own in-game check passes
([acceptance](../../docs/engine-packs/elden-ring.md#future-acceptance-for-hold-follow-and-attack)).

## Build a mod from this reference

From your mod's own copy (`scripts\project.ps1 new -Engine elden-ring`), with Windows
PowerShell 5.1. Large extraction and work folders go under `-Root`; pass one on a disk with
room (default `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>`).

```powershell
$er = 'ports\elden-ring\mod.ps1'
powershell -ExecutionPolicy Bypass -File $er doctor   -GameDir "<ELDEN RING>\Game" -Tools <tools> -Root <root>
powershell -ExecutionPolicy Bypass -File $er build    -GameDir "<ELDEN RING>\Game" -Tools <tools> -Root <root>
powershell -ExecutionPolicy Bypass -File $er assemble -GameDir "<ELDEN RING>\Game" -Tools <tools> -Root <root>
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 pair -WslDistro <name> -WslServerPath /var/www/html/custom-mods/<id> `
  -OutFile <root>\runtime\config.json -AllowedActions follow_player,hold_position -NpcId <id> -NpcName "<name>" [-VoiceEnabled]
```

| Step | Does | Never |
|---|---|---|
| `doctor` | Reads `eldenring.exe` (version, size, PE timestamp, SizeOfImage, SHA-256) against `game-build.json`, the game inputs, the tools (control README, Tools), .NET, Visual Studio, me3, and the build and runtime folders; one readiness line each | Writes anything; counts as an in-game result |
| `build` | Refuses any other game build; `client\build.ps1` into `<root>\elden-ring\client`, `control\build-package.ps1` (with `-ControlConfig`, default the example: follow and hold, attack left out) into a new `<root>\elden-ring\builds\<time>`, with the DLL and every file's SHA-256 in its `build.json` | Installs, downloads, or writes to the game, me3 or a save |
| `assemble` | Copies one verified build (default the newest) into `<root>\runtime`: `natives\`, `package\` and an offline profile `<id>.me3` with its own save `<id>.sl2`; prints the pair, `profile show` and launch commands. The same build again changes nothing; another build needs `-Replace`, which moves the old assembled files (only if unchanged) into `runtime\superseded\<time>` | Writes or reads `config.json`, launches, copies or deletes saves, uses `start_online` or `disable_arxan` |
| `pair` | Creates the private `config.json` in the runtime with the mod's own `npc_id`, `npc_name`, voice flag and client allowlist | Overwrites an existing file (kept byte for byte); enables actions on the server |

`pair -AllowedActions` sets only the client's list. Also enable the same actions in the
server's `allowed_actions`: `follow_player` on the dashboard **Settings** page, and
`hold_position` by adding it to `allowed_actions` in the server's private `config/config.php`
([getting-started, Deploy and pair](../../docs/getting-started.md#deploy-and-pair)). Leave
`config.json` in the runtime; the check is the launch below and the engine pack's
acceptance, not `KagrenacClient.exe`.

`-Root` must be a local folder outside the repository, every Git checkout and web root, the
game's install folder and the tools; its `elden-ring` and `runtime` folders must be new or
already this mod's. Before the first launch, back up the whole save folder
`%APPDATA%\EldenRing` yourself, then run the printed `me3 launch ... --online false
--savefile <id>.sl2` command with the game closed. Each PROJECT.md row (6a build, 6b runtime
and pairing, 6c prototype, 6d each action) needs its own evidence.

Evidence is kept by kind. An earlier prototype of the client was reported by the user as
generally working in game (box, reply text, voice); that is user-reported and is not proof
of any individual action. The renamed client, the current control package and each action
still need their own in-game check. Engine facts and citations are in
[docs/engine-packs/elden-ring.md](../../docs/engine-packs/elden-ring.md); the port's
history is in [control/EVIDENCE.md](control/EVIDENCE.md).

Testing is offline only, with an isolated me3 `savefile` and a save backup first (me3
creates the isolated save as a copy of an existing one). No online play, no
`disable_arxan`, and no code that bypasses or hides from anti-cheat. No engine SDK, mod
loader, game file or third-party library is copied into or installed by this repository.

## Probe build

Outside the repository; MSVC x64 with the Visual Studio generator, `/W4 /WX`:

```powershell
cmake -S ports/elden-ring/probe -B D:/build/kagrenac-elden-probe -G "Visual Studio 17 2022" -A x64
cmake --build D:/build/kagrenac-elden-probe --config Release
D:/build/kagrenac-elden-probe/Release/kagrenac_er_inspect.exe "<game>/Game/eldenring.exe"
```

The inspector exits 0 for a qualified build, 3 for an identified but unqualified build
(every build today), 1 when the file cannot be identified and 2 on wrong usage. The probe
DLL logs hold, follow and attack as unsupported: it integrates no game backend.

## Stages

1. **Inventory (read-only).** Record the exact installed game build, the mod loader and
   its version, and the SDK or reverse-engineering resources available, each with its
   source. Install nothing and change no game files.
2. **Native capability probe (only under the user's implementation authorization).** A
   bounded native plugin that proves, in order: the DLL loads through the qualified loader;
   a game-thread callback runs; it can reach the player and one NPC instance; it selects a
   hostile target locally; and the NPC can hold, follow and attack that target on command.
   This comes before any full voice or dialogue UI. Unknown facts are questions for the
   probe to answer; never fake or guess an API. The probe does not need every row below to
   be verified first.
3. **Optional voice, input and subtitles**, in this probe plan only after the action
   control proof. They do not gate the probe. (The [native client](client/README.md)
   already offers optional voice; that does not change this order for the probe.)

## Action rules

- The hostile target is captured locally by the game-side code. It is never a pointer or
  raw id chosen by the model, and an action's `args.target_id` stays the speaking NPC
  ([PROTOCOL.md](../../PROTOCOL.md)).
- The server knows `follow_player`, `hold_position` and `attack_hostile`
  ([PROTOCOL.md](../../PROTOCOL.md)); each is offered only when it is in both allowlists.
  Here only follow and hold are reference actions, and none is verified in game.

## Evidence

Status words are those in the engine pack, plus "Blocked" (no cited mechanism for this build)
and "Not qualified"; Unknown until cited; "Verified (in engine)" only
after testing in the game.

| Capability | Stage | Evidence | Status |
|---|---|---|---|
| Exact game build and mod loader version | 1 | File 2.7.2.0 (Steam build 25827938; 2.7.1.0 before the 2026-10-20 update), file SHA-256 and PE headers in `game-build.json`; me3 v0.13.0 (989b522); title patch Unknown | Identified, not qualified |
| Offline mod launch with an isolated save | 1 | me3 `savefile` (a copy of an existing save; back up first), offline default (cited); `probe/kagrenac_er_probe.me3.example` | Not tested (no game launch) |
| Native DLL load through the loader, and its architecture | 2 | x64 DLL built, `kagrenac_probe_init` exported; called only from a separate test process | Built; not loaded by me3 |
| Game-thread tick or callback | 2 | me3 initializer runs on a spawned loader thread; fromsoftware-rs task interfaces cited for 2.7.1.0, not integrated | Not qualified |
| Worker threads or HTTP allowed from the plugin | 2 | Not used by the probe | Unknown |
| Player instance, and NPC instance with a stable identity | 2 | fromsoftware-rs actor interfaces cited (handles have no generation field); not integrated | Not qualified |
| Hostile target selected locally | 2 | fromsoftware-rs team data cited, no hostility helper; not integrated | Not qualified |
| NPC hold position on command | 2 | No NPC command mechanism found (fromsoftware-rs AI fields are opaque); logged `unsupported`; future acceptance in the engine pack | Blocked |
| NPC follows the player on command | 2 | Same | Blocked |
| NPC attacks the local target on command | 2 | Same | Blocked |
| Save and load hooks with a stable save identity | 2 | | Unknown |
| Player text input and subtitle display | 3 | | Unknown |
| WAV playback on an NPC; microphone capture | 3 | | Unknown |

This table covers the native probe route. The control package and native client keep
their own status in [control/](control/README.md) and [client/](client/README.md).
