# AGENTS.md

Guidance for coding agents working on KagrenacClient, the `client/` component of KAGRENAC AI
Mod Maker, or on a mod copied from it. These rules add to the root [../AGENTS.md](../AGENTS.md);
read [../PROJECT.md](../PROJECT.md) for the user's brief before changing anything.

## Keep it simple

- C++17 with the Windows SDK and the bundled nlohmann/json header. Do not add package
  managers, networking frameworks or large dependencies unless the user asks.
- Keep the file layout: game code behind `GameAdapter`, protocol code in `ai_client`,
  settings in `config`, the turn lifecycle in `turn_runtime`, console commands and input in
  `main.cpp`. `ai_client`, `config` and `turn_runtime` form the `KagrenacClientCore` library
  target; keep it free of game and console code.
- Never claim the console example works inside a real game. Only claim engine support after
  testing in that engine.

## Stable boundaries

- **GameAdapter** (`src/game_adapter.h`) is the only code that touches the game. A real
  port implements it with engine APIs and leaves `ai_client` unchanged.
- **Game thread**: only the game thread calls `GameAdapter` and `TurnRuntime`. Network calls
  are blocking and run on `TurnRuntime`'s bounded workers; results come back through its
  mailbox and are applied in `tick()`. Workers never call the game, including during
  `shutdown()`. Real engines usually crash or misbehave when touched from other threads.
- **Stale replies**: the runtime remembers the `request_id` it waits for and ignores any
  other reply. `cancel()` clears it and tells the server; cancels are serialized per session
  and NPC. Keep both. Before applying a reply, its actions or its voice,
  `GameAdapter::isSameNpc()` must confirm the captured NPC is still there; never retry a
  failed turn automatically. An action's `args.target_id` must equal that NPC.
- **Actions**: an action runs only if it is in the client's `allowed_actions` *and* the port
  registered a handler for that exact name with `TurnRuntime::setActionHandler()`. With no
  handler, it is rejected (fail closed). Never map action names to console commands, scripts,
  file paths or anything generic. Text and actions are applied once, before optional voice;
  a voice completion never reruns them.
- **Protocol** ([../PROTOCOL.md](../PROTOCOL.md), the single copy shared with the server):
  `"protocol": 1`. Check the reply's shape before using it, as `sendTurn()` does. Bump the
  version in the server and the client together for incompatible changes.
- **Config**: shipped defaults in `config.default.json`; secrets only in the untracked
  `config.json`.
- **Voice is optional**: text first; voice is made after the subtitle and actions, and is
  played only if its turn was not cancelled or replaced, the session is unchanged and the
  NPC is still the same instance. On any voice failure keep the subtitle or let the
  player type, and say so. Never report voice success without a WAV file. If the user
  wants voice, start with PocketTTS for TTS and Parakeet for STT (the recommended
  DwemerDistro choices) before the supported alternatives. Do not assume they are installed
  or running: within the scope the user has authorized, verify the services are available
  and running before enabling or testing voice, then verify them on the server.
- **Third-party code**: keep `third_party/nlohmann/LICENSE.MIT`. Do not edit `json.hpp`.

## Checks before finishing

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build.ps1   # in client/; x64 and x86, must have no warnings
```

Build only in the Windows development copy, with output outside the repository (the script's
default). Never build, or write `config.json`, inside the server copy in Apache's web root.

Then, with KagrenacServer running in mock mode, run the table in README "Smoke checks" for
the architectures you changed. Report what ran, and what was not tested (real engine,
voice services).
