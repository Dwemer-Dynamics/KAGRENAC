# Protocol, version 2 (draft)

Status (2026-11-20): draft for review. Not implemented; no server or client accepts
`"protocol": 2` yet. [PROTOCOL.md](../../PROTOCOL.md) (version 1) remains the only contract in
force. When version 2 ships, this file moves into the root contract and this draft is retired.

Version 2 adds asynchronous, streamed dialogue, a doorbell, spoken receipts and game RPC.
Version 1 endpoints keep working unchanged and run on the same server pipeline.

## Unchanged from version 1

- `Authorization: Bearer <token>` on every request except `health.php`.
- JSON bodies with a `protocol` field; the server refuses versions it does not know.
- The error shape `{"protocol":2,"ok":false,"error":{"code","message"}}` with a matching HTTP
  status, and the same codes where they apply.
- Request ids: 8-64 characters of `A-Z a-z 0-9 _ . : -`, new for each request, never reused.
- Clients never retry automatically.
- Everything from the game is untrusted and size-limited.

`health.php` adds `"protocols":[1,2]` and the capabilities `dialogue_async`, `doorbell`,
`spoken_receipt` and `game_rpc`. A client uses version 2 only when all four are listed.

## Envelope

Every version 2 request body has:

| Field | Rule |
|---|---|
| `protocol` | `2` |
| `type` | The request type, for example `dialogue.request` |
| `request_id` | As above |
| `session_id` | One per save load (load epoch), chosen by the client. A new load means a new id |
| `game_time` | Optional. The port's sortable game clock value ([GAME_ADAPTER.md](../GAME_ADAPTER.md)) |

## POST dialogue/request

One player line or one game event that needs a reply.

```json
{
  "protocol": 2,
  "type": "dialogue.request",
  "request_id": "req-1a2b3c4d5e6f7a8b9c0d1e2f",
  "session_id": "load-7f3c9a",
  "chain_id": "chain-41d2",
  "npc": {"id": "npc_guide", "name": "Guide"},
  "player": {"name": "Traveler"},
  "input_mode": "text",
  "text": "Follow me, please.",
  "context": {"location": "Market Square"},
  "capabilities": {"offered_actions": ["follow_player"]}
}
```

| Field | Rule |
|---|---|
| `chain_id` | Groups the lines of one exchange so it can be cancelled together |
| `input_mode` | `text`, `voice` (transcript the player confirmed) or `event` |
| `capabilities` | What the game can run now; the server returns nothing outside it |
| `context` | As in version 1 until the observation schema is designed |

Reply, before any provider call:

```json
{"protocol":2,"ok":true,"type":"dialogue.accepted","request_id":"req-1a2b3c4d5e6f7a8b9c0d1e2f"}
```

HTTP 202. The server then generates the reply and publishes one message per line.

## Doorbell

A WebSocket the client opens after pairing. The server sends only:

```json
{"type":"message_available","message_id":42,"request_id":"req-1a2b3c4d5e6f7a8b9c0d1e2f"}
```

The doorbell never carries dialogue text, audio or actions. The client fetches the message.
If the socket is down, the client may fetch pending messages for its session instead.
Endpoint, authentication of the socket and ports: open decision D1 in the
[migration plan](../MIGRATION_PLAN.md).

## GET messages/{id}

Delivers a completed message once. A pending message answers `409 pending`; a delivered,
cancelled or expired one answers `404 unknown_message`.

```json
{
  "protocol": 2,
  "ok": true,
  "type": "dialogue.result",
  "request_id": "req-1a2b3c4d5e6f7a8b9c0d1e2f",
  "session_id": "load-7f3c9a",
  "chain_id": "chain-41d2",
  "npc_id": "npc_guide",
  "segment": {"index": 0, "count": null},
  "text": "Of course.",
  "audio": "cache/audio/7c1e.wav",
  "actions": [{"name": "follow_player", "args": {"target_id": "npc_guide"}}]
}
```

- `segment.count` is `null` while the model is still writing; the last line carries the real
  count.
- `audio` is optional; without it the client shows the text only.
- `actions` appear at most once in an exchange and follow the version 1 rules.
- A message whose `session_id` or `npc_id` is not the one the client is waiting for is
  dropped before it is shown, spoken or reported.

## POST dialogue/spoken

The receipt for one line, sent when playback starts and when it ends.

```json
{"protocol":2,"type":"dialogue.spoken","request_id":"spk-91ab","session_id":"load-7f3c9a",
 "message_id":42,"status":"started"}
```

`status` is `started`, `finished`, `interrupted` or `skipped`. The server records only lines
the player actually heard or read in history. A receipt never changes a reply already sent.

## POST dialogue/cancel

Cancels pending lines by `npc_id`, `request_id` or `chain_id` within one session. Cancelled
messages are never delivered. Cancellation may not stop the provider call already running.

## Game RPC

The server sends over the socket:

```json
{"type":"rpc.request","id":"rpc-5521","method":"inventory.get","params":{"npc_id":"npc_guide"},
 "timeout_ms":1500}
```

The client answers on the same socket:

```json
{"type":"rpc.response","id":"rpc-5521","ok":true,"result":{"items":[]}}
```

- Methods are allowlisted on both sides; `health.php` lists the server's.
- `timeout_ms` defaults to 1500 and is capped at 5000.
- Errors: `unknown_method`, `bad_params`, `not_found`, `not_in_game`, `busy`, `internal_error`.
- A response for an unknown or expired id is ignored.

## Open questions

- Socket authentication: token in the upgrade request, or a short-lived ticket from an HTTP
  call.
- Whether game events without a reply move to version 2 or stay on `event.php`.
- The observation schema that replaces free `context` pairs.
- Limits: message lifetime, messages per exchange, RPC calls in flight.
