# Setup: KAGRENAC AI Mod Maker (KagrenacServer + KagrenacClient)

This walkthrough installs KagrenacServer inside DwemerDistro, builds the KagrenacClient
console client on Windows, and connects the two. Both come from one repository: the server
is the repository root and the client is `client/`. The short developer path, including
`scripts\project.ps1`, is [docs/getting-started.md](docs/getting-started.md). Allow about 15 minutes. It is the
canonical reference for installation and operations; for orientation, the feature checklist
and troubleshooting by request ID, start with [START_HERE.md](START_HERE.md).

## What this is, and what it is not

- **KagrenacServer** is a small PHP 8.2 + PostgreSQL server. It gives an NPC a reply (mock or
  a real LLM) and at most one safe action, `follow_player`.
- **KagrenacClient** is a Windows console program that plays a fake game. It shows the
  `GameAdapter` boundary you replace with a real engine's APIs.
- It is **not** a plugin for any real game. Your copy of the repository has no automatic
  upstream; only the dashboard's presentation is adapted third-party work (see
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). A project made from this template
  takes later template changes by hand.
- This guide is a **manual install** into `/var/www/html/custom-mods/KagrenacServer`; the official
  launcher and updater do not install, update or back up that copy. Alternatively, the
  launcher can install the server under **Mods > Custom mods** in its own folder and
  database; see [LAUNCHER_CUSTOM_MOD.md](LAUNCHER_CUSTOM_MOD.md). The client is always built
  as described in section 2.

## Requirements

| Where | What |
|---|---|
| Windows | DwemerDistro installed and started (it provides WSL, Apache with the shared custom mods port 19000, PostgreSQL, PHP 8.2). |
| Windows | Visual Studio 2022 with "Desktop development with C++" (MSVC, CMake). |
| Optional | An OpenAI-compatible LLM endpoint (cloud or local). Not needed for the mock. |
| Optional | For voice, start with DwemerDistro PocketTTS (text-to-speech, audio.cpp, port 8086) and Parakeet (speech-to-text, port 8022); faster-whisper (port 9876) is an alternative. |

| Repository | URL |
|---|---|
| Kagrenac (server at the root, client in `client/`) | <https://github.com/Dwemer-Dynamics/Kagrenac> |

It offers `main` (default, the stable baseline) and `dev` (development). For your own
project, create your own repository with GitHub's **Use this template** (or a fork) and
clone that instead ([MAKE_IT_YOURS.md](MAKE_IT_YOURS.md)).

### Two copies, two jobs

| Copy | Where | Used for | Never |
|---|---|---|---|
| Windows development copy | Any folder you own on Windows, outside DwemerDistro | Editing, building the client (output in `%LOCALAPPDATA%`), `scripts\project.ps1` | Served by Apache |
| WSL server copy | `/var/www/html/custom-mods/KagrenacServer` (manual) or `/custom-mods/example-server` (launcher) | Running the server: `install.sh`, `update.sh`, `smoke.sh`, pairing to a file outside the web root | Building the client, writing a client `config.json`, or holding build output |

The server copy is not synced from the Windows copy. From Windows,
`scripts\project.ps1 deploy -WslDistro <name>` installs or updates it from your committed
HEAD through DwemerDistro Core
([getting-started](docs/getting-started.md#deploy-and-pair)); a manual clone is updated with
`update.sh`, and a launcher install with the launcher. This page describes the manual route.

## Before you install: web protection

The server copy is the whole repository, so Apache's web root also holds `.git/` and the
source-only `client/`, `docs/` and `ports/` folders. Install DwemerDistro Core's custom mod
web protection **before** you install this server or update an existing install to this
consolidated layout. It comes with **Update Distro** in a Core version whose
`ddistro_custom_mod setup-web` writes the deny rules described in Core's `CUSTOM_MODS.md`;
then apply it:

```bash
sudo ddistro_custom_mod setup-web
grep -qF 'client|ports|docs|config|lib|sql|scripts' /etc/apache2/sites-available/dwemerdistro-custom-mods.conf && echo protected
```

It must print `protected`. A Core whose rules list fewer source folders (for example only
`client|ports|docs`) does not give this protection and these flags may not yet be in a
public Core release: wait for a compatible Core, or add equivalent server-side Apache rules
yourself before installing. The protection covers `.git/` under every custom mod, and the
source folders `client/`, `ports/`, `docs/`, `config/`, `lib/`, `sql/` and `scripts/` plus
any `config.json` or `.env` file under `/custom-mods/KagrenacServer`,
`/custom-mods/example-server` and `/ExampleServer`. Any other folder (a renamed copy or a
fork) is covered only after `sudo ddistro_custom_mod setup-web --protect-project <folder>`
(a folder directly under `custom-mods/`, run **before** you clone into it, same Core
requirement), or by equivalent server-side Apache rules of your own; nothing protects
arbitrary paths by itself. The `grep` only shows the rules exist: after installing, check
for HTTP 403 on every Apache port that serves `/var/www/html` as
[START_HERE.md](START_HERE.md#deployment-and-exposure) describes, using your own folder in
the URL.

## 1. Install the server (inside DwemerDistro)

For your own mod, the usual route is `project.ps1 deploy` from Windows
([getting-started](docs/getting-started.md#deploy-and-pair)). The manual install below is a
separate route; deploy never adopts or repoints it, but can update it when you name it with
`-WslServerPath`.

Open a DwemerDistro WSL shell as the `dwemer` user, for example from Windows:

```powershell
wsl -d DwemerAI4Skyrim3 -u dwemer
```

Clone the repository into the custom mods folder of Apache's web root (add `-b dev` for the
development branch). The folder name stays `KagrenacServer`; that is the server's route. The
first command creates the empty install folder, owned by `dwemer`:

```bash
sudo install -d -o dwemer -g dwemer /var/www/html/custom-mods/KagrenacServer
git clone https://github.com/Dwemer-Dynamics/Kagrenac.git /var/www/html/custom-mods/KagrenacServer
```

Optional, for a local repository that is not published anywhere: export its committed
history as a Git bundle on Windows and clone the bundle inside WSL. This avoids Git
ownership errors when WSL reads a Windows checkout.

```powershell
$bundleFolder = Join-Path $env:LOCALAPPDATA "DwemerDynamics"
New-Item -ItemType Directory -Force $bundleFolder
git -C "C:\path\to\Kagrenac" bundle create (Join-Path $bundleFolder "Kagrenac.bundle") --all
```

```bash
sudo install -d -o dwemer -g dwemer /var/www/html/custom-mods/KagrenacServer
git clone /mnt/c/Users/<windows-user>/AppData/Local/DwemerDynamics/Kagrenac.bundle /var/www/html/custom-mods/KagrenacServer
```

A bundle is a snapshot, not an update source: set a real remote with
`git remote set-url origin https://github.com/<owner>/<repository>.git` before using
`update.sh`.

Run the installer:

```bash
cd /var/www/html/custom-mods/KagrenacServer
sudo bash scripts/install.sh
```

The installer:

- copies `config/config.example.php` to `config/config.php` **only if it is missing**, with
  a new random token;
- sets `config/` to owner `www-data`, group `dwemer` (the checkout owner's primary group),
  mode `2770`, and `config/config.php` (plus an existing `config.php.lock`) to
  `www-data`:`dwemer` mode `660`, keeping the file contents. Run it again to repair them;
- creates the configured database (default `example_ai_mod`) **only if it is missing**, owned by the existing
  `dwemer` role (no new roles, grants or server settings);
- applies new migrations from `sql/` (safe to repeat);
- changes nothing in Apache, PHP or any other product.

Running it again keeps your config and data.

You already ran `setup-web` in [Before you install](#before-you-install-web-protection);
it serves every folder directly under `/var/www/html/custom-mods/` on the shared custom mods
port, including this one. Running it again is safe (it only writes the distro's own Apache
site and never changes official servers):

```bash
sudo ddistro_custom_mod setup-web
```

All custom PHP mods share this one loopback port, `CUSTOM_MODS_PORT` in
`/etc/dwemerdistro_services.conf` (default `19000`, allowed `19000`-`19999`), each under
its own path and with its own database. Official server ports such as 8081 are unchanged.
If the port is busy, `setup-web` says so and changes nothing. To use another port, set
`CUSTOM_MODS_PORT` as root, run `sudo ddistro_custom_mod setup-web` again, then update
every client's `server_url` (pair again, below) to the new port. The examples here
assume `19000`.

Check it:

```bash
curl http://127.0.0.1:19000/custom-mods/KagrenacServer/health.php
# {"protocol":1,"ok":true,"service":"example-ai-server","schema":"007_connector_calls","expected_schema":"007_connector_calls","capabilities":["turn","cancel","result","game_event","action_target","decision","speak","listen","profiles","memory","trace"],"baseline":"baseline-1","server_version":"0.1.0"}
bash scripts/smoke.sh
```

`"service":"example-ai-server"` is a fixed compatibility identity; it does not follow the
project name.

The shared port serves each folder directly under `/var/www/html/custom-mods/` at
`/custom-mods/<folder>`, so this install answers at
`http://127.0.0.1:19000/custom-mods/KagrenacServer`. `smoke.sh` and the client's shipped
`server_url` default to that address, and pairing infers it from the folder.

### A separate copy with its own database

Use a distinct folder and database when another KagrenacServer is already installed. Put
the copy in its own folder directly under `/var/www/html/custom-mods/`, for example
`my-project`; it is served at `/custom-mods/my-project`. Use letters, digits, `.`, `_` or `-`
in the folder name so pairing can infer the address, and do not use an id the launcher
installs, such as `example-server`. A folder with another name is **not** covered by Core's
default web protection: before cloning, run
`sudo ddistro_custom_mod setup-web --protect-project my-project` or add equivalent Apache
rules ([Before you install](#before-you-install-web-protection)). The
installer creates `database.name` from
your private config if it is missing. Use 1-63 lowercase letters, digits or underscores,
starting with a letter. Choose a new name for your own project; never point a copy at
another product's database.

```bash
sudo install -d -o dwemer -g dwemer /var/www/html/custom-mods/my-project
git clone https://github.com/Dwemer-Dynamics/Kagrenac.git /var/www/html/custom-mods/my-project
cd /var/www/html/custom-mods/my-project
# Before running install.sh:
cp config/config.example.php config/config.php
php -r '$p="config/config.php"; $s=file_get_contents($p); file_put_contents($p, str_replace("CHANGE_ME_TOKEN", bin2hex(random_bytes(24)), $s));'
# Edit only database.name in config/config.php to my_project_ai.
nano config/config.php
sudo bash scripts/install.sh
curl http://127.0.0.1:19000/custom-mods/my-project/health.php
bash scripts/smoke.sh http://127.0.0.1:19000/custom-mods/my-project
# Pair from this folder too; its server_url is .../custom-mods/my-project.
```

Keep the generated token private. The existing config is preserved on later installer
runs. Do not run the default-database removal commands below against another copy's data.

### Who can read what

| Path | Owner:group | Mode | Why |
|---|---|---|---|
| checkout files | `dwemer`:`www-data` (inherited) | default | Apache (`www-data`) only reads code. |
| `config/` | `www-data`:`dwemer` | `2770` | New files (lock, temporary saves) inherit the `dwemer` group. |
| `config/config.php`, `config.php.lock` | `www-data`:`dwemer` | `660` | Token and database password; the dashboard saves it, `dwemer` reads and writes it through the group. |
| backups (`backup.sh`) | `dwemer` | `700` / `600` | Kept in `/home/dwemer/example-ai-server-backups`, outside the web root. |
| dashboard backups | web server user | `700` / `600` | `backup_dir` in the config, or an app folder in the system temp directory. |

The API keeps conversation state in its own database. Dashboard CSRF checks use PHP's
session storage.

**Saving settings from the dashboard.** The settings pages rewrite `config/config.php`
atomically: they take `config/config.php.lock`, read the latest file, change only their own
section, write a temporary file in `config/` and rename it over the config, keeping its
owner, group and mode. They never change `token`, `database` or keys they do not know, but
comments in the file are not kept. They refuse to save, with a clear message and no
change, when:

- `config/` or `config/config.php` is not writable by the web server user (the folder needs
  write access for the lock and temporary files);
- the web server user does not own the file (a rename would change the owner);
- the web server user is not in the file's group and `config/` is not setgid with that group
  (the temporary file would get a different group);
- the config path, or its folder, is a symbolic link.

The installer sets up the ownership that allows saving (`www-data` does not need to be in
the `dwemer` group). If you changed it by hand, run `sudo bash scripts/install.sh` again;
the dashboard itself never changes the config's owner or group. Check **Control Panel > Diagnostics** ("Dashboard can save
settings") after any change.
Do not rely on `.htaccess` to protect secrets. Secrets are kept in `config/config.php`,
which prints nothing when served through PHP. `scripts/smoke.sh` checks that the token is
not visible at `config/config.php`. It does not check other files in the checkout. Only
DwemerDistro Core's web protection ([Before you install](#before-you-install-web-protection))
stops Apache from serving `.git/` and the source-only `client/`, `docs/` and `ports/`
folders, and only at the known install paths; other non-PHP files stay readable. Check that
yourself as [START_HERE.md](START_HERE.md#deployment-and-exposure) describes.

You can also open `http://127.0.0.1:19000/custom-mods/KagrenacServer/` directly in your browser; there is
no dashboard login. Keep it on localhost or a trusted network: anyone who can open it can
change settings and keys. It offers settings, LLM, Voice, NPC selection and API key pages,
a conversation test, retained history, checkpoints, diagnostics and backups. Its test
session is `dashboard-demo` by default, separate from the console client's default session. See [UI_GUIDE.md](UI_GUIDE.md) to extend its
blank, form and table example pages.

## 2. Build the client (Windows)

Use your Windows development copy, never the server copy in WSL:

```powershell
git clone https://github.com/Dwemer-Dynamics/Kagrenac.git
cd Kagrenac
powershell -ExecutionPolicy Bypass -File client\scripts\build.ps1
```

`powershell -ExecutionPolicy Bypass -File scripts\project.ps1 setup` runs the same build and
reports what else is still a manual step.

This builds x64 and x86 into `%LOCALAPPDATA%\DwemerDynamics\KagrenacClient\build\x64\Release` and `...\x86\Release`
(change with `-BuildRoot`). `config.default.json` is copied next to each `KagrenacClient.exe`.

## 3. Connect them

From Windows, one command writes the private client config (your agent runs it):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 pair -WslDistro <name> `
  -WslServerPath /var/www/html/custom-mods/KagrenacServer -OutFile <full path>\config.json
```

Put `-OutFile` outside every repository and web root (next to `KagrenacClient.exe`, or the
game-side runtime folder). The file is created private to you, and the token is never
printed. An existing file with the same URL, token and session is kept as already paired;
anything different is refused. Options: `-ServerUrl`, `-SessionId`, `-AllowedActions`.

What it runs, if you work inside WSL instead: `pair_client.php` writes a new file with mode
0600, outside the web root, in a folder you own that other users cannot write to (your
home folder is fine); an existing file or link is never replaced and the token is not
printed:

```bash
cd /var/www/html/custom-mods/KagrenacServer
sudo -u dwemer php scripts/pair_client.php --out /home/dwemer/example-client.json
```

The address is inferred for installs under `/var/www/html` (here
`http://127.0.0.1:19000/custom-mods/KagrenacServer`; a copy in `/var/www/html/custom-mods/my-project` gets
`.../custom-mods/my-project`; a launcher install gets `.../custom-mods/example-server`), on port 19000. If you changed `CUSTOM_MODS_PORT`, or the folder
is anywhere else, add `--base-url http://127.0.0.1:<port>/<path>`. The shared port listens
on loopback only. `--session-id` is optional.

Copy that file to Windows next to `KagrenacClient.exe` and name it `config.json` (git-ignored),
for example from PowerShell:

```powershell
Copy-Item \\wsl.localhost\DwemerAI4Skyrim3\home\dwemer\example-client.json .\config.json
```

Then delete the WSL copy if you do not need it. Treat both copies like a password.

Run:

```text
> KagrenacClient.exe --health
Server is ready.
Versions: client 0.1.0, client baseline baseline-1, server 0.1.0, server baseline baseline-1, schema 007_connector_calls, protocol 1.
> KagrenacClient.exe --say "Follow me"
[Guide] Of course. Lead the way.
* npc_guide is now following you (simulated).
> KagrenacClient.exe
* Type to talk. Commands: /cancel  /listen <file.wav>  /decide <text>  /event <type> <text>  /react <type> <text>  /npc guide|scout  /session <id>  /unload  /load  /quit
```

After `--say "Follow me"` the client also sends an optional result report, printed as
`Result reported to server: follow_player handled (client-reported, console simulation).`
Open Control Panel > Logs: the turn shows as `complete` and its details show the report
under "Client reported (untrusted)". It is what the console client says, not a game engine.

To see cancellation, set `'mock_delay_seconds' => 3` in `config/config.php`, type a line,
then `/cancel` before the reply arrives. Logs then shows the turn as `cancelled`.

If the server runs on another PC, set `server_url` to that host. The token travels in plain
HTTP, so only do this on a trusted local network.

## 4. Use a real LLM (optional)

Reuse a provider you already have. Otherwise the recommended start is OpenRouter with
[`google/gemma-4-31b-it`](https://openrouter.ai/google/gemma-4-31b-it) for dialogue
(`decision.php` choices can use [`typesafe/jev-1.13`](https://openrouter.ai/typesafe/jev-1.13),
never chat or actions; [CONNECTORS.md](CONNECTORS.md)). Nothing has to answer on port 1234
unless you chose `dwemerllm` or a local server there. The easiest way is the dashboard:

1. Open **Configuration > LLM** and choose a **Reply mode**: `openai`, `openrouter`,
   `local` (any OpenAI-compatible server you run, such as LM Studio) or `dwemerllm`
   (DwemerDistro LLM Studio). `mock` needs nothing.
2. For `local`, set **Base URL** to the server's `/v1` address, for example
   `http://127.0.0.1:1234/v1`. For `openai` it is optional (empty means
   `https://api.openai.com/v1`); `openrouter` and `dwemerllm` use fixed URLs.
3. Set **Model** to the exact model name your provider or local server lists. Every mode
   except `mock` needs one.
4. If the provider needs a key, open **Configuration > API keys**, paste it into the `llm.api_key`
   slot and press **Save keys**. The key is never shown again; `dwemerllm` never receives it.
5. Back on **Configuration > LLM**, press **Save LLM settings** (saving never contacts the
   provider), then **Send test**. The test shows the reply and its time, or, on failure, a
   short reason such as `HTTP 401` (key refused), `HTTP 404` (URL or model not found) or a
   network error (could not connect, timed out). Provider replies are never shown. A test
   may cost money; it saves no history and runs no actions.

Or edit `config/config.php` in WSL. `mode` is one of `mock`, `openai`, `openrouter`, `local`
or `dwemerllm`; every mode except `mock` needs an explicit `model`. Copyable blocks for each
are in [CONNECTORS.md](CONNECTORS.md). For example:

```php
'llm' => [
    'mode' => 'openai',
    'base_url' => 'https://api.openai.com/v1',   // or any OpenAI-compatible server
    'model' => 'your-model-name',
    'api_key' => '',                             // paste your key; empty for servers without keys
    'timeout_seconds' => 30,
    'max_tokens' => 200,
    'mock_delay_seconds' => 0,
],
```

Changes apply on the next request; no restart needed. If the model fails, the game gets
`502 llm_unavailable` and the reason is in the Apache error log.

## 5. Voice (optional)

Voice is off by default and is never needed for text. To try it:

1. Start with PocketTTS (audio.cpp) for text-to-speech (TTS) and Parakeet for
   speech-to-text (STT). They are the recommended DwemerDistro starting choices and are
   often already available in existing setups. In the DwemerDistro launcher, check that
   each one you want is there, install it if it is missing, and start it.
2. In `config/config.php` (or on the dashboard Voice page) set
   `'tts' => ['enabled' => true, ...]` and/or `'stt' => ['enabled' => true, ...]`. The
   default URLs are `http://127.0.0.1:8086/v1/audio/speech` and
   `http://127.0.0.1:8022/v1/audio/transcriptions`; change them if your services run
   elsewhere. To use faster-whisper instead of Parakeet, see [CONNECTORS.md](CONNECTORS.md).
   For PocketTTS a blank model or voice saves the defaults `pocket-tts` and `alba`.
3. Test on the dashboard **Configuration > Voice** page after saving: **Speak** should play
   audio, and for Parakeet choose a short WAV file (at most 10 MB) under **Test
   transcription** and press **Transcribe**; the transcript appears in the box below. Both
   show a request id that **Control Panel > Connector calls** lists.
4. In the client `config.json` set `"voice_enabled": true`. Replies are saved as WAV files
   in `%TEMP%\dwemer-ai-example\`. Use `/listen <file.wav>` or `--listen <file.wav>` for
   speech input.

Every voice call has a request id. The client prints it with the turn it belongs to, for
example `Trace: voice tts-... for turn req-... (ok)`, and **Control Panel > Connector calls** lists
the call (provider, status, time taken; never audio or text) under that turn. A profile with
a TTS voice changes the voice for its NPCs (the client sends the NPC id with the speech).

Only these services are supported: PocketTTS, an OpenAI-compatible speech endpoint that
returns WAV (`'provider' => 'openai'`, see [CONNECTORS.md](CONNECTORS.md)), Parakeet and
faster-whisper.
Other DwemerDistro voice services are not wired in. When a voice service is off, fails or
hears nothing usable, the client says so and keeps text or asks the player to type.

## 5b. Profiles, memory and tracing (optional)

Nothing here is needed for the walkthrough, and all of it is off or empty after install. The
installer applies migrations `005_profiles`, `006_memory` and `007_connector_calls` (also on an
upgrade from `004_game_events`); they add tables and columns only and change no existing row.

- **Profiles**: Configuration > World & Behavior > **Profiles**. Create a profile (name and
  system prompt; model, reply mode and TTS voice are optional and inherit the config when
  empty), then assign NPC ids. Tick **Default** to apply it to every NPC without its own
  profile. A profile can switch only to `mock` or LLM Studio (`dwemerllm`), so a stored profile
  never sends your key to another provider. Keys stay in `config/config.php`.
- **Memory**: Configuration > AI & Voice > **Memory settings**. **Enabled** gives each turn
  this session's saved summary and newest diary entries. **Automatic notes** and **Automatic
  fact proposals** call the NPC's model after each successful reply (extra calls; with a paid
  provider they cost money). Review on Roleplay > **Memory**: edit or regenerate the summary,
  add or delete diary entries, approve or reject candidate facts, or clear one session's
  memory for one NPC.
- **Vector search**: on Memory settings choose `mock` (hashed words, needs nothing, not
  semantic) or `openai` (any OpenAI-compatible `/v1/embeddings` URL; set the key on API keys),
  enable it, save, then press **Reindex**. Turns fall back to the keyword search whenever the
  embedding call fails or a fact has no current vector. Editing a fact clears its vector.
- **Tracing**: every turn, event, voice and NPC selection request has a request id. Search for
  it on Logs, Connector calls or in the Apache error log (`example-ai [<id>]: ...`; the
  prefix is a fixed log identity).

Checkpoints copy the summary and diary with the session's lines; restoring one puts them back
and deletes candidate facts the session proposed after the checkpoint. Approved facts are
shared knowledge and stay. Backups and their "verify restore" include every new table.

## 6. Back up and update

Before the first update that brings the consolidated layout (`client/`, `docs/`, `ports/`)
into an existing install, install the web protection
([Before you install](#before-you-install-web-protection)).

```bash
cd /var/www/html/custom-mods/KagrenacServer
sudo bash scripts/backup.sh      # database + config to /home/dwemer/example-ai-server-backups/<time>/
sudo bash scripts/update.sh      # refuses local edits, backs up, fast-forwards, migrates
```

The config in a backup is a copy of the standard `config/config.php` itself. Keep every
private setting in that file (or on the dashboard): a `config/config.php` that only loads
settings from a file elsewhere is not supported, because no backup captures what it loads.

An install made by `project.ps1 deploy` is updated by running deploy again after a new
commit: Core backs up and fast-forwards to exactly that commit (`update <id>
--expect-commit`), and the same commit again keeps config and data untouched. These flags
are not yet in a public DwemerDistro Core release, so **Update Distro** may not supply them
yet. If Core lacks them, deploy stops with a clear message and changes nothing; wait for a
compatible Core version, and meanwhile update a manual clone with `update.sh`.

- `update.sh` stops if tracked files have local changes. Keep your settings in
  `config/config.php` (untracked) and your code changes in your own fork.
- It only fast-forwards. If your branch has no upstream or has diverged it stops; merge by hand.
- It stops if the update would start tracking a file you have here untracked or ignored,
  such as `config/config.php`, because git would overwrite it without asking.
- It never deletes the database or the config, and never resets or restores anything itself.
- If a migration fails, that migration is rolled back (earlier ones stay), the code is
  already updated, and `update.sh` exits `3` and prints the backup folder. Fix the cause and
  run `sudo -u dwemer php scripts/migrate.php` again, or restore that backup by hand (below).

**Versions.** `health.php` and **Control Panel > Diagnostics** show four different things:
`server_version` (this server's release, `0.1.0`), `protocol` (the client/server contract, `1`), `baseline` (which template feature set
this code is, `baseline-1`; not a release number) and the schema (the ordered `sql/` migrations
this code needs, listed in `lib/app.php` `SCHEMA_MIGRATIONS`). `scripts/migrate.php` applies
missing migrations in name order, one transaction per file, and lets only one runner work at a
time (a second one waits). It refuses, changing nothing, when the database has migrations this
code does not know (exit `3`; update the code) or has a later migration without an earlier
one (exit `3`; restore a backup), or when `sql/` and `SCHEMA_MIGRATIONS` differ (exit `3`). A
failed file exits `2`. Add a new migration as a new `sql/NNN_name.sql` and append its name to
`SCHEMA_MIGRATIONS`; never edit an applied file. Health, the dashboard and every database write
(turns, events, cancel, result, checkpoints, bios and facts, seeding) answer `not_migrated`,
`schema_too_new` or `schema_mismatch` until both match. To release your own server, change
only `SERVER_VERSION` in `lib/version.php`; the client's version is `project(... VERSION)` in
the client's `CMakeLists.txt`.
- Restore a backup:
  `sudo -u postgres pg_restore --clean --if-exists -d YOUR_DATABASE < /path/to/backup/YOUR_DATABASE.dump`
  This overwrites that database. To inspect a backup first, restore it into a new,
  disposable database and compare, leaving the live one alone:

  ```bash
  sudo -u postgres createdb --owner=dwemer --template=template0 example_ai_restore_check
  sudo -u postgres pg_restore --no-owner --role=dwemer -d example_ai_restore_check < /path/to/backup/YOUR_DATABASE.dump
  sudo -u postgres psql -d example_ai_restore_check -c 'SELECT count(*) FROM ex_turns'
  sudo -u postgres dropdb example_ai_restore_check   # only this disposable copy
  ```

- **Dashboard backups** (**Control Panel > Backups**) are database-only: `pg_dump` of this
  app's database, without `config/config.php`, at most 20 files of 100 MB, 60 seconds per
  run. They go to `backup_dir` from the config (an absolute path outside the web root,
  owned by the web server user, mode `700`) or, if empty, an app folder in the system temp
  directory that may be emptied on restart. Files are listed, never downloaded.
  **Verify restore** restores one listed dump into a new database named
  `<database>_verify_<random>` with the configured role, which needs `CREATEDB`; it then
  compares table counts and migrations with the live database. It never restores over an
  existing database and never drops anything: remove the verify database yourself with
  `dropdb` when finished. To really restore, use the command line steps above.

### Bios, knowledge and session checkpoints

NPC bios and knowledge facts are edited on the dashboard's **Configuration > NPC bios**
page and stored in this database. Nothing is added automatically. To try retrieval with two
fictional NPCs (Mira = `npc_guide`, Oren = `npc_scout`) and a few facts, run once (safe to
repeat; it never overwrites your edits):

```bash
php scripts/seed_example.php
```

A **checkpoint** is a named copy of one session's conversation lines, inside this database.
A **backup** (`backup.sh`) is a full dump of the whole database plus config. Restoring a
checkpoint changes only that session's lines and memory notes (summary and diary), and deletes
candidate facts the session proposed after it; bios, approved knowledge, profiles, config and
other sessions stay as they are.

```bash
php scripts/checkpoint.php save    demo-save-1 before-boss
php scripts/checkpoint.php list    demo-save-1
php scripts/checkpoint.php restore demo-save-1 before-boss
php scripts/checkpoint.php delete  demo-save-1 before-boss
```

Run them as `dwemer` (who can read the config). **Roleplay > Checkpoints** on the dashboard
does the same with the same limits and locking; restore and delete ask for confirmation
first. The server never reads game saves: you
choose which checkpoint matches a game save, using the client's `session_id`. Stop or
cancel pending client requests before restoring; any turn still in flight for that session
is answered `409 stale` and not saved. Each session keeps at most 20 checkpoints of up to
2000 lines.

## 7. Remove

Back up first, then:

```bash
sudo -u postgres dropdb YOUR_DATABASE    # use this copy's configured name; deletes its data
rm -rf /var/www/html/custom-mods/KagrenacServer
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `health.php` 403 or 404 | Run `sudo ddistro_custom_mod setup-web` and check its output. The folder must sit directly under `/var/www/html/custom-mods/` and the URL must include `/custom-mods/<folder>` and your `CUSTOM_MODS_PORT`. |
| `500 server_not_configured` | `config/config.php` missing, unreadable by `www-data`, or token still `CHANGE_ME_TOKEN`. |
| `503 database_unavailable` | PostgreSQL running? Database settings in `config/config.php`? |
| `503 not_migrated` | Run `sudo bash scripts/install.sh` again. |
| `503 schema_mismatch` | This code's `sql/` folder and `SCHEMA_MIGRATIONS` in `lib/app.php` differ. Add the new file name to the list, in order. |
| `503 schema_too_new` | The database came from newer code (or a newer copy shares its name). Update this checkout; never downgrade the database by hand. |
| `migrate.php` exit `1` | Config missing or invalid, or the database connection failed. Nothing was changed. |
| `migrate.php` exit `3` | Refused, nothing changed: `sql/` does not match `SCHEMA_MIGRATIONS` (add the new file name to the list), unknown newer migrations (update the code) or a gap in the order (restore a backup). |
| `migrate.php` exit `4` | Connected, but the migration lock or table could not be used. |
| `update.sh`: "would track ..." | The upstream started tracking a file you have privately. Keep your copy; ask upstream to remove it. |
| `update.sh` exit `3` | Code updated, a migration failed and was rolled back. Use the printed backup path and steps. |
| Client `--health`: `server baseline not reported` | Older server; everything in protocol 1 still works. Update both for the newest examples. |
| Client: `WinHTTP error 12029` | Server not reachable at `server_url`. |
| Client: `401 unauthorized` | Token in `config.json` does not match the server. |
| A reply ignores the profile | Is the NPC id assigned (Profiles), or is a default profile marked? The turn's Logs details show which profile was used. |
| Memory settings: Reindex disabled | Vector search is off or the database is not migrated. Enable it and save first. |
| Connector calls shows `embedding` `failed` | The embeddings URL, model, key or vector size is wrong; turns used keyword search. Details (without the provider reply) are in the Apache error log under the call's parent request id. |
| Memory call `stale` | A newer turn, cancel, clear or checkpoint restore came first, so nothing was saved. Expected. |
