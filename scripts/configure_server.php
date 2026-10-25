<?php
// Sets the dialogue provider, voice and server allowlist of this install from the command line,
// and optionally tests them once. Run by 'scripts\project.ps1 configure' inside DwemerDistro WSL,
// as the config's owner www-data:
//   sudo -u www-data php scripts/configure_server.php [--expect-id <manifest id>]
//       [--llm-mode openrouter|dwemerllm|mock] [--llm-model <model>] [--reuse-llm-key-from <private config.php>]
//       [--tts pockettts|off] [--tts-voice <voice>] [--allowed-actions <a,b>]
//       [--test-providers --base-url http://127.0.0.1:19000/custom-mods/<id>]
//
// - Every change goes through config_update() in lib/config_writer.php: one lock, the latest
//   config read inside it, only the llm, tts and allowed_actions sections changed (token,
//   database and unknown settings kept), owner, group, mode and lock kept. The same request
//   again writes nothing. A config www-data cannot save is refused with exit code 2. A test
//   alone changes nothing, so it only reads the config with config_read_fresh().
// - No key is ever an argument, read from stdin or printed. openrouter keeps the key already
//   configured only when llm.mode already is openrouter; otherwise --reuse-llm-key-from names
//   another install's private config, and only its llm.api_key is taken, after checking that its
//   llm.mode is openrouter. Its output and errors are discarded; its token, database and every
//   other setting are never copied. dwemerllm and mock leave llm.api_key as it is (neither sends it).
// - --tts pockettts enables DwemerDistro PocketTTS at its default local address with the voice
//   given; --tts off only turns voice off. --allowed-actions replaces the server allowlist with
//   known action names (or 'none' for an empty list); the caller checks nonempty lists against the game side first.
// - --test-providers makes one turn.php call (offered_actions [], its own test session) and one
//   speak.php call with that reply, no retry. It refuses before any call when vector search or
//   automatic memory would add model calls, or a profile would change the mode or model, and
//   passes only when the turn's event records the configured mode. Only status, timing, shape,
//   the reply's character count and the WAV's format, size and SHA-256 are printed; text and
//   audio are never printed or saved here. turn.php records the test turn in its own session like any turn.
// Exit codes: 0 done, 1 refused or failed (nothing saved), 2 the config cannot be saved,
// 3 saved (or unchanged) but the provider test failed.

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
require __DIR__ . '/../lib/config_writer.php';
require __DIR__ . '/../lib/app.php';
require __DIR__ . '/../lib/llm.php';
require_once __DIR__ . '/../lib/action_catalog.php';
require __DIR__ . '/../lib/profiles.php';
require __DIR__ . '/../lib/embeddings.php';
require __DIR__ . '/../lib/memory.php';

const CONFIGURE_LLM_MODES = ['openrouter', 'dwemerllm', 'mock'];
const POCKETTTS_LOCAL = ['provider' => 'pockettts', 'url' => 'http://127.0.0.1:8086/v1/audio/speech', 'model' => 'pocket-tts'];
const TEST_TEXT = 'Hello, can you hear me?';

function say(string $status, string $text): void
{
    echo "[$status] $text\n";
}

function refuse(string $text, int $code = 1): never
{
    say('FAIL', $text);
    exit($code);
}

$options = ['--expect-id' => null, '--llm-mode' => null, '--llm-model' => null, '--reuse-llm-key-from' => null,
    '--tts' => null, '--tts-voice' => null, '--allowed-actions' => null, '--base-url' => null];
$test = false;
for ($i = 1; $i < $argc; $i++) {
    if ($argv[$i] === '--test-providers') {
        $test = true;
        continue;
    }
    if (!array_key_exists($argv[$i], $options) || $options[$argv[$i]] !== null || $i + 1 >= $argc) {
        refuse('usage: php scripts/configure_server.php [--expect-id <id>] [--llm-mode openrouter|dwemerllm|mock] [--llm-model <model>] [--reuse-llm-key-from <file>] [--tts pockettts|off] [--tts-voice <voice>] [--allowed-actions <a,b>] [--test-providers --base-url <url>]');
    }
    $options[$argv[$i]] = $argv[++$i];
}

// Everything is checked before the config is touched.
$appDir = dirname(__DIR__);
if ($options['--expect-id'] !== null) {
    $manifest = json_decode((string)@file_get_contents("$appDir/dwemer-mod.json"), true);
    if (!is_array($manifest) || ($manifest['id'] ?? null) !== $options['--expect-id']) {
        refuse('This install is not ' . (preg_match('/^[a-z0-9-]{1,32}$/D', $options['--expect-id']) ? $options['--expect-id'] : 'the expected project') . ' (its dwemer-mod.json id differs). Nothing was changed.');
    }
}
$mode = $options['--llm-mode'];
if ($mode !== null && !in_array($mode, CONFIGURE_LLM_MODES, true)) {
    refuse('--llm-mode must be openrouter, dwemerllm or mock; set other modes on the dashboard LLM page.');
}
$model = $options['--llm-model'];
if ($model !== null && ($mode === null || $mode === 'mock' || form_name($model, 200, false) === null)) {
    refuse('--llm-model needs --llm-mode openrouter or dwemerllm and at most 200 characters of letters, digits and _ . : / @ + -');
}
if ($mode !== null && $mode !== 'mock' && $model === null) {
    refuse("--llm-mode $mode needs --llm-model (every mode except mock needs a model).");
}
$source = $options['--reuse-llm-key-from'];
if ($source !== null && $mode !== 'openrouter') {
    refuse('--reuse-llm-key-from is only for --llm-mode openrouter: a key is never reused for another provider.');
}
$tts = $options['--tts'];
$voice = $options['--tts-voice'];
if ($tts !== null && $tts !== 'pockettts' && $tts !== 'off') {
    refuse('--tts must be pockettts or off; set other voice providers on the dashboard Voice page.');
}
if (($tts === 'pockettts') !== ($voice !== null) || ($voice !== null && form_name($voice, 64, false) === null)) {
    refuse('--tts pockettts needs --tts-voice (at most 64 characters of letters, digits and _ . : / @ + -), and --tts-voice needs it.');
}
$actions = null;
if ($options['--allowed-actions'] !== null) {
    $actions = $options['--allowed-actions'] === 'none' ? [] : explode(',', $options['--allowed-actions']);
    // Only the actions the server knows: each has its prompt hint and target rule in ActionCatalog.
    if (count(array_unique($actions)) !== count($actions) || array_diff($actions, ActionCatalog::names())) {
        refuse('--allowed-actions must be different names from ' . implode(', ', ActionCatalog::names()) . ', separated by commas.');
    }
}
$baseUrl = $options['--base-url'];
if ($test) {
    // The test sends this install's token, so it only goes to this distro's own Apache.
    $parts = $baseUrl === null ? false : parse_url($baseUrl);
    if (!is_array($parts) || ($parts['scheme'] ?? '') !== 'http' || !in_array($parts['host'] ?? '', ['127.0.0.1', 'localhost'], true)
        || isset($parts['user']) || isset($parts['pass']) || isset($parts['query']) || isset($parts['fragment'])
        || !preg_match('#^(/[A-Za-z0-9._-]+)+$#D', $parts['path'] ?? '') || strlen($baseUrl) > 300) {
        refuse('--test-providers needs --base-url http://127.0.0.1:<port>/<route> of this install (the token is sent only to this distro).');
    }
} elseif ($baseUrl !== null) {
    refuse('--base-url is only used with --test-providers.');
}
if ($mode === null && $tts === null && $actions === null && !$test) {
    refuse('Nothing to do: name --llm-mode, --tts, --allowed-actions or --test-providers.');
}

// Loads a PHP config file with every byte it prints and every error discarded, also if it
// exits (then this script fails), so none of its values can reach the output. Returns what it
// returns, or null.
function load_private_config(string $file): mixed
{
    $loading = true;
    register_shutdown_function(function () use (&$loading): void {
        if ($loading) {
            while (ob_get_level() > 0) {
                ob_end_clean();
            }
            say('FAIL', 'That config stopped this script while it was loaded, so nothing was taken. Nothing was changed.');
            exit(1);
        }
    });
    $level = error_reporting(0);
    set_error_handler(fn() => true);
    ob_start(fn() => '');
    try {
        $value = (static fn(string $path) => require $path)($file);
    } catch (Throwable) {
        $value = null;
    } finally {
        $loading = false;
        ob_end_clean();
        restore_error_handler();
        error_reporting($level);
    }
    return $value;
}

// The OpenRouter key of another install's private config, named by the operator. Only
// llm.api_key leaves this function; nothing about the file's contents is printed.
function reused_openrouter_key(string $file, string $target): string
{
    clearstatcache();
    $real = realpath($file);
    if (strlen($file) > 300 || !preg_match('#^(/[A-Za-z0-9_.-]+)+\.php$#D', $file) || preg_match('#/\.\.?(/|$)#', $file)
        || $real !== $file || is_link($file) || !is_file($file)) {
        refuse('--reuse-llm-key-from must be the absolute path of an existing PHP config file, reached without links or . and .. parts. Nothing was changed.');
    }
    $targetReal = realpath($target);
    $stat = stat($file);
    if ($targetReal === $real || ($targetReal !== false && ($targetStat = stat($targetReal)) !== false
        && $targetStat['ino'] === $stat['ino'] && $targetStat['dev'] === $stat['dev'])) {
        refuse('--reuse-llm-key-from names this install\'s own config; leave it out to keep the key already configured. Nothing was changed.');
    }
    if (($stat['mode'] & 0007) !== 0) {
        refuse('--reuse-llm-key-from must be a private config (no access for other users); this one is not, so it was not read. Nothing was changed.');
    }
    if ($stat['size'] > CONFIG_MAX_BYTES || !is_readable($file)) {
        refuse('www-data cannot read that config, or it is too large. Nothing was changed.');
    }
    $config = load_private_config($file);
    $llm = is_array($config) && is_array($config['llm'] ?? null) ? $config['llm'] : null;
    $key = $llm['api_key'] ?? null;
    if ($llm === null || ($llm['mode'] ?? null) !== 'openrouter') {
        refuse('That config does not load, or its llm.mode is not openrouter, so its key is not taken. Nothing was changed.');
    }
    if (!is_string($key) || form_secret($key) !== $key || strlen($key) < 20 || preg_match('/CHANGE_ME|YOUR|<|>/i', $key)) {
        refuse('That config has no real OpenRouter llm.api_key, so nothing was taken. Nothing was changed.');
    }
    return $key;
}

$path = config_file_path();
$reusedKey = $source !== null ? reused_openrouter_key($source, $path) : null;
$notes = [];
$readOnly = $mode === null && $tts === null && $actions === null;
if ($readOnly && (!is_file($path) || !is_readable($path))) {
    refuse('www-data cannot read the config, so nothing was tested. Nothing was changed.');
}
try {
    $changed = false;
    $saved = $readOnly ? config_read_fresh($path) : config_update(function (array $latest) use ($mode, $model, $reusedKey, $tts, $voice, $actions, &$notes, &$changed): array {
        $new = $latest;
        if ($mode !== null) {
            $llm = is_array($latest['llm'] ?? null) ? $latest['llm'] : [];
            $current = $llm['mode'] ?? 'mock';
            $key = (string)($llm['api_key'] ?? '');
            if ($reusedKey !== null) {
                $notes[] = $key === $reusedKey ? 'llm.api_key: the named config holds the same key already configured (not shown).'
                    : 'llm.api_key: set from the named config\'s OpenRouter key (not shown); its token, database and other settings were not copied.';
                $llm['api_key'] = $reusedKey;
            } elseif ($mode === 'openrouter') {
                if ($current !== 'openrouter' || $key === '') {
                    throw new ConfigWriteError('openrouter needs its own key: llm.mode is ' . (is_string($current) ? $current : 'unknown')
                        . ' now, and a key is never reused across providers. Set the OpenRouter key on the dashboard API keys page with the LLM page in openrouter mode, or name another install\'s private config with --reuse-llm-key-from. Nothing was saved.');
                }
                $notes[] = 'llm.api_key: kept the OpenRouter key already configured (not shown).';
            } elseif ($key !== '') {
                $notes[] = "llm.api_key: left as it was; $mode never sends it.";
            }
            $llm['mode'] = $mode;
            if ($model !== null) {
                $llm['model'] = $model;
            }
            $new['llm'] = $llm;
        }
        if ($tts !== null) {
            $section = is_array($latest['tts'] ?? null) ? $latest['tts'] : [];
            // tts.api_key and unknown keys stay; PocketTTS never receives a key.
            $new['tts'] = $tts === 'off' ? ['enabled' => false] + $section
                : ['enabled' => true] + POCKETTTS_LOCAL + ['voice' => $voice, 'timeout_seconds' => (int)($section['timeout_seconds'] ?? 30)] + $section;
        }
        if ($actions !== null) {
            $new['allowed_actions'] = $actions;
        }
        $changed = $new !== $latest;
        return $new;
    });
} catch (ConfigWriteError $error) {
    // Exit 2 when the dashboard could not save it either; the caller adds the repair step.
    refuse($error->getMessage(), !$readOnly && config_write_problems($path) ? 2 : 1);
} catch (Throwable $error) {
    refuse('The config could not be saved (' . get_class($error) . '). Nothing was changed.');
}
unset($reusedKey);
foreach ($notes as $note) {
    say('INFO', $note);
}
$llm = is_array($saved['llm'] ?? null) ? $saved['llm'] : [];
$voiceSection = is_array($saved['tts'] ?? null) ? $saved['tts'] : [];
$printable = fn(mixed $value) => is_string($value) && preg_match('/^[\x21-\x7E]{1,200}$/D', $value) ? $value : '(not set)';
say('OK', ($changed ? 'Saved' : ($readOnly ? 'Read (test only; nothing was written)' : 'Unchanged (the same settings were already saved; nothing was written)'))
    . ': llm.mode ' . $printable($llm['mode'] ?? 'mock') . ', llm.model ' . $printable($llm['model'] ?? '')
    . ', tts ' . (!empty($voiceSection['enabled']) ? 'on (' . $printable($voiceSection['provider'] ?? 'pockettts') . ', voice ' . $printable($voiceSection['voice'] ?? 'alba') . ')' : 'off')
    . ', allowed_actions ' . (is_array($saved['allowed_actions'] ?? null) ? ($saved['allowed_actions'] ? implode(',', array_filter($saved['allowed_actions'], fn($n) => is_string($n) && preg_match('/^[A-Za-z0-9_]{1,40}$/D', $n))) : 'none') : 'default (' . implode(',', ActionCatalog::DEFAULT_ALLOWED) . ')') . '.');
echo 'RESULT config=' . ($changed ? 'saved' : 'unchanged') . ' test=' . ($test ? 'run' : 'skipped') . "\n";
if (!$test) {
    exit(0);
}

// One bounded provider test. Every refusal below happens before any call.
$mode = $llm['mode'] ?? 'mock';
if ($mode === 'mock' || !is_string($mode)) {
    refuse('Provider test not run: llm.mode is mock, which calls no provider. Nothing was called.', 3);
}
if (empty($voiceSection['enabled'])) {
    refuse('Provider test not run: voice is off (tts.enabled false), so no WAV could be made. Nothing was called.', 3);
}
// The same settings run_turn() reads: each would add model calls (and memory writes) to the one turn.
$memory = memory_settings($saved);
$extra = array_keys(array_filter(['embeddings.enabled' => embedding_settings($saved) !== null,
    'memory.auto_notes' => $memory['auto_notes'], 'memory.auto_extract' => $memory['auto_extract']]));
if ($extra) {
    refuse('Provider test not run: ' . implode(', ', $extra) . (count($extra) > 1 ? ' are' : ' is') . ' on, so the test turn would make more calls than its one reply. Turn ' . (count($extra) > 1 ? 'them' : 'it') . ' off on the dashboard Memory settings page to test here. Nothing was called.', 3);
}
$npcId = 'provider-test';
$db = db_connect_quiet($saved);
$profile = $db !== null && schema_problem($db) === null ? profile_for_npc($db, $npcId) : false;
if ($profile === false) {
    refuse('Provider test not run: the database or its profiles could not be read. Nothing was called.', 3);
}
if (is_array($profile) && (string)($profile['llm_mode'] ?? '') !== '' && $profile['llm_mode'] !== $mode) {
    refuse('Provider test not run: the default profile switches every unassigned NPC to ' . $printable($profile['llm_mode']) . ', so the reply would not come from ' . $mode . '. Nothing was called.', 3);
}
// profile_llm() also swaps in a profile's model while keeping the provider and its key.
if (is_array($profile) && (string)($profile['llm_model'] ?? '') !== '' && $profile['llm_model'] !== ($llm['model'] ?? null)) {
    refuse('Provider test not run: the default profile sets model ' . $printable($profile['llm_model']) . ' for every unassigned NPC, so ' . $mode . ' would be asked for that model instead of llm.model ' . $printable($llm['model'] ?? '') . '. Nothing was called.', 3);
}
say('INFO', 'Testing llm.mode ' . $printable($mode) . ', llm.model ' . $printable($llm['model'] ?? '') . ' (no profile override), then voice ' . $printable($voiceSection['provider'] ?? 'pockettts') . '.');
$headers = ['Content-Type: application/json', 'Authorization: Bearer ' . $saved['token']];
$session = 'provider-test-' . bin2hex(random_bytes(8));
$turnId = 'cfg-turn-' . bin2hex(random_bytes(8));
$body = json_encode(['protocol' => 1, 'request_id' => $turnId, 'session_id' => $session,
    'npc' => ['id' => $npcId, 'name' => 'Guide'], 'player' => ['name' => 'Traveler'], 'text' => TEST_TEXT, 'offered_actions' => []]);
$started = microtime(true);
try {
    [$status, $raw] = http_post("$baseUrl/turn.php", $headers, $body, min(120, (int)($llm['timeout_seconds'] ?? 30) + 15), 65536);
} catch (Throwable) {
    [$status, $raw] = [0, ''];
}
$ms = (int)round((microtime(true) - $started) * 1000);
$data = json_decode($raw, true);
$reply = is_array($data) && ($data['ok'] ?? null) === true && is_string($data['reply'] ?? null) ? clean_line($data['reply']) : '';
$shape = is_array($data) ? 'JSON, ok ' . var_export($data['ok'] ?? null, true) . ', reply ' . (is_string($data['reply'] ?? null) ? 'text' : 'missing')
    . ', ' . (is_array($data['actions'] ?? null) ? count($data['actions']) : 'no') . ' action(s)' : 'not JSON';
if ($status !== 200 || $reply === '' || $reply === '...' || ($data['actions'] ?? null) !== [] || ($data['protocol'] ?? null) !== 1) {
    $code = is_array($data) && is_string($data['error']['code'] ?? null) && preg_match('/^[a-z_]{1,40}$/D', $data['error']['code']) ? ', error ' . $data['error']['code'] : '';
    refuse("turn.php HTTP $status in $ms ms ($shape$code): no real reply from $mode, so speak.php was not called. Nothing was retried.", 3);
}
// The turn's own event row names the mode Apache actually used (after any profile), so a reply
// from an older cached config, such as mock, is never counted as this provider's.
$row = ($data['request_id'] ?? null) === $turnId && ($data['logged'] ?? null) === true ? @pg_query_params($db,
    "SELECT provider FROM ex_events WHERE request_id = $1 AND session_id = $2 AND kind = 'turn' AND status = 'complete'",
    [$turnId, $session]) : false;
$used = $row !== false ? pg_fetch_assoc($row) : false;
if (!is_array($used) || $used['provider'] !== $mode) {
    refuse("turn.php HTTP 200 in $ms ms ($shape), but " . (is_array($used) ? 'its event records provider ' . $printable($used['provider']) . " instead of $mode"
        : "no event of this turn confirms $mode (not logged or not found)") . ', so the reply is not counted and speak.php was not called. Nothing was retried.', 3);
}
say('OK', "turn.php HTTP 200 in $ms ms ($shape): a reply of " . mb_strlen($reply) . " characters from $mode as its event records (text not shown), session $session.");

$started = microtime(true);
try {
    [$status, $wav] = http_post("$baseUrl/speak.php", $headers, json_encode(['protocol' => 1, 'text' => $reply,
        'request_id' => 'cfg-tts-' . bin2hex(random_bytes(8)), 'parent_request_id' => $turnId]), min(120, (int)($voiceSection['timeout_seconds'] ?? 30) + 15), 20000000);
} catch (Throwable) {
    [$status, $wav] = [0, ''];
}
unset($reply, $data, $raw);
$ms = (int)round((microtime(true) - $started) * 1000);
// The WAV's fmt chunk, then its data chunk; anything else is not a usable WAV. Every chunk must
// fit in what was received; only a data chunk may declare the streaming size 0xFFFFFFFF
// (the rest of the file).
$format = null;
$dataBytes = 0;
for ($at = 12; is_wav($wav) && $at + 8 <= strlen($wav); $at += 8 + $size + ($size & 1)) {
    ['id' => $id, 'size' => $size] = unpack('a4id/Vsize', $wav, $at);
    $left = strlen($wav) - $at - 8;
    if ($id === 'data' && $size === 0xFFFFFFFF) {
        $size = $left;
    }
    if ($size > $left) {
        break;
    }
    if ($id === 'fmt ' && $size >= 16) {
        $format = unpack('vcode/vchannels/Vrate/Vbyterate/vblock/vbits', $wav, $at + 8);
    } elseif ($id === 'data') {
        $dataBytes = $format !== null ? $size : 0;
        break;
    }
}
// PCM (1) or float (3), and the byte rate, block size and data length agree with them.
$valid = $status === 200 && $format !== null && $dataBytes > 0 && $format['channels'] >= 1 && $format['channels'] <= 8
    && $format['rate'] >= 8000 && $format['rate'] <= 192000
    && in_array($format['bits'], $format['code'] === 1 ? [8, 16, 24, 32] : ($format['code'] === 3 ? [32, 64] : []), true)
    && $format['block'] === $format['channels'] * $format['bits'] / 8 && $format['byterate'] === $format['rate'] * $format['block']
    && $dataBytes % $format['block'] === 0;
if (!$valid) {
    refuse("speak.php HTTP $status in $ms ms: " . (is_wav($wav) ? 'a WAV without a usable PCM or float fmt and a complete data chunk' : 'no WAV') . ' (' . strlen($wav) . ' bytes). Voice failed; nothing was retried.', 3);
}
say('OK', "speak.php HTTP 200 in $ms ms: WAV format {$format['code']}, {$format['channels']} channel(s), {$format['rate']} Hz, {$format['bits']}-bit, $dataBytes data bytes, "
    . strlen($wav) . ' bytes, SHA-256 ' . hash('sha256', $wav) . ' (not saved).');
say('OK', "Provider test passed: a real reply from $mode and a valid WAV from " . $printable($voiceSection['provider'] ?? 'pockettts') . '. Generated is not heard: voice counts only once someone hears it (dashboard Voice page Speak, or in game).');
exit(0);
