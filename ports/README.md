# Game ports

This folder holds your mod's game-specific source, one folder per engine: `ports/<engine>/`.
The template ships no game port and claims support for no game.

- `project.ps1 new -Engine <engine>` records the engine in the new project's PROJECT.md and,
  when `ports/<engine>/PLAN.md` is missing, writes a short starter plan. Qualify it with
  [Engine planning](../docs/ENGINE_PLANNING.md) before writing port code.
- Keep the port's sources, build route, `PLAN.md`, `game-build.json` pin and detailed
  evidence here; record the engine's facts with the
  [engine evidence record](../docs/engine-packs/ENGINE_PACK.md).
- Builds, staged runtimes and paired configs stay outside the repository and every web root
  (PROJECT.md Paths). `configure -Build` and `pair` accept only schema-2
  [build records](../docs/PORT_BUILD_RECORDS.md).
- Deployed copies must deny this folder over HTTP like the other source folders;
  `project.ps1 doctor` probes `ports/README.md` for HTTP 403.
