# Plan the game integration before building it

Start with the user's game, starting feature and mod name, and the Gameplay design the agent
fills from the conversation ([Gameplay design](GAMEPLAY_DESIGN.md)); the plan serves that loop.
The agent fills in the rest from the installed game and primary sources; do not hand the user
a research form. Record the
short decision in PROJECT.md and the evidence in `ports/<engine>/PLAN.md`. Use the current
coding agent to build, test, review the actual diff in a separate pass, fix and retest. An
external worker is optional only when the user requests one; it is not a setup prerequisite.

## 1. Survey the installation

Record the edition, store app/build, executable path, architecture and SHA-256; engine and
runtime (for example Unreal, Unity Mono/IL2CPP or Lua); installed loaders, their versions and
existing mods; saves and configuration paths; and the user's intended offline launch route.
Inspect before installing or replacing anything. A loader file or an old log is not evidence
that it runs on the current build. A separate character is not necessarily a separate save.

Use [the tool catalogue](research/MODDING_TOOLS.md) as a shortlist, then read the selected
tool's current upstream docs and compatibility list. Prefer the shipped SDK or scripting API,
then an established loader/reflection API, then a bounded native investigation. Do not start
by inventing offsets or copying a different game's bridge.

## 2. Map the requested feature to mechanisms

For each row, give an exact file/function/property or primary-source link, the game build it
applies to, the permitted thread/callback, the planned check and what remains unknown.

| Required part | Questions the plan must answer |
|---|---|
| Loader and lifecycle | What loads the mod? Where is its callback? How does it stop without leaving game calls running? |
| NPC and player | Which entity is the speaker? How are save, run, entity instance, replacement and death distinguished? |
| Input and display | How does a line enter the mod, how is a subtitle shown, and how are player controls restored? |
| Transport and voice | Who owns HTTP and audio? How do results return without blocking a game callback? Is voice positional or only audible? |
| Awareness | Which exact live API supplies each value, in what units and at what time? What will be explicitly unavailable? |
| Each action | What game-owned handler changes state? Which target, instance check, preconditions, cancel and observable result constrain it? |
| Persistence and launch | Where is history/session identity stored? How are saves preserved and offline launch verified? |
| Automatic trigger (if requested) | Which game event starts it, how is it bounded, and how does player input preempt it? Which participants and listeners can the game read? |
| First demo | What five-minute in-game sequence shows the user's actual feature and its Gameplay design loop, not a console simulation? |

Asset names are research leads, not callable APIs. A last-rested bonfire is not current
location; an enemy tag is not verified hostility; a saved roster is not live nearby actors.
Keep observations separate from lore, guesses and advice. The model never supplies executable
commands, function names or arbitrary targets.

Keep the player's interaction within the game. Investigate native menus, widgets, subtitles
and input APIs first, then supported in-process UI/render hooks. Selection, text entry,
reply display, errors and cancel should not require switching to a separate desktop window.
An always-on-top desktop overlay is still an external fallback. Qualify focus capture and
restoration, menu conflicts, resolution/fullscreen behavior and scene/unload lifetime.

Use external resources only where an appropriate game-side mechanism is unavailable.
An external transport or audio helper may run in the background without becoming the
player-facing UI. Document why each external component is necessary. If only an external
interaction window is feasible, explain the exact blocker and tradeoff before adopting it;
do not silently change the expected in-game experience to finish the prototype.

## 3. Resolve unknowns with bounded probes

For each unknown, name the sources or probe, its stopping point and the result needed. A
small read-only reflection or loader probe can be the next step once its mechanism, safety
boundary and acceptance are written down. It is a qualification tool, not a replacement demo.
Use a disposable output folder; record build-specific evidence without distributing game files.

Choose among concrete options: an in-engine script/plugin, a small native adapter, or a
script plus an external helper (see [script engines](feature-recipes/PORT_RECIPES.md#script-engines-and-an-external-helper)).
Select the simplest supported route. Do not silently turn a requested physical companion
into a disembodied narrator. If the requested action cannot yet be qualified, keep its
blocker explicit while continuing the independent server/provider setup.

## 4. Write the readiness decision

Before game-port implementation, the agent records:

- **Chosen architecture:** loader, callback, speaker, transport, input, display and voice.
- **Repository layout:** one repo by default; record an explicitly chosen client/server
  split and its shared-code/build/deploy plan before creating it
  ([layout options](getting-started.md#repository-layout)).
- **Qualified facts:** build-specific citations and probe results, with their limits.
- **Unknowns and next probe:** owner, stopping point and what independent work can continue.
- **Initial capabilities:** readable fields and explicit action handlers; no action is a valid
  first-stage capability list (`configure` and `pair -AllowedActions none`). An omitted option
  retains its documented default and does not mean none.
- **Acceptance:** one voiced exchange, an accurate changing observation, each requested action,
  cancel, pause/death/replacement, reload and repeated setup. Mark each separately.

Stage 2 is ready when the selected thin slice has a concrete cited route and the remaining
unknowns have a chosen bounded test. A missing critical mechanism blocks that slice, not the
entire project. Do not mark the plan done merely because a reference was copied. The agent
reviews the plan against the user's brief and proceeds within existing authority; there is
no extra approval ceremony. Commits for the independent server/setup may happen before the
game integration is ready.

Name the next missing mechanism precisely: for example, friendly entity creation, a stable
instance handle or a per-NPC movement call. Give the next probe, stopping point and evidence
needed. Additional server checks cannot qualify that mechanism. Do not replace a blocked
physical companion with a narrator or mark the requested mod complete because its server
works. A probe needing a live game stays pending until the human launches it.

## 5. Build and review the first slice

For the default single repo, use maintained commands: create, commit, deploy, configure providers, build
the port, assemble, configure capabilities, pair, install and start any helper. A new port
can use [generic capability records](PORT_BUILD_RECORDS.md) without changing the shared CLI.
Its route owns game-specific preflight, packaging and install checks. Print complete next
commands with literal paths, project id and distro; never require copying a token.

Label inherited console-client builds separately from a game-port build. Test conversation
with empty allowlists rather than enabling a simulated action to satisfy a smoke check.
Before an endpoint suite, check that dialogue, voice, decisions, embeddings and automatic
memory cannot make an unintended provider call. A real provider test is a separate,
authorized check.

For awareness, record capture time or sequence, units, source and maximum age. A recently
received heartbeat is not necessarily a snapshot captured for this turn. Either request a
new capture before sending or describe its actual age and reject expired observations.

Test locally with mocks first, then one authorized provider/voice test, then a human-launched
game test. Capture the exact code commit and artifact hashes. Review the actual diff in a
separate pass for stale replies, controls, entity replacement, cancellation ordering, keys,
file handling and repeated setup. Fix findings and rerun the checks they affect. Generated
audio is not heard audio; an accepted handler is not observed movement.

Keep `docs/KAGRENAC_FLOW_REVIEW.md` in the mod with: stage, expected command/result, actual
evidence, workaround, minimal upstream improvement, generic versus engine-specific, and
first/repeat outcome. Keep successful build/provider evidence even when an engine hook is
blocked. End with a short prioritized list that can be reviewed back into the template.

## End-of-pass handoff

Before reporting, reconcile the current PROJECT.md stage table, chosen architecture in the
port plan, and flow ledger with what actually ran. Preserve old findings as dated history;
do not leave them as current instructions. If implementation switches from a DLL to an
external helper, update loading, input, display, paths and launch instructions together.

Report these separately:

| Milestone | Required evidence |
|---|---|
| Server-ready | Exact deployed commit, health/protection, configuration and provider test results |
| Port-built | Actual game adapter/helper build, artifact identity, runtime assembly and pairing; distinguish uncommitted source |
| Gameplay-verified | Human-launched loader compatibility, live awareness, heard voice, controls and each action's own result |

Generated audio does not complete heard-voice acceptance. An interruption ends that pass,
not the remaining work: record the last completed check, preserved files and exact next
step. Do not repeat paid tests just to refresh a handoff.

## First-launch guide

Give exact helper start/stop and game launch commands; the actual mod-menu switches and
warnings; where the NPC appears; input/send/cancel keys; and one test per action. For a game
requiring unrestricted script I/O, explain its own switch before launch. Do not assume a
settings-file edit survives the game rewriting it. Back up before authorized settings changes
and use the game's own switch when the supported route requires it. Never edit or delete saves.
