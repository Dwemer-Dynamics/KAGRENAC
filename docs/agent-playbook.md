# Agent playbook: turn the template into a real mod

Paste the prompt below into your coding agent, from the root of your copy of the
**KAGRENAC AI Mod Maker** repository (KagrenacServer at the root, KagrenacClient in
`client/`) with your engine's modding SDK or project available. Make the copy from
<https://github.com/Dwemer-Dynamics/Kagrenac> with GitHub's **Use this template** or a
fork. You do not need to fill in [PROJECT.md](../PROJECT.md) or "Authorized now" first:
the agent fills PROJECT.md from your conversation and earlier instructions, and
"Authorized now" is an optional pre-fill. The agent keeps going through everything you
authorized and asks only for what is materially missing.

Companion files: [engine-packs/ENGINE_PACK.md](engine-packs/ENGINE_PACK.md) is the blank
evidence record for your engine, and [feature-recipes/PORT_RECIPES.md](feature-recipes/PORT_RECIPES.md)
has one bounded recipe per stage. The canonical port checklist and evidence levels are in
[START_HERE.md](../START_HERE.md#porting-to-a-real-engine).

---

```text
You are porting the KAGRENAC AI Mod Maker template, KagrenacServer (the AI server, at the
repository root) and KagrenacClient (a console "fake game" client, in client/), into an AI
NPC mod for my engine. Before changing anything, read PROJECT.md, START_HERE.md, AGENTS.md,
client/AGENTS.md, README.md, client/README.md, PROTOCOL.md, SETUP.md,
docs/engine-packs/ENGINE_PACK.md and docs/feature-recipes/PORT_RECIPES.md. Follow both
AGENTS.md files. Host setup is in SETUP.md; provider settings are in CONNECTORS.md.

AUTHORIZED NOW (optional pre-fill. A blank item is not authorized unless my current or
earlier instructions already grant it; "no" means do not do it. See HOW TO WORK.)
- Project name:
- Engine, SDK and project location:
- Stages in scope (default: all that apply):
- Real provider calls (none, or which ones):
- Voice work (no / yes):
- Actions beyond follow_player (none, or which ones):
- Commits (no / yes, where):

HOW TO WORK
- Fill in PROJECT.md from this conversation and my earlier instructions. Do not ask me to
  confirm what I already said, and do not ask again for permission I already gave.
- Continue through every authorized stage without pausing for review. Never treat silence
  as permission for a side effect (installs, provider calls, commits, publishing). An
  optional item (provider calls, voice, extra actions) that is "no", or blank and not
  granted by my instructions, means skip it and report it as skipped or Not tested; never
  stop just for these.
- Stop and ask only for: required material that lacks authority (above or given earlier
  by me); a material decision (a protocol, schema, endpoint or
  dependency change, or anything a recipe marks out of scope); or a blocker you cannot
  resolve (an engine API you cannot find, a build you cannot fix, source that contradicts
  the docs).
- Never invent engine APIs. Cite the SDK file or doc for every engine fact. If something is
  unknown, write "Unknown" in your engine pack, leave a clearly marked TODO, and say so.
- Skip optional stages that are not authorized and say they were skipped.
- Rerun the server and console smoke checks only when server or shared client code
  changed. For engine-only stages, rebuilding the console just confirms the shared code
  still compiles.

STAGES (recipes in docs/feature-recipes/PORT_RECIPES.md; record results in your copy of
docs/engine-packs/ENGINE_PACK.md)
0. Scope. List the docs you read, the constraints you noted and the authorized items.
   Do not pause.
1. Recon. Fill the "SDK facts" part of the engine pack: plugin architecture (native,
   managed or script), lifecycle hooks, main-thread tick, threading and HTTP, NPC
   identity, display, follow, save hooks, config location, logging, optional audio.
2. Baseline. Install the server and build the console client unchanged, as SETUP.md says.
   Run evidence levels 1 and 2 from START_HERE. Change nothing until they pass.
3. Project identity. Rename folders, database name and ids in docs. Add your own notice
   to README and THIRD_PARTY_NOTICES.md; keep LICENSE (GPL-3.0-only) unchanged and every
   existing and third-party notice; never rename or remove the
   existing holder (MAKE_IT_YOURS.md). If the server will be
   published for the launcher, change the manifest id first (LAUNCHER_CUSTOM_MOD.md).
   Your project is a separate copy; template changes are merged by hand, if ever.
4. Plugin lifecycle. Load, per-tick mailbox drain, NPC leaving, unload and quit, in plugin
   glue outside GameAdapter.
5. Typed dialogue. Player input to turn, reply to subtitle, through a GameAdapter that
   uses only real engine APIs.
6. Actions. follow_player with the engine's own follow behaviour. Extra actions only if
   authorized, following WAVE_ACTION.md.
7. Game events. Only if the engine has the hooks. Bounded; no responding event while any
   turn is pending or a cancel for that NPC in that session is still out.
8. Saves and sessions. session_id per save, cancel in the old session before switching.
   No checkpoint automation.
9. Voice (optional, only if authorized). WAV saved and audible in game are separate
   results.
10. Diagnostics and packaging. Recommended client log fields; ship plugin artifacts, not
    the console program.
11. Acceptance report (below).

STATUS WORDS
- For GameAdapter, plugin glue and packaging, use only: Not started; Implemented,
  untested; Verified (in engine); Not tested (say why).
- "Verified (console/mock)" is allowed only for server code and shared client code
  (ai_client, config), and only for checks you actually ran.

ACCEPTANCE REPORT
- Files changed, per component (server, client, port).
- Each START_HERE checklist item with its status and the evidence (command, in-game step).
- Evidence levels 1-4, each reported separately: what ran, its result, or "Not tested".
  Provider calls (level 3) may stay "Not tested".
- Engine facts still Unknown, open TODOs, and stages skipped and why.
- Never call the mod working in a game until level 4 was done in that game.
```

---

## Warm-up exercise (before stage 5)

A small change that touches each boundary once, on your own copy with a disposable
database, so the agent learns the seams before porting:

1. **Game side** (`client/src/console_game.h`, behind `GameAdapter`): add a third fictional
   NPC, e.g. `npc_smith` "Smith" at "Forge Lane", and let `/npc smith` face it. Nothing in
   `ai_client` or `PROTOCOL.md` changes: the NPC id is just data.
2. **Server data** (dashboard **NPC bios**, or `scripts/seed_example.php` for samples): give
   `npc_smith` a bio and one fact, e.g. "Forge hours: the forge closes at dusk."
3. **Check**: `/npc smith`, then `When does the forge close?`. Logs shows the fact under
   "Retrieved for this request". Then `/event item_given The player gave the smith ore.`
   (log only) and `/react combat_started Bandits at the forge.` (Smith reacts).
4. **Leave alone**: protocol version, the event type list, action allowlists, provider
   settings in `config/config.php` and the client's `config.json`. A new event type or
   action is a change to the server, the client and `PROTOCOL.md` together, not part of
   this exercise.

If `--health` or the server fails on first run, see
[SETUP.md, Troubleshooting](../SETUP.md#troubleshooting): it covers `not_migrated`,
`schema_too_new`, a refused `update.sh` and an older server without a `baseline`.

## What a real engine port must provide

The list is the checklist in
[START_HERE, Porting to a real engine](../START_HERE.md#porting-to-a-real-engine).
Record where your engine provides each item in your copy of
[engine-packs/ENGINE_PACK.md](engine-packs/ENGINE_PACK.md). Checkpoints are matched to saves
by hand (see the [client README](../client/README.md#npc-bios-knowledge-and-checkpoints)).

## What the services need

| Service | Default | Required |
|---|---|---|
| KagrenacServer (Apache in DwemerDistro, shared custom mods port) | `http://127.0.0.1:19000/custom-mods/KagrenacServer` (launcher install: `.../custom-mods/example-server`; pairing writes the actual route) | Yes |
| PostgreSQL in DwemerDistro | `localhost:5432`, database `example_ai_mod` | Yes |
| LLM: OpenAI, OpenRouter, local OpenAI-compatible or DwemerDistro LLM Studio (`127.0.0.1:1234`) | `llm.mode` in `config/config.php`, see [CONNECTORS.md](../CONNECTORS.md) | No (mock otherwise) |
| TTS: PocketTTS (audio.cpp), default | `http://127.0.0.1:8086/v1/audio/speech`, off until enabled | No |
| STT: Parakeet, default | `http://127.0.0.1:8022/v1/audio/transcriptions`, off until enabled | No |
| STT: faster-whisper, supported alternative | `http://127.0.0.1:9876/api/v0/transcribe` | No |
| NPC selection (`decision.php`, mock or OpenRouter decisions) | off | No; selection only, never actions |

All URLs are configurable; provider settings are in [CONNECTORS.md](../CONNECTORS.md). None
of these are installed or started by the template; start them from the DwemerDistro
launcher or your own setup.

The companion [MAKE_IT_YOURS.md](../MAKE_IT_YOURS.md) maps the source files to customize.
[WAVE_ACTION.md](../WAVE_ACTION.md) is a worked optional action exercise; wave remains
disabled in this template. The port checklist and evidence levels are in
[START_HERE.md](../START_HERE.md#porting-to-a-real-engine). Use the staged prompt above,
[engine-packs/ENGINE_PACK.md](engine-packs/ENGINE_PACK.md) and
[feature-recipes/PORT_RECIPES.md](feature-recipes/PORT_RECIPES.md) rather than adding a
second workflow.
