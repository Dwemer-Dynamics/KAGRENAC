# Content authoring: NPC bios and world knowledge

How to turn sources you are allowed to use into reviewed NPC bios and knowledge facts, and
import them in one step instead of typing each one on the dashboard. Two tools do this:

- `scripts/content/kagrenac_content.py` (Python 3.9+, standard library only) collects
  sources, drafts candidate rows, checks your review and exports `import.json`.
- `scripts/import_content.php` (command line on the server) checks that file and inserts
  the missing rows.

Nothing here runs automatically, changes the game or the turn flow, or adds a schema. Both
tools work offline by default.

## What goes where

| Content | Stored as | Rules |
|---|---|---|
| Who an NPC is | One bio per NPC (`ex_npc_bios`): name, role, bio | Bios are capped at 600 characters, the amount the server sends with each turn (the database allows 1000) |
| Something an NPC knows | A fact scoped to that NPC (`ex_knowledge`) | Topic up to 64 characters, fact up to 300, one topic per scope |
| Something everyone knows | A global fact (npc_id empty) | Same limits; any NPC may use it |
| Persona, model, voice | A profile on the dashboard (`ex_profiles`) | Written by you on the dashboard. These tools never write profiles |
| Location, inventory, relationships, quest state | Live game awareness from the port | Read by the game with a source and freshness. Never import these as static lore |

The server sends the bio and up to three matching facts with each turn as quoted reference
data. Generated or sourced text only ever becomes a draft row; after a person approves it,
it reaches the model as that quoted data, never as profile or system instructions.

There is no quest, save or chapter gating. `scope` only chooses between one NPC and every
NPC, so an imported row is available from the first turn of every playthrough. You classify
each row's `availability` during review, and only `static` rows can be exported (see
[Review](#3-review)).

Bios and NPC facts use the NPC id your game adapter actually sends as `npc.id`. Fill in that
id yourself. Never derive it from a page title or display name.

## Workflow

Use a workspace folder outside every source checkout and web root, for example
`%LOCALAPPDATA%\DwemerDynamics\Kagrenac\projects\<id>\content`. The tool refuses `--out`
paths inside a Git checkout, `/var/www` (including `\\wsl$\...\var\www`), `htdocs`,
`public_html` and `wwwroot`. It writes these files there:

| File | Holds |
|---|---|
| `sources.jsonl` | One row per source: id, title, subject, URL, licence, attribution, revision, date, sha256 and plain text (max 20,000 characters) |
| `review.csv` | Candidate rows that you review and edit |
| `import.json` | The approved rows, written by `export` |
| `report.json` | Counts and the licence and attribution for every source the export used |
| `cache/` | Successful model drafts, keyed to the whole request: prompt, model, subject, title and source text |

All files are UTF-8 (NFC) with LF line endings. Running `export` again on the same review
gives byte-identical output.

### Try it with the fictional samples

In PowerShell, from the root of your checkout (use `py -3` instead of `python` if that is
how Python starts on your PC):

```powershell
$Repo = (Get-Location).Path
$Out = "$env:LOCALAPPDATA\DwemerDynamics\Kagrenac\projects\example\content-sample"
function kc { & python "$Repo\scripts\content\kagrenac_content.py" @args }

kc extract --out $Out --input "$Repo\scripts\content\samples\ferry_keeper.md" --subject npc --license CC0-1.0 --attribution 'KAGRENAC sample'
kc extract --out $Out --input "$Repo\scripts\content\samples\larkford.md" --license CC0-1.0 --attribution 'KAGRENAC sample'
kc draft --out $Out
Copy-Item "$Repo\scripts\content\samples\review.csv" "$Out\review.csv"
kc validate --out $Out
kc export --out $Out
```

`draft` writes offline candidate rows to `review.csv`. The copied `samples/review.csv` is
the reviewed version of those rows, and `export` prints the sha256 of `import.json`. The
remaining examples in this guide use the same `kc`, `$Repo` and `$Out`.

In bash (Linux, macOS or WSL), the same commands work with a shell function and a workspace
outside the checkout:

```bash
kc() { python3 scripts/content/kagrenac_content.py "$@"; }
OUT="$HOME/kagrenac-content/content-sample"
kc extract --out "$OUT" --input scripts/content/samples/ferry_keeper.md --subject npc --license CC0-1.0 --attribution 'KAGRENAC sample'
kc extract --out "$OUT" --input scripts/content/samples/larkford.md --license CC0-1.0 --attribution 'KAGRENAC sample'
kc draft --out "$OUT"
cp scripts/content/samples/review.csv "$OUT/review.csv"
kc validate --out "$OUT"
kc export --out "$OUT"
```

`samples/review.csv` contains an approved `static` bio, NPC facts and global facts, a fact
that clashes with the `seed_example.php` row for `npc_guide`, a row classified `spoiler`
and rejected, and a pending row with no availability yet.

### 1. Collect sources

**Offline (recommended).** Save pages or notes you may use as `.txt`, `.md` or `.html` and
add them:

```powershell
kc extract --out $Out --input 'C:\notes\blacksmith.md' --subject npc --license 'own work' --attribution 'Your name'
```

`--subject npc` drafts a bio and NPC facts, while `world` (the default) drafts global facts.
The source id comes from the file name, or from `--id` when there is a single file.
`--url` records where a single file came from but never fetches it.

**Fetch (optional).** This gets an exact list of public https pages. There is no crawling, link
following or page discovery. Put one line per page in a text file:

```text
smith_page html https://wiki.example.org/wiki/Blacksmith
mill_page mediawiki https://wiki.example.org/w/api.php Old Mill
```

`html` downloads that page. `mediawiki` uses the standard
[parse API](https://www.mediawiki.org/wiki/API:Parsing_wikitext) of the bare `api.php` URL
for the named page, so no extra extension is needed. Then run:

```powershell
kc fetch --out $Out --urls 'C:\notes\urls.txt' --license 'CC BY-SA 4.0' --attribution 'Example Wiki contributors' --contact you@example.org --allow-network
```

Without `--allow-network`, it checks the list and stops before opening any connection.
When fetching, it:

- reads each site's `robots.txt` first ([robotparser](https://docs.python.org/3.11/library/urllib.robotparser.html))
  and skips disallowed pages. Only a 404 or 410 counts as "no robots.txt". Any other answer
  that is not 200 (for example 401, 403, 407, 429, 451, a redirect or a server error) stops
  the run before any page from that site is requested.
- sends one request at a time and waits at least `--delay` seconds (a finite number, default
  2, minimum 1) between requests to a site, or longer if `robots.txt` sets a crawl delay or
  request rate.
- identifies itself honestly as `KagrenacContentTool/1 (+<contact>)`.
- does not follow redirects. List the final URL yourself.
- stops the whole run on 401, 403, 407, 429, 451, a server error, a MediaWiki `maxlag` or
  rate-limit reply, or a reply larger than `--max-bytes`. It never retries or works around a
  block. No proxy workaround is implemented; Python's `urllib` does use a proxy set in your
  environment (such as `HTTPS_PROXY`).
- refuses `http://` URLs, URLs with credentials and query parameters that look like keys or
  tokens. Error messages show only the host and status.
- keeps sources already in `sources.jsonl`. To get a new version, give it a new id.

Check the site's licence and terms yourself. Paraphrase in your review rather than copying
long passages, and keep the attribution `report.json` lists.

### 2. Draft candidates

```powershell
kc draft --out $Out
```

The offline draft splits each source into paragraphs. For an NPC source, the first
paragraph becomes the bio and the rest become facts, each cut at a sentence boundary and
titled by the nearest heading. Every row starts `pending` with `availability` and `npc_id`
empty. The `flags` column holds hints for the reviewer: English keywords that often mean
conditional, spoilery, player-specific or instruction-like text, plus brackets, URLs or
excessive length. Hints miss other languages and paraphrases and also match harmless lore,
so they decide nothing on their own.

`draft` only adds rows for sources that have none in `review.csv` yet. Rows you edited are
never changed. To redraft a source, delete its rows first.

**Model drafting (optional, paid).** This sends each source's text to OpenRouter and may cost
money:

```powershell
$env:OPENROUTER_API_KEY = [Net.NetworkCredential]::new('', (Read-Host 'OpenRouter key' -AsSecureString)).Password
kc draft --out $Out --generate --allow-paid-calls
Remove-Item Env:OPENROUTER_API_KEY
```

Type the key at the hidden prompt yourself. It then exists only in that PowerShell session,
not in the command line, history or a file; never paste it into a chat or commit it. In
bash, use `read -rs OPENROUTER_API_KEY; export OPENROUTER_API_KEY`, then
`kc draft --out "$OUT" --generate --allow-paid-calls` and `unset OPENROUTER_API_KEY`.

Optional flags: `--model <OpenRouter model id>` (default `google/gemma-4-31b-it`) and
`--max-calls <n>` (default 10; the remaining sources wait for the next run).

- The key is read only from the `OPENROUTER_API_KEY` environment variable. It is never
  written, logged or accepted as an argument.
- It sends one POST per source, with no retries, no redirects and a capped reply size. A
  failed or malformed reply stops the run, and no fallback text is invented.
- The source goes into the user message as untrusted data. The system prompt tells the model
  to use only what the source states.
- Each successful reply is cached under `cache/`, keyed to the whole request (prompt,
  model, subject, title and source text), and reused instead of a new call when the same
  request comes up again. Cached replies are checked like fresh ones. A failed or malformed
  reply is not cached, so deliberately running again repeats that call and may cost again.

Generated rows are drafts like any other. Check each one against the source.

### 3. Review

Edit `review.csv` in a text editor, or import it into a spreadsheet with every column set to
Text (do not open it by double-clicking), and save it as UTF-8 CSV. This keeps NPC ids such as
`000123`, sha256 values and source cells exactly as written. For each row:

- set `availability` (see below). It starts empty, and only `static` rows can be approved.
- set `status` to `approved` or `rejected` (rows still `pending` are skipped).
- for a bio or NPC fact, set `scope` to `npc` and `npc_id` to the game's real `npc.id`.
  For a fact everyone knows, set `scope` to `global` and leave `npc_id` empty.
- write the fact as one plain, self-contained sentence, and give each fact a topic that is
  unique within its scope.
- leave `source_id` and `source_sha256` as they are, so each row stays traceable to its source.

| `availability` | Means | Can be exported |
|---|---|---|
| `static` | Suitable for the chosen NPC (or every NPC, for a global row) at the supported starting or story point, whatever the player has done | Yes, when approved |
| `conditional` | True only after or until something happens: a quest step, a choice, a death | No: reject it or keep it pending |
| `spoiler` | Reveals a twist, ending or secret the player should learn later | No: reject it or keep it pending |
| `live` | Changes during play: location, inventory, relationships, quest state | No: the port reads it from the game instead |

The tools have no runtime progress or quest gates, so `conditional`, `spoiler` and `live`
rows stay pending or rejected until a port implements real gating. If a row you classify
`static` has hints in `flags`, either rewrite it or write a short reason in `notes` (for
example "quest is the name of the inn"). You do not need to reword a harmless sentence.
The tools cannot tell whether a fact is true or spoiler-free; that is your call.

### 4. Validate and export

```powershell
kc validate --out $Out
kc export --out $Out
```

Each approved row must meet these rules, and every problem is reported with its row number:

- NPC id: 1-64 characters of `A-Z a-z 0-9 _ . : -` and nothing else (no trailing line break).
- Lengths: name 1-64, role up to 64, bio 1-600, topic 1-64, fact 1-300 characters.
- Text: no line breaks, control characters, `[` `]` (which could form an action tag) or URLs.
- Scope: one bio per NPC and one topic per scope. Bios are always NPC-scoped, and global
  rows have no `npc_id`.
- Source: a known source with a licence and an unchanged sha256.
- Availability: `static`. A row whose text matches an English hint also needs a note.

`export` refuses to replace an existing `import.json` or `report.json` with different
content unless you add `--overwrite`.

### 5. Import on the server

Copy `import.json` to a private place outside the web root that the `dwemer` account can
read. Run the importer from the deployed server folder that contains it (the same place as
`seed_example.php`; see [SETUP.md](../SETUP.md#bios-knowledge-and-session-checkpoints)).
The dry run loads no config, so plain `php` works. `--check-db` and `--apply` read
`config/config.php`, so run them as `dwemer`, like the other server scripts in SETUP.md:

```bash
php scripts/import_content.php --file /private/path/import.json                           # check the file, print sha256; no database
sudo -u dwemer php scripts/import_content.php --file /private/path/import.json --check-db  # compare with the database; writes nothing
sudo -u dwemer php scripts/import_content.php --file /private/path/import.json --apply --expect-sha256 <sha256 from export>
```

The importer runs only from the command line. Before opening the database it checks the
file's structure, NPC ids, text rules, length limits and duplicate keys, and one bad row
refuses the whole file. It does not see sources, licences or availability: those were
checked by the Python tool and your review, and the sha256 ties the import to that file. `--apply` needs the
exact sha256 of the file you reviewed and inserts in one database transaction, so the file
is applied completely or not at all.

The importer only inserts. If a bio with the same NPC id, or a fact with the same topic in
the same scope, already exists, for example a dashboard edit or a `seed_example.php` row, it
keeps the existing row and lists it as `kept`. Change kept rows on the dashboard. Imported
facts are marked `manual`, the same as dashboard facts, while their source and licence stay
in your `report.json`. Keyword search finds new facts at once, with or without
vectors. If vector search is on, read the Reindex limits below.

## Limits

- The dashboard's **NPC bios** page shows bounded lists. Its bio list shows up to 50 bios
  that match its search by name or NPC id. Its Knowledge section shows up to 100 facts,
  the selected NPC's first and then global ones, with its own search by topic or fact text
  and a scope filter. Imported rows beyond those bounds are stored and retrieved normally;
  use the two searches to find them. The page's own add form stops at 50 facts per scope;
  the importer has no such limit.
- Retrieval sends at most three facts per turn, matched by keywords or vectors. Short,
  specific topics and facts match best.
- Vector search: each **Reindex** press on Memory settings embeds at most 64 facts that have
  no vector yet, and a turn compares only the newest 200 stored vectors for that NPC and
  global facts combined. More Reindex presses, made on purpose, process the remaining facts.
  With a paid embedding provider each press costs money, so decide first whether a large
  library needs vectors. Facts without a vector, or outside the newest 200, still match by
  keywords.
- There is no conditional or progress-gated knowledge. Facts that should change during the
  game need a port feature that reads the real state.
- Not covered: updating or deleting rows in bulk (use the dashboard), profiles and memory
  notes.
