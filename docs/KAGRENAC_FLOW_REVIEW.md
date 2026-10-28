# Build and publishing rehearsal

The Noita pilot started from published KAGRENAC main `ae95691` in a fresh Codex
agent. The normal `new -Engine noita`, native build records and v2 packaging
worked. The temporary publishing-test repository is no longer needed.

## Findings

- A valid text-only mod produced five false smoke failures because follow was
  assumed. Smoke now respects the server allowlist and reports the successful
  follow-result cases as skipped when follow is disabled. An unsupported action
  probe is chosen outside the allowlist, including custom names.
- The old config check passed any response without the token, including HTTP 200.
  It now requires HTTP 403 and discards the response body on every result.
- The real install stopped at a missing PHP security helper on an outdated
  distro. PHP was already patched. Publishing guidance now makes Update Distro
  and a compatible launcher explicit; local unrelated Core work was preserved.
- A standalone Lua CLI was absent. The pilot used the installed LuaJIT DLL in a
  disposable host for offline checks; no new runtime dependency was installed.

## Evidence and remaining acceptance

Real public GitHub publication, catalog discovery, pinned artwork, release
downloads and candidate Core/launcher installation/private pairing passed.
Mock endpoint checks passed for empty and default follow allowlists. These are
separate from native gameplay acceptance. The Noita SDK warns that its text
input may behave differently outside settings; visible input, focus, controls,
pause/death/restart and current observations still need the player's test.
Real providers and heard voice were not tested. The launcher candidate was not
published as a product release; the full production updater was not exercised.
