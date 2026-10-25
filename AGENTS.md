# AGENTS.md

Guidance for coding agents working on KAGRENAC AI Mod Maker, or on a project copied from it.
The repository root is the KagrenacServer component (these rules); `client/` is the
KagrenacClient component, which adds its own rules in [client/AGENTS.md](client/AGENTS.md).
Follow both when a change touches both.

## Start of every task

Use the user's chosen coding agent for implementation, tests and a separate review of the
actual diff. There is no mandatory external worker or model-specific setup. Delegate only
when the user asks. Follow [Engine planning](docs/ENGINE_PLANNING.md) before game-port code;
use [the tool catalogue](docs/research/MODDING_TOOLS.md) as leads, never compatibility proof.
Track first-run/repeat friction in the mod's `docs/KAGRENAC_FLOW_REVIEW.md` with evidence,
minimal proposed fixes and generic versus engine-specific scope. Preserve the original brief.

1. Read [PROJECT.md](PROJECT.md) and resume at the first stage in its Stages and readiness
   table that is not done and is ready to work on; that table is the one current status.
   If it is blank or incomplete, fill it in yourself from the conversation and the user's
   earlier instructions; never send the user a form or ask them to confirm what they
   already said. A blocked stage does not freeze the rest: record what blocks it and the
   next action, tell the user, and say which independent stages you continue with.
2. Follow the route in [docs/getting-started.md](docs/getting-started.md): ask only for what
   is missing of game, starting feature and mod name, and write the integration plan in
   PROJECT.md before building mod code. Fill its Gameplay design from the conversation too
   ([Gameplay design](docs/GAMEPLAY_DESIGN.md)): the loop the player will see and hear, not
   only a chat. A copy made before that section existed gets it added, keeping its status and
   work. DwemerDistro, server install, client checks, LLM and voice setup do not wait
   for either. Do not replace the user's goal with a different demo.
3. Inspect real capabilities before promising anything: this repository
   ([README.md](README.md#what-works-today)), the one DwemerDistro the user named
   (`scripts/project.ps1 doctor -WslDistro <name>`; diagnostic only, and a service the user
   did not choose, such as port 1234 beside OpenRouter, blocks nothing), any reference port
   already in `ports/<engine>/` (reuse it), and what the engine's SDK and files
   actually offer. Cite every engine fact; never invent an API or address. For an unknown,
   do bounded research with a stated stopping point, then summarize two or three concrete
   options with a recommendation; it is a short step, not a detour.
4. Permissions the user already gave stay in force: continue routine, reversible setup
   within them without asking again. Do the service, dashboard and browser work yourself
   when you have the tools and that authority; only when a step is a GUI you cannot drive,
   give the user its exact steps. Silence never grants a side effect (installs, provider
   calls, commits, publishing); ask only for a missing provider, key or install that needs
   the user's information. A chosen provider, a key the user set up privately and a request
   to test it authorize that test, and no other paid call. Keys go on the dashboard **API
   keys** page or in the private `config/config.php`, never in chat; pair with
   `project.ps1 pair` so the user never copies a token. Set the provider, voice and server
   allowlist with `project.ps1 configure` (nonempty actions only against a verified `-Build`
   or with `-ConsoleClient`; `-AllowedActions none` needs neither; a key is reused only from a config the user names with
   `-ReuseProviderFrom`); its `-TestProviders` is one such authorized test. Reuse a provider the user already
   configured; otherwise recommend OpenRouter `google/gemma-4-31b-it` for dialogue,
   `typesafe/jev-1.13` only for `decision.php` choices, and PocketTTS for voice.
5. Mock mode and the console client are developer checks, not the user's demo; the
   console's follow is a printed simulation. A full port records evidence in a copy of
   [docs/engine-packs/ENGINE_PACK.md](docs/engine-packs/ENGINE_PACK.md).
6. Keep PROJECT.md short and current; detailed engine history goes in `ports/<engine>/`.
   Report evidence by kind: source, build, fixture, provider, user-reported, in game. A
   user's broad "it works" is user-reported and never proof of each action; an action is
   usable only after its own in-game check.
7. Before ending a build pass, reconcile PROJECT.md, the port plan and the flow review with
   the actual files and validation. Record uncommitted artifacts and interrupted work. Give
   server-ready, port-built and gameplay-verified separate results; a completed chat does not
   mean a completed mod. Leave one concrete next probe for each critical engine blocker.

## Layout and copies

- Keep player-facing interaction inside the game: NPC selection, text entry, replies,
  status and cancel. Prefer the game's native UI/input APIs, then a qualified in-process
  rendering integration. External windows, desktop overlays and companion apps are last
  resorts, not the default prototype. Record the missing mechanism and explain the fallback
  before adopting it. Background helpers must not require a separate conversation window;
  use external transport/audio only when the game cannot provide a suitable supported route.

- Keep the server at the repository root. In the template, the manifest id `example-server`,
  `config/config.php`, database placeholder `example_ai_mod`, service identity
  `example-ai-server`, port and routes stay unchanged. A user's new copy sets its own `id`
  and `name` in `dwemer-mod.json` before its first deploy (deploy refuses `example-server`
  for a new install); Core then names the database `custom_<id>`. Default to one repository per mod:
  in the template, start a mod with `scripts/project.ps1 new` (getting-started, New project),
  which writes an independent copy outside every checkout and web root and leaves the
  template unchanged; the copy is committed explicitly before its first deploy.
- Offer a separate game-client repository and server repository as an optional layout when
  discussing independent maintenance or when the user asks. Keep the single-repository
  default without adding a setup question. Record the choice in PROJECT.md Decisions before
  creating a split. The current `new` command creates one repo; a split needs an explicit
  plan for shared protocol/client sources, build paths, deploy and pairing. Do not pretend
  there is a split-repo CLI switch or split an existing project without a request. See
  [Repository layout](docs/getting-started.md#repository-layout).
- `client/`, `docs/` and `ports/` are source only. The server copy in Apache's web root
  contains them because it is one repository; DwemerDistro Core's custom mod web protection
  must be installed before a server install or update (SETUP.md). Never build the client,
  write a client `config.json` or put build output inside the server copy or the
  repository; builds go outside both (the client script defaults to `%LOCALAPPDATA%`).
- New ports use the data-only [generic build record](docs/PORT_BUILD_RECORDS.md) for action
  configuration and pairing; keep game-specific install/runtime checks in the port's route.
  `-AllowedActions none` explicitly disables actions while conversation is being qualified.
- `scripts/project.ps1` is a thin Windows wrapper over the existing scripts. Keep it free of
  dependency installation, database resets and background services. `deploy` sends only a
  bundle of the committed HEAD into the named distro and installs through DwemerDistro Core
  (or a named manual install's `update.sh`); it never adopts or repoints an install. Other
  server installs through it stay explicit opt-in for a named WSL checkout.
- A port with a maintained route builds through it, never a one-off script (Elden Ring:
  `ports/elden-ring/mod.ps1` `doctor`, then `build`, `assemble`, then `project.ps1 pair` into the
  runtime). Run its doctor first; record build, runtime and pairing, and each in-game result,
  in their own PROJECT.md rows. The game build it accepts lives in one file
  (`ports/elden-ring/game-build.json`); change it only from a fresh read of the installed game,
  never to make an unknown build pass. The user launches the game; never copy or delete saves.
- `ports/<engine>/` holds evidence and capability gates. Do not mark a port implemented,
  copy an engine SDK into the repository, or install SDK dependencies without the user's
  explicit request and evidence from that engine.

## Keep it simple

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
- **Config and secrets**: settings live in untracked `config/config.php`. Add new settings
  to `config/config.example.php` with a safe default. Optional features (LLM key, TTS, STT)
  must fail cleanly with a clear error and never pretend to succeed.
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
