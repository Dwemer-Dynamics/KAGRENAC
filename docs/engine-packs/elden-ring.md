# Engine pack: Elden Ring (diagnostic foundation, not qualified in engine)

Copied from [ENGINE_PACK.md](ENGINE_PACK.md). Scope: the native diagnostic probe in
[ports/elden-ring/](../../ports/elden-ring/README.md), not dialogue, voice or protocol work.
The separate event-script route for hold, follow and attack is in
[ports/elden-ring/control/](../../ports/elden-ring/control/README.md); its package builds
and verifies in full from the user's own files, and it is not tested in game.
Sources were read on 2026-10-19 through the GitHub API at the pins below; nothing was
downloaded into the repository or installed, and no source code was copied. Three
projects were examined. fromsoftware-rs explicitly handles the installed file version
and has task (game-thread) and actor interfaces, so a game-thread callback and actor
access are potentially available; none of it is integrated or verified in engine. No
NPC AI goal or target order was found in any of the three, which is not a claim that no
such mechanism exists elsewhere.

## Sources consulted

| Source | Pin | Licence | Relevant content |
|---|---|---|---|
| me3 mod loader, [github.com/garyttierney/me3](https://github.com/garyttierney/me3) | tag v0.13.0, commit [`989b522214e39c83d701f4182c4f0a86ad79a30a`](https://github.com/garyttierney/me3/tree/989b522214e39c83d701f4182c4f0a86ad79a30a) | MIT OR Apache-2.0 ([Cargo.toml](https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/Cargo.toml#L23)) | `schemas/mod-profile.json`, `docs/configuration-reference.md`, `crates/mod-host/src/host.rs`, `crates/mod-host/src/lib.rs` |
| fromsoftware-rs, [github.com/vswarte/fromsoftware-rs](https://github.com/vswarte/fromsoftware-rs) | commit [`6933967b176332a37e9ce6773f8dcd74b9feaf42`][fsrs] (read 2026-10-19; `eldenring` and `shared` crates only) | `Cargo.toml` says MIT OR Apache-2.0; the repository ships `LICENSE-MIT-NON-AI` and `LICENSE-ASL2-NON-AI`. Not a dependency; its terms need review only if it is ever imported | `crates/eldenring/src/rva.rs`, `cs/task.rs`, `cs/world_chr_man.rs`, `cs/chr_ins.rs`, `cs/field_ins.rs`, `cs/team_relation.rs`, `cs/targeting.rs`, `cs/chr_ins/module.rs`, `cs/chr_ins/module/action_request.rs`, `crates/shared/src/task.rs` |
| libER, [github.com/Dasaav-dsv/libER](https://github.com/Dasaav-dsv/libER) | commit [`d8ae5c92719adca4344d8d902b63286b807f562b`](https://github.com/Dasaav-dsv/libER/tree/d8ae5c92719adca4344d8d902b63286b807f562b) (2025-04-24, "1.16-game-upd") | Apache-2.0 with LLVM exceptions ([LICENSE](https://github.com/Dasaav-dsv/libER/blob/d8ae5c92719adca4344d8d902b63286b807f562b/LICENSE)) | `include/`, `symbols/*.csv`, `source/detail/app_version.cpp` |

## SDK facts

| Item | SDK fact | Citation |
|---|---|---|
| Engine and version | Installed `eldenring.exe`: file version 2.7.1.0, PE timestamp 0x6a96b418, SizeOfImage 0x05e0da00, 87042128 bytes, file SHA-256 `1a3547101327f65d0c76da2f9190ac0aa66871ea42bae2aecc61e11a8b597891`. Steam build 25080141. The title patch is Unknown: a file version is not a patch number | Identity: `kagrenac_er_inspect` output, 2026-10-19, SHA-256 matched by `Get-FileHash`. Steam build: `buildid` in the Steam `appmanifest_1245620.acf` |
| Plugin architecture | Native x64 DLL loaded by me3 from `[[natives]]` | me3 [configuration-reference.md][me3-config] |
| Load hook | Optional `initializer = { function = "..." }`: an `extern "C" fn() -> bool`, called after the DLL loads. A false return is only logged ("native failed to initialize") | me3 [`host.rs` `load_native`](https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/crates/mod-host/src/host.rs#L82-L129) |
| Initializer thread | In `after_game_main`, the first native with an initializer, and every native after it, loads on a thread me3 spawns with `std::thread::spawn`. This probe's initializer therefore runs on that spawned loader thread, after the game's main function has started and concurrently with it. Not a verified game thread | me3 [`lib.rs` `after_game_main`](https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/crates/mod-host/src/lib.rs#L161-L227) |
| `optional` | Default false. With `optional = false`, a delayed native that fails to load (missing DLL or export) fails the me3 loader; whether the game keeps running after that is unverified, so do not assume it survives the failure. With `true` it is only a warning. An initializer returning false is not a load failure | me3 [`lib.rs`](https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/crates/mod-host/src/lib.rs#L213-L227), [`mod-profile.json`](https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/schemas/mod-profile.json#L92-L96) |
| Unload hook | `finalizer` is in the schema, but no call site in `host.rs` or `lib.rs` at this pin: Unknown | me3 [`mod-profile.json`](https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/schemas/mod-profile.json#L128) |
| Isolated save | `savefile` makes the game use another file name. If that file does not exist, me3 creates it as a copy of an existing base save; the default save directory is unchanged | me3 [configuration-reference.md][me3-config] |
| Offline | me3 calls `start_offline()` unless `start_online` is set | me3 [`lib.rs`](https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/crates/mod-host/src/lib.rs#L174-L176), [configuration-reference.md][me3-config] |
| Anti-tamper option | `disable_arxan` exists ("Try to neutralize Arxan GuardIT code protection"); this project does not use it | me3 [`mod-profile.json`](https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/schemas/mod-profile.json#L311-L318) |
| Build support in fromsoftware-rs | `rva.rs` maps `(LANG_ID_EN, "2.7.1.0")` to its `Ww2710` address table and panics on an unsupported executable. It checks the version string only, not a file hash, so its addresses are unverified against the installed file | fromsoftware-rs [`rva.rs`][fsrs-rva] |
| Main-thread tick or callback | fromsoftware-rs: `CSTaskImp::wait_for_instance` and `SharedTaskImpExt::run_recurring(closure, CSTaskGroupIndex)`, with groups such as `FrameBegin` and `ChrIns_PreBehavior`; `RecurringTask::cancel()` only sets a flag at this pin. libER: `CS::CSEzTask::register_task` at a fixed RVA for its own target build, not applicable here | fromsoftware-rs [`cs/task.rs`][fsrs-task], [`shared/src/task.rs`][fsrs-stask]; libER [`symbols/tasks.csv`][liber-tasks], [`include/detail/symbols.hpp`][liber-sym] |
| libER version mapping | libER rewrites file version 2.x.y as 1.(10+x).y, so 2.7.1.0 would read as 1.17.1; its symbols target "1.16". Recorded only as libER's own convention | libER [`app_version.cpp`][liber-ver] |
| Player, NPC identity, hostile selection | fromsoftware-rs: `WorldChrMan.main_player`, character sets and `chr_ins_by_handle`; `EnemyIns` with `npc_think_param`; `FieldInsHandle { selector, block_id }` has no generation field, so incarnation safety needs a check of our own; `ChrIns.team_type` and team-relation data, with no "hostile to player" helper. None in me3 or libER | fromsoftware-rs [`world_chr_man.rs`][fsrs-wcm], [`chr_ins.rs`][fsrs-chr], [`field_ins.rs`][fsrs-field], [`team_relation.rs`][fsrs-team] |
| NPC hold, follow, attack | No NPC AI goal or target order in any of the three. fromsoftware-rs: `com_manipulator`, `ChrCtrl.manipulator` and the module container's `ai` are opaque `usize` fields, and targeting data is read-only; its action-request module and debug flags are input or freeze state, not AI commands. libER only has AI param definitions and singleton addresses (e.g. `CSWorldAiManager`) | fromsoftware-rs [`chr_ins.rs`][fsrs-chr], [`module.rs`][fsrs-mod], [`targeting.rs`][fsrs-tgt], [`action_request.rs`][fsrs-act]; libER [`include/param/paramdef`](https://github.com/Dasaav-dsv/libER/tree/d8ae5c92719adca4344d8d902b63286b807f562b/include/param/paramdef), [`symbols/singletons.csv`][liber-single] |
| Worker threads or HTTP | Unknown; not used by the probe | |
| Player text input, subtitles, WAV, microphone | Unknown; out of scope for this stage | |

[me3-config]: https://github.com/garyttierney/me3/blob/989b522214e39c83d701f4182c4f0a86ad79a30a/docs/configuration-reference.md#L39-L40
[liber-tasks]: https://github.com/Dasaav-dsv/libER/blob/d8ae5c92719adca4344d8d902b63286b807f562b/symbols/tasks.csv
[liber-sym]: https://github.com/Dasaav-dsv/libER/blob/d8ae5c92719adca4344d8d902b63286b807f562b/include/detail/symbols.hpp
[liber-ver]: https://github.com/Dasaav-dsv/libER/blob/d8ae5c92719adca4344d8d902b63286b807f562b/source/detail/app_version.cpp
[liber-single]: https://github.com/Dasaav-dsv/libER/blob/d8ae5c92719adca4344d8d902b63286b807f562b/symbols/singletons.csv
[fsrs]: https://github.com/vswarte/fromsoftware-rs/tree/6933967b176332a37e9ce6773f8dcd74b9feaf42
[fsrs-rva]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/rva.rs#L25
[fsrs-task]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/cs/task.rs
[fsrs-stask]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/shared/src/task.rs
[fsrs-wcm]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/cs/world_chr_man.rs
[fsrs-chr]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/cs/chr_ins.rs
[fsrs-field]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/cs/field_ins.rs
[fsrs-team]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/cs/team_relation.rs
[fsrs-tgt]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/cs/targeting.rs
[fsrs-mod]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/cs/chr_ins/module.rs
[fsrs-act]: https://github.com/vswarte/fromsoftware-rs/blob/6933967b176332a37e9ce6773f8dcd74b9feaf42/crates/eldenring/src/cs/chr_ins/module/action_request.rs

## Implementation and verification

What the probe reads: the host executable file on disk (version resource, PE headers,
file SHA-256) and the PE headers of the host image loaded in its own process. It does not
access actors or game state, write memory, hook, start threads or use the network.

| Item | Where | Status | Evidence |
|---|---|---|---|
| Exact file identity, fail closed | `ports/elden-ring/probe/src/build_id.cpp` | Implemented; inspector verified offline | 2026-10-19: inspector on the installed exe printed the identity above, `qualified: no (fail closed)`, exit 3; missing file exit 1 |
| Qualified build table | `kQualifiedBuilds` in `build_id.cpp` | Empty on purpose | No build has in-engine evidence |
| DLL and initializer | `kagrenac_probe_init` in `probe_dll.cpp`, `kagrenac_er_probe.me3.example` | Built; not loaded by me3 or the game | 2026-10-19 rerun after the log-text correction, separate test process (not the game): returned false twice; log "blocked: host is not eldenring.exe" and three `unsupported` action lines |
| Loaded PE header identity | `loaded_pe_headers_match_file()` | Implemented, untested in game | Compares only TimeDateStamp and SizeOfImage. It does not show that code or data in memory match the file (loaders, protection code and other mods may patch the image) |
| Log failure visibility | `Log` in `probe_dll.cpp` | Tested outside the game | 2026-10-19: with the log path blocked, one OutputDebugString line "cannot open kagrenac_er_probe.log (error 5)" |
| Game-thread callback | none | Not integrated, not qualified | Potentially available through fromsoftware-rs tasks (cited); the probe integrates no game backend |
| Player, companion, hostile identity | none | Not integrated, not qualified | Potentially available through fromsoftware-rs actor interfaces (cited); the probe has no actor access |
| Hold, follow, attack (native) | none | Not integrated, not qualified | No NPC command mechanism found in the three native sources; the probe logs `unsupported (no qualified game-thread/actor/action backend integrated; nothing sent to the game)` |
| Companion copy beside The First Step | `erpack place` ([README](../../ports/elden-ring/control/README.md#where-the-copy-stands)) | Implemented; full package build verified; not tested in game | 2026-10-19, `D:/build/kagrenac-first-step/package-20261019`, exit 0 in 71 s. Grace from the user's own data: BonfireWarpParam 61423601 `[Limgrave] The First Step`, tile `m60_42_36_00` (area 60, grid 42/36), position (-12.83, 90.7, -54.5) = asset `AEG099_090_9011` (entity 1042361981); bonfire entity 1042361951 registered by RegisterBonfire 2009[03] in that tile's event 0 (enemy deactivation distance 5.0 m); height reference player part `c0000_9003` (-11.53, 90.55, -56.72). Copy `c4311_9901`, entity 1042360890, at (-15.86, 91.0, -56.25), 3.50 m from the grace; only name, instance, entity id, position and its two Gatefront entity groups differ from 1042370200; model `c4311` added; with the additions removed the MSB equals the user's original byte for byte (decompressed). Ground contact not shown |
| Hold, follow, attack (event route) | `ports/elden-ring/control` ([README](../../ports/elden-ring/control/README.md)) | Implemented; full package build verified; not tested in game | 2026-10-19: Lua 5.0.3 contract tests 8 pass. Full `build-package.ps1` run (Windows PowerShell 5.1, example config), exit 0, `package.json` read back: merge-events `ok`, original 253 events to 254, collateral empty, only event 1042378801 (68 instructions) and `InitializeEvent(0, 1042378801, 0)` at index 0 of event 0 added, `--expect-teams 48 47` matched; pack `ok`, LUAINFO goal 431990 `kagrenac431990_Logic` valid, cloned think row 43111190 differs only in `logicId`. Rerun to `package-ready-20261019` (exit 0, same three hashes): id 1042378801 free in the original `m60_42_36_00`/`m60_42_37_00` event files, every team command on 1042370200 (`entity_ok`), luabnd order kept. First Step rebuild (`D:/build/kagrenac-first-step/package-20261019`, exit 0): the control event now targets the copy 1042360890; compared with `package-ready-20261019`, only 35 instruction arguments differ (1042370200 to 1042360890), and the luabnd and regulation hashes are the same. Hashes in the [control README](../../ports/elden-ring/control/README.md#build). Nothing installed or loaded |

## Future acceptance for hold, follow and attack

Applies to any route, including the event route. An action counts as caused by the command
only when all of these hold, each recorded here with in-game evidence:

- **Control trials.** Each action is also measured without a command, under the same
  setup. A pass needs the commanded trial to differ from the control: hold must stop a
  companion that was following or moving on its own; follow must move a companion that
  stayed put for a set time while the player walked away; attack must start combat that
  the control trial did not show.
- **Inactive start.** The companion and the target are both idle and out of combat before
  attack; a summon or other default follower is not evidence for follow, and an idle or
  AI-less NPC is not evidence for hold.
- **Actor identity.** Native route: player, companion and target are resolved on a
  verified game thread each time and checked against a per-actor incarnation (not only an
  id) and a world generation, so a despawn, respawn or world reload never reuses a stale
  actor. Event route: the fixed MSB entity ids, checked against the user's MSBs at build
  time, and loaded-and-alive checks in the event before each order.
- **Measurements.** Positions must be finite and within bounds; a timeout is checked
  before observation; hit attribution needs a defined baseline.
- **Cancel and release.** Every command can be cancelled, and the companion returns to its
  previous behaviour on cancel, timeout and world reload without a crash or hang; the
  native route also on DLL unload, the event route also on rest, warp and reload with the
  package and after removing it. None of this is qualified yet.

## Port decisions

| Decision | Choice and reason |
|---|---|
| Loader | me3 natives: documented initializer, isolated `savefile`, offline by default (cited above) |
| No libER dependency now | Its symbols are fixed for another build and it has no character-control API |
| No fromsoftware-rs dependency now | Read-only research: nothing installed, vendored or added. Its build support, tasks and actor interfaces are leads for later integration, not verified in engine; its licence terms are reviewed only if it is ever imported |
| Initializer return value | Always false, so me3 logs "native failed to initialize"; expected for this diagnostic probe |
| `optional = false` in the profile | A missing DLL or export fails the me3 loader; whether the game keeps running after that is unverified, so do not assume it survives the failure |
| Diagnostics log | `kagrenac_er_probe.log` next to the DLL, rewritten once per process; on failure, one OutputDebugString line. No UI |
| Initializer cost | Hashes the about 87 MB executable once, on me3's spawned loader thread |

## Offline manual gates (not yet run; need the user to launch)

1. Back up the save folder first (mandatory): me3 creates the new `savefile` as a copy of an
   existing save. Use a separate me3 profile from the template, outside the repository;
   no `start_online`, no `disable_arxan`. This repository installs and launches nothing.
2. Launch offline through me3, never online; do not add or change anti-cheat files.
3. Check `kagrenac_er_probe.log`: build line, "loaded PE header identity matches file",
   "blocked: build not in the qualified table" and three `unsupported` action lines; the
   me3 log shows "native failed to initialize".
4. The probe's hold, follow and attack lines stay `unsupported`. Actions go through the
   separate event route; its First Step checklist is in
   [control/README.md](../../ports/elden-ring/control/README.md#first-step-checklist), and
   a result counts only if it meets the acceptance above.

## Open questions

| Question | Blocking | Next step |
|---|---|---|
| A game-thread callback that works on the installed build | Game access | Integrate and test a backend offline; fromsoftware-rs tasks are the cited lead |
| Resolving the player and a companion with incarnation-safe handles | Identity | Same; handles need a generation check of our own |
| Commanding hold, follow and attack of a specific target, with cancel and hit attribution | Actions | Event route written (event script with bank 2004 AI instructions plus AI logic: follow on `TARGET_LOCALPLAYER`, attack on `TARGET_EVENT`). User report on the earlier package (2026-10-19): the copy was hostile before any press, a Talk prompt showed, and it ran away after the press; cause not proven ([control README](../../ports/elden-ring/control/README.md#user-test-of-the-earlier-package-2026-10-19)). The friendly package (copy starts on its own control think row and team-47 NpcParam row, holds; release, reload and loss restart to a friendly hold) is built and verified as files (exit 0), not run in game. Next: the user's offline First Step test of that package. Native route: no mechanism in the three sources; freezing a character or injecting action requests is not a command |
| Whether control team 47 acts friendly to the player | Attack, follow | Now set only as the raw NpcParam `teamType` of the copy's private row (the EMEDF event `Team Type` enum lists neither 47 nor 48; Paramdex names NpcParam 47 "Spirit Summon", used by 115 spirit-summon rows). Observe in the First Step test |
| A hostile that is reliably loaded near the companion | Attack | The configured Man-Bat is on the copy's tile but about 152 m away; kept as the target |
| Whether the copy stands on the ground, and whether a team-47 copy blocks the grace | Placement | Height checked only against the grace asset and its player part; it is inside the grace's 5.0 m enemy deactivation distance. User check in game |
| Whether me3 calls `finalizer` at all | Unload | Read me3 source at a newer pin, or test |
| Title patch number of the installed build | Build row | In-game title screen check by the user |
