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
| Loader and lifecycle | What loads the mod when the game is launched normally ([automatic load and connect](#automatic-load-and-connect))? Is that loader cited for this exact build? Where is its callback? How does it stop without leaving game calls running? |
| NPC and player | Which entity is the speaker? How are save, run, entity instance, replacement and death distinguished? |
| Input and display | Which native field, key and input mode make the default in-game composer ([Player input](GAMEPLAY_DESIGN.md#player-input)): free typed text to a recipient shown as "To: <name>", Enter to send, Esc to close? How are game controls captured while it is open and restored on send, Esc, pause, loading, death, recipient unload and focus loss? How is a subtitle shown? Push-to-talk microphone capture only if speech input was asked for |
| Transport and voice | Who owns HTTP and audio? How do results return without blocking a game callback? Is voice positional or only audible? |
| Awareness | Which exact live API supplies each value, in what units and at what time? What will be explicitly unavailable? |
| Each action | What game-owned handler changes state? Which target, instance check, preconditions, cancel and observable result constrain it? |
| Persistence and launch | Where is history/session identity stored? How are saves preserved and offline launch verified? How does a normal launch find the private paired config, and what does the player see while the server is unavailable? |
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
- **Acceptance:** a normal launch that loads and connects by itself
  ([below](#automatic-load-and-connect)), one voiced exchange, an accurate changing
  observation, each requested action, cancel, pause/death/replacement, reload, an unavailable
  server and repeated setup. Mark each separately.

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

Use [readable awareness and actual wire data](feature-recipes/PORT_RECIPES.md#readable-awareness-and-actual-wire-data)
to check the real adapter path, including nested serialization and current self/player/location
facts. A handcrafted request cannot qualify that path.

For the default single repo, use maintained commands: create, commit, deploy, configure providers, build
the port, assemble, configure capabilities, pair and install the game-side mod (with any
helper the mod itself starts). These are developer and one-time setup commands the agent
runs, not steps the player repeats each session. A new port
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

## Automatic load and connect

The finished player flow has two parts:

1. **Once (setup).** The agent installs the game-side mod through a qualified loader or
   in-process route, deploys the mod's own server into the user's DwemerDistro, configures it
   and pairs the game side privately (`project.ps1 deploy`, `configure`, `pair`, and the
   port's build and install route). The agent runs these commands itself; the user runs only
   an installer that needs their own consent or account. Creating a loader profile, or a
   file association or shortcut the user approves, is part of setup.
2. **Every session (play).** The user starts the game through its normal launch (below). The
   mod loads with the game, reads its private paired config, connects to its own server and
   project id, and keeps selection, input, replies, status, errors and cancel inside the game.

**Normal launch.** The game's own entry (its executable, or the Steam or store **Play**
button), or, when the engine needs one, the documented play entry of an established loader
or mod manager that is cited for this exact build and meets the game's offline requirements
(for example a loader profile launched offline). Setting that entry up once is
setup. Not a normal launch: a one-off script, a wrapper or launcher this project wrote,
attaching or injecting into a running game, or a helper the player starts each session.
Never launch a modded game through an anti-cheat-protected or online path to get a "normal"
launch, and never disable or bypass anti-cheat. Do not promise a one-click entry, file
association or shortcut until the loader's own documentation shows it exists.

None of these is a normal per-session player step: a terminal, PowerShell or script command,
attaching or injecting into a running game, a watcher or scheduled task, a separate helper or
chat window, or a launcher the project wrote. Build, install, doctor, check and test
commands remain developer and setup tools.

- **Loader.** Prefer the engine's own mod or plugin support, then an established loader that
  is cited as compatible with this exact build (the executable hash or store build from the
  [survey](#1-survey-the-installation)) and shown by its own load probe. Never invent an entry
  point, export, offset or API. If no qualified route loads the mod on a normal launch, that
  is the missing mechanism: name it, give its next bounded probe and keep stage 6b open. A
  working console client or a manually started helper does not pass this gate. A qualified
  offline loader entry is the established route, not a gap to close by moving to a protected
  online launch. If that entry is still a long printed command, record a shorter entry
  through the loader's own documented features as an open flow-review item, without
  claiming one exists.
- **Hidden helper (only when required).** Use one only when the engine cannot carry HTTP or
  audio in process. The game mod starts it when it loads and stops it on quit; when the
  engine's scripts cannot start processes, the qualified loader's documented sidecar or
  launch hook may start it instead, under the same rules. It belongs to that exact game
  instance and ends when that instance ends, even after a crash. It runs at most once per
  game instance: a second launch, a game restart or a leftover helper is detected and handled
  without stacking helpers or stopping unrelated processes. It has no console or chat window
  and reads only this mod's own private paired config. It never receives a key or token on
  its command line, through the game mailbox or other game IPC, or through any file other
  than that private paired config (no game-readable unprotected file or shared mailbox).
  Neither the helper nor the loader adds an operating-system watcher, service or startup entry.
- **Never block the game.** Game start, loading and play never wait on the network, the
  server, a helper or a provider. A stopped, missing or slow server shows a short in-game
  status, keeps the game responsive, and is checked again when the player next uses the
  mod; turns are still never retried automatically.

- **Nothing global by default.** No Windows startup entry, service, watcher or scheduled
  task, and no change outside the game's mod folder, the mod's runtime folder, the loader's
  profile for this mod, a shortcut the user approved and the mod's own server install. The
  game side never installs or starts the server; the DwemerDistro the user runs hosts it, and
  the mod only reports when it is unreachable. A key is never assumed from another install
  unless the user names that config (`configure -ReuseProviderFrom`).
- **External fallback.** An external window, overlay, companion app or manual start step is
  adopted only after the missing mechanism is named, the tradeoff explained and the user
  approves that scope; record it in PROJECT.md Decisions and the flow review. It is never
  reported as the finished port.

Acceptance, each checked and recorded separately (build, fixture, provider and in-game
evidence stay apart). Stages a copy already marked done keep their status; these checks are
added as extra acceptance or flow-review items, not a reset.

- A normal launch (above), without a per-session command or manual attach, loads the mod (an
  in-game status or a mod log line).
- The first authenticated request succeeds with the paired private config, against this
  project's own install route ([Server folder](getting-started.md#server-folder)); a refused
  token or another mod's route fails the check.
- With this project's route unavailable, the game starts and stays playable and the in-game
  status says so; after the route returns, the next request works. Make only this project's
  route unreachable, for example with a temporary private runtime copy paired to an unused
  port. Make no change to shared Apache, the DwemerDistro, TTS/STT or another mod's install
  unless the user explicitly asks. The unused-port copy is fixture evidence; in-game evidence
  needs the user's own launch.
- When a helper is used, a second launch attempt and a game restart leave at most one per
  running game instance, and quit or a crash leaves none.
- The Gameplay design loop with a real reply in game, its automatic trigger when requested
  without a manual chat step, and heard voice when voice was wanted.

### Installed startup acceptance

Fill this in for every shipped mod, even when its gameplay loop is still awaiting a human
test. An installer, copied DLL or successful helper command alone does not pass it.

| Check | Evidence required before handoff |
|---|---|
| Player entry | Exact game executable or established loader/mod-list entry, plus its one-time install/enable step. No recurring terminal command. A supported game argument for an isolated save profile may be saved in a shortcut; do not replace a native loader with a project-written launcher and call it normal loading. |
| Client transport | Name the in-process HTTP/audio code, or the qualified game/loader callback that starts the hidden helper. Helper spawning must happen outside DLL loader lock. |
| Ownership | Bind a helper to the exact game instance, prevent duplicate starts, and clean up on quit/crash/restart. Validate with a disposable native host when possible; keep actual game lifecycle acceptance separate. Never stop unrelated helpers by executable name. |
| Configured use | Read the existing private pair automatically. A configured mod cannot require `start`, `arm`, `EnableProvider` or a test-only call budget each session. Deliberate in-game enable/stop controls remain valid. Starting transport must not itself call a paid provider. |
| Installed provenance | Build from the reviewed commit, compare the installed DLL/helper/script hashes with the build record, preserve private config and old artifacts, and record the normal entry in the handoff. A source-only fix is not deployed. |
| Failure and repeat | Test duplicate initialization, unavailable helper/server and owned-process exit using proportional fixtures. Then have the human launch normally, quit and launch again. Never start shared servers or install dependencies from a game callback. |

PowerShell build/install/doctor/provider probes belong to the developer checklist, not the
player's everyday instructions. If an engine or incomplete game installation prevents a
qualified normal load, leave the integration gate open with the exact missing mechanism and
next bounded probe. A hidden terminal, desktop shortcut to a wrapper, or standalone diagnostics
do not turn that blocker into a working mod. Record each mod's state independently; a working
startup route in one game is not evidence for another.

## End-of-pass handoff

Before reporting, reconcile the current PROJECT.md stage table, chosen architecture in the
port plan, and flow ledger with what actually ran. Preserve old findings as dated history;
do not leave them as current instructions. If implementation switches from a DLL to an
external helper, update loading, input, display, paths and launch instructions together.

Report these separately:

| Milestone | Required evidence |
|---|---|
| Server-ready | Exact deployed commit, health/protection, configuration and provider test results |
| Port-built | Actual game adapter/helper build, artifact identity, runtime assembly, install into the loader's folder and pairing; distinguish uncommitted source |
| Gameplay-verified | A normal human launch that loaded and connected automatically ([acceptance](#automatic-load-and-connect)), loader compatibility, unavailable-server behaviour, live awareness, heard voice, controls and each action's own result |

Generated audio does not complete heard-voice acceptance. An interruption ends that pass,
not the remaining work: record the last completed check, preserved files and exact next
step. Do not repeat paid tests just to refresh a handoff.

## First-launch guide

Tell the user how to start the game through its normal launch
([automatic load and connect](#automatic-load-and-connect)), including an established
loader's offline entry when the engine needs one, and what in-game status shows the mod loaded and connected; the actual mod-menu
switches and warnings; where the NPC appears; input/send/cancel keys; and one test per action.
Other per-session terminal commands and helper start/stop belong only in a developer section,
or in a fallback the user approved. For a game
requiring unrestricted script I/O, explain its own switch before launch. Do not assume a
settings-file edit survives the game rewriting it. Back up before authorized settings changes
and use the game's own switch when the supported route requires it. Never edit or delete saves.
