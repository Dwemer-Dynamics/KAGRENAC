# Elden Ring companion control: follow, hold, attack (not tested in game)

One NPC that you opt in with the action button follows you, holds its position, or
attacks one fixed hostile, using the game's own event script and AI scripting. The
package builds in full from the user's own files (2026-10-19, exit 0), but nothing here
has run in the game yet. Voice, an LLM and the server bridge are not part of this stage.

## Status

| Piece | File | Implemented | Checked so far | Not yet shown |
|---|---|---|---|---|
| Control event | `kagrenac_control.js.in` | One flagless `Restart` event, id 1042378801, started once from common event 0 | Compiled and decompiled on its own with DarkScript3 3.6.3, exit 0 | Running in game |
| Event merge into the user's `common.emevd` | `build-package.ps1`, `erpack merge-events` | Adds that one event and its one start to the user's original binary, keeping everything else | Full build 2026-10-19: `ok` true, original 253 events, merged 254; owned event 1042378801 (`Restart`, 68 instructions) and `InitializeEvent(0, 1042378801, 0)` at index 0 of event 0; collateral empty (no file metadata or event changed); original unchanged; `--expect-teams 48 47` matched both `SetCharacterTeamType` raw args on 1042370200; DarkScript3 reads the merged file back | Running in game |
| AI logic | `kagrenac_companion.lua.in` | Follow, hold and attack goals on `TARGET_EVENT` (20) | Lua 5.0.3 contract tests: 8 pass | Running in game |
| Think row and Lua packing | `erpack` | Clones think row 43111100 as 43111190 with `logicId` 431990 and adds the logic to `aicommon.luabnd` | A pack run on the user's own files: exit 0; the only differing cell was `logicId` (10000 to 431990); no other rows, files or compression settings changed | Loading in game |
| Full package build | `build-package.ps1` | Builds the three assets and `package.json` | 2026-10-19, Windows PowerShell 5.1, example config: exit 0 in about 1 minute; erpack built with 0 warnings and 0 errors; `package.json` read back | Installing, loading and running in game |
| Native DLL route | `../probe` | Diagnostics only | | Not qualified; it controls no actor |

The existing diagnostic DLL is separate and unchanged: it returns false from its
initializer and sends nothing to the game. This package does not use it.

## How the control works

The action button (param row 6000) on the companion steps through one fixed cycle. Each
press moves one step:

**idle -> follow -> hold -> attack -> release -> idle**

- **Idle**: the companion keeps its vanilla AI and team. At Gatefront it starts hostile.
- **Follow** (first press): the companion switches to the control think row and control
  team, its event target becomes you, and it moves to you when farther than 4 m.
- **Hold** (second press): it waits where it is.
- **Attack** (third press): only if the configured hostile is loaded and alive at that
  moment. The companion moves to it (walk or run is not yet observed) and, within 3 m, uses animation 3000, an attack its own
  battle goal (431000) uses. If the hostile is not loaded and alive, this press releases
  instead.
- **Release** (fourth press, or automatically): clears the order and target, restores the
  original think row and team, and returns to idle. Attack also releases automatically
  when the hostile unloads or dies, or after a 60-second lease.
- **Companion lost** (unloaded or dead while controlled): the event sends nothing to it,
  waits until it is loaded and alive again, then restores its original think row and
  team and returns to idle.

To go from hold back to follow, finish the cycle (attack or release, then release) and
press again. There is no direct hold-to-follow step.

The Lua logic runs `COMMON_Initialize` and `COMMON_EasySetup_Initial` first. Only a true
result from the setup (a goal already queued) takes precedence; nil or false falls
through to the order. It never falls back to the NPC's normal combat while controlled.

## First test setup (from `kagrenac_control.example.json`)

| Role | Entity | Map tile | Ids |
|---|---|---|---|
| Companion | Godrick Soldier `c4311_9021`, entity 1042370200 | `m60_42_37_00` | think 43111100, NpcParam 43111110, team 48 |
| Hostile | Man-Bat `c4200_9005`, entity 1042360215 | `m60_42_36_00` (the next tile) | team 6 |

The control team is 47. That number was read from the game's spirit-summon NpcParam rows;
whether team 47 actually acts friendly to the player in the engine is not verified. The
Man-Bat is on a neighbouring tile, so it may not be loaded when you stand next to the
soldier; a nearer, grounded hostile would suit the attack test better but none has been
chosen yet. The builder re-reads these ids from your own files and refuses on any
mismatch. In the full build the new logic is registered like the game's own logic
entries: a 961-byte `kagrenac431990_logic.lua` in `aicommon.luabnd` and a LUAINFO goal
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

Verified build, 2026-10-19 (Windows PowerShell 5.1, exit 0 in 67 s; the earlier
`package-final-20261019` run wrote the same three hashes):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ports/elden-ring/control/build-package.ps1 `
  -Config ports/elden-ring/control/kagrenac_control.example.json `
  -GameDir "D:/SteamLibrary/steamapps/common/ELDEN RING/Game" `
  -Tools D:/build/kagrenac-elden-control/tools -OutDir D:/build/kagrenac-elden-control/package-ready-20261019
```

| Output | Bytes | SHA-256 |
|---|---|---|
| `event/common.emevd.dcx` | 35472 | `918c20c449fa3c3e76af98f1aa98e201a6b3614a835f4992e17cfe4154e23f06` |
| `script/aicommon.luabnd.dcx` | 143984 | `aada21171b6c4d53399d1158815369f9b990cfc5283274d8dba4dfaec783c67b` |
| `regulation.bin` | 1935520 | `d0d51e383825a07eb9d5020a36cab90db96a84619ce7f1d06f3f35a34218a67b` |

The hashes were checked independently and match `package.json`. merge-events also showed
event 1042378801 is neither defined nor started in the original `m60_42_36_00` (31 events)
and `m60_42_37_00` (9 events) event files, and both `SetCharacterTeamType` commands target
1042370200 (`entity_ok` true). The luabnd files kept their original order; the new entry
went in by id at index 167. The regulation copy
differs only in the new think row 43111190, whose only differing cell from 43111100 is
`logicId` (10000 to 431990); no other regulation file, think row, luabnd file, container
metadata or compression setting changed. An earlier run wrote the same three assets but
hung while writing `package.json`. Under Windows PowerShell 5.1, `ConvertTo-Json -Depth 12`
also serializes the PSPath/PSDrive/PSProvider notes that `Get-Content` adds to each line,
and the `steps.ids` lines came from `Get-Content`, so the output grew about tenfold per
depth level. The builder now reads `inspect.out` with `[IO.File]::ReadAllLines`.

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

## Gatefront checklist

1. Back up your whole save folder first. me3 creates `KagrenacControl.sl2` as a copy of an
   existing save the first time.
2. Play offline, only with this isolated save and profile.
3. Go to the Godrick Soldier (entity 1042370200). Before any press it is hostile, as in
   the vanilla game; be ready for it to attack you.
4. Use the action button on it. No custom prompt text is added; whatever prompt the game
   shows for button row 6000 is what you will see. Record what you actually see.
5. **Follow**: walk away. It should come to you and stop around 2 to 4 m away.
6. **Hold**: press again, then walk away. It should stay put.
7. **Attack**: press again. Only if the Man-Bat (entity 1042360215) is loaded and alive
   does the soldier go after it; otherwise this press is a release. Attack ends by itself
   after 60 seconds.
8. **Release**: press again. The soldier gets its original AI and team back, so it is
   hostile to you again. Step away before releasing.
9. To follow again after hold, go through attack and release, then press once more.

Note for each step what happened, and whether the soldier behaves differently from an
untouched one, then record the result in `docs/engine-packs/elden-ring.md`.

## Limits

- No in-game run, so follow, hold, attack, release and recovery are all unproven.
- Team 47 is not confirmed friendly in the engine.
- The hostile may not be loaded at Gatefront.
- The package is a verified file build only; it has not been installed, loaded or run.
- A reload or warp while controlled restarts the event at idle without a restore; the game
  must rebuild the companion with its original AI and team (not tested).
- The native SDK and DLL backend are not qualified; this route does not use them.
- No voice, LLM or server bridge yet.
