# Elden Ring port: diagnostic foundation, not qualified in engine

There is no working Elden Ring port. `probe/` holds a native x64 diagnostic DLL (me3
native) and an offline build inspector. The DLL identifies the exact host file, compares
the loaded image's PE header identity with that file, fails closed because no build is
qualified, and logs hold, follow and attack as unsupported because it integrates no game
backend. The fromsoftware-rs SDK handles the installed file version and has cited
game-thread task and actor interfaces, but no NPC AI goal or target order was found in
the three sources examined ([evidence](../../docs/engine-packs/elden-ring.md)). The DLL
does not access actors, write game memory, hook or start threads. No dialogue, subtitles, voice or actions are supported. No
engine SDK, mod loader, game file or third-party library is copied here or installed by
this repository. The DLL has not been loaded by me3 or the game.

Build (outside the repository; MSVC x64 with the Visual Studio generator, `/W4 /WX`):

```powershell
cmake -S ports/elden-ring/probe -B D:/build/kagrenac-elden-probe -G "Visual Studio 17 2022" -A x64
cmake --build D:/build/kagrenac-elden-probe --config Release
D:/build/kagrenac-elden-probe/Release/kagrenac_er_inspect.exe "<game>/Game/eldenring.exe"
```

The inspector exits 0 for a qualified build, 3 for an identified but unqualified build
(every build today), 1 when the file cannot be identified and 2 on wrong usage.

This folder records the plan and the evidence for a port. Engine facts go in
`docs/engine-packs/elden-ring.md`, copied from
[ENGINE_PACK.md](../../docs/engine-packs/ENGINE_PACK.md); scope and authorization are in
[PROJECT.md](../../PROJECT.md).

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
3. **Optional voice, input and subtitles**, only after the action control proof. They do
   not gate the probe.

Testing is offline only: a documented mod launch procedure with an isolated save, on the
exact game build and loader version qualified in stage 1. No online play, and no code that
bypasses or hides from anti-cheat.

## Action rules

- The hostile target is captured locally by the game-side code. It is never a pointer or
  raw id chosen by the model, and an action's `args.target_id` stays the speaking NPC
  ([PROTOCOL.md](../../PROTOCOL.md)).
- `follow_player` exists today only as the console client's printed simulation. Hold and
  attack do not exist: each needs future allowlist, protocol and client handler work
  ([WAVE_ACTION.md](../../WAVE_ACTION.md)), which this repository does not include.

## Evidence

Status words are those in the engine pack, plus "Blocked" (no cited mechanism for this build)
and "Not qualified"; Unknown until cited; "Verified (in engine)" only
after testing in the game.

| Capability | Stage | Evidence | Status |
|---|---|---|---|
| Exact game build and mod loader version | 1 | File 2.7.1.0, file SHA-256 recorded; me3 v0.13.0 (989b522) chosen, not installed; title patch Unknown | Identified, not qualified |
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

Until a row is verified in the game, the only working client is the console simulation in
[client/](../../client/README.md).
