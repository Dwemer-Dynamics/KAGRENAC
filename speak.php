<?php
// OPTIONAL VOICE: POST {"protocol":1,"text":"..."} and get audio/wav back.
// The provider call, profile voice and WAV check live in SpeechService (lib/speech.php).
// When TTS is off or fails, the reply is a JSON error and the game keeps the text subtitle.
// Optional fields (protocol 1 additions): request_id (made here when missing), parent_request_id
// (the turn this speech belongs to) and npc_id (only to pick that NPC's profile voice; it never
// changes who speaks or anything else). After the reply, one connector-audit row is written with
// ids, status and timing only: never the text or the audio.

require_once __DIR__ . '/lib/app.php';
require_once __DIR__ . '/lib/audit.php';
require_once __DIR__ . '/lib/speech.php';

$started = (float)($_SERVER['REQUEST_TIME_FLOAT'] ?? microtime(true));
$config = start_request('POST');
$input = read_json_body();
$requestId = trace_start($input['request_id'] ?? null);
$parentId = isset($input['parent_request_id']) ? require_id($input['parent_request_id'], 'parent_request_id', 8) : null;
$npcId = isset($input['npc_id']) ? require_id($input['npc_id'], 'npc_id') : null;
$text = require_text($input['text'] ?? null, 'text', 1000);

$tts = $config['tts'] ?? [];
$provider = SpeechService::provider($tts);
$audit = ['kind' => 'tts', 'provider' => $provider, 'request_id' => $requestId, 'parent_request_id' => $parentId, 'npc_id' => $npcId];
// The reply goes first; the audit row is written after it and can never change it.
$finish = function (int $status, ?string $code, string $message, array $row) use ($config, $started, $audit): never {
    send_json_then($status, ['ok' => false, 'error' => ['code' => $code, 'message' => $message]],
        fn() => audit_record($config, $row + ['error_code' => $code, 'duration_ms' => event_duration_ms($started)] + $audit));
};
// Every provider problem gives the game the same answer; only the audit detail differs.
$failed = fn(string $detail) => $finish(502, 'tts_unavailable', 'Text to speech failed. Show the text instead.',
    ['status' => 'failed', 'detail' => $detail]);
if (empty($tts['enabled'])) {
    $finish(503, 'tts_disabled', 'Text to speech is turned off on the server.', ['status' => 'disabled']);
}

// The NPC's profile may choose its voice. Any problem keeps the configured voice.
$speech = SpeechService::forNpc($config, $tts, $npcId);
[$wav, $detail] = $speech->synthesize($text);
if ($wav === null) {
    $failed($detail);
}

reply_then(200, 'audio/wav', $wav, fn() => audit_record($config, ['status' => 'ok', 'duration_ms' => event_duration_ms($started),
    'detail' => $detail] + $audit), ['X-Voice-Source: ' . $speech->voiceSource()]);
