# Legacy launcher branch route (manifest version 1)

This is a developer reference for the template's `schema_version: 1` manifest: a
server-only install that clones one Git branch into DwemerDistro. Players of a finished mod
do not use it. A finished mod is shared as a version 2 release
([community publishing](docs/PUBLISHING.md)); players open **Mods > Custom mods > Browse
mods** in the launcher, select the mod and choose **Install server**. Once the server is
installed, **Download mod release** fetches the game plugin, which is then installed by
following the game's own loader or mod-manager instructions.

This route installs the template's PHP server, not a game plugin. The template publishes no
release, so it is not a version 2 mod that Browse mods can install; this page is its
command-line, developer and manual compatibility route. To build your own mod, use
[guided setup](docs/getting-started.md); generated projects default to a named server root.
The legacy identity and paths below remain unchanged for existing template installs.
Check [Core compatibility](docs/getting-started.md#before-you-start) before deployment.

`dwemer-mod.json` lets DwemerDistro Core's `ddistro_custom_mod` helper install
KagrenacServer from this repository. Inside the distro, preview the branch and its exact
commit (this changes nothing), then install that commit. After reviewing the check output,
replace the `COMMIT` value with the full commit id it shows:

```bash
ddistro_custom_mod check https://github.com/Dwemer-Dynamics/Kagrenac --json
COMMIT='<full commit id shown by check>'
sudo ddistro_custom_mod install https://github.com/Dwemer-Dynamics/Kagrenac --expect-commit "$COMMIT"
```

The full version 1 contract is documented in DwemerDistro Core's `CUSTOM_MODS.md`. This
route manages the PHP server only; the KagrenacClient console client is built separately on
Windows from your development copy ([client/README.md](client/README.md)), never inside the
installed folder.

The launcher clones the whole repository, including the source-only `client/`, `docs/` and
`ports/` folders. Update DwemerDistro Core first so its custom mod web protection is in
place before you install or update this mod; it denies those folders and `.git/` at
`/custom-mods/example-server` ([SETUP.md, Before you install](SETUP.md#before-you-install-web-protection)).

What the distro does with this manifest:

- Clones the `main` branch to `/var/www/html/custom-mods/example-server`. This is separate
  from a manual install in `/var/www/html/custom-mods/KagrenacServer`. The manifest `id`
  (`example-server`) and the template database name (`example_ai_mod`) are kept from the
  template's earlier name on purpose: an `id` cannot change after install, so renaming it
  would orphan existing installs.
- Creates its own database `custom_example_server`, owned by the existing `dwemer` role.
- Copies `config/config.example.php` to `config/config.php` only if that file is missing,
  replacing `'CHANGE_ME_TOKEN'` with a random token and `'example_ai_mod'` with
  `custom_example_server`. Nothing else in the template changes.
- Runs `php scripts/migrate.php` as `dwemer`, then requires
  `http://127.0.0.1:19000/custom-mods/example-server/health.php` to answer 200.
- Dashboard: `http://127.0.0.1:19000/custom-mods/example-server/ui/`.
- Client `server_url`: `http://127.0.0.1:19000/custom-mods/example-server`.

19000 is the distro's shared loopback port for all custom mods (`CUSTOM_MODS_PORT` in
`/etc/dwemerdistro_services.conf`, 19000-19999); each mod has its own path and database,
and official server ports are unchanged. If it is changed, run
`sudo ddistro_custom_mod setup-web` and update the client's `server_url` to the new port.

It never runs `scripts/install.sh` or `scripts/update.sh`, and never runs repository PHP as
root. **Update** refuses local edits to tracked files, backs up `config/config.php` and the
database first, and only fast-forwards. To pair the console client with this install, run
`pair_client.php` from `/var/www/html/custom-mods/example-server`; it writes that install's
actual route, `.../custom-mods/example-server`, rather than the manual-install default
([SETUP.md, Connect them](SETUP.md#3-connect-them)).

## Branches: main and dev

This repository offers two branches:

```json
"branches": { "default": "main", "allowed": ["main", "dev"] }
```

| Branch | Use it for |
|---|---|
| `main` (default) | The stable baseline. New installs use it. |
| `dev` | Development work that has not reached `main` yet. It may change more often. |

**Update** and **Switch** are the helper's `update` and `switch` operations; the launcher
calls the same operations for an installed branch mod.

- **Switch** moves an install to the other branch. The launcher first shows the exact
  commit it will install; it then backs up the config and database, keeps the private
  config, migrates and checks health. If the switch fails, the code goes back to the
  previous branch and commit, but database changes are **not** rolled back; restore the
  backup taken just before the switch if you need to.
- **Update** always stays on the branch the install is on. It never moves an install to
  another branch, even if the default changes.
- Only the manifest on the default branch (`main`) decides which branches are offered, and
  every listed branch must exist.

Because users can switch in both directions, keep both branches compatible with the same
database:

- Every offered branch keeps the same `id` and `config_path`.
- Migrations are additive and safe to run twice (`CREATE TABLE IF NOT EXISTS`,
  `ADD COLUMN IF NOT EXISTS`). Never drop or rename a table or column another offered
  branch still reads, and do not fail on tables or columns you do not know.
- At first, `main` and `dev` share the same schema: the same `sql/*.sql` files and the same
  `SCHEMA_MIGRATIONS` list in `lib/app.php`.
- The server refuses a database that has a migration its code does not list
  (`schema_too_new` in `lib/app.php`; `scripts/migrate.php` exits 3 and changes nothing),
  even when that migration's SQL is purely additive. So before either branch offers a newer
  schema, add the same `sql/NNN_name.sql` file and the same `SCHEMA_MIGRATIONS` entry to
  both offered branches, so an install can switch back and forth.
- A migration that exists only on `dev` blocks switching back to an older `main`: once
  `dev` has applied it, `main` refuses that database until `main` also lists that migration.

## Making your own launcher mod from this template

A copy of this template is a different mod. To share it with players, publish a version 2
release ([community publishing](docs/PUBLISHING.md)). If you also offer a version 1 branch
install, before publishing it:

- Create your own public HTTPS repository and its branches (for example `main` and `dev`),
  and set `project_url` to that repository.
- Your new `id` is a folder Core's web protection does not know. Set `server_folder` (for
  example `"MyModServer"`; `project.ps1 new` does): Core then installs the mod at
  `/var/www/html/MyModServer` and denies `.git/`, the source folders, `config.json` and `.env`
  there before the folder is made. Without it, add equivalent Apache deny rules for
  `/custom-mods/<your-id>`, or keep those folders out of the repository you publish.
- `project_url` is optional: leave it out until your mod has its own public repository.
- Change `id` to your own unique value (3-32 characters, `a-z`, `0-9` and single hyphens,
  starting with a letter). It cannot change after install, and the launcher derives the
  folder and database names from it (`custom_<id>`), so your mod never shares this
  example's database.
- Change `name`, `description` and, if you like, `assets`.
- Change `database_placeholder` together with the database name in
  `config/config.example.php`, keeping it unique to your project.
- Keep or replace the `branches` section. Without it, only the repository default branch
  is offered.

Rules every copy must follow:

- Keep `config/config.php` untracked. A repository that tracks it is rejected.
- Keep `'CHANGE_ME_TOKEN'` and the database name each exactly once in the template, as
  quoted PHP strings.
- Keep `scripts/migrate.php` safe to repeat and exiting non-zero on failure.
- Do not add symbolic links or submodules.

## Icon and banner (optional)

`assets` gives the launcher and the Dashboard pictures for the mod. KagrenacServer uses the
square 512 x 512 PNG `ui/images/kagrenac.png` as both the icon and the banner. Your own mod
can use any PNG or JPEG banner; about 2:1 is recommended.

- Commit the image files and the `assets` entry together. Each path is relative to the
  repository root and must point to a tracked `.png`, `.jpg`, or `.jpeg` file. Links,
  `..`, hidden folders, and web addresses are rejected.
- Use a square icon; it is shown at 26 x 26. The launcher shows the banner whole in its
  picture area, so a wide picture of about 2:1 fills it best. Keep each file under 4 MB.
- Pictures come from the installed version. After you change them, users see the new
  ones only once they choose **Update**.
- Either key, or `assets` itself, may be left out. Without a banner the launcher uses, for
  a `github.com` repository, its GitHub preview picture or else the owner's avatar, then a
  plain placeholder; without an icon it shows the name only. The launcher skips any picture
  over 4 MB.
  Older installs and manifests without `assets` keep working.

## Local testing of unpublished changes (optional)

Normal installs accept only public HTTPS URLs such as the one above. For an administrator
test of changes not yet pushed, clone a Git bundle bare inside the distro and install from
it:

```bash
git clone --bare /path/to/Kagrenac.bundle /path/to/Kagrenac.git
sudo ddistro_custom_mod install --local-source /path/to/Kagrenac.git
```
