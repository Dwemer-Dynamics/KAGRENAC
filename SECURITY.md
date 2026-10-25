# Security and private data

KAGRENAC's baseline dashboard has no login. Use localhost or a trusted local network;
do not expose it directly to the public internet. API tokens use plain HTTP in the local
setup, and the server has no rate limiting.

## Installation boundary

Use a compatible DwemerDistro Core that protects the install route before placing source.
Verify HTTP 403 for `config/`, `.git/`, `client/`, `docs/` and `ports/` on every Apache
listener. Do not rely on `.htaccess`. See [SETUP.md](SETUP.md) for the full checks.
An unsupported Core must stop deployment; do not remove the version/capability guard.

Keep private config, client pairing, build output and backups out of source and web roots.
Provider keys belong on the dashboard's **API keys** page or in private PHP config, never
in chat, an issue or a PR. `.gitignore` is only a convenience; inspect staged files before
publishing.

The event database contains player text, game context, replies and retrieved NPC knowledge.
Treat exports and backups as private. Diagnostic logs and connector audit must exclude
keys, prompts, transcripts, audio and provider bodies.

## Sensitive reports

Do not publish credentials, personal conversations or exploitable details in a public
issue. Use a private security advisory if the repository's Security tab offers it, or
arrange a private report with a maintainer. Include the affected commit, component and
minimal reproduction with synthetic data. If a key was exposed, revoke it with its
provider; deleting the public message alone does not revoke it.
