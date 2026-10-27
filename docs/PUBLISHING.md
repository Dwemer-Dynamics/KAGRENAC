# Publish a community mod

Keep client and server in one repository. Tell your agent **Prepare this mod for
publishing**. It fills `dwemer-mod.json`, builds the qualified client, reviews the
packages and asks for publication only after there is a concrete release to review.
Existing version 1 branch installs keep working. Version 2 packages need matching
Core and launcher support; do not add version 2 fields to a version 1 manifest.

Before a player install, run **Update Distro** and use a launcher build containing
the community browser. Core's release commands and PHP security helper must both
be installed; a downloaded package alone does not establish distro readiness.
If Core asks for an update, resolve that prerequisite without disabling its checks
or overwriting unrelated local source changes.

## One authored manifest

Use `schema_version: 2`, retain the existing server identity/setup/assets fields and
add the following sections. Paths for setup, health, dashboard and artwork describe
the **installed server**, relative to the selected server root.

Optional `features` lists up to 16 short gameplay descriptions. Optional `testing`
contains a `summary` (author-reported, at most 500 characters) and `evidence_path`,
relative to the repository root, for a committed build/gameplay record. The launcher
links to that pinned source file; it need not be installed. Never label fixture checks
as heard voice or live game acceptance. Feature descriptions do not qualify handlers.

The launcher's mod cards show `name` as the title, `game.name` directly below it and
optional top-level `author` as "By ...". `author` is a plain author or team name of at
most 80 characters (trimmed, no control characters); it is display text, not a
verification. Without it the launcher shows the repository owner. A version 1 manifest
has no game, so none is shown. Installed servers refresh this text on their next update.

```json
"schema_version": 2,
"name": "My Mod",
"author": "My Mod Team",
"game": { "id": "my-game", "name": "My Game", "executable": "Game.exe" }
```

The full `game` and `distribution` sections:

```json
"game": {
  "id": "my-game",
  "name": "My Game",
  "executable": "Game.exe",
  "version": "Author-tested game build",
  "enable_in_game": "Enable the mod in the game's Mods menu."
},
"distribution": {
  "server": {
    "root": ".",
    "include": ["*.php", "lib/**", "ui/**", "sql/**", "config/config.example.php", "scripts/migrate.php"],
    "exclude": ["ui/dev/**", "**/*.map"]
  },
  "client": {
    "root": ".",
    "include": ["**"],
    "exclude": ["**/*.pdb", "**/*.log"],
    "install": {
      "profile": "game-directory",
      "path": "mods/my-mod",
      "config_path": "config.json"
    }
  }
}
```

- Server root may be `.` or a directory such as `server/`. No existing files move.
- Client root is inside the external build directory supplied at package time.
- Includes/excludes are case-sensitive, relative POSIX paths. `*` and `?` match within
  one component; `**` matches zero or more components. Exclusions win. No negation.
- At most 64 patterns per list, 20,000 files and 512 MiB unpacked per package.
- Required config template, migration, health and artwork files must be included.
  The packager adds the release's manifest automatically. Licenses must be included
  wherever their terms require them.
- Known private config/credential files, links and traversal paths are rejected.
  The author must also review the exact ZIP contents for private/custom runtime data.
  Excluding a file from a package does not make a public repository file private.
- The initial client profile describes files beneath a selected game directory and a
  private Kagrenac JSON config there. Use it only for an engine adapter that actually
  reads that format and loads through its native loader. Record that qualification in
  PROJECT.md; the install profile is not evidence that a game adapter works. Do not rely
  on the current launcher to place or pair these files: the mod's loader instructions
  must cover them (see [How players install it](#how-players-install-it)).
- Optional `steam_app_id` enables Steam library detection. Optional `loader_path` must
  exist before install; `loader` explains it. Optional `executable_sha256` enforces an
  exact supported executable. `version` is author-reported compatibility text.
  `enable_in_game` names any remaining mod-manager/load-order step. No arbitrary
  post-install scripts, SDK installs or game launches run from the manifest.

## Build and review

Python 3.11+ is an author tool (standard library only); players do not need it on Windows.
Commit the reviewed source first. Keep the build output and release folder outside source.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/project.ps1 package `
  -ClientDirectory D:\build\my-mod\client -ReleaseVersion v1.0.0 `
  -ReleaseDirectory D:\build\my-mod\releases\v1.0.0
```

This writes `<id>-server.zip`, `<id>-client.zip` and `kagrenac-release.json`, with
the source commit, package sizes, SHA-256 digests and a receipt for every file.
The server is read from committed Git objects, not a dirty working directory.
Inspect both ZIP file lists, then test the packaged server's migrations/health and the
packaged native client. Fixtures are not provider, heard-voice or gameplay evidence.
Run `scripts/smoke.sh` only against a mock-only install with speech disabled. It
checks the configured action allowlist; a text-only mod need not enable follow.
Real providers and native game input/presentation need their own acceptance checks.

## Publish after approval

Use your own public GitHub repository in `project_url`. This never makes a private
repository public. Publication needs authenticated GitHub CLI and the exact repository
authorized by the human; the commit must already exist there.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/project.ps1 publish `
  -ReleaseDirectory D:\build\my-mod\releases\v1.0.0 -ConfirmPublish owner/my-mod
```

The command creates a draft release with both ZIPs and the generated descriptor, publishes
it, then adds topic `kagrenac-mod` without replacing existing topics. Prefer immutable
GitHub releases. Do not republish a version with different bytes. Publishing the topic
opts into the community catalog, not Dwemer endorsement or gameplay verification.

Core installs the server only from the server ZIP, checks every file against its
receipt and never clones client source, docs or tests into Apache. Updates remove only
files owned by the previous package; private configuration, data and unrelated files stay.
If a server update is interrupted, retry that release before selecting another version.

## How players install it

The launcher's community browser lists every public, non-archived GitHub repository with
the topic `kagrenac-mod`, even before it has a suitable release. **Install server** needs
a published stable release with a valid KAGRENAC descriptor and packages; a draft or
prerelease alone leaves the card without an installable release.

1. In the launcher, open **Mods > Custom mods > Browse mods**, select the mod and choose
   **Install server**. Core installs the release's server package and checks its health.
2. Once the server is installed, **Download mod release** downloads the game plugin (the
   client package).
3. The player installs the plugin by following the game's own loader or mod-manager
   instructions, using your `game.loader` and `game.enable_in_game` text and your mod's
   documentation, including how its private config is paired.

The current launcher does not install or pair game files automatically. A server install
alone is not a working mod; in-game acceptance remains after these steps.

A package install does not adopt an existing branch install with the same id. Keep the
developer install separate when testing the player release. Existing branch installs
retain their own update route; include/exclude rules apply to release packages only.
