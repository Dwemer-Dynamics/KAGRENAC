# Build records for a new game port

`project.ps1 configure -AllowedActions <names> -Build <folder>` and `pair` accept the following
data-only contract for game ports. Nothing named by a record is executed. Records with any
other schema, including older schema-1 records, are refused: by `pair` before WSL is used, and
by `configure` before any server configuration changes (without `-WslServerPath`, configure
first reads Core's registry through WSL, which can start the distro). This format does not
change the server protocol.

## Build

The port's build command creates an external `builds/<yyyyMMdd-HHmmss>` folder. Its
`build.json` uses schema 2. This illustrative record has placeholder hashes, not test proof:

```json
{
  "schema_version": 2,
  "kind": "kagrenac-port-build",
  "id": "my-mod",
  "engine": "my-engine",
  "build": "20261020-120000",
  "source_commit": "<40 lowercase hex characters>",
  "source_dirty": false,
  "game_build_sha256": "<sha256 of ports/my-engine/game-build.json>",
  "game": { "sha256": "<sha256 of the accepted game executable>" },
  "entrypoint": "client/helper.exe",
  "supported_actions": ["follow_player", "hold_position"],
  "action_handlers": {
    "follow_player": "mod/main.lua",
    "hold_position": "mod/main.lua"
  },
  "files": {
    "client/helper.exe": "<sha256>",
    "mod/main.lua": "<sha256>"
  }
}
```

The game pin is a source file containing at least `sha256` (the accepted executable identity).
The build records both that identity and the hash of the entire pin file, so a pin change
requires a new build. The port's doctor/build must compare the actual installed executable;
the shared CLI checks consistency, not the current game installation.

`files` records 1-128 packaged artifacts by relative slash-separated path and lowercase
SHA-256. No links, traversal, aliases or duplicate Windows paths. `entrypoint` and every
action's handler must be recorded artifacts. `supported_actions` is a unique list of 0-8
action names; an empty list uses `action_handlers: {}`. The server must also have an explicit
handler contract/prompt hint for each configured action; its config helper rejects unknown
names. A record never adds a server handler. Each action remains a candidate until tested in
the game. The agent reviews that the named artifact really implements it.

These are unsigned local provenance records. They detect accidental mismatch and tampering
against the recorded hashes; they cannot prove correctness against an operator who rewrites
the code and all records together. Do not accept downloaded records as trusted code evidence.

## Runtime

The assembled external runtime has `runtime.json` with schema 2, kind
`kagrenac-port-runtime`, the same `id`, `engine`, `build` and `game_build_sha256`, plus the
absolute local `build_dir`. `files` maps runtime-relative paths to hashes. `build_files` maps
those same paths to their original build-relative paths. Stage every build artifact exactly
once, even scripts that are later installed into the game. Private `config.json`, logs,
mailbox files and saves never belong in either artifact map.

For the example above, the runtime can use the same paths:

```json
"files": { "client/helper.exe": "<sha256>", "mod/main.lua": "<sha256>" },
"build_files": { "client/helper.exe": "client/helper.exe", "mod/main.lua": "mod/main.lua" }
```

`pair -OutFile <runtime>/config.json` discovers this runtime record. It checks the build,
every staged artifact and their mapping before writing a new private config. An explicit
`-Build` must name the same build. Repeating a matching pair preserves the existing config
byte for byte; changed action options do not overwrite it. To replace a private config, use
a new explicit output path after reviewing what should change.

For conversation/awareness before any action is built, use `-AllowedActions none` on both
`configure` and `pair`. This needs no `-Build`. If a runtime record is present, pair still
validates it. Omitting the option keeps the legacy follow default. No schema or runtime
record grants permission to install dependencies, alter saves or launch a game.
