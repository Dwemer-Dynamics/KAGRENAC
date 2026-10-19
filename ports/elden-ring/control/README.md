# Elden Ring companion control: follow, hold, attack (not tested in game)

One NPC, friendly and holding from the start, that you step with the action button: it
follows you, holds its position, or attacks one fixed hostile, using the game's own event
script and AI scripting. The package builds in full from the user's own files (2026-10-19,
exit 0). The user ran the earlier, hostile-at-start event package once in game (see
[User test](#user-test-of-the-earlier-package-2026-10-19)); the friendly package below has
not been run in game. Voice, an LLM and the server bridge are not part of this stage.

## Status

| Piece | File | Implemented | Checked so far | Not yet shown |
|---|---|---|---|---|
| Control event | `kagrenac_control.js.in` | One flagless `Restart` event, id 1042378801, started once from common event 0; sets no team and no AI id | Compiled, merged and decompiled with DarkScript3 3.6.3 in the full build | Running in game |
| Event merge into the user's `common.emevd` | `build-package.ps1`, `erpack merge-events` | Adds that one event and its one start to the user's original binary, keeping everything else | Full friendly build 2026-10-19: `ok` true, 253 to 254 events; owned event 1042378801 (`Restart`, 66 instructions) and `InitializeEvent(0, 1042378801, 0)` at index 0 of event 0; collateral empty; original unchanged; no `SetCharacterTeamType` (`--expect-teams` with no value); all 11 character AI calls on the copy 1042360890 | Running in game |
| AI logic | `kagrenac_companion.lua.in` | Hold with no order; follow on `TARGET_LOCALPLAYER` (21); attack on `TARGET_EVENT` (20); no `COMMON_EasySetup_Initial` | External Lua 5.0.3 contract test on the generated file: 11 pass | Running in game |
| Think, NpcParam and Lua packing | `erpack pack` | Clones think row 43111100 as 43111190 (`logicId` 431990) and NpcParam 43111110 as 43111190 (`teamType` 47), and adds the logic to `aicommon.luabnd` | Full build: the only differing cells are `logicId` and `teamType` (48 to 47); every other row, 43111100 and 43111110 included, and every other file unchanged | Loading in game |
| Companion copy at The First Step | `erpack place` | Adds one copy of the Gatefront soldier, with its own entity id, name, think row 43111190, NpcParam row 43111190 and `BackupEventAnimID` -1, to a copy of `m60_42_36_00.msb.dcx`, 3.5 m from The First Step grace | Full build: one part and the `c4311` model entry added; with them removed the file equals the user's original byte for byte (decompressed); id and name free in every extracted MSB and event file | Standing on the ground and loading in game |
| Full package build | `build-package.ps1` | Builds the four assets and `package.json` | 2026-10-19, Windows PowerShell 5.1, example config: exit 0 in about 1 minute; erpack built with 0 warnings and 0 errors; `package.json` read back | Installing, loading and running in game |
| Native DLL route | `../probe` | Diagnostics only | | Not qualified; it controls no actor |

The existing diagnostic DLL is separate and unchanged: it returns false from its
initializer and sends nothing to the game. This package does not use it.

## How the control works

The copy is meant to be friendly and holding as soon as it loads. Its MSB part uses its own
rows, not the Gatefront soldier's: think row 43111190 (the control logic) and NpcParam row
43111190 (a clone of 43111110 with `teamType` 47). With no order the logic only waits, so
the package is designed to have no hostile window before the first press (not yet
verified in game), and no event changes a team or AI id.

The action button (param row 6000) on the companion steps through one fixed cycle. Each
press moves one step:

**hold -> follow -> hold -> attack -> release (hold)**

- **Hold** (at the start and after every release): no order; it waits where it is.
- **Follow** (first press): it moves to you (`TARGET_LOCALPLAYER`) when farther than 4 m
  and stops about 2 m away.
- **Hold** (second press): it waits where it is.
- **Attack** (third press): only if the configured hostile is loaded and alive at that
  moment. Its event target becomes the hostile; it moves to it (walk or run is not yet
  observed) and, within 3 m, uses animation 3000, an attack its own battle goal (431000)
  uses. If the hostile is not loaded and alive, this press releases instead.
- **Release** (fourth press, or automatically when the hostile unloads or dies, or after a
  60-second lease): the event restarts, clears the order and the AI target, and the
  companion holds, still friendly.
- **Companion lost** (unloaded or dead), **reload** or **warp**: the event restarts, sends
  nothing until the companion is loaded and alive, then clears the order and target. A
  reloaded copy takes its rows from the MSB again, so it is intended to come back friendly and holding (not yet verified in
  game).

To go from hold back to follow, finish the cycle (attack or release), then press again.

The Lua logic calls `COMMON_Initialize` (in the game's bytecode it has no direct `AddTopGoal` site,
though it may call helpers that were not checked), then
reads the order. It does not call `COMMON_EasySetup_Initial`: in the game's bytecode that
function has 22 `AddTopGoal` sites, some on `TARGET_ENE_0` and
`GOAL_COMMON_AttackTunableSpin`, so it could queue its own goal ahead of the order. The
logic never falls back to the NPC's normal combat. Of the two targets, `TARGET_LOCALPLAYER`
(21) appears in the game's own AI scripts (for example the white-phantom battle goal);
`TARGET_EVENT` (20) is only defined in `ai_define` and used by none of them.

### Team 47 is set in the param row, not by the event

The EMEDF `Team Type` enum of `SetCharacterTeamType` lists -1 to 33, 67 and 70, but not 47
or 48. The earlier event set 47 and restored 48 through it, so both were outside the
documented event enum. The Paramdex `TEAM_TYPE` enum of NpcParam `teamType` agrees with the
event enum on the shared values (6 Enemy, 8 Ally, 26 Friendly NPC, ...) and names 47
"Spirit Summon"; the user's regulation has 115 NpcParam rows with team 47, the
`[Spirit Summon]` rows. So 47 is only written as a raw NpcParam value, as the game does, and
the builder refuses any other control team. Whether it keeps the soldier and the player
off each other is not shown in game.

## First test setup (from `kagrenac_control.example.json`)

| Role | Entity | Map tile | Ids |
|---|---|---|---|
| Companion | Copy `c4311_9901`, entity 1042360890, beside The First Step grace | `m60_42_36_00` (package copy of the MSB) | think 43111190 (logic 431990), NpcParam 43111190 (team 47), `BackupEventAnimID` -1, no talk script |
| Template | Godrick Soldier `c4311_9021`, entity 1042370200, at Gatefront; stays in the game as it is | `m60_42_37_00` (not changed) | think 43111100 (logic 10000), NpcParam 43111110 (team 48), `BackupEventAnimID` 704; rows unchanged |
| Hostile | Man-Bat `c4200_9005`, entity 1042360215 | `m60_42_36_00`, about 152 m from the copy and 19.5 m lower | team 6 |

### Where the copy stands

Everything below is read from the user's own files at build time, and `erpack place` refuses
if any of it no longer holds:

- **Grace**: BonfireWarpParam row 61423601, named `[Limgrave] The First Step` in the Paramdex
  names; `areaNo` 60, `gridXNo` 42, `gridZNo` 36, so tile `m60_42_36_00`; position
  (-12.83, 90.7, -54.5) in that tile; bonfire entity 1042361951, registered once by
  RegisterBonfire (EMEDF 2009[03]) in event 0 of `m60_42_36_00.emevd` (flag 1042360001,
  enemy deactivation distance 5.0 m).
- **Landmark**: the one asset at exactly that position, `AEG099_090_9011` (entity
  1042361981, rotation 166.15). The grace character `c1000_9001` (entity 1042360951) is at the
  same X and Z, 0.5 m lower.
- **Height reference**: the nearest player part, `c0000_9003` (entity 1042360981) at
  (-11.53, 90.55, -56.72), 2.57 m from the grace.
- **Copy**: (-15.86, 91.0, -56.25), 3.50 m from the grace: 3.03 m towards -X and 1.75 m
  towards -Z, which is west-south-west if +Z is north (not checked in game). The template's
  rotation (128.126) is kept. Y 91.0 is 0.30 m above the grace asset and 0.45 m above the
  player part. It is also the plane through the base heights of the grace asset (90.7) and
  the two ground assets either side of the spot, `AEG001_290_7135` (91.03) and
  `AEG001_290_7026` (90.9), which are 2.29 m and 2.21 m away. What those two assets are is not
  known.
- **Kept clear**: the player part 4.36 m away; White Mask Varré (`c0000_9000`, talk
  301006000) 8.4 m and his message region 7.9 m away; the NT-only tutorial cylinder (entity
  1042362657, radius 3.5 m) 6.1 m away. These, and the Man-Bat distances below, are
  horizontal distances measured from the MSB coordinates while choosing the spot; they are
  not checked in game and not all recorded in `package.json`. The builder
  requires 2.5 m to any character, 2 m to any asset and 1 m outside any event region.

Changes from the template, all intentional: name `c4311_9901` (instance 9901), entity
1042360890, position, its two Gatefront entity groups (1042375110, 1042375810) cleared
so no Gatefront group order reaches it, its own think and NpcParam rows (43111190 each),
and `BackupEventAnimID` 704 to -1. -1 is what 141 of the 156 enemies in the two extracted
tiles use; 704 is the template's backup event animation (what it shows in game is not
verified), which a friendly copy might
never leave. The template has no collision, patrol route or
tile-load reference, so there is nothing to remap; every other field equals the template.
The Gatefront map event that starts a common event for 1042370200 (`m60_42_37_00` event 50)
does not apply to the copy. The template model entry `c4311` was added to the tile, which
did not have one.

The Man-Bat is on the same tile as the copy but about 152 m away, so attack means a long walk
first; the attack target was left as it was. The builder re-reads these ids from your own
files and refuses on any mismatch. In the full build the new logic is registered like the game's own logic
entries: a 931-byte `kagrenac431990_logic.lua` in `aicommon.luabnd` and a LUAINFO goal
431990 `kagrenac431990_Logic` with logic interrupt `kagrenac431990_Interupt`, all fields
checked; the existing goals and LUAGNL globals were kept. Whether the game loads it is
not tested.

## Tools (supplied by you, not installed by this repository)

The builder installs nothing and downloads nothing. It needs:

- .NET 10 SDK, with `dotnet` on `PATH` (builds `erpack` into the output folder)
- Windows PowerShell 5.1 (`powershell.exe`)
- A portable tools root (`-Tools`). The exact paths are at the top of
  `build-package.ps1`; currently:

```text
<tools>/darkscript/DarkScript3.exe                      DarkScript3 3.6.3
<tools>/darkscript/er-common.emedf.json
<tools>/lua50-msvc/luac.exe                             Lua 5.0.3, x64 build
<tools>/uxm/UXM Selective Unpack 2.4.2.0/UXM Selective Unpack.exe
<tools>/witchy/Assets/Paramdex.zip                      WitchyBND 3.0.1
<tools>/witchy-lib/SoulsFormats.dll, ZstdNet.dll, DrSwizzler.dll, libzstd.dll
```

UXM Selective Unpack is only used as a library, headless: `extract-inputs.ps1` reads a
fixed allowlist of files from your archives and never unpacks or patches the game.

## Build

```powershell
powershell -File ports/elden-ring/control/build-package.ps1 `
  -Config <your copy of kagrenac_control.example.json, outside the repository> `
  -GameDir <Elden Ring>/Game -Tools <tools> -OutDir <new empty folder outside the repository and the game>
```

Exit codes: **0** the package was built (an asset build, not tested or qualified in the
game); **1** refused or a step failed, with the reason printed. Output: `<out>/package/`
(the override files), `<out>/work/` and `<out>/package.json`.

Verified friendly build for The First Step, 2026-10-19 (Windows PowerShell 5.1, exit 0 in
46 s, run once into a new folder):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ports/elden-ring/control/build-package.ps1 `
  -Config ports/elden-ring/control/kagrenac_control.example.json `
  -GameDir "D:/SteamLibrary/steamapps/common/ELDEN RING/Game" `
  -Tools D:/build/kagrenac-elden-control/tools -OutDir D:/build/kagrenac-first-step/package-friendly-20261019
```

| Output | Bytes | SHA-256 |
|---|---|---|
| `event/common.emevd.dcx` | 35440 | `786e348e167bc4042684c5869857a33c7e181765715b1933863806a38a5ae4b8` |
| `map/mapstudio/m60_42_36_00.msb.dcx` | 35344 | `6805f7ee4612a0b9472d4fc9ff6b335ad090c11888be51dcafd192854c3d9262` |
| `script/aicommon.luabnd.dcx` | 143984 | `b5377bb55010b1c6fe09745670f06ba1d51b2d50bf890fab9196c4e2ff5e2034` |
| `regulation.bin` | 1925616 | `2f7a704fe51469f5bad466e1c00363f51e77b60dc5c07dbdcae8d5158760cb0d` |

merge-events: `ok`, 253 to 254 events, collateral empty, original unchanged, event
1042378801 free in the original `m60_42_36_00` (31 events) and `m60_42_37_00` (9 events)
event files, no team command, every character AI call on 1042360890 (`entity_ok`). pack:
`ok`; think 43111190 differs from 43111100 only in `logicId` (10000 to 431990) and NpcParam
43111190 from 43111110 only in `teamType` (48 to 47); no other row of either param, no other
regulation or luabnd file and no container setting changed; the luabnd files kept their
order and the new entry went in by id at index 167. place: `ok`, one part and one model
entry added, the copy differing from the template only in the fields listed above, the id
appearing once in the output, and with the additions removed the output equals the user's
original byte for byte (decompressed). The last inspect, with the packaged regulation,
shows `c4311_9901 entity=1042360890 npc=43111190 think=43111190 talk=0 groups= logic=431990
goal=431000 team=47`; the template, and the other Gatefront soldiers that share its rows,
still show `npc=43111110 think=43111100 ... logic=10000 goal=431000 team=48`. The game's
`regulation.bin` SHA-256 equals the build's input copy, the six extracted inputs equal those
of the earlier build byte for byte, and the earlier `package-ready-20261019` still matches
its recorded hashes; nothing was written to either.

External checks on this build (scratch, outside the repository, not committed):

- Lua 5.0.3 contract test on the generated logic: 11 of 11 pass (no order, a cleared order
  and hold wait; follow approaches `TARGET_LOCALPLAYER` only beyond 4 m; attack approaches,
  or swings 3000, on `TARGET_EVENT`; `COMMON_EasySetup_Initial` never called). The same test
  fails 9 of 11 on the earlier package's logic.
- Structural check of DarkScript3's decompile of the packaged event: a loaded-and-alive
  wait, then order and target cleared before the first press wait; one step per press; the
  hostile loaded-and-alive guard before the event target; every path ends in the restart; no
  team or AI id change; only the companion addressed. It fails on the earlier package.
- erpack refused: an NpcParam clone with the source team, an NpcParam id that already
  exists, the earlier event (teams 47 and 48) when no team is allowed, the new event checked
  against the original soldier's id, and `place` without `--think`.

The earlier, hostile-at-start builds (`package-20261019`, `package-ready-20261019`) were left
as they were.

`place` (earlier version) also refused, with nothing written, each of these in a scratch run: an output that
already exists, the template's id, the template's name, the Gatefront coordinates, a
height 1.3 m above the grace, another grace name for the row, a spot inside the tutorial
cylinder, and a NaN coordinate.

Under Windows PowerShell 5.1, `ConvertTo-Json -Depth 12` also serializes the
PSPath/PSDrive/PSProvider notes that `Get-Content` adds to each line, so the builder reads
`inspect.out` with `[IO.File]::ReadAllLines` (an earlier run hung there).

## Launch profile

1. Copy `kagrenac_er_control.me3.example` into `<out>`, next to the `package` folder, and
   rename it, for example to `kagrenac_er_control.me3`. It loads the `package` folder
   only: no DLL, online stays blocked, anti-tamper is left alone, and the save is
   `KagrenacControl.sl2`.
2. Check it without launching the game:
   `<me3>/bin/me3.exe profile show --file <out>/kagrenac_er_control.me3`
3. Launch (you, not this repository):

```powershell
<me3>/bin/me3.exe launch --game eldenring --exe "<Elden Ring>/Game/eldenring.exe" `
  -p "<out>/kagrenac_er_control.me3" --online false --savefile KagrenacControl.sl2
```

`me3 launch --help` (0.13.0, run 2026-10-19 without launching) lists `--online [<START_ONLINE>]`
with possible values `true, false`, and `--exe <EXE>` and `--savefile <SAVEFILE>`; the explicit
`--online false` stays as an offline guard.

## First Step checklist

1. Back up your whole save folder first. me3 creates `KagrenacControl.sl2` as a copy of an
   existing save the first time.
2. Play offline, only with this isolated save and profile.
3. Rest at or warp to The First Step. The copied Godrick Soldier (`c4311_9901`, entity
   1042360890) should stand about 3.5 m west-south-west of the grace (if +Z is north; not
   checked) and 8.4 m from White Mask Varré. It should be friendly and standing still from
   the start. First check: does it attack or react to you before any press? Does it stand on
   the ground (not floating, sunk or fallen), in a normal pose? Can you still rest at the
   grace? The original soldier at Gatefront is unchanged and not controlled.
4. Use the action button on it. No custom prompt text is added; whatever prompt the game
   shows for button row 6000 (text id 7000) is what you will see. Record what you see.
5. **Follow** (first press): walk away. It should come to you and stop around 2 to 4 m
   away. Note whether it moves away from you instead, or attacks.
6. **Hold** (second press), then walk away. It should stay put.
7. **Attack** (third press). Only if the Man-Bat (entity 1042360215, about 152 m away and
   lower down) is loaded and alive does the soldier go after it; otherwise this press is a
   release. Attack ends by itself after 60 seconds.
8. **Release** (fourth press): it should stop and hold, still friendly.
9. Rest at the grace, quit and reload, and warp away and back: each time it should be
   friendly and holding again.

Note for each step what happened, and whether the soldier behaves differently from an
untouched one, then record the result in `docs/engine-packs/elden-ring.md`.

## User test of the earlier package, 2026-10-19

The user reported one offline run of the earlier, hostile-at-start event package (the copy
kept the Gatefront rows; the event switched its team and AI on the first press):

- The soldier beside The First Step was hostile and attacked before any interaction.
- A Talk prompt was available on it.
- After pressing Talk it ran away. Whether it still attacked after the press is not known.

The hostility before the press is what that package did by design: until the first press
the copy kept NpcParam 43111110 (team 48) and think row 43111100 (logic 10000). Why it ran
away is not proven. The code and the game's own data point at possible causes, none
confirmed in game: `COMMON_EasySetup_Initial` running before the order (it can queue goals
on `TARGET_ENE_0`, which was the player it was fighting); team 47 set and team 48 restored
through `SetCharacterTeamType`, whose EMEDF enum lists neither; follow on `TARGET_EVENT`,
which no game AI script uses; and the old combat target, not cleared on the first press.
The friendly package removes each of these. The run did not record logs or which files the
game loaded.

## Limits

- The friendly package has not been run in game: friendliness at spawn, hold, follow,
  attack, release and recovery are all unproven. The one in-game report is for the earlier
  package (above).
- Team 47 (the raw NpcParam value of the game's spirit-summon rows) is not shown in game to
  keep the soldier and the player off each other, or to let its attack hurt the hostile.
- `TARGET_EVENT` after `SetCharacterEventTarget` is not shown to be the hostile.
- The hostile may not be loaded, and is about 152 m from the copy.
- The copy's ground contact is not shown: its height is checked only against the grace asset
  and its player part, not against terrain collision. Two nearby assets of unknown kind
  (`AEG001_290_7135`, `AEG001_290_7026`) are 2.2 to 2.3 m away.
- The copy is within the 5.0 m enemy deactivation distance of the grace's RegisterBonfire;
  whether a team-47 character there blocks resting is not tested.
- Without `BackupEventAnimID` 704 the copy's starting pose is not checked in game; whether
  it respawns after being killed is not tested.
- The friendly package is a verified file build only; this repository installed and loaded
  nothing.
- A reload, warp or death while controlled relies on the game rebuilding the copy from its
  MSB rows and on the event restarting (not tested).
- The native SDK and DLL backend are not qualified; this route does not use them.
- No voice, LLM or server bridge yet.
