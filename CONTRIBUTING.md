# Contributing

Start with [AGENTS.md](AGENTS.md) and the rules nearest the files you change. Keep one
behavioral concern per draft PR and preserve existing work. For a new game integration,
qualify the installed game and loader before promising support; use
[engine planning](docs/ENGINE_PLANNING.md).

## Validate the change

- PHP: lint changed files, then run the existing mock smoke checks when server behavior
  changes. Run migrations twice against a disposable database for schema changes.
- Shared C++ client: build x64 and x86 with `client/scripts/build.ps1`, without warnings.
  Exercise the affected lifecycle with the existing checks in [client/README.md](client/README.md).
- Game port: use its maintained build route. Verify its actual serialized requests,
  entity lifetime and native UI/input, not just a handcrafted server request.
- Docs: check file links, heading anchors and every copied command against the current
  script. Do not change a template row that `project.ps1 new` fills without testing creation.

Use existing checks and focused probes first. Do not add a broad test harness by default.
Keep build output and disposable validation artifacts outside the repository and web roots.

## Describe the result

Give the problem, resulting behavior, exact validation and remaining limits. Separate
source, build, fixture, provider and live-game evidence. Include game/loader versions and
normal launch/install instructions for a port. Do not claim voice was heard from a WAV
or gameplay was verified from a log.

Before publishing, inspect the actual diff and staged files. Exclude private configs,
tokens, provider keys, databases, logs, memory exports, paired client configs and personal
paths. Keep licence files and third-party notices. Do not include game binaries, SDKs or
voice samples without an explicit distribution basis.

## Report a problem

Include the KAGRENAC commit, game/loader versions, component, steps to reproduce, expected
result and actual result. Include a request ID, HTTP status and short error code when
available. State whether the failure is a build, fixture, provider or in-game result.
Redact private data; do not attach full configs, databases or conversation logs.
See [SECURITY.md](SECURITY.md) for sensitive reports.
