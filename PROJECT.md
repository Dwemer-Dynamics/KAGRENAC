# Project brief

Your project's single source of truth for what you are building with KAGRENAC AI Mod Maker.
You do not have to fill it in first: your coding agent reads it at the start of every task
([AGENTS.md](AGENTS.md)), fills it in from your conversation and earlier instructions, and
asks only for what is still missing for the next step. You can also pre-fill any row. Keep
it current, short, factual and free of secrets, keys, private URLs and personal data. A
blank row is not a permission: anything you have not asked for or allowed stays not
authorized.

## User brief

| Question | Answer |
|---|---|
| Project name | |
| Game or engine, and version | |
| Engine SDK or modding tools, and where they are | |
| What the player should be able to do | |
| Voice wanted? (no / text-to-speech / speech-to-text / both) | |
| Actions beyond `follow_player` (none, or which) | |
| Real LLM provider (mock only, or which) | |
| Who will test in game, and on which architecture (x64 / x86) | |

## Decisions

Record each choice with its date and reason. Leave a row blank until it is decided.

| Date | Decision | Reason |
|---|---|---|
| | | |

## Acceptance

What "done" means for this project. Start from the evidence levels in
[START_HERE.md](START_HERE.md#porting-to-a-real-engine) and add your own.

- [ ] Level 1: server lint, migrations twice and `scripts/smoke.sh` in mock mode
- [ ] Level 2: console client smoke checks ([client/README.md](client/README.md#smoke-checks))
- [ ] Level 3: each real provider call you chose, tested on its own (or "Not in scope")
- [ ] Level 4: in game, talk, subtitle, follow, cancel, NPC unload and server stop without a
      crash or hang

## Backlog

| Item | Status (Not started; In progress; Done; Dropped) | Notes |
|---|---|---|
| Fill in the user brief (agent, from the conversation) | Not started | |
| Qualify the engine in `docs/engine-packs/<engine>.md` | Not started | |

## Evidence

What actually ran, with date and result. Never record a claim you did not test.

| Date | What ran (command or in-game step) | Result |
|---|---|---|
| | | |
