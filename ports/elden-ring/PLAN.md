# Elden Ring integration plan for a companion built on this reference

`scripts\project.ps1 new -Engine elden-ring` copies the table below into the new project's
PROJECT.md as its chosen starting plan, so an agent starting a companion from this reference
need not plan from scratch. It is a choice, not proof that it fits every mod: each row names
the reference mechanism and where it is cited, and none of it is verified in game yet
([README.md](README.md)). The project's stage 2 stays `in progress` until its agent has checked
every row against the project's starting feature and revised each one that departs from the
reference; keep this page about the reference only.

Requires: the one game build in [game-build.json](game-build.json) (file 2.7.2.0; any other
build is refused by the package build and leaves the client's game link off), me3 v0.13.0,
offline play with an isolated save. The route is [mod.ps1](README.md#build-a-mod-from-this-reference):
`doctor`, then `build`, `assemble` and `pair`; you launch the game yourself.

Actions: follow_player, hold_position

| Part | Plan | Fact (citation) or Unknown |
|---|---|---|
| Player input in game | F8 opens the mod-owned Win32 text box over the game; Enter sends, Esc cancels | Source and fixture: [client/README.md, How it works](client/README.md#how-it-works); not loaded by me3 yet |
| NPC identity and lifetime | The one companion copy the control package places beside The First Step grace (entity 1042360890); the mod's own `npc_id` and `npc_name` are written into the private `config.json` when `pair -NpcId -NpcName` creates it; the DLL lives for the game process | Build: [control/README.md, First test setup](control/README.md#first-test-setup-from-kagrenac_controlexamplejson); [client/README.md, Config](client/README.md#config) |
| HTTP off the game thread, result back on it | WinHTTP on the DLL's own network worker, one turn at a time; results go to the DLL's own UI thread, so no game-thread callback is used. A qualified game-thread callback stays Unknown and is not needed by this route | Source: [client/README.md, How it works](client/README.md#how-it-works); Unknown: [engine pack, Open questions](../../docs/engine-packs/elden-ring.md#open-questions) |
| Reply display | The reply text in the mod-owned box, shown before any audio | Source: [client/README.md, How it works](client/README.md#how-it-works) |
| Audio playback | `speak.php` WAV from the server's PocketTTS, checked (RIFF/WAVE, at most 20 MB) and played by the DLL after the text; off unless `voice_enabled` (`pair -VoiceEnabled`) | Source: [client/README.md, How it works](client/README.md#how-it-works) |
| Game awareness: each value's source and freshness; unread values sent as `unavailable` | Location (The First Step tile, else `unavailable`), the companion's state and the one fixed hostile, read from the bridge mailbox flags each pass; inventory, combat, other actors and line of sight `unavailable` | Source: [client/README.md, Game link and orders](client/README.md#game-link-and-orders) |
| Action bridge (existing mechanism only): capability, target, instance check, preconditions | `follow_player` and `hold_position` as requests through the guarded event-flag mailbox to the control event; the client links only when exactly one mailbox candidate is live; target is the companion copy only; instance check: companion loaded and alive, mailbox armed for this load; precondition: no order pending. Attack is left out of the package (`attack_enabled` false) and out of both allowlists | Build: [control/README.md, Bridge mailbox](control/README.md#bridge-mailbox-not-verified-in-game); [README.md, Action rules](README.md#action-rules) |
| Saves, offline play, cancel | `mod.ps1 assemble` writes an offline me3 profile with its own save `<id>.sl2` (me3 creates it as a copy of an existing save; back up the save folder first); no launch, save copy or deletion by the route; Esc cancels the turn through `cancel.php` and requests a safe hold; reload, warp or companion loss restart the control event to a friendly hold | Source: [README.md, Build a mod](README.md#build-a-mod-from-this-reference); [control/README.md, How the control works](control/README.md#how-the-control-works) |
| First thin slice and its acceptance | After doctor, build, assemble and pair, you launch offline with the printed command: press F8, type a line, see the companion's reply text and hear its voice; then `/hold` and `/follow`, each checked on its own | Acceptance: [engine pack, Future acceptance](../../docs/engine-packs/elden-ring.md#future-acceptance-for-hold-follow-and-attack) |
