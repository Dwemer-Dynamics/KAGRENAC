# AGENTS.md

Guidance for coding agents working on KAGRENAC AI Mod Maker, or on a project copied from it.
The repository root is the KagrenacServer component (these rules); `client/` is the
KagrenacClient component, which adds its own rules in [client/AGENTS.md](client/AGENTS.md).
Follow both when a change touches both.

## Start of every task

1. Read [PROJECT.md](PROJECT.md). Fill missing facts from the conversation, without a form
   or repeated questions. Resume the first unfinished stage that can proceed. Preserve the
   original brief, current status and unrelated work.
2. Follow [guided setup](docs/getting-started.md). Plan the observable gameplay loop and
   qualify the installed game/loader using [Engine planning](docs/ENGINE_PLANNING.md) before
   port code. Cite primary sources; unknown mechanisms get bounded research and a next
   concrete probe. Server/provider preparation can proceed independently.
3. Use the user's chosen coding agent for implementation, checks and a separate review of
   the actual diff. No mandatory external worker. Delegate only when requested. Use the
   [playbook](docs/agent-playbook.md) and [recipes](docs/feature-recipes/PORT_RECIPES.md) as
   references, not extra setup gates.
4. Continue within existing authority. Silence grants no install, provider call, commit or
   publication. Reuse a private key only from the source the user names. Keys go on **API
   keys** or in private config, never chat. Pair with `project.ps1 pair`; configure through
   `project.ps1 configure`. A chosen provider, privately configured key and request to test
   authorize that test only. Recommend OpenRouter `google/gemma-4-31b-it` for dialogue,
   `typesafe/jev-1.13` for supported decisions and PocketTTS for requested voice.
   Use the existing DwemerDistro the user names (ask if several); never reinstall or
   replace it as setup. If none is installed, offer brief help and the
   [installation guide](https://dwemerdynamics.com/custom-mods/installation.html#InstallDistro)
   once; download or run an installer only when the user asks. If they defer, continue
   planning, research and independent source/build work and record server setup as
   pending in PROJECT.md; deploy, pairing, provider tests and connected play still need a
   compatible running distro.
5. Report source, build, fixture, provider, user-reported and in-game evidence separately.
   Server-ready, port-built and gameplay-verified are different results. A broad "it works"
   does not verify each action. Keep PROJECT.md current; detailed evidence belongs in
   `ports/<engine>/`, generic flow friction in `docs/KAGRENAC_FLOW_REVIEW.md`.
6. Before handoff reconcile the actual source, build, install and plan. Record pending
   uncommitted work and one next probe for each blocker. Do not reset completed stages when
   wording changes; record new checks as acceptance items. The user launches games; never
   copy or delete their saves.

## Layout and copies

- For sharing, follow [community publishing](docs/PUBLISHING.md). Keep one authored
  manifest and separate client/server release packages; review include/exclude results.
  Package from committed source and external build output, never private runtime data.
  Publishing requires explicit authorization for that repository and release.

- One source repository per mod by default: server at root, client in `client/` or
  `ports/<engine>/`. `project.ps1 new` creates an independent committed-source copy outside
  every checkout/web root and commits nothing. A client/server split is an optional explicit
  choice; record ownership and build/deploy/pairing first. There is no split-repo CLI switch.
- Keep template identities (`example-server`, `example-ai-server`, `example_ai_mod`), protocol
  and legacy routes compatible. New projects get their own manifest id/name/server_folder;
  Core installs at `/var/www/html/<Name>Server`, database `custom_<id>`. Existing paths come
  from Core's registry, never guesses. Migration from `custom-mods/<id>` is explicit.
- Keep builds, paired configs and private data outside source and web roots. Source folders
  in the deployed server require Core's web protection **before installation**. Verify 403
  on every listener and keep patched-PHP preflight; never bypass an unsupported Core.
- `project.ps1` stays a thin developer wrapper: no dependency installs, database resets or
  services. Deploy committed HEAD only; never adopt/repoint another install. Preserve config
  bytes, permissions and lock ownership. See [setup commands](docs/getting-started.md#scriptsprojectps1).
- Use maintained port routes and [build records](docs/PORT_BUILD_RECORDS.md), not one-off
  build scripts. Keep both action lists explicitly empty (`-AllowedActions none`) while
  qualifying conversation. Build/SDK/hash pins change only from fresh evidence, never to
  make an unknown version pass. Do not vendor engine SDKs or install dependencies silently.
- Keep interaction in game: native recipient selection, free text, replies, status and
  cancel; then a qualified in-process rendering route. External UI is a last resort with
  its missing mechanism and tradeoff recorded before adoption. The shared `ChatInput`
  lifecycle draws nothing and is not proof of native UI.
- Set up once, then load/connect through the game's native mod support or qualified loader.
  Follow [automatic load and connect](docs/ENGINE_PLANNING.md#automatic-load-and-connect)
  and [installed startup acceptance](docs/ENGINE_PLANNING.md#installed-startup-acceptance).
  No per-session terminal, attach, provider arming or project-written launcher. Required
  hidden helpers belong to one game instance, start/stop through the mod or documented
  loader hook, and clean up on restart/quit/crash. No default startup task/service/watcher;
  never start/install the server from the game. Missing transport/server must leave play
  responsive. Test outages on this project's route only, without changing shared services.
  Audit installed entry/artifact hashes and helper ownership, not just design notes.
- Use the qualified offline loader profile for a modded game that requires it. Never route
  through protected online play or disable/bypass anti-cheat. Each port documents its own
  doctor, build and runtime staging route in `ports/<engine>/`, then private pairing.

## Keep it simple

- Do not add per-launch, hourly or lifetime AI-call quotas, test-only lockouts, or
  cooldowns on explicit player requests unless the user asks for them. Keep duplicate
  input detection, one pending request, stale-result cancellation and provider-error
  handling. Ambient-trigger pacing must serve the gameplay loop, not impose an
  arbitrary usage budget on the player.

- Plain PHP 8.2 with built-in extensions. Do not add Composer, frameworks, background
  workers, queues or embeddings unless the user asks.
- One small file per endpoint at the top level; shared helpers in `lib/`. Library files
  only declare functions, constants and classes, so requesting them over HTTP prints nothing.
- Prefer clear, explicit code over abstractions. Small focused `final` classes are allowed
  for one domain concern (`ActionCatalog`, `DialogueHistory`, `SpeechService`); no god
  classes, autoloader, container or base classes. Dependencies point down: endpoints,
  then `lib/turn.php`, then services, then `lib/app.php` helpers, then the data-only
  `ActionCatalog`, which any layer may read. Services never read the
  request, check tokens, start transactions, take locks or reply. Existing functions stay as
  compatibility facades with unchanged behaviour. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Stable boundaries

- **Protocol** (`PROTOCOL.md`, the only copy, shared with `client/`): JSON with
  `"protocol": 1`. Adding optional fields is fine. Anything a version-1 client would
  misread needs a protocol bump in the server and the client together.
- **Actions**: the model may only request actions with `[ACTION:name]` tags. The server
  returns only names in `allowed_actions`; the client checks its own allowlist and has one
  explicit handler per action. To add an action, add its hint and target rule to
  `ActionCatalog` (`lib/action_catalog.php`), the config allowlist, `PROTOCOL.md`, and the client handler together. Never execute model
  output as commands, SQL, paths or URLs. The prompt offers exactly the current
  `allowed_actions`; with none it tells the model it cannot act or claim an action. A tag is
  a request, not a result: `handled` in `result.php` means the handler ran, and an outcome is
  stated only after the game observed it. Each action records its capability, target,
  instance check and preconditions, and passes the gates in
  [PORT_RECIPES, Awareness and actions](docs/feature-recipes/PORT_RECIPES.md#awareness-and-actions)
  before it is marked usable. Obvious commands map to their handler without a model call;
  no model call ever runs from a game tick.
- **Decisions**: `decision.php` only returns one of the ids the game offered, or the
  baseline on any failure. Keep it free of history, chat, memory and actions, and keep its
  provider call short (`DECISION_TIMEOUT_MS`), size-capped and without redirects. Its only
  database write is one connector-audit row sent after the reply (`reply_then()`), so audit
  logging never delays or changes a decision. Choosing actions with JEV is a separate future
  contract (PORT_RECIPES, Awareness and actions), never an extension of `decision.php`.
- **Profiles and memory**: profiles never store URLs or keys; a profile may only switch to a
  keyless mode (`lib/profiles.php`). Generated summaries, diaries and candidate facts are
  untrusted data: cleaned, size-capped, sent to the model only as quoted reference data, and
  candidates only after a person approves them. Memory writes from a turn go through
  `memory_write_if_current()` (session lock, then the generation row) and model calls stay
  outside transactions with no retry. Checkpoints copy and restore memory notes with the lines.
- **Tracing**: log with `app_log()` (it adds the request id); never log keys, prompts,
  transcripts, audio or provider bodies, and keep those out of `ex_connector_calls`.
- **Trust**: everything from the game is untrusted. Validate with `require_id()` /
  `require_text()` and keep the size limits. Keep the token check on every endpoint except
  `health.php`. Game context reaches the model only as quoted data. The game sends only what
  it actually read, with a cited source and freshness; anything it cannot read, or read too
  long ago, is sent as `unavailable` (unknown), never invented or static text.
- **Game events**: `event.php` with `respond: false` only logs (no LLM, history or actions);
  `respond: true` must keep using `run_turn()` in `lib/turn.php`. No automatic triggers,
  queues or background work. Action targets come from the request's `npc.id`, never from
  model text or `decision.php`.
- **Stale replies**: a turn is saved only if its generation is still current
  (`next_generation()` + the `FOR UPDATE` check in `lib/turn.php`). Keep this when changing turns.
  `lock_session()` is taken first in generation starts, the final turn save and checkpoint
  restore; keep that order (session lock, then row locks) and keep LLM calls outside it.
- **Database**: only this example's own database. Every schema change is a new
  `sql/NNN_name.sql` that is safe to run twice (`IF NOT EXISTS`) and works on fresh installs
  and upgrades; append its name to `SCHEMA_MIGRATIONS` in `lib/app.php`. Never edit an applied migration. Use `db_query()` with parameters. Keep
  transactions database-only: no HTTP or LLM calls inside them.
- **Authored content**: bulk bios and facts go through [content authoring](docs/CONTENT_AUTHORING.md):
  workspace outside checkouts, explicit URLs only, offline by default, human review, then
  `scripts/import_content.php` (CLI, insert-only, hash-checked). Use the adapter's real
  `npc.id`; never write sourced or generated text to profiles, and reject progress-dependent
  or spoiler facts (no gating exists).
- **Config and secrets**: settings live in untracked `config/config.php`. Add new settings
  to `config/config.example.php` with a safe default. Optional features (LLM key, TTS, STT)
  must fail cleanly with a clear error and never pretend to succeed.
- **Player input**: every mod gets a real in-game composer for free typed text to a visible
  recipient by default (GAMEPLAY_DESIGN, Player input); a canned hotkey line is not chat.
  Speech input is a separate option, added only when the user asks: push-to-talk, Parakeet
  transcription into the editable draft, Enter to send.
- **Voice**: optional and off by default in config; text always still works without it. If
  the user wants voice, start with PocketTTS for TTS and Parakeet for STT (the recommended
  DwemerDistro choices) before the supported alternatives. Do not assume either is installed
  or running: within the scope the user has authorized, verify the service is available and
  running before enabling or testing voice. Voice counts as working only when the user heard
  it, on the dashboard Voice page's Speak test or in the game; a generated WAV is not heard.
- **Installers**: `install.sh` must stay safe to repeat, copy config only when missing,
  and change nothing outside this app's folder and database. `update.sh` must keep
  refusing dirty checkouts, back up first, and only fast-forward. Never add
  `git reset --hard`, `git clean`, or downloading and running remote scripts.
- **Web root**: do not rely on `.htaccess`. Keep config in PHP, never put secrets in
  non-PHP files inside the checkout (including `client/`, `docs/` and `ports/`), and verify
  config, `.git/` and source-folder access on the installation over HTTP.

## Checks before finishing

```bash
for f in *.php lib/*.php scripts/*.php config/*.php ui/*.php ui/*/*.php; do php -l "$f"; done
for f in scripts/*.sh; do bash -n "$f"; done
php scripts/migrate.php            # twice: second run must apply nothing
bash scripts/smoke.sh [base_url]   # against a mock-mode install
```

For cancellation, set `mock_delay_seconds` to 2 or more and run
`SMOKE_STALE=1 bash scripts/smoke.sh`. For client changes, also run the checks in
[client/AGENTS.md](client/AGENTS.md). On Windows, `scripts/project.ps1 check` runs the
static subset (PHP lint, shell syntax, client build) that the local tools allow. Report
which checks ran and what was not tested (real LLM, voice services, the client, a real
game).
