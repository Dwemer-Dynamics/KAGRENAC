# Agent playbook: build and review a game port

Use the user's chosen coding agent. Start with [guided setup](getting-started.md) and
[PROJECT.md](../PROJECT.md); this is the focused build sequence once the brief is known.
Do not ask the user to fill another authorization form or repeat decisions.

## Build sequence

1. **Qualify the loop.** Fill Gameplay design and the integration plan from the conversation.
   Inspect the installed game and exact loader/build. Cite real hooks for identity, current
   context, UI/input, transport, audio, actions and normal loading. Resolve unknowns with
   bounded probes. Use [Engine planning](ENGINE_PLANNING.md), not guessed API names.
2. **Prepare independent services.** Create the mod's own identity, commit, deploy, configure
   and pair through [the guided commands](getting-started.md#scriptsprojectps1). Reuse a
   reference port when qualified. Skip paid provider tests or optional voice without
   authority; keep building independent work and report the precise gate.
3. **Prove native integration.** Establish load/unload, real entity selection, the native
   composer and reply display before extending behavior. Keep controls captured only while
   the composer is visible; restore them on close, focus loss, scene/save change and failure.
   The console and `ChatInput` lifecycle do not implement the game's UI.
4. **Connect the first slice.** Send the actual adapter snapshot asynchronously, display
   text first and add requested voice. Check the compiled adapter's wire bytes and a
   round trip, not just handcrafted JSON. Keep request/session/generation/entity identity
   through completion; cancel or drop stale work. See [port recipes](feature-recipes/PORT_RECIPES.md).
5. **Add qualified behavior.** Use the engine's own movement/combat for requested actions.
   Register explicit handlers, validate both allowlists, target and instance, and report
   observed outcomes separately from handler invocation. Automatic events must be relevant,
   bounded, player-preemptible and unable to trigger themselves indefinitely. JEV chooses
   only from a validated, explicitly designed candidate contract; dialogue is not authority.
6. **Review and install.** Review the actual diff in a separate pass, fix findings and rerun
   proportional checks. Install reviewed artifacts once through the qualified loader; pair
   privately. Check the actual installed entry, hashes, helper ownership and automatic
   connection using [startup acceptance](ENGINE_PLANNING.md#installed-startup-acceptance).
   Do not add a per-session terminal command disguised by a shortcut.
7. **Hand off the playable slice.** Give the exact normal/offline launch route and a short
   in-game sequence. Record each evidence level separately in PROJECT.md and the
   [engine pack](engine-packs/ENGINE_PACK.md). The human checks targeting, controls, shown
   reply, heard voice and each requested action. Continue safe independent work around
   unresolved human gates; never claim those gates passed from logs.

## End-of-pass report

- Source branch/commit and actual changes, including uncommitted or interrupted work.
- Server-ready, port-built and gameplay-verified status separately.
- Build/fixture, provider and live-game evidence, with commands or observed steps.
- Installed paths, hashes, exact normal launch entry and connection behavior.
- Remaining mechanism or authority gates, each with a concrete next action.
- Generic KAGRENAC friction versus game-specific limitations in `docs/KAGRENAC_FLOW_REVIEW.md`.

Use existing tests and focused probes. Rebuild the console when shared client code changes;
for an engine-only change, it proves only that the shared library still compiles. The
[wave exercise](../WAVE_ACTION.md), optional memory and advanced profiles are learning or
expansion work, not prerequisites for the first in-game conversation.
