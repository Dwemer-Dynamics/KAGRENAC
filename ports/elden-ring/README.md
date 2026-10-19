# Elden Ring port: NOT IMPLEMENTED

There is no Elden Ring port in this repository. Nothing here loads into the game, and no
Elden Ring feature (dialogue, subtitles, follow or any other action, voice, microphone or
playback) is supported or claimed. No engine SDK, mod loader, game file or third-party
library is copied here, and none is installed by this repository. No in-game test has run.

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

Status words are those in the engine pack: Unknown until cited; "Verified (in engine)" only
after testing in the game.

| Capability | Stage | Evidence | Status |
|---|---|---|---|
| Exact game build and mod loader version | 1 | | Unknown |
| Offline mod launch with an isolated save | 1 | | Unknown |
| Native DLL load through the loader, and its architecture | 2 | | Unknown |
| Game-thread tick or callback | 2 | | Unknown |
| Worker threads or HTTP allowed from the plugin | 2 | | Unknown |
| Player instance, and NPC instance with a stable identity | 2 | | Unknown |
| Hostile target selected locally | 2 | | Unknown |
| NPC hold position on command | 2 | | Unknown |
| NPC follows the player on command | 2 | | Unknown |
| NPC attacks the local target on command | 2 | | Unknown |
| Save and load hooks with a stable save identity | 2 | | Unknown |
| Player text input and subtitle display | 3 | | Unknown |
| WAV playback on an NPC; microphone capture | 3 | | Unknown |

Until a row is verified in the game, the only working client is the console simulation in
[client/](../../client/README.md).
