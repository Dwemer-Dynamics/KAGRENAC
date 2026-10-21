# Elden Ring companion control: project history

This was the repository's root `PROJECT.md` while it tracked the Elden Ring control probe.
It was copied here on 2026-10-19, when the root `PROJECT.md` went back to a blank template
brief. Only this header and the link paths changed; newer evidence goes at the end. This is
the one place for this history. The brief, acceptance and backlog below are a snapshot from
before the user's last report: the latest status is the last row of the Evidence table.

## User brief

| Question | Answer |
|---|---|
| Project name | KAGRENAC Elden Ring companion (capability probe stage) |
| Game or engine, and version | Elden Ring, installed `eldenring.exe` file 2.7.1.0 (Steam build 25080141) when this brief was written; file 2.7.2.0 (Steam build 25827938) since the 2026-10-20 update, as in `../game-build.json`; title patch not confirmed |
| Engine SDK or modding tools, and where they are | me3 v0.13.0 native loader (not installed); libER and fromsoftware-rs read only; none installed or in the repository ([evidence](../../../docs/engine-packs/elden-ring.md)) |
| What the player should be able to do | Eventually talk to a voiced companion; first, order a controlled companion to hold, follow the player and attack a locally selected hostile |
| Voice wanted? (no / text-to-speech / speech-to-text / both) | Wanted for the later demo; not in this stage |
| Actions beyond `follow_player` (none, or which) | hold, attack (wanted; written as an event script plus AI logic in `ports/elden-ring/control`; the friendly package is not tested in game; the native probe still logs them as unsupported; no protocol or client change yet) |
| Real LLM provider (mock only, or which) | Not in scope for this stage |
| Who will test in game, and on which architecture (x64 / x86) | The user, x64, offline with an isolated save, at The First Step grace (a dedicated copy of the Gatefront soldier is placed beside it); the user ran the earlier event package once (copy hostile before any press, ran away after Talk) and the friendly package once ("just stands there and does nothing" after Talk; the user confirmed they then walked roughly 10 m away, the prompt remained and it did not follow; cause not proven); the current package has not been run in game |

## Decisions

Record each choice with its date and reason. Leave a row blank until it is decided.

| Date | Decision | Reason |
|---|---|---|
| 2026-10-19 | Separate native x64 probe under `ports/elden-ring/probe`; server, protocol and console client unchanged | Qualify real action control before voice or LLM work |
| 2026-10-19 | me3 natives as the loader candidate; no libER dependency | me3 documents initializer and isolated save; libER has no character control and targets another build |
| 2026-10-19 | Fail closed: empty qualified-build table; hold, follow and attack logged as unsupported, no gameplay code or stub interface | No game backend integrated or qualified; no NPC command mechanism found in me3, libER or fromsoftware-rs |
| 2026-10-19 | Action route: event script (EMEDF 2004[2/11/16/17/19/20]) plus an AI goal reading `GetEventRequest`, in `ports/elden-ring/control`; action button as first input; native flag bridge deferred | Engine-documented route; the flag manager cannot be located without the SDK or a guessed address |
| 2026-10-19 | Test companion: a dedicated copy of Gatefront soldier 1042370200 (entity 1042360890, `c4311_9901`) placed 3.5 m from The First Step grace in a package copy of `m60_42_36_00.msb.dcx`; the original soldier, the control event's steps and the Man-Bat target are unchanged | The user asked for the soldier right next to The First Step grace. The dedicated copy (so the original stays as it is) was the agent's choice, and the user was told; the 3 to 4 m range and the 3.5 m spot were also chosen by the agent |
| 2026-10-19 | After the friendly-package report: the logic is also shipped as its own `script/431990_logic.luabnd.dcx` (laid out like the game's `010000_logic.luabnd.dcx`, `aicommon` entry kept); follow approaches with the game's `TARGET_SELF` fourth argument and, within 4 m, turns to face the player; event, regulation and MSB unchanged | Standing still right after Talk was the design (press within 4 m, logic waited), but the user confirmed it did not follow after they walked roughly 10 m away (cause not proven); 70 of 84 used logic ids have their own per-logic file and 431990 had none, so the logic may never have run (not proven); both game approaches to `TARGET_LOCALPLAYER` pass `TARGET_SELF` fourth; the turn is the one visible sign that the order reached the logic |
| 2026-10-19 | Friendly copy: the copy alone gets its own think row 43111190 (logic 431990) and a private NpcParam 43111190 (clone of 43111110, `teamType` 47) in its MSB part, plus `BackupEventAnimID` -1; the event sets no team or AI id and every release, loss or reload restarts to a friendly hold (order and AI target cleared); the logic drops `COMMON_EasySetup_Initial` and follows `TARGET_LOCALPLAYER` | The user saw the copy hostile before any press and running away after Talk, and asked for a peaceful hold at spawn and follow after the first Talk. The EMEDF event `Team Type` enum lists neither 47 nor 48, while the game's spirit-summon NpcParam rows use raw team 47; the original soldier and its shared rows stay unchanged |

## Acceptance

What "done" means for this project. Start from the evidence levels in
[START_HERE.md](../../../START_HERE.md#porting-to-a-real-engine) and add your own.

- [ ] Level 1: server lint, migrations twice and `scripts/smoke.sh` in mock mode
- [ ] Level 2: console client smoke checks ([client/README.md](../../../client/README.md#smoke-checks))
- [ ] Level 3: each real provider call you chose, tested on its own (or "Not in scope")
- [ ] Level 4: in game, talk, subtitle, follow, cancel, NPC unload and server stop without a
      crash or hang

Current stage (Elden Ring diagnostic foundation; actions through the event route, not tested in game):

- [x] Exact file identity of the installed `eldenring.exe`, fail closed on an empty
      qualified table (inspector, offline)
- [x] x64 DLL and inspector build with `/W4 /WX`; initializer tested from a separate
      process, not the game
- [ ] DLL loads through me3 offline with an isolated save, and its log is checked (needs
      the user to launch; the profile must be a copy of `kagrenac_er_probe.me3.example`,
      outside the repository, renamed to end in `.me3`)
- [x] Control package builds in full (`control/build-package.ps1`, exit 0, `package.json`
      read back); file build only, nothing installed or loaded
- [ ] Hold, follow and attack on command in game at The First Step (event route,
      [control/README.md](README.md)); must meet the acceptance in
      [the engine pack](../../../docs/engine-packs/elden-ring.md#future-acceptance-for-hold-follow-and-attack)

## Backlog

| Item | Status (Not started; In progress; Done; Dropped) | Notes |
|---|---|---|
| Fill in the user brief (agent, from the conversation) | Done | |
| Qualify the engine in `docs/engine-packs/<engine>.md` | In progress | `docs/engine-packs/elden-ring.md`; event route written, native route not qualified |
| Elden Ring diagnostic foundation | Done | Built, not loaded: file identity, loaded PE header identity, log; not yet loaded by me3 or the game |
| Elden Ring hold / follow / attack | In progress | Event, AI logic, extractor and builder written (`ports/elden-ring/control`); full package build verified (exit 0; event merge, think row and Lua registration checked). The user's first run of the earlier package: hostile before any press, ran away after Talk (cause not proven). Friendly package run once by the user: stood still after Talk (design within 4 m) and, user-confirmed, did not follow after they walked roughly 10 m away, prompt still shown (cause not proven; logic loading not proven). Current package `D:/build/kagrenac-first-step/package-turn-perlogic-20261019` (per-logic file, face-the-player sign). Next: the user's offline test of it (turn after the first press, then walk 10 m). Team 47 friendliness (raw NpcParam team of the spirit-summon rows), `TARGET_EVENT` reaching the hostile, the Man-Bat on the same tile, about 152 m away, being loaded, and reload or warp recovery are unverified |

## Evidence

What actually ran, with date and result. Never record a claim you did not test.

| Date | What ran (command or in-game step) | Result |
|---|---|---|
| 2026-10-19 | Probe configure (`-G "Visual Studio 17 2022" -A x64`) and clean Release build, `/W4 /WX`, in `D:/build/kagrenac-elden-probe` | Built DLL and inspector with no warnings |
| 2026-10-19 | `kagrenac_er_inspect.exe` on the installed `eldenring.exe` (read-only) | Identity recorded; `qualified: no (fail closed)`, exit 3; SHA-256 equals `Get-FileHash` |
| 2026-10-19 | Inspector on a missing file; configure with `-A Win32` | Exit 1 "file not found or not accessible"; configure stopped "x64 MSVC only" |
| 2026-10-19 | `kagrenac_probe_init` called twice from a separate short-lived test process (not the game) | False both times; log "blocked: host is not eldenring.exe" and three `unsupported` action lines |
| 2026-10-19 | Same, with the log path blocked | One OutputDebugString line "cannot open kagrenac_er_probe.log (error 5)" |
| 2026-10-19 | Read-only SDK research: fromsoftware-rs `eldenring` and `shared` crates at `6933967b`, through the GitHub API; nothing installed, vendored or added | Handles file 2.7.1.0 (`rva.rs`); task and actor interfaces cited; no NPC AI goal or target order ([engine pack](../../../docs/engine-packs/elden-ring.md#sdk-facts)) |
| 2026-10-19 | After the log-text correction: clean Release rebuild, `/W4 /WX` | Built DLL and inspector with no warnings |
| 2026-10-19 | Inspector rerun on the installed exe and on a missing file | Same identity, `qualified: no (fail closed)`, exit 3, SHA-256 equals `Get-FileHash`; missing file exit 1 |
| 2026-10-19 | Wrong-host test rerun (separate process, not the game), then with the log path blocked | False twice; log "kagrenac_er_probe diagnostics (no game control)", "blocked: host is not eldenring.exe", three lines "unsupported (no qualified game-thread/actor/action backend integrated; nothing sent to the game)"; blocked: one "cannot open kagrenac_er_probe.log (error 5)" line |
| 2026-10-19 | `control/build-package.ps1` (earlier version, since replaced; it no longer has exit 3) with placeholder ids on the installed exe and DarkScript3 3.6.3 EMEDF, test JS only (scoped temp) | Exit 3, 22 event instructions resolved to the intended EMEDF ids with matching argument counts; refused wrong exe, repository or game output folder, non-empty output, duplicate entity and existing event id. Not compiled by DarkScript3; Lua not compiled; not tested in game |
| 2026-10-19 | Control event compiled and decompiled on its own with DarkScript3 3.6.3 (`/cmd`, scratch folder outside the repository) | Exit 0, standalone (the merge into the user's `common.emevd` is verified in the full build below); not run in game |
| 2026-10-19 | Lua 5.0.3 contract tests of the AI logic | 8 pass. Not run in game |
| 2026-10-19 | erpack pack on the user's own `aicommon.luabnd` and a copy of `regulation.bin` | Exit 0; think row 43111190 differs from 43111100 only in `logicId` (10000 to 431990); no other rows, files or compression settings changed |
| 2026-10-19 | Full `build-package.ps1` run (Windows PowerShell 5.1, example config) to `D:/build/kagrenac-elden-control/package-verified-20261019` | All three assets written and verified (merge and pack `ok` true), then it hung at 100% CPU while writing `package.json`; only that builder process was stopped, with no children left. Cause, reproduced in a small test outside the repository: `ConvertTo-Json -Depth 12` in 5.1 also serializes the PSPath/PSDrive/PSProvider notes on `Get-Content` lines (`steps.ids`), about 10x per depth level. Fixed by reading `inspect.out` with `[IO.File]::ReadAllLines` |
| 2026-10-19 | Full `build-package.ps1` run after the fix, same inputs, `-OutDir D:/build/kagrenac-elden-control/package-final-20261019`, `--expect-teams 48 47` passed to merge-events | Exit 0 in about 1 minute; erpack 0 warnings, 0 errors; `package.json` (16995 bytes) read back. Merge: `ok` and `teams_ok` true, 253 to 254 events, collateral empty, original unchanged, only event 1042378801 (`Restart`, 68 instructions) and its start at index 0 of event 0 added; team commands on 1042370200: 47 and 48. Pack: `ok` true, 961-byte logic, LUAINFO goal 431990 valid, only `logicId` changed in the cloned think row, no other row, file or compression change. Output SHA-256s match independent hashes and the earlier run byte for byte. Not installed; not run in game |
| 2026-10-19 | Same build after the review fixes, `-OutDir D:/build/kagrenac-elden-control/package-ready-20261019` | Exit 0 in 67 s; erpack 0 warnings, 0 errors; the three SHA-256s equal `package-final-20261019`. Merge: `ok`, `teams_ok`, `entity_ok` true (both team commands on 1042370200); id 1042378801 free in the original `m60_42_36_00` and `m60_42_37_00` event files. Pack: `ok`, luabnd order kept (sorted, new entry at index 167). Not installed; not run in game |
| 2026-10-19 | `me3 launch --help` (portable me3 0.13.0), no launch | `--online [<START_ONLINE>]` with possible values `true, false`; `--exe` and `--savefile` listed; README keeps `--online false` |
| 2026-10-19 | `me3 profile show --file` (portable me3 0.13.0) on a renamed copy of `kagrenac_er_control.me3.example`, outside the repository | Exit 0: savefile `KagrenacControl.sl2`, Elden Ring supported, one package `kagrenac-control`, no natives, online and Arxan options unset. Game not launched |
| 2026-10-19 | Full `build-package.ps1` run with the First Step copy (Windows PowerShell 5.1, example config), `-OutDir D:/build/kagrenac-first-step/package-20261019` | Exit 0 in 71 s; four outputs, hashes in that folder's `package.json` (the README now lists the friendly build). Grace from the user's data: BonfireWarpParam 61423601 `[Limgrave] The First Step`, `m60_42_36_00`, asset `AEG099_090_9011` at (-12.83, 90.7, -54.5). erpack place `ok`: one part plus model `c4311` added, the output with them removed equals the original byte for byte (decompressed), id 1042360890 and name `c4311_9901` free in all five extracted MSB and event files. merge-events `ok`, both team commands on 1042360890; luabnd and regulation identical to `package-ready-20261019`. Scratch negative runs of place refused 8 bad inputs. Not installed; not run in game |
| 2026-10-19 | Same build after the doc review, one `untested` line added (BackupEventAnimID 704 and hostile-copy risks), `-OutDir D:/build/kagrenac-first-step/package-ready-20261019` | Exit 0 in 65 s; erpack 0 warnings, 0 errors; the four output SHA-256s equal `package-20261019`; `package.json` (30223 bytes) read back with 11 `untested` lines, and apart from output paths it differs from the earlier one only by the new line. Not installed; not run in game |
| 2026-10-19 | User's offline in-game run of the earlier event package at The First Step (reported by the user) | The copy was hostile and attacked before any interaction; a Talk prompt was available; after pressing Talk it ran away. Whether it still attacked after the press is unknown. No log or loaded-file record. Cause of the running away not proven ([control README](README.md#user-test-of-the-earlier-package-2026-10-19)) |
| 2026-10-19 | Own-data reads (scratch, outside the repository): EMEDF `Team Type` enum, Paramdex NpcParam `TEAM_TYPE`, the user's regulation, MSBs, event files and `aicommon.luabnd` (names and constants only, `luac -l`) | Event enum: -1 to 33, 67, 70, no 47 or 48. NpcParam: 115 rows team 47 (`[Spirit Summon]`), 43111110 team 48, id 43111190 free in NpcParam and NpcThinkParam. BackupEventAnimID -1 on 141 of 156 enemies in the two tiles, 704 on the template. `COMMON_EasySetup_Initial`: 22 `AddTopGoal` sites (some on `TARGET_ENE_0`); `COMMON_Initialize`: none. `TARGET_EVENT` = 20 and `TARGET_LOCALPLAYER` = 21 in `ai_define`; only the latter is used by other game AI scripts. Back-home fields of think 43111100 are `COMMON_SetBattleActLogic` arguments (Paramdex) |
| 2026-10-19 | Full `build-package.ps1` run of the friendly package (Windows PowerShell 5.1, example config), `-OutDir D:/build/kagrenac-first-step/package-friendly-20261019` | Exit 0 in 46 s; erpack 0 warnings, 0 errors; hashes in the [control README](README.md#build). merge-events `ok`, 253 to 254 events, collateral empty, no team command, all 11 character AI calls on 1042360890. pack `ok`: only `logicId` (think) and `teamType` 48 to 47 (NpcParam) differ from the source rows; no other row or file changed. place `ok`: copy differs from the template only in name, instance, entity, position, entity groups, think, NpcParam and BackupEventAnimID (704 to -1); original entries byte-identical. Inspect with the packaged regulation: copy `logic=431990 team=47`, template and its other users still `logic=10000 team=48`. Game `regulation.bin` hash equals the input copy; `package-ready-20261019` unchanged. me3 0.13.0 `profile show` on `kagrenac_er_control.me3` there: exit 0, savefile `KagrenacControl.sl2`, no natives. Not installed; not run in game |
| 2026-10-19 | User's offline in-game run of `package-friendly-ready-20261019` (reported by the user) | "he just stands there and does nothing when i click talk on him"; no hostility reported. Asked whether they walked over 4 m away and whether the prompt stayed, the user replied "yes i did": after one Talk press they walked roughly 10 m away, the prompt remained and it did not follow. Cause not proven. No log ([control README](README.md#user-test-of-the-friendly-package-2026-10-19)) |
| 2026-10-19 | Own-data reads after that report (scratch `D:/build/kagrenac-first-step/diag-talk-20261019`, read-only; archive index, four per-logic files, `aicommon` bytecode listings with `luac -l`) | 70 of 84 logic ids used by NpcThinkParam rows have `script/<id>_logic.luabnd.dcx`; 431990 had none; 10000, 410000 and 430000 per-logic `.lua` byte-identical to `aicommon`. `ApproachTarget` fourth argument `TARGET_SELF` at 101 of 131 sites and at both approaches to `TARGET_LOCALPLAYER`; `AddTopGoal(GOAL_COMMON_Turn, life, target, n, 0, 0)` at 10 sites |
| 2026-10-19 | Full `build-package.ps1` run (Windows PowerShell 5.1, example config), `-OutDir D:/build/kagrenac-first-step/package-turn-perlogic-20261019` | Exit 0 in 63 s; erpack 0 warnings, 0 errors. pack `ok`, `logic_file` `ok` (layout of `010000_logic.luabnd.dcx`, only logic 431990 registered), collateral empty. Event, regulation and MSB byte-identical to `package-friendly-ready-20261019`, which still matches its hashes. External Lua contract test 12 of 12 (fails 4 on the earlier logic). Not installed; not run in game |
| 2026-10-19 | External checks on the `package-friendly-20261019` build (scratch, not committed): Lua 5.0.3 contract test of the generated logic; structural check of DarkScript3's decompile of the packaged event; erpack negative runs | Lua 11 of 11 pass (fails 9 of 11 on the earlier logic). Event check passes (loaded-and-alive wait then clear before the first press, one step per press, hostile guard, every path to the restart, no team or AI id change, only the companion addressed; fails on the earlier event). erpack refused 5 bad inputs (source-team NpcParam clone, existing NpcParam id, earlier event with no team allowed, original soldier's id as the expected entity, `place` without `--think`). Not run in game |
| 2026-10-19 | User's latest report in conversation, after the current package was handed over | "okay it works": recorded as the user reporting the companion controls working. Which of hold, follow and attack were seen, which package build ran, and release, reload or warp recovery were not stated; no log. Not verified by the agent. No AI, LLM or voice is involved yet |
| 2026-10-20 | Game update to `eldenring.exe` 2.7.2.0 (Steam build 25827938, SHA-256 `f9118fea...e298ffb328`, PE timestamp 0x6aabf7e7, SizeOfImage 0x05dfd600), read from the installed file; recorded in `ports/elden-ring/game-build.json`. Bridge: links only when exactly one beacon candidate is live; package: `attack_enabled` (example: false); `mod.ps1` doctor, build, assemble | Native DLL built `/W4 /WX` with the gate from `game-build.json`. `mod.ps1 doctor` on the installed game and tools: every check OK. Template rendering checked with attack on and off (no marker or placeholder left). `assemble` exercised on a test build of dummy package files: offline profile accepted by `me3 profile show`, same build again wrote nothing, another build refused without `-Replace`, changed files refused, `-Replace` moved the old files aside and kept `config.json` byte for byte. Full package build on 2.7.2.0 not run here; nothing loaded in game |
