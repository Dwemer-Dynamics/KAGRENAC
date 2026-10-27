# Make it yours

Start from a copy of [KAGRENAC AI Mod Maker](https://github.com/Dwemer-Dynamics/Kagrenac)
(KagrenacServer at the root, KagrenacClient in `client/`) in your own repository, with your
own branches. Use [guided setup](docs/getting-started.md) first; `project.ps1 new` sets
the manifest identity, named server root and project record. This page is an optional
customization map, not another required setup route. Keep private settings out of Git.
Then use this map for your own project. A copy made with GitHub's **Use this template** has
its own, unrelated Git history: to take later template changes, compare them with your project and copy or adapt
the ones you want by hand. A clone that keeps the template's history can instead keep the
template as an extra remote and merge reviewed updates on a working branch.
`scripts/update.sh` is separate: it updates an installed copy of your own project.

| Change | Edit |
|---|---|
| Project/build name | `client/CMakeLists.txt` (`project`, every `KagrenacClient` target reference including POST_BUILD/TARGET_FILE_DIR), `client/scripts/build.ps1` build folder and output message (and the matching default in `scripts/project.ps1`), the `--version` label in `client/src/main.cpp`, and README commands |
| Server folder/route | `new` sets `server_folder` to `<Name>Server`; Core protects and installs that named root. `pair` resolves the registered route and writes the private `server_url`. Legacy manual routes remain in [SETUP.md](SETUP.md#before-you-install-web-protection); do not move an existing install or hand-edit shared Apache rules as a renaming exercise |
| Database | Server `config/config.php`: set `database.name` to a new lowercase identifier; `install.sh` creates it |
| Manifest (do this first) | Server `dwemer-mod.json`: `new` sets your unique `id`, `name` and `server_folder` before deployment. Core uses database `custom_<id>` and route `/<Name>Server` (legacy: `/custom-mods/<id>`). Add your `description`, `project_url` and `branches`; leave `setup` placeholders intact. See [launcher publishing](LAUNCHER_CUSTOM_MOD.md#making-your-own-launcher-mod-from-this-template) |
| Navbar branding | Server `ui/tmpl/navbar.php` and `ui/tmpl/header.php`: title and icon; replace `ui/images/kagrenac.png` (also the manifest icon and banner, and the README logos) with your own image; keep existing source notices (including `ui/HERIKA-LICENSE`) |
| Colors | Server `ui/css/chim-theme.css`: blue accent variables; search the scoped CSS for remaining blue literals |
| Fictional page samples | Server `ui/examples/` (blank, form, table); unsaved previews. `ui/logs.php` (event log) and `ui/profiles.php` (saved profiles) are working pages, not samples |
| NPC bios and knowledge | Dashboard **NPC bios** page (saved); sample rows in `scripts/seed_example.php`; bulk import of reviewed sources: [content authoring](docs/CONTENT_AUTHORING.md); retrieval limits in `lib/knowledge.php` |
| Session checkpoints | `scripts/checkpoint.php`; match checkpoints to your game saves by the client's `session_id` (SETUP.md section 6) |
| NPC/player/context | `client/src/console_game.h`: `readContext()`; use stable engine NPC IDs when porting |
| Real game integration | `client/src/game_adapter.h` plus your implementation (record engine facts under `docs/engine-packs/`, port notes under `ports/<engine>/`); call it only on the game thread |
| Model behavior | Server `lib/llm.php`: `openai_reply()` system prompt; `mock_reply()` for predictable tests |
| Safe actions | Both allowlists, explicit adapter/handler, `PROTOCOL.md`; see [WAVE_ACTION.md](WAVE_ACTION.md) |
| Private endpoints/keys | Server `config/config.php`, client `config.json` (next to the built exe, outside the repository); never shipped defaults or documentation |
| Your project brief | `PROJECT.md`: brief, integration plan, stages, decisions and latest evidence |
| Your copyright notice | Add your notice to README and `THIRD_PARTY_NOTICES.md` (and `client/THIRD_PARTY_NOTICES.md` for client binaries); keep `LICENSE` (GPL-3.0-only) and every existing and third-party notice |

For local WSL setup, commit your changes and run
`scripts\project.ps1 deploy -WslDistro <name>` from your Windows copy
([getting-started](docs/getting-started.md#deploy-and-pair)); Core creates the folder, the
protection, the private config and the `custom_<id>` database. The manual route still
works: clone your own repository into `/var/www/html/custom-mods/your-folder` as SETUP
describes, choose your own database name, run the installer twice and run smoke checks on
your actual route. Backups and updates use that same configured database.

The agent handoff is [docs/agent-playbook.md](docs/agent-playbook.md),
with [docs/engine-packs/ENGINE_PACK.md](docs/engine-packs/ENGINE_PACK.md) for engine evidence and
[docs/feature-recipes/PORT_RECIPES.md](docs/feature-recipes/PORT_RECIPES.md) for each stage. Give the
agent the repository, your brief (in conversation; it records it in [PROJECT.md](PROJECT.md)) and your actual engine SDK. Keep `GameAdapter`, protocol validation,
worker/main-thread separation, stale replies and both action allowlists intact. Do not
invent engine APIs. Report mock checks separately from real in-game proof.
