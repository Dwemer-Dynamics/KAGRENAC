# AGENTS.md

Guidance for coding agents working on KAGRENAC AI Mod Maker, or on a project copied from it.
The repository root is the KagrenacServer component (these rules); `client/` is the
KagrenacClient component, which adds its own rules in [client/AGENTS.md](client/AGENTS.md).
Follow both when a change touches both.

## Start of every task

1. Read [PROJECT.md](PROJECT.md): the user's brief, decisions, acceptance criteria and
   evidence so far. If it is blank or incomplete, fill it in yourself from the current
   conversation and the user's earlier instructions; the user does not have to fill in a
   form first, and you do not ask them to confirm what they already said.
2. Settle scope before building: which game or engine, whether voice is wanted, and which
   actions beyond `follow_player`. Take what the user already said; ask only for facts that
   are materially missing for the next step. Do not assume any of them. Permissions the
   user already gave stay in force, so do not ask for them again; silence never grants a
   side effect (installs, provider calls, commits, publishing).
3. Inspect real capabilities before promising anything: what this repository does today
   ([README.md](README.md#what-works-today), [START_HERE.md](START_HERE.md#feature-and-status-checklist)),
   what is installed and running (`scripts/project.ps1 doctor`), and what the engine's SDK
   actually offers.
4. Qualify the engine with a copy of [docs/engine-packs/ENGINE_PACK.md](docs/engine-packs/ENGINE_PACK.md)
   (cited SDK facts versus verified in engine) before promising game support, microphone
   capture, audio playback or real actions. The console's follow is a printed simulation.
5. Record the brief, decisions and evidence in `PROJECT.md` as you go; keep it short and
   factual.

## Layout and copies

- Keep the server at the repository root, with its id `example-server`, `config/config.php`,
  database placeholder `example_ai_mod`, service identity `example-ai-server`, port and routes
  unchanged unless the user explicitly asks.
- `client/`, `docs/` and `ports/` are source only. The server copy in Apache's web root
  contains them because it is one repository; DwemerDistro Core's custom mod web protection
  must be installed before a server install or update (SETUP.md). Never build the client,
  write a client `config.json` or put build output inside the server copy or the
  repository; builds go outside both (the client script defaults to `%LOCALAPPDATA%`).
- `scripts/project.ps1` is a thin Windows wrapper over the existing scripts. Keep it free of
  dependency installation, source copying into WSL, database resets and background services;
  server installs through it stay explicit opt-in for a named WSL checkout.
- `ports/<engine>/` holds evidence and capability gates. Do not mark a port implemented,
  copy an engine SDK into the repository, or install SDK dependencies without the user's
  explicit request and evidence from that engine.

## Keep it simple

- Plain PHP 8.2 with built-in extensions. Do not add Composer, frameworks, background
  workers, queues or embeddings unless the user asks.
- One small file per endpoint at the top level; shared helpers in `lib/`. Library files
  only define functions and constants, so requesting them over HTTP prints nothing.
- Prefer clear, explicit code over abstractions.

## Stable boundaries

- **Protocol** (`PROTOCOL.md`, the only copy, shared with `client/`): JSON with
  `"protocol": 1`. Adding optional fields is fine. Anything a version-1 client would
  misread needs a protocol bump in the server and the client together.
- **Actions**: the model may only request actions with `[ACTION:name]` tags. The server
  returns only names in `allowed_actions`; the client checks its own allowlist and has one
  explicit handler per action. To add an action, update the prompt in `lib/llm.php`, the
  config allowlist, `PROTOCOL.md`, and the client handler together. Never execute model
  output as commands, SQL, paths or URLs.
- **Decisions**: `decision.php` only returns one of the ids the game offered, or the
  baseline on any failure. Keep it free of history, chat, memory and actions, and keep its
  provider call short (`DECISION_TIMEOUT_MS`), size-capped and without redirects. Its only
  database write is one connector-audit row sent after the reply (`reply_then()`), so audit
  logging never delays or changes a decision.
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
  `health.php`.
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
- **Voice**: optional, off by default; text and mock come first. If the user wants voice,
  start with PocketTTS for TTS and Parakeet for STT (the recommended DwemerDistro choices)
  before the supported alternatives. Do not assume either is installed or running: within
  the scope the user has authorized, verify the service is available and running before
  enabling or testing voice, then confirm with the dashboard Voice page test.
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
