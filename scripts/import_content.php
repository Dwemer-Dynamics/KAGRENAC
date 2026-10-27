<?php
// Imports a reviewed content file (import.json from scripts/content/kagrenac_content.py export)
// into NPC bios and knowledge facts. Command line only; see docs/CONTENT_AUTHORING.md.
// The whole file is checked before anything else; one bad row refuses the file. This checks
// structure, ids, text, limits and the reviewed sha256 only: licences, sources and whether a
// row is static, spoiler-free lore were checked by the Python tool and the human review.
//   --file <path>                         check the file and print its sha256 (no database)
//   --file <path> --check-db              also compare it with the configured database (read only)
//   --file <path> --apply --expect-sha256 <sha256 of the reviewed file>
//                                         add missing rows in one transaction
// It only inserts. An existing bio, or a fact with the same topic in the same scope (including
// dashboard edits), is kept and reported; nothing is updated or deleted. Imported facts are
// source 'manual' (a person reviewed them); provenance stays in the external report.json.

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}
require __DIR__ . '/../lib/app.php';
require __DIR__ . '/../lib/knowledge.php';

const IMPORT_MAX_BYTES = 8 * 1024 * 1024;

function import_stop(string $message): never
{
    fwrite(STDERR, "import_content: $message\n");
    exit(1);
}

// Text must already be one clean line (what clean_line() would keep), without [ ] or URLs.
function import_text(mixed $value, string $where, int $min, int $max): string
{
    if (!is_string($value) || !mb_check_encoding($value, 'UTF-8') || clean_line($value) !== $value) {
        import_stop("$where must be one line of UTF-8 text without control characters or outer spaces.");
    }
    $length = mb_strlen($value);
    if ($length < $min || $length > $max) {
        import_stop("$where must be $min-$max characters (has $length).");
    }
    if (strpbrk($value, '[]') !== false || preg_match('~https?://|www\.~i', $value)) {
        import_stop("$where must not contain [ ] or a URL.");
    }
    return $value;
}

function import_id(mixed $value, string $where): string
{
    if (!is_string($value) || !preg_match('/^[A-Za-z0-9_.:-]{1,64}$/D', $value)) {
        import_stop("$where must be the game's npc.id: 1-64 characters of A-Z a-z 0-9 _ . : -");
    }
    return $value;
}

function import_fields(mixed $row, array $keys, string $where): array
{
    if (!is_array($row) || array_is_list($row) || count($row) !== count($keys) || array_diff($keys, array_keys($row))) {
        import_stop("$where must have exactly the fields " . implode(', ', $keys) . '.');
    }
    return $row;
}

$options = ['file' => null, 'apply' => false, 'check-db' => false, 'expect-sha256' => null];
for ($i = 1; $i < $argc; $i++) {
    $name = str_starts_with($argv[$i], '--') ? substr($argv[$i], 2) : '';
    if (!array_key_exists($name, $options)) {
        import_stop("unknown argument {$argv[$i]}. Usage: --file <path> [--check-db | --apply --expect-sha256 <sha256>]");
    }
    $options[$name] = is_bool($options[$name]) ? true : ($argv[++$i] ?? import_stop("--$name needs a value."));
}
if ($options['file'] === null) {
    import_stop('--file <path> is required.');
}
if ($options['apply'] && !preg_match('/^[0-9a-f]{64}$/D', (string)$options['expect-sha256'])) {
    import_stop('--apply needs --expect-sha256 with the sha256 the export printed for the reviewed file.');
}
if (!$options['apply'] && $options['expect-sha256'] !== null) {
    import_stop('--expect-sha256 is only used with --apply.');
}

$path = $options['file'];
if (!is_file($path) || !is_readable($path)) {
    import_stop('--file is not a readable file.');
}
$bytes = file_get_contents($path, false, null, 0, IMPORT_MAX_BYTES + 1);
if ($bytes === false || strlen($bytes) > IMPORT_MAX_BYTES) {
    import_stop('the file could not be read or is over ' . IMPORT_MAX_BYTES . ' bytes.');
}
$sha256 = hash('sha256', $bytes);
$data = json_decode($bytes, true, 8);
if ($data === null && json_last_error() !== JSON_ERROR_NONE) {
    import_stop('the file is not valid JSON (' . json_last_error_msg() . ').');
}
if (!is_array($data) || ($data['format'] ?? null) !== 'kagrenac-content' || ($data['version'] ?? null) !== 1
    || !is_array($data['bios'] ?? null) || !array_is_list($data['bios'])
    || !is_array($data['facts'] ?? null) || !array_is_list($data['facts'])) {
    import_stop('not a kagrenac-content version 1 file with bios and facts lists.');
}

$bios = [];
foreach ($data['bios'] as $n => $row) {
    $where = 'bios[' . $n . ']';
    $row = import_fields($row, ['npc_id', 'name', 'role', 'bio'], $where);
    $id = import_id($row['npc_id'], "$where.npc_id");
    if (isset($bios[$id])) {
        import_stop("$where repeats the bio for $id.");
    }
    $bios[$id] = [$id, import_text($row['name'], "$where.name", 1, 64),
        import_text($row['role'], "$where.role", 0, 64), import_text($row['bio'], "$where.bio", 1, MAX_BIO_CHARS)];
}
$facts = [];
foreach ($data['facts'] as $n => $row) {
    $where = 'facts[' . $n . ']';
    $row = import_fields($row, ['npc_id', 'topic', 'fact'], $where);
    $id = $row['npc_id'] === null ? null : import_id($row['npc_id'], "$where.npc_id");
    $topic = import_text($row['topic'], "$where.topic", 1, 64);
    $key = ($id ?? '') . "\n" . mb_strtolower($topic);
    if (isset($facts[$key])) {
        import_stop("$where repeats the topic \"$topic\" in its scope.");
    }
    $facts[$key] = [$id, $topic, import_text($row['fact'], "$where.fact", 1, MAX_FACT_CHARS)];
}
$global = count(array_filter($facts, fn($fact) => $fact[0] === null));
$summary = 'File valid: ' . count($bios) . ' bio(s), ' . (count($facts) - $global) . " NPC fact(s), $global global fact(s).\n"
    . "sha256 $sha256\n";
if (!$options['apply'] && !$options['check-db']) {
    echo $summary;
    echo "Dry run: the database was not opened. Add --check-db to compare, or --apply --expect-sha256 $sha256.\n";
    exit(0);
}
if ($options['apply'] && !hash_equals($options['expect-sha256'], $sha256)) {
    import_stop("the file sha256 $sha256 differs from --expect-sha256; it changed after review. Nothing was imported.");
}
// Nothing goes to stdout until the database work has succeeded: the shared helpers below stop
// with fail(), which sends headers and a JSON error, and earlier output would break that.

$db = db_connect(load_config());
require_schema($db);
$apply = $options['apply'];
$counts = ['new' => 0, 'same' => 0, 'kept' => 0];
$kept = [];
// Inserts a missing row; reports an existing one as identical or kept (different).
$import = function (string $label, string $select, array $key, array $values, string $insert, array $insertParams)
    use ($db, $apply, &$counts, &$kept): void {
    $existing = pg_fetch_row(db_query($db, $select, $key));
    if ($existing === false && $apply) {
        $existing = pg_affected_rows(db_query($db, $insert, $insertParams)) === 1 ? false : [];
    }
    if ($existing === false) {
        $counts['new']++;
    } elseif ($existing === $values) {
        $counts['same']++;
    } else {
        $counts['kept']++;
        $kept[] = $label;
    }
};

if ($apply) {
    db_query($db, 'BEGIN');
}
foreach ($bios as [$id, $name, $role, $bio]) {
    $import("bio $id",
        'SELECT name, role, bio FROM ex_npc_bios WHERE npc_id = $1', [$id], [$name, $role, $bio],
        'INSERT INTO ex_npc_bios (npc_id, name, role, bio) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING',
        [$id, $name, $role, $bio]);
}
foreach ($facts as [$id, $topic, $fact]) {
    $import('fact ' . ($id ?? 'global') . " / $topic",
        "SELECT topic, fact FROM ex_knowledge WHERE coalesce(npc_id, '') = $1 AND lower(topic) = lower($2)",
        [$id ?? '', $topic], [$topic, $fact],
        "INSERT INTO ex_knowledge (npc_id, topic, fact, source) VALUES ($1, $2, $3, 'manual') ON CONFLICT DO NOTHING",
        [$id, $topic, $fact]);
}
$missingBios = [];
foreach (array_unique(array_filter(array_column($facts, 0), fn($id) => $id !== null)) as $id) {
    if (!isset($bios[$id]) && pg_fetch_row(db_query($db, 'SELECT 1 FROM ex_npc_bios WHERE npc_id = $1', [$id])) === false) {
        $missingBios[] = $id;
    }
}
if ($apply) {
    db_query($db, 'COMMIT');
}

echo $summary;
echo ($apply ? 'Added' : 'Would add') . ": {$counts['new']}, already identical: {$counts['same']}, "
    . "existing and different, kept unchanged: {$counts['kept']}\n";
foreach ($kept as $label) {
    echo "  kept: $label\n";
}
if ($missingBios) {
    echo 'Note: no bio yet for ' . implode(', ', $missingBios) . " (facts still work).\n";
}
if ($apply && $counts['new'] > 0) {
    echo "Keyword search finds the new facts now. If vector search is on, each Reindex press on Memory\n"
        . "settings embeds up to 64 facts; see docs/CONTENT_AUTHORING.md (Limits) for the search limit.\n";
}
