# Project brief

The resumable record of your mod and its one current status. Your coding agent fills it in
from your conversation, asks only for what is missing and resumes at the first stage that is
not done and can be worked on ([docs/getting-started.md](docs/getting-started.md)). Keep it
short and factual. Never put keys, tokens, private URLs or personal data here: keys go on the
dashboard **API keys** page or in the private `config/config.php`. A blank row is not a
permission.

## Brief

| Question | Answer |
|---|---|
| Game, version and modding tools | |
| Starting feature (new companion or existing NPC, and what it does) | |
| Mod name | |
| Project id and name in `dwemer-mod.json` (own values, set before deploy) | |
| Voice (none, or PocketTTS replies; speech input later?) | |
| LLM provider (name only) | |
| DwemerDistro (the one WSL distro name) | |

## Gameplay design

The agent fills this from the conversation before engine-port code, following
[Gameplay design](docs/GAMEPLAY_DESIGN.md); it is not a form for the user. One short answer
per row. A basic manual mod needs only a few words in each. JEV in "Decision and stakes"
today only picks which NPC answers a player's line (`decision.php`); other JEV choices are
planned.

| Design question | Answer |
|---|---|
| Player fantasy (one sentence) | |
| Observable loop (what the player does, sees and hears in 2-3 minutes) | |
| Interaction mode (manual, ambient/social, companion or operator; a mix is fine) | |
| Trigger and bounds (player line, or the one automatic event with its limits) | |
| Participants and listeners (who is present, who can hear) | |
| Decision and stakes (what can change; decided by a rule, the engine, JEV or dialogue) | |
| Actions and the outcome the player sees or hears | |
| Memory (verified events only; one session or every session) | |
| Missing mechanism and next bounded probe (or none) | |

## Integration plan (required before building mod code)

First follow [Engine planning](docs/ENGINE_PLANNING.md). Record the installation survey,
selected loader/tool versions and primary sources, the chosen architecture, bounded probes
for unknowns and a five-minute acceptance sequence in `ports/<engine>/PLAN.md`. The agent
checks the plan against this brief before game-port implementation; independent server and
provider setup can proceed. Use the current coding agent for build, tests and a separate
diff review, unless the user explicitly chooses delegation. Record flow friction in
`docs/KAGRENAC_FLOW_REVIEW.md`.

Each row: the chosen mechanism, and whether it is a cited fact (SDK file, doc or game data)
or Unknown. For an Unknown, note the bounded research (where, and when to stop) and the
options offered.

| Part | Plan | Fact (citation) or Unknown |
|---|---|---|
| Player input in game | | |
| NPC identity and lifetime | | |
| HTTP off the game thread, result back on it | | |
| Reply display | | |
| Audio playback | | |
| Game awareness: each value's source and freshness; unread values sent as `unavailable` | | |
| Action bridge (existing mechanism only): capability, target, instance check, preconditions | | |
| Saves, offline play, cancel | | |
| First thin slice and its acceptance | | |

## Stages and readiness

This table is the one current status of the mod; update a row whenever its state or evidence
changes. A stage is `done` only with evidence of the kind in its second column; otherwise it is
`not started`, `in progress`, `blocked: <what blocks it>; <next action>; <who>` or `not wanted`.
Stages 3 to 5 do not wait for stage 2: they run while engine unknowns are researched. Only
stage 6 needs the Gameplay design and the integration plan with an option chosen for every
Unknown. A blocked stage does not stop the others.

| Stage | Done only with | State | Latest evidence (date, kind) |
|---|---|---|---|
| 1. Brief: game, starting feature, mod name | source: the Brief rows above | not started | |
| 2. Integration plan; each Unknown researched, with an option chosen | source: Gameplay design rows filled, with an existing mechanism for the requested loop and any automatic trigger, or the missing one named with its next probe; every plan row cited, or Unknown with an option chosen | not started | |
| 3. DwemerDistro: own id committed, deployed | build: `project.ps1 deploy -WslDistro <name>` reported the commit deployed (health ok, exposure probes HTTP 403). Doctor output is diagnostic only; pairing is part of 6b | not started | |
| 4. LLM | provider: the dashboard **Send test**, or a real `turn.php` turn (same server path), returned a real reply from the chosen provider (nothing has to answer on port 1234 unless that is the provider) | not started | |
| 5. Voice | user-reported or in-game: a PocketTTS reply heard on the dashboard **Speak** test or in the game (a generated WAV is not heard); or `not wanted` | not started | |
| 6a. Game-side build | build: the port's preflight passed and its build finished into the folders under Paths (Elden Ring: `mod.ps1 doctor`, then `mod.ps1 build` exit 0 with its `build.json`) | not started | |
| 6b. Game-side runtime, paired | build: the runtime folder assembled from that build (Elden Ring: `mod.ps1 assemble`) and `project.ps1 pair` wrote its private `config.json`; nothing launched yet | not started | |
| 6c. First prototype | in-game: the Gameplay design loop seen in the game, launched by the user, with its automatic trigger when one was requested and heard voice when voice was wanted | not started | |
| 6d. Action `<name>` (one row per action) | in-game: that action's own check; a broad "it works" does not count | not started | |
| 7. Expand: next feature named | source | not started | |

## Paths

Everything built or private stays outside this repository and every web root. `<id>` is the
id in `dwemer-mod.json`; the template itself keeps the client build in
`%LOCALAPPDATA%\DwemerDynamics\KagrenacClient\build`. A port route's `-Root <folder>` (for
example on a disk with more room) replaces `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>`
in the game-side rows; record it here when you use one.

| What | Where |
|---|---|
| Client build (`project.ps1 setup` and `check` default) | `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>\client` |
| Game-side builds (the port's build route; Elden Ring: `mod.ps1 build`) | `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>\<engine>\<part>` |
| Game runtime folder (Elden Ring: `mod.ps1 assemble`) with the private `config.json` (`pair -OutFile`) | `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>\runtime` |
| Deploy bundles and records (`project.ps1 deploy`) | `%LOCALAPPDATA%\DwemerDynamics\Kagrenac\deploy\<id>` |
| Server copy and database in the DwemerDistro | `/var/www/html/custom-mods/<id>`, database `custom_<id>` with `-` as `_` |

## Decisions

Record the repository layout here: one repo by default, or a user-chosen client/server
split with its build/deploy plan. Keep the current architecture and stage results aligned
with actual files. Report server-ready, port-built and gameplay-verified separately;
uncommitted code and interrupted checks remain explicit pending work.

| Date | Decision | Reason |
|---|---|---|

## Latest evidence

The last few results only; older detail goes in `ports/<engine>/`. Never record what did not
run. Kind is one of source, build, fixture, provider, user-reported or in-game; a broad
"it works" is not evidence for each action.

| Date | Kind | What ran (command or in-game step) | Result |
|---|---|---|---|
