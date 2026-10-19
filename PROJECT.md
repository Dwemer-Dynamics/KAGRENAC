# Project brief

Your project's single source of truth for what you are building with KAGRENAC AI Mod Maker.
You do not have to fill it in first: your coding agent reads it at the start of every task
([AGENTS.md](AGENTS.md)), fills it in from your conversation and earlier instructions, and
asks only for what is still missing for the next step. You can also pre-fill any row. Keep
it current, short, factual and free of secrets, keys, private URLs and personal data. A
blank row is not a permission: anything you have not asked for or allowed stays not
authorized.

## User brief

| Question | Answer |
|---|---|
| Project name | KAGRENAC Elden Ring companion (capability probe stage) |
| Game or engine, and version | Elden Ring, installed `eldenring.exe` file 2.7.1.0 (Steam build 25080141); title patch not confirmed |
| Engine SDK or modding tools, and where they are | me3 v0.13.0 native loader (not installed); libER and fromsoftware-rs read only; none installed or in the repository ([evidence](docs/engine-packs/elden-ring.md)) |
| What the player should be able to do | Eventually talk to a voiced companion; first, order a controlled companion to hold, follow the player and attack a locally selected hostile |
| Voice wanted? (no / text-to-speech / speech-to-text / both) | Wanted for the later demo; not in this stage |
| Actions beyond `follow_player` (none, or which) | hold, attack (wanted; not implemented: the native probe only logs them as unsupported; no protocol or client change yet) |
| Real LLM provider (mock only, or which) | Not in scope for this stage |
| Who will test in game, and on which architecture (x64 / x86) | The user, x64, offline with an isolated save; no in-game test has run |

## Decisions

Record each choice with its date and reason. Leave a row blank until it is decided.

| Date | Decision | Reason |
|---|---|---|
| 2026-10-19 | Separate native x64 probe under `ports/elden-ring/probe`; server, protocol and console client unchanged | Qualify real action control before voice or LLM work |
| 2026-10-19 | me3 natives as the loader candidate; no libER dependency | me3 documents initializer and isolated save; libER has no character control and targets another build |
| 2026-10-19 | Fail closed: empty qualified-build table; hold, follow and attack logged as unsupported, no gameplay code or stub interface | No game backend integrated or qualified; no NPC command mechanism found in me3, libER or fromsoftware-rs |

## Acceptance

What "done" means for this project. Start from the evidence levels in
[START_HERE.md](START_HERE.md#porting-to-a-real-engine) and add your own.

- [ ] Level 1: server lint, migrations twice and `scripts/smoke.sh` in mock mode
- [ ] Level 2: console client smoke checks ([client/README.md](client/README.md#smoke-checks))
- [ ] Level 3: each real provider call you chose, tested on its own (or "Not in scope")
- [ ] Level 4: in game, talk, subtitle, follow, cancel, NPC unload and server stop without a
      crash or hang

Current stage (Elden Ring diagnostic foundation, action probe blocked):

- [x] Exact file identity of the installed `eldenring.exe`, fail closed on an empty
      qualified table (inspector, offline)
- [x] x64 DLL and inspector build with `/W4 /WX`; initializer tested from a separate
      process, not the game
- [ ] DLL loads through me3 offline with an isolated save, and its log is checked (needs
      the user to launch; the profile must be a copy of `kagrenac_er_probe.me3.example`,
      outside the repository, renamed to end in `.me3`)
- [ ] Hold, follow and attack on command: blocked, no NPC command mechanism found; must meet the future
      acceptance in [the engine pack](docs/engine-packs/elden-ring.md#future-acceptance-for-hold-follow-and-attack)

## Backlog

| Item | Status (Not started; In progress; Done; Dropped) | Notes |
|---|---|---|
| Fill in the user brief (agent, from the conversation) | Done | |
| Qualify the engine in `docs/engine-packs/<engine>.md` | In progress | `docs/engine-packs/elden-ring.md`; action control blocked |
| Elden Ring diagnostic foundation | Done | Built, not loaded: file identity, loaded PE header identity, log; not yet loaded by me3 or the game |
| Elden Ring hold / follow / attack | Blocked | fromsoftware-rs has cited task and actor interfaces for 2.7.1.0 but no AI goal or target order; next: an actual NPC command mechanism, then integration and in-game tests |

## Evidence

What actually ran, with date and result. Never record a claim you did not test.

| Date | What ran (command or in-game step) | Result |
|---|---|---|
| 2026-10-19 | Probe configure (`-G "Visual Studio 17 2022" -A x64`) and clean Release build, `/W4 /WX`, in `D:/build/kagrenac-elden-probe` | Built DLL and inspector with no warnings |
| 2026-10-19 | `kagrenac_er_inspect.exe` on the installed `eldenring.exe` (read-only) | Identity recorded; `qualified: no (fail closed)`, exit 3; SHA-256 equals `Get-FileHash` |
| 2026-10-19 | Inspector on a missing file; configure with `-A Win32` | Exit 1 "file not found or not accessible"; configure stopped "x64 MSVC only" |
| 2026-10-19 | `kagrenac_probe_init` called twice from a separate short-lived test process (not the game) | False both times; log "blocked: host is not eldenring.exe" and three `unsupported` action lines |
| 2026-10-19 | Same, with the log path blocked | One OutputDebugString line "cannot open kagrenac_er_probe.log (error 5)" |
| 2026-10-19 | Read-only SDK research: fromsoftware-rs `eldenring` and `shared` crates at `6933967b`, through the GitHub API; nothing installed, vendored or added | Handles file 2.7.1.0 (`rva.rs`); task and actor interfaces cited; no NPC AI goal or target order ([engine pack](docs/engine-packs/elden-ring.md#sdk-facts)) |
| 2026-10-19 | After the log-text correction: clean Release rebuild, `/W4 /WX` | Built DLL and inspector with no warnings |
| 2026-10-19 | Inspector rerun on the installed exe and on a missing file | Same identity, `qualified: no (fail closed)`, exit 3, SHA-256 equals `Get-FileHash`; missing file exit 1 |
| 2026-10-19 | Wrong-host test rerun (separate process, not the game), then with the log path blocked | False twice; log "kagrenac_er_probe diagnostics (no game control)", "blocked: host is not eldenring.exe", three lines "unsupported (no qualified game-thread/actor/action backend integrated; nothing sent to the game)"; blocked: one "cannot open kagrenac_er_probe.log (error 5)" line |
