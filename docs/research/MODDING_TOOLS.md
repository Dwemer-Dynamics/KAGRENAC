# Modding and reverse-engineering tool catalogue

Checked against upstream GitHub repositories on **2026-10-20 (local time)**. Stars, last-push
dates and archive flags below are a discovery snapshot, not a compatibility score. Recheck
the selected release, supported games/versions, architecture and licenses for each mod.
Use links and local investigation notes; do not vendor these projects or copy their code
into KAGRENAC. No tools are installed by this catalogue.

## Find the right layer

| Game/runtime | First investigation | What it can establish | What still needs a game-specific check |
|---|---|---|---|
| Shipped script API (Lua, etc.) | Installed API/component docs and stock examples | Supported callbacks, entity reads and script actions | I/O permissions, input focus, dynamic audio, pause/save lifetime |
| Unreal Engine | UE4SS runtime reflection; FModel/CUE4Parse for packaged assets | Reflected classes/properties/functions; separately, asset names and structure | Exact shipping build, mappings, live NPC identity/friendliness, callable movement and game thread |
| Unity Mono/IL2CPP | BepInEx or MelonLoader after runtime/architecture inventory; AssetRipper for assets | Candidate plugin/hook and asset workflow | Correct runtime variant, supported loader release, object lifecycle and player/NPC APIs |
| RE Engine | REFramework and its supported-game docs | Candidate scripting/plugin and reflected runtime route | Game/version-specific hooks and safe entity/action calls |
| Souls games | Smithbox/WitchyBND for game data; a loader explicitly supporting the exact title/edition | Map/param/event data and separately a launch/loading mechanism | Edition, offline enforcement, save isolation and runtime companion control |
| Unknown native engine | Ghidra static analysis, then a bounded x64dbg/Frida probe if needed | Candidate types/functions and observed behavior on the exact executable | Thread ownership, lifetime, safe invocation and update compatibility |

An asset editor does not provide a runtime NPC API. A loader does not provide AI movement.
An address/signature belongs to one qualified build until proven otherwise. Begin with the
least invasive documented mechanism that can deliver the requested feature.

## Current upstream shortlist

| Repository | Use in planning | Stars (approx.) | Last push | State / GitHub license metadata |
|---|---|---:|---|---|
| [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) / [docs](https://docs.ue4ss.com/) | Unreal Lua/C++ modding, runtime reflection, SDK/property inspection | 3,000 | 2026-10-17 | Active, MIT |
| [REFramework](https://github.com/praydog/REFramework) / [docs](https://cursey.github.io/reframework-book/) | RE Engine scripting, plugins and runtime inspection | 5,700 | 2026-10-11 | Active, MIT |
| [BepInEx](https://github.com/BepInEx/BepInEx) / [docs](https://docs.bepinex.dev/) | Unity/XNA plugin and patching route; select the runtime variant | 8,900 | 2026-10-20 | Active, LGPL-2.1 |
| [MelonLoader](https://github.com/LavaGang/MelonLoader) | Unity Mono/IL2CPP loader alternative; qualify rather than stack loaders | 4,300 | 2026-10-20 | Active, Apache-2.0 |
| [AssetRipper](https://github.com/AssetRipper/AssetRipper) | Inspect Unity assets and serialized structure | 8,700 | 2026-10-20 | Active, GPL-3.0 |
| [FModel](https://github.com/4sval/FModel) | Browse Unreal archives/assets; check required version mappings | 3,300 | 2026-10-18 | Active, GPL-3.0 |
| [CUE4Parse](https://github.com/FabianFG/CUE4Parse) | Unreal package parsing library behind inspection workflows | 660 | 2026-10-20 | Active, Apache-2.0 |
| [Smithbox](https://github.com/vawser/Smithbox) | Souls map, param and related data editing; verify the specific game's support | 740 | 2026-10-01 | Active, MIT |
| [WitchyBND](https://github.com/ividyon/WitchyBND) | Unpack/repack supported FromSoftware formats | 275 | 2026-07-06 | Active, GPL-3.0 |
| [me3](https://github.com/garyttierney/me3) / [docs](https://me3.help/) | Game instrumentation/mod-loading profiles; consult the supported-game list | 650 | 2026-10-14 | Active, Apache-2.0 |
| [Ghidra](https://github.com/NationalSecurityAgency/ghidra) | Static disassembly/decompilation and annotated build-specific findings | 92,000 | 2026-10-20 | Active, Apache-2.0 |
| [Frida](https://github.com/frida/frida) / [docs](https://frida.re/docs/home/) | Bounded dynamic instrumentation to qualify candidate runtime behavior | 22,000 | 2026-10-20 | Active, metadata inconclusive; inspect component licenses |
| [x64dbg](https://github.com/x64dbg/x64dbg) / [docs](https://help.x64dbg.com/) | Windows native debugging and observation | 50,000 | 2026-10-20 | Active, metadata inconclusive; inspect upstream LICENSE |
| [Mod Engine 2](https://github.com/soulsmods/ModEngine2) | Historical loader documentation, only for its explicitly supported titles | 1,100 | 2024-07-19 | **Archived**, MIT |
| [DSMapStudio](https://github.com/katalash/DSMapStudio) | Historical map/editor evidence; inspect Smithbox first for current work | 173 | 2023-06-16 | **Archived**, MIT |
| [Original Mod Engine](https://github.com/katalash/ModEngine) | Historical game-specific file-replacement/injection lead | 77 | 2020-03-04 | Not archived but old; no license detected by API |

Activity means repository activity, not a tested stable release. License labels are API
metadata, not a complete license audit or permission to redistribute game assets. Check
the selected component's upstream LICENSE before incorporating a dependency.

## What to record for a selected tool

In `ports/<engine>/PLAN.md`, keep: upstream repo and documentation link; release/tag/commit
and checked date; license and intended use (external tool versus runtime dependency); exact
supported game/edition/runtime/architecture; the local path/version found; existing mods to
preserve; a named loader/API probe and its evidence; known incompatibilities; rollback; and
which requested feature it actually enables. Cite exact local SDK files or source symbols.

Refresh these facts when the game or tool changes. Keep API excerpts short and necessary;
link to primary documentation instead of maintaining a second copy. No game binaries,
extracted assets, keys, saves or SDK dumps belong in the public knowledge base.

For a Souls companion, qualify body identity, AI control, target selection, offline launch
and save isolation separately. For an Unreal conversation, qualify a live friendly NPC and
its lifecycle before any movement call; a class name in an archive is only a lead. For a
script familiar, qualify callbacks and I/O first, then the helper bridge and audio. The
shared workflow is [Engine planning](../ENGINE_PLANNING.md).
