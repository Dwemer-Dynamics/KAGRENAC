# Make it yours

Start from copies of [KagrenacServer](https://github.com/Dwemer-Dynamics/KagrenacServer) and
[KagrenacClient](https://github.com/Dwemer-Dynamics/KagrenacClient) in your own repositories,
with your own branches (for example `main` and `dev`). Run [SETUP.md](SETUP.md) first
(orientation is in [START_HERE.md](START_HERE.md)). Keep private settings out of Git.
Then use this map for your own project. A copy made with GitHub's **Use this template** has
its own, unrelated Git history: to take later template changes, compare them with your project and copy or adapt
the ones you want by hand. A clone that keeps the template's history can instead keep the
template as an extra remote and merge reviewed updates on a working branch.
`scripts/update.sh` is separate: it updates an installed copy of your own project.

| Change | Edit |
|---|---|
| Project/build name | KagrenacClient/CMakeLists.txt (`project`, every `KagrenacClient` target reference including POST_BUILD/TARGET_FILE_DIR), scripts/build.ps1 build folder and output message, the `--version` label in `src/main.cpp`, and README commands |
| Server folder/route | Clone into `/var/www/html/custom-mods/your-folder` (the shared port serves it at `/custom-mods/your-folder`); change the default base URL in server `scripts/smoke.sh` and client `config.default.json` and `src/config.h`, and set the client's private `server_url` to that route |
| Database | Server `config/config.php`: set `database.name` to a new lowercase identifier; `install.sh` creates it |
| Launcher manifest | Server `dwemer-mod.json`: your own unique `id`, `name`, `description`, `project_url`, `branches` and database placeholder; see [LAUNCHER_CUSTOM_MOD.md](LAUNCHER_CUSTOM_MOD.md#making-your-own-launcher-mod-from-this-template) |
| Navbar branding | Server `ui/tmpl/navbar.php` and `ui/tmpl/header.php`: title and icon; replace `ui/images/kagrenac.png` (also the manifest icon and banner, and the README logos) with your own image; keep existing source notices (including `ui/HERIKA-LICENSE`) |
| Colors | Server `ui/css/chim-theme.css`: blue accent variables; search the scoped CSS for remaining blue literals |
| Fictional page samples | Server `ui/examples/` (blank, form, table); unsaved previews. `ui/logs.php` (event log) and `ui/profiles.php` (saved profiles) are working pages, not samples |
| NPC bios and knowledge | Dashboard **NPC bios** page (saved); sample rows in `scripts/seed_example.php`; retrieval limits in `lib/knowledge.php` |
| Session checkpoints | `scripts/checkpoint.php`; match checkpoints to your game saves by the client's `session_id` (SETUP.md section 6) |
| NPC/player/context | KagrenacClient/src/console_game.h: `readContext()`; use stable engine NPC IDs when porting |
| Real game integration | KagrenacClient/src/game_adapter.h plus your implementation; call it only on the game thread |
| Model behavior | Server `lib/llm.php`: `openai_reply()` system prompt; `mock_reply()` for predictable tests |
| Safe actions | Both allowlists, explicit adapter/handler, both PROTOCOL.md files; see [WAVE_ACTION.md](WAVE_ACTION.md) |
| Private endpoints/keys | Server `config/config.php`, client `config.json`; never shipped defaults or documentation |
| Your copyright notice | Add your notice to README and `THIRD_PARTY_NOTICES.md`; keep `LICENSE` (GPL-3.0-only) and every existing and third-party notice |

For local WSL setup, clone your own repository into
`/var/www/html/custom-mods/your-folder` as SETUP describes. Generate the private config,
choose your own database name, run the installer twice and run smoke checks using your actual route. Backups and updates use
that same configured database. Use that database name when restoring or removing it.

The agent handoff is [KagrenacClient/AGENT_PLAYBOOK.md](https://github.com/Dwemer-Dynamics/KagrenacClient/blob/main/AGENT_PLAYBOOK.md),
with [ENGINE_PACK.md](https://github.com/Dwemer-Dynamics/KagrenacClient/blob/main/ENGINE_PACK.md) for engine evidence and
[PORT_RECIPES.md](https://github.com/Dwemer-Dynamics/KagrenacClient/blob/main/PORT_RECIPES.md) for each stage. Give the agent both
repositories and your actual engine SDK. Keep `GameAdapter`, protocol validation,
worker/main-thread separation, stale replies and both action allowlists intact. Do not
invent engine APIs. Report mock checks separately from real in-game proof.
