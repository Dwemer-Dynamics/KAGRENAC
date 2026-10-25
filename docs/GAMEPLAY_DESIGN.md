# Gameplay design: from the player's fantasy to a verified loop

An AI mod is worth playing when something in the game changes because of it, rather than
only because a chat window answers. Before writing engine-port code, the agent fills the short
**Gameplay design** table in [PROJECT.md](../PROJECT.md) from the conversation, next to the
integration plan ([Engine planning](ENGINE_PLANNING.md)). It is not a form. The agent reuses
what the user already said and asks only for what is missing. Writing the design needs no new
permission; installs and provider calls keep their existing rules. A basic manual mod (the
player talks to one NPC) fills each row in a few words and needs nothing else from this page.

## What exists today

| Piece | What it does today | What it does not do |
|---|---|---|
| `turn.php` | One player line to one NPC: one reply, and only allowlisted actions targeting that NPC | No NPC-to-NPC exchange, listener or participant list |
| `decision.php` | Picks which of up to 8 NPCs offered by the game answers a **player's line**, or falls back to the baseline | Choosing actions, ambient moments or any other kind of id |
| `event.php` | Four fixed types (`location_entered`, `item_given`, `combat_started`, `combat_ended`). `respond: true` is a normal turn for one NPC that the port sends when its own trigger fires. History stores it as a player-role line marked `Game event (<type>): <text>`; it is the game's report, not something the player said | Built-in triggers, schedulers, queues or cooldowns: the port owns them. Accepts only the four fixed types; a new type needs an explicit server, client and `PROTOCOL.md` change |
| `TurnRuntime` (client) | One pending turn per runtime. `submitTurn()` (with `eventType` for an event) replaces any pending turn or voice; `cancel()` drops it and tells the server | Running an ambient exchange beside the player's turn |
| `result.php` | Records that a handler ran (`handled`), was refused (`rejected`) or failed (`failed`) | Reporting that the outcome happened in the game |
| Memory | History, plus optional summary and diary notes (off by default), per `session_id` and NPC; the port decides which save a session is (`setSession`). Bios and approved facts belong to one NPC or are global, across every session; fact candidates wait for a person's approval | Tracking listeners or overheard lines, or keeping private and overheard knowledge apart |

**Planned, not implemented:** a purpose-specific decision call (JEV choosing one of the ids
the engine offers, or none), an ambient coordinator, a participant and listener contract
with audience-scoped knowledge, and an observed-outcome event. A port may need one of these.
Each is designed in the server, the client and [PROTOCOL.md](../PROTOCOL.md) together,
implemented and tested before anyone promises it. Until then, record it as the missing
mechanism (see [Acceptance](#acceptance)).

## The design flow

Work through these in order and write one short answer per row in PROJECT.md.

1. **Player fantasy.** One sentence: what the player gets to feel, for example "my
   colonists have lives of their own" or "my companion has my back".
2. **Observable loop (2 to 3 minutes).** What the player does, sees and hears, start to
   finish, so that it can be repeated in a test. If nothing visible or audible changes, it is
   not yet a loop.
3. **Interaction mode** (a mix is fine; name the primary one):

   | Mode | Who starts it | Needs today |
   |---|---|---|
   | Manual | The player talks to an NPC | `turn.php`; works with the current contract |
   | Ambient, one speaker | One of the four fixed game events; one NPC remarks on it | `event.php` with `respond: true`; the port owns the trigger, bounds and cooldown. Works with the current contract |
   | Ambient, social | A bounded game event; NPCs talk among themselves | The planned participant and listener contract. Today's protocol cannot express it honestly |
   | Companion | The player, plus bounded reactions to events | `turn.php`, `event.php` with `respond: true`, and existing action handlers |
   | Operator | The player asks for a report or gives an order, or a fixed game event prompts a bounded report | `turn.php` with real observations in `context`, or `event.php` with `respond: true`; obvious orders go straight to handlers |

   Record the ambient kind the brief asks for. Name the participant contract as the missing
   mechanism only for NPC-to-NPC social exchanges; never shrink a requested social loop to
   one speaker to make it fit.
4. **Real observations.** Only values that the integration plan cites, each with its source
   and freshness. Anything the game cannot read, or read too long ago, is `unavailable`.
5. **A bounded decision with stakes.** What can turn out differently, why the player cares,
   and who decides: a rule, the engine, JEV choosing from ids the engine offers (today: only
   which NPC answers a player's line; other choices are planned), or the dialogue model. One
   decision per exchange.
6. **Legal engine actions.** Existing handlers only, each with its target, instance check
   and preconditions ([Awareness and actions](feature-recipes/PORT_RECIPES.md#awareness-and-actions)).
7. **An outcome the player sees or hears.** A subtitle, a voice line, a movement or a changed
   state the player can notice.
8. **Memory of verified events only.** Remember what the game observed, never what a reply
   claimed.

## Characters

Ground each NPC in a current goal, one or two relationships with people in the scene, and
what they are doing now. That gives the model something to act on. A name alone gives it too
little, and a long backstory buries the situation. Keep bios short and factual. Keep them to
what the NPC would plausibly know.

## Identity

Use a persistent `npc.id` where the engine provides one, with its citation. Otherwise use an
id scoped to the run, and drop it when the session or the NPC instance changes. Never invent
an identity that carries across saves.

## NPC-to-NPC exchanges (planned)

- **Participants** are NPCs the game reads as present, alive and able to talk now, each with
  an id as above and an instance check.
- **Listeners** are the participants who can hear a line, by the game's own distance or
  locale (the same room, cell or area). The player is a listener only when they are actually
  in earshot.
- **Never fake a player turn.** One NPC's line must not be sent as if the player said it to
  another NPC. That writes false history and confuses who said what. Use the planned
  participant contract instead.
- **Private and overheard knowledge.** What an NPC learned privately stays with that NPC.
  Other NPCs know only what they heard as listeners. This needs the planned contract.
- **Save scope.** The port decides which save a `session_id` stands for. Record whether each
  memory belongs to one session or to every session (bios and facts).
- When the player addresses someone, the ambient exchange ends and the player's turn takes
  over.

## Who decides

| Need | Use | Not |
|---|---|---|
| Already-known rules, emergencies (flee, heal, hostile in range), native combat | The game's own AI or a fixed rule | Any model call |
| An obvious command (a button, a key or a fixed phrase) | Its handler directly | A model call |
| An ambiguous choice among options the engine offers right now | JEV (`typesafe/jev-1.13`), returning one offered id or none, and only once that contract exists | Free text, invented ids or targets |
| Words the player will read or hear | Gemma (`google/gemma-4-31b-it`), only when a line is actually needed | A line every tick, or a line nobody will hear |
| Voice | PocketTTS, after the text is shown | Blocking the text |

**When not to add a model:** the outcome is already fixed by the rules; one option is always
right; the game's AI already does it well; or nobody will see or hear the result. A qualified
tick or callback may detect an event and hand it over as one bounded job. The model call then
starts on a worker for that event. There are no per-frame or blocking provider calls on the
game thread.

## Automatic interactions

Start with **one** automatic interaction and keep it bounded:

- **Player input comes first.** Send an ambient turn through the player's runtime and session
  only while no player turn is pending. When the player speaks, submit the line with
  `submitTurn()`: it replaces the pending ambient turn or voice at once (same NPC: the
  player's turn makes the ambient one stale on the server; another NPC: the runtime queues
  the old turn's cancel itself). Late ambient results and voice are discarded locally, but
  text already presented or actions already executed are not undone. If `submitTurn()` is
  refused, or the port called `cancel()` first and that queued a server cancel (a turn, not
  only its voice, was pending and a cancel slot was free), the port keeps at most one pending
  player line, stays responsive, and submits it once after `tick()` lets it. A voice-only
  `cancel()` is local and needs no wait. The port never replays the old HTTP request or the
  ambient turn. If that submit is refused or fails, show it; never lose the player's line
  silently. "First" means ambient speech never queues ahead of the player; it does not bypass
  the server's cancel ordering.
- **Cancel limits.** The generation fence (`cancel.php`, `409 stale`) only stops a save that
  has not yet committed. It cannot undo an ambient reply already saved to history, and an old
  request that reaches the server after the cancel starts a new, current generation. Muting
  or cancelling locally does not remove committed history. The template gives no automatic
  scheduler or coordinator; the port qualifies its own. Never move ambient turns to a made-up
  session to avoid this ordering; a separate social-participant contract is future work.
- **Bounded exchange:** a fixed number of lines and participants, then it stops.
- **Cooldown and dedupe:** a minimum gap between exchanges and before the same participants
  talk again, and the same trigger is never handled twice.
- **Expiry and identity rechecks:** drop an exchange whose observations are too old, or whose
  NPC instance, session or generation changed, before showing text, playing voice or running
  actions.
- **Failure fallback:** on any failure, nothing is said and the game carries on. No retry.
- **No chains:** generated lines, and action requests the mod made itself, never trigger
  another automatic exchange. An outcome the game later observed may start a new bounded
  exchange, with its cause recorded, after dedupe and cooldown.
- **Native orders carry on:** NPCs keep their game-driven jobs. The mod never steers them
  continuously.

Example values for a first prototype, to tune per port. They are not config keys or current
defaults; record the chosen values under "Port decisions" in the
[engine pack](engine-packs/ENGINE_PACK.md):

| Bound | Example |
|---|---|
| Gap between automatic exchanges | 45 s |
| Before the same participants talk again | 2 min |
| Lines per exchange | 1 per participant, at most 2 participants |
| Maximum age of an observation used | 10 s |
| Automatic exchanges per hour | 20 |

## Actions: ownership and outcomes

- The mod cancels only orders it issued itself and can recognize as its own. It never clears
  the player's orders or the NPC's native job.
- A player order overrides the mod's order. The mod then stops and waits for the player.
- Before running an action, check its preconditions on a fresh read: resources, current
  inventory, a target the game identifies uniquely and that the NPC can use, and the NPC's
  state.
- A tag in a reply is a request. `handled` means the handler ran. The action succeeded only
  once a later observation shows it.

Record each result separately: **generated** (the server returned it), **presented** (the
subtitle was shown), **played** (the game delivered the audio, as far as the engine can
tell), **heard** (a person reported hearing it; a generated WAV or a played call is not
heard), **handled** (the handler ran) and **observed** (the game later read the outcome).

## Budgets and the growth path

Set a cost budget for each mod (calls per exchange, exchanges per hour). Profiles may
optionally give an NPC its own model or a keyless mode; without one, the config applies. The
growth path starts with the first loop of the chosen mode, then adds one bounded automatic
interaction or one action with an observed outcome, one at a time. A director, queue or
memory platform is never required up front. Add one only when a measured need appears, and
design it as a new contract.

## Worked example: a colony game (illustrative)

"Common Ground" is a made-up colony mod used only to show the patterns. None of this is an
existing port.

- **Operator report (operator; possible with today's contract).** The player asks the
  overseer "How are we doing?", or the port sends a `combat_ended` event. The port sends the
  food stock, the number of injured and the threats it actually read, each with its age.
  Gemma answers in two sentences, and PocketTTS speaks the answer. Demo: ask, hear the
  report, change the food stock, ask again and hear the change.
- **Arrival remark (ambient, one speaker; today's contract).** On `location_entered` the
  port sends one `event.php` turn with `respond: true` to the nearest colonist, at most once
  per cooldown. Demo: walk into the yard, hear one line, walk out and back in at once and
  hear nothing.
- **Companion bounded action (companion; today's contract plus a port handler).** The player
  says "hold the gate". A fixed phrase goes straight to the existing `hold_position` handler,
  with no model call. A looser request may get an offered `[ACTION:hold_position]` tag.
  Demo: give the order, see the colonist stop, override it with a native order, and see the
  mod let go.
- **Meal social (ambient, social; needs the planned participant contract).** Two colonists at
  the same table at mealtime say one line each about a real observation (the food ran low
  yesterday). The player hears them only when nearby. Demo: watch the meal, hear two lines,
  walk up and speak (the ambient exchange stops), then wait out the cooldown. Today this is
  a missing mechanism to record, not something to fake with player turns.

## Acceptance

Stage 6c in PROJECT.md is the loop from the Gameplay design, seen in the game and launched by
the user. It includes the automatic trigger when one was requested, and heard voice when
voice was requested. Do not replace a requested companion with a narrator, and do not move
the interaction to an external window, just to finish. Mock mode, the console client and
diagnostics are developer checks, not the loop, and none is required before an ambient or
operator loop. When a mechanism is missing, name it exactly (for example "no participant
contract" or "no per-NPC hearing read"), give the next bounded probe and its stopping point,
and continue with the stages that do not depend on it.
