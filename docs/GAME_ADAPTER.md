# Game adapter boundary

Status (2026-11-20): planned for architecture v2 ([MIGRATION_PLAN.md](MIGRATION_PLAN.md)).
Today's client already keeps engine code behind `GameAdapter` (`client/src/game_adapter.h`);
the server has no game-specific code yet. This page names every place where one game differs
from another, so that the shared server and client never assume a particular engine.

Rule: shared code may only depend on the seams below. Anything the seam does not offer is
`unavailable`, never guessed or filled with static text.

## Client seams

| Seam | The port supplies | Shared code relies on |
|---|---|---|
| Game thread | A way to post a task to the game thread and to tell whether the caller is on it | Network and audio work never touch engine objects; results are applied through this seam |
| Lifecycle | Loader entry, shutdown hook, save created, save loaded, new game | A new load epoch on each load; work from an older epoch is dropped before it is shown, spoken, reported or stored |
| Entity identity | A stable id for each speaker and the player, how runtime-created entities are told apart, and an instance check | `isSameNpc()` before any reply, action or voice is applied |
| Snapshot readers | Current values with their source and freshness: location, time, condition, inventory, nearby entities | Only read values are sent; each missing value is sent as `unavailable` |
| Event source | Which engine events exist and how each maps to a server event type | Bounded, de-duplicated events; no model call from a game tick |
| Player input | A native text field with focus capture and release, recipient display, optional push-to-talk | `ChatInput` lifecycle: draft, Enter, Esc, release on pause, load, death and focus loss |
| Speaker output | Subtitle display, positional or flat audio playback, optional mouth movement, muting the game's own voice line | Text first, then voice; spoken receipts reported from real playback events |
| Action executors | One handler per allowed action, its target rule, preconditions and observable outcome | An action runs only if allowlisted, offered and registered; outcomes reported, never assumed |
| RPC methods | Handlers for each allowlisted server question and the thread each must run on | Deadlines, calls in flight and typed errors |
| UI host (optional) | Any in-game pages beyond the composer | Pages receive no ids, URLs, tokens or prompts |

## Server seams

| Seam | Supplied by | Default in the template |
|---|---|---|
| Identity resolver | The port's server package: turns the game's ids into stable character ids and back | Opaque ids exactly as sent (`npc.id` today) |
| Player identity | The resolver; never a hard-coded engine constant | `player.name` from the request |
| Game time | A converter from the game's clock to one sortable timestamp | Server receive time |
| Prompt universe | A template naming the world, tone and reply format (including any gestures the game can play) | A neutral template with no world assumed |
| Voice fallback | A table from game voice types or character traits to TTS voices | The connector's default voice |
| Knowledge packs | Bios and world facts imported through [content authoring](CONTENT_AUTHORING.md) | Empty |
| Observation schema | The list of private observations the game may send and how each is shown to the model | `context` key/value pairs as in protocol 1 |
| Capabilities | The actions and features the game says it can run now | `offered_actions` as in protocol 1 |

Keep game names out of shared code, prompts, tables and tests. A fixture that needs a world
uses the fictional samples in `scripts/content/samples/`.

## Where each port records its choices

Each port documents its seams in `ports/<engine>/PLAN.md` using
[Engine planning](ENGINE_PLANNING.md): the cited mechanism for each row above, or an Unknown
with its next bounded probe. The PROJECT.md integration plan summarizes them.
