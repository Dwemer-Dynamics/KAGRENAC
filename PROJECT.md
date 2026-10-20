# Project brief

The resumable record of your mod. Your coding agent fills it in from your conversation,
asks only for what is missing and resumes at the first unchecked stage it can work on
([docs/getting-started.md](docs/getting-started.md)). Keep it short and factual. Never put
keys, tokens, private URLs or personal data here: keys go on the dashboard **API keys** page
or in the private `config/config.php`. A blank row is not a permission.

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

## Integration plan (required before building mod code)

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

## Stages

Stages 3 to 5 do not wait for stage 2: they run while engine unknowns are researched. Only
stage 6 needs the integration plan with an option chosen for every Unknown. A blocked stage
gets one line here (what blocks it, the next action, who does it) and work continues on the
others.

- [ ] 1. Brief: game, starting feature, mod name
- [ ] 2. Integration plan written; each Unknown researched, with an option chosen
- [ ] 3. DwemerDistro: own id set and committed; `project.ps1 deploy -WslDistro <name>`
      reports the commit deployed (health ok, exposure probes HTTP 403); the game side paired
      with `project.ps1 pair`. Doctor output is diagnostic only
- [ ] 4. LLM: the dashboard **Send test** returned a real reply from the chosen provider
      (nothing has to answer on port 1234 unless that is the chosen provider)
- [ ] 5. Voice: PocketTTS running; a reply heard on the dashboard **Speak** test or in the
      game (a generated WAV is not "heard"), or "not wanted"
- [ ] 6. First prototype: the thin slice seen and heard in the game, each action reported
      on its own
- [ ] 7. Expand: next feature named

## Decisions

| Date | Decision | Reason |
|---|---|---|

## Latest evidence

The last few results only; older detail goes in `ports/<engine>/`. Never record what did not
run. Kind is one of source, build, fixture, provider, user-reported or in-game; a broad
"it works" is not evidence for each action.

| Date | Kind | What ran (command or in-game step) | Result |
|---|---|---|---|
