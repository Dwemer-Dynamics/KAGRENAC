<?php
// Text to speech for speak.php: the provider request, the NPC's profile voice and the WAV check.
// This file only declares a class, so requesting it over HTTP prints nothing.
// tts.provider 'pockettts' uses DwemerDistro PocketTTS (audio.cpp, port 8086); 'openai' uses
// any OpenAI-compatible /v1/audio/speech endpoint that returns WAV. The endpoint keeps request
// validation, the token check, the disabled answer and the connector audit row; this class
// never sees the request, never replies and never logs the text, the audio or a key.

require_once __DIR__ . '/app.php';
require_once __DIR__ . '/profiles.php';

final class SpeechService
{
    public const MAX_WAV_BYTES = 20000000;

    private function __construct(private array $tts, private string $voiceSource)
    {
    }

    // The configured provider. Configs from before tts.provider existed are PocketTTS.
    // Takes the raw config section, which may not be an array, so speak.php can name the
    // provider in its audit row before checking tts.enabled.
    public static function provider(mixed $tts): mixed
    {
        return $tts['provider'] ?? 'pockettts';
    }

    // The tts settings for one request. The NPC's profile may choose its voice; any problem
    // keeps the configured voice. $npcId only picks the voice, never who speaks.
    public static function forNpc(array $config, array $tts, ?string $npcId): self
    {
        if ($npcId !== null) {
            $db = db_connect_quiet($config);
            $profile = $db !== null && schema_problem($db) === null ? profile_for_npc($db, $npcId) : false;
            if ($profile === false) {
                app_log('profile voice lookup skipped; using the configured voice');
            } elseif (($profile['tts_voice'] ?? null) !== null) {
                return new self(profile_tts($tts, $profile), 'profile');
            }
        }
        return new self($tts, 'config');
    }

    // 'profile' or 'config': where the voice came from.
    public function voiceSource(): string
    {
        return $this->voiceSource;
    }

    // One provider call, no retry. Returns [WAV bytes, audit detail] or [null, audit detail].
    public function synthesize(string $text): array
    {
        $tts = $this->tts;
        $provider = self::provider($tts);
        $headers = ['Content-Type: application/json', 'Accept: audio/wav'];
        $request = ['model' => $tts['model'] ?? 'pocket-tts', 'input' => $text, 'voice' => $tts['voice'] ?? 'alba'];
        if ($provider === 'openai') {
            if ((string)($tts['model'] ?? '') === '') {
                app_log('tts.model must be set for the openai provider');
                return [null, 'model missing'];
            }
            $request['response_format'] = 'wav';
            $apiKey = (string)($tts['api_key'] ?? '');
            if ($apiKey !== '') {
                $headers[] = "Authorization: Bearer $apiKey";
            }
        } elseif ($provider !== 'pockettts') {
            app_log('unknown tts.provider');
            return [null, 'unknown provider'];
        }

        try {
            [$status, $wav] = http_post((string)($tts['url'] ?? ''), $headers, json_encode($request),
                (int)($tts['timeout_seconds'] ?? 30), self::MAX_WAV_BYTES);
        } catch (Throwable $error) {
            app_log($error->getMessage());
            [$status, $wav] = [0, ''];
        }
        if ($status !== 200 || !is_wav($wav)) {
            app_log("TTS failed with HTTP $status");
            return [null, "provider HTTP $status, voice from {$this->voiceSource}"];
        }
        return [$wav, 'WAV ' . strlen($wav) . " bytes, voice from {$this->voiceSource}"];
    }
}
