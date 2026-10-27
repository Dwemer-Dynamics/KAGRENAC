# Getting started: from download to your first AI prototype

Talk to your coding agent. It runs setup, writes the plan and records current progress in
[PROJECT.md](../PROJECT.md). You supply missing choices, enter credentials privately and
check the result in game. There is no form to complete first.

## Before you start

You need Windows, Git, a coding agent and the selected game's mod tools. The C++ console
and native C++ ports need Visual Studio C++ tools; do not require them for every script port.
Use the one DwemerDistro the user names. If several are installed, ask which one. Never
reinstall or replace an existing distro as a setup step.

**No DwemerDistro yet?** The agent offers brief help and the
[installation guide](https://dwemerdynamics.com/custom-mods/installation.html#InstallDistro)
once. It downloads or runs an installer only when you ask. You can defer installation:
gameplay planning, engine research and independent source/build work continue, with
server setup recorded as pending in PROJECT.md. Deployment, pairing, provider tests and
connected gameplay still need a compatible, running distro.

**Core compatibility:** run **Update Distro**, including after a fresh base-image install.
The launcher fetches Core's current `main` and installs its helpers; no launcher rebuild is
needed for this compatibility update. Guided deployment needs `setup-web --protect-project`,
`setup-web --protect-root`, `update --expect-commit` and `server_folder` support. The older
v1.0.8 tag lacks them; a fresh base image can need this update too. Check capabilities rather than the version label.
Inspect the installed `ddistro_custom_mod --help` and run `doctor` after updating.
If the switches are still missing, inspect the failed updater step and stop deployment;
do not weaken the preflight or patch shared tools silently. The [manual route](../SETUP.md)
is separate and still requires its own web-protection and patched-PHP checks.

Doctor is diagnostic, not a readiness test. It does not start a stopped distro. A missing
service you did not select, such as local port 1234 when using OpenRouter, blocks nothing.

## The route

1. **Download and brief.** Clone KAGRENAC or use GitHub's **Use this template**, open your
   agent and use the [first prompt](../README.md#first-prompt-for-your-coding-agent). Reuse
   the conversation; ask only for the missing game, starting feature and mod name. From a
   template checkout, [create the independent mod](#new-project) and work there thereafter.
2. **Design the gameplay.** Fill PROJECT.md's Gameplay design with the experience the
   player will see and hear. Use [Gameplay design](GAMEPLAY_DESIGN.md) for meaningful
   triggers, participants, decisions, memory and outcomes. Free typed in-game chat is the
   default; speech input is optional and must be requested. Automatic interactions yield
   to the player and end cleanly. Do not substitute a hotkey with a canned line for chat.
3. **Qualify the game integration.** Follow [Engine planning](ENGINE_PLANNING.md). Inspect
   the installed game/build, native UI/input, observation sources, entity lifetime,
   async transport, audio, action mechanisms and normal mod loading. Cite primary sources;
   unknowns get a bounded probe and concrete alternatives. Reuse a reference port when
   available, but check it against this game build and brief before port code.
4. **Prepare the server alongside research.** Run doctor, commit the independent source
   and deploy to its own named root. Existing configurations and other apps stay intact.
   Set up providers and requested voice under the user's existing authority; missing game
   hooks do not block independent server work. Credentials go on **API keys**, never in chat.
5. **Build the first connected slice.** Prove the requested native mechanism first, then
   connect it to the server. Install once through the qualified loader, pair privately,
   review the actual diff and fix findings. Test the adapter's actual wire bytes, cancellation,
   input restoration, text fallback and installed startup. A scaffold or console is not
   the demo. The player should start the distro and the game, without transport, attach
   or provider-arming commands each session.
6. **Verify and expand.** Report server-ready, port-built and gameplay-verified separately.
   The user launches the game and checks the visible loop, heard voice and each requested
   action. Never infer those from a build or WAV. Add one feature at a time afterwards.
   For NPC bios and world knowledge in bulk, follow [content authoring](CONTENT_AUTHORING.md).

A blocked stage does not freeze independent work. Record the blocker, evidence and next
probe in PROJECT.md; keep detailed engine notes in `ports/<engine>/PLAN.md` and generic
setup friction in `docs/KAGRENAC_FLOW_REVIEW.md`. The agent performs authorized reversible
setup itself and asks only when information, a material choice or authority is missing.
Do not launch a game or make a paid call merely to fill a checklist.

## Repository layout

Default to **one source repository per mod**: server at the root, game client under
`client/` or `ports/<engine>/`. Runtime copies are not separate repos. Offer a client/server
split when independent maintenance is relevant or the user asks; record the choice and
protocol/build/deploy ownership first. `new` has no two-repository switch.

## Where each copy lives

| Copy | Job |
|---|---|
| Windows development checkout | Agent, source edits and build commands |
| WSL server install | PHP runtime, database, private server config and dashboard |
| Game runtime/mod folder | Installed plugin and private paired client config |

Keep builds and paired configs outside source and every web root. A user-chosen D: build
root is fine; record it in PROJECT.md. The deployed server is a committed runtime copy,
not a second development checkout.

## `scripts\project.ps1`

Run these developer commands with Windows **powershell.exe**, from the mod's own checkout.
They are setup/check tools, not the player's per-session launch steps.

| Command | Purpose |
|---|---|
| `new` | Copy committed template HEAD into a new independent repo; no history or secrets |
| `doctor` | Read-only tool, distro, server and exposure diagnostics; WARN/SKIP are not readiness |
| `setup` | Build the console/shared C++ client; optional for a port that does not use it |
| `check` | PHP/shell checks and warning-free x64/x86 client build; no database writes |
| `deploy` | Install/update committed HEAD through Core, preserving private config and data |
| `configure` | Change the owned install's provider, voice or server action allowlist |
| `pair` | Write a new private client config, without printing a token |
| `package` | Package committed server source and an external client build as release ZIPs for review; see [community publishing](PUBLISHING.md#build-and-review) |
| `publish` | After approval, publish a reviewed release to the exact authorized repository; see [community publishing](PUBLISHING.md#publish-after-approval) |

### New project

Create the parent folder first. This example is a conversation-only starting brief,
not a claim of support for a particular engine:

```powershell
New-Item -ItemType Directory -Force D:\Mods | Out-Null
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 new `
  -Destination D:\Mods\MyMod -Id my-mod -Name "My Mod" `
  -Game "<game and installed version>" -Feature "Talk to nearby NPCs in game" `
  -Engine <engine-folder> -InteractionMode manual -Voice none -WslDistro <distro>
```

The destination must be new, on a local fixed disk, outside every checkout and web root.
Only committed HEAD is copied; uncommitted template work is reported and excluded.
`new` sets the mod's manifest, brief, paths and stage states and runs `git init`; it commits
nothing. An existing engine reference is a starting plan, not proof. An unknown engine
gets a short PLAN.md starter without invented capabilities. `-InteractionMode` only records
planning text. Optional brief fields include `-LlmProvider`, `-Voice` and `-ServerFolder`.

Review and commit the copy before deployment. Every later command runs in that copy:

```powershell
Set-Location D:\Mods\MyMod
git add -A
git commit -m "Start My Mod from KAGRENAC"
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 doctor -WslDistro <distro>
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 deploy -WslDistro <distro>
```

### Deploy and pair

Deploy refuses dirty/untracked files and the template's `example-server` for a new install.
It exports HEAD, protects the route before installation, installs that exact commit and
checks health plus HTTP 403 on protected paths. A repeated deploy at the same commit does
not update code or rewrite private config. A new commit is backed up and fast-forwarded.
The deployment record lives outside source under `%LOCALAPPDATA%\DwemerDynamics\Kagrenac`.

Core can leave config readable but not dashboard-writable. Deploy checks saving as
`www-data` and repairs ownership through that commit's installer when needed, verifying
config bytes and the lock are preserved. Launcher/Core updates may restore read-only
ownership; run deploy again if doctor reports that condition.

Once the port's runtime exists, pair into its private config path:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 pair -WslDistro <distro> `
  -OutFile D:\build\my-mod\runtime\config.json -AllowedActions none
```

Pair defaults to this project's own registered server. Use `-ServerUrl` for a different
listener; `-WslServerPath` explicitly names an existing manual install. Same URL/token/session
keeps an existing config byte for byte; different pairing is refused, never overwritten.
Identity/voice options shape a new file only. Use the port's instructions for native fields.

### Configure providers, voice and actions

Keep conversation qualification actionless on **both** sides:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 configure -WslDistro <distro> `
  -LlmProvider mock -Tts off -AllowedActions none
```

For real dialogue, use the user's configured provider. The recommended default is
OpenRouter `google/gemma-4-31b-it`; supported bounded decisions use `typesafe/jev-1.13`.
JEV's shipped endpoint selects an answering NPC, not arbitrary actions. See
[CONNECTORS.md](../CONNECTORS.md) for configuration and contracts.

After setting the key privately on **API keys** with OpenRouter selected, an agent can use:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\project.ps1 configure -WslDistro <distro> `
  -LlmProvider openrouter -LlmModel google/gemma-4-31b-it -AllowedActions none
```

`-ReuseProviderFrom <private-config-path>` copies only the OpenRouter LLM key from a source
the user explicitly named; never silently reuse another product's private config.
For requested voice, verify PocketTTS is installed/running, then use
`-Tts pockettts -TtsVoice alba`. Other settings and providers stay on the dashboard.
`configure` uses the existing config writer as `www-data`, preserving secrets, database,
unknown settings, permissions and lock. Repeating identical settings writes nothing.

Test only with authority. The dashboard **LLM > Send test** supports a dialogue-only check.
`configure -TestProviders` instead makes **one real turn and one speech call**, without
retry. It requires real dialogue and enabled voice, no automatic memory/vector search, and
no default-profile model/mode override. It prints status/counts and WAV metadata, never
keys, reply text or audio. A generated WAV is not heard voice. Do not invoke it for mock-only
or text-only validation.

Nonempty action configuration needs `-Build <port-build-folder>` with validated
[build records](PORT_BUILD_RECORDS.md), or `-ConsoleClient` for the simulated follow exercise.
Pair checks the client's capabilities separately. Omitting `-AllowedActions` preserves
legacy defaults, so pass `none` explicitly until the actual handlers are qualified. A
supported build is a candidate; each action still needs its own in-game outcome check.

### Server folder

`new` sets `server_folder` to `<Name>Server`, for example `MyModServer`, under
`/var/www/html/`, served at `http://127.0.0.1:19000/MyModServer`. Core still manages its
database (`custom_<id>`, hyphens become underscores), backups and lifecycle. Use
`-ServerFolder` for another valid, unreserved name; an existing folder is refused.

Resolve an existing install from Core's registry, then the manifest, then the legacy
`custom-mods/<id>` fallback. Old copies stay compatible. Moving an existing install is a
separate explicit `ddistro_custom_mod migrate-root` operation, not an automatic update.
The template retains its `example-server` manifest identity.

For sharing a completed mod, use [community publishing](PUBLISHING.md): package selected
client/server files from one repository, then publish after reviewing the exact release.
For manual installation, maintenance, recovery and removal use [SETUP.md](../SETUP.md).
For engine-specific build/install acceptance use the port's maintained route and
[installed startup acceptance](ENGINE_PLANNING.md#installed-startup-acceptance).
