# Browser Runtime

Jido Browser 2.1.0 requires `agent-browser` 0.20.2. The flake exposes that exact binary as
`packages.agent-browser` for Linux x86_64/ARM64 and Darwin x86_64/ARM64.

On Linux, the package patches the downloaded ELF to use Nix's glibc interpreter and RPATH,
then wraps it with the Nix Chromium executable. It does not depend on `/lib64`, `nix-ld`, a
globally installed browser, or a manually patched `_build` artifact.

## Development

`nix develop` adds the package to `PATH` and exports:

```text
GNOME_GARDEN_BROWSER_PATH=/nix/store/...-agent-browser-0.20.2/bin/agent-browser
```

`config/runtime.exs` applies that path to Jido Browser. `GnomeGarden.Browser` delegates all
session operations to Jido, so it uses the same immutable runtime indirectly.

Garden owns browser lifecycle through a supervised session manager. Each caller receives an
isolated session that is reused across navigation and evaluation, closed explicitly with
`GnomeGarden.Browser.close/0`, and automatically closed when the caller exits. Stateless HTTP
retrieval does not open a browser session. Snapshot, fetch, and download output is bounded before
it crosses the facade.

## Credential and session custody

Provider passwords and API keys enter Ash actions as sensitive arguments and are persisted only as
encrypted envelopes. Authenticated browser storage state follows the same rule: the database stores
an AES-GCM envelope authenticated with both the procurement source ID and source credential ID. It
does not store a reusable filesystem path.

`SourceBrowserSession` records expire by timestamp and are bound to the credential fingerprint that
created them. Rotating, disabling, or compromising a credential invalidates all bound sessions;
compromise also deletes the encrypted session payload. Scanners resolve session state through the
Procurement domain and materialize it into a `0600` temporary file for one operation only.

Playwright receives a public payload and a separate secret envelope through private temporary files.
Neither command arguments nor the ordinary JSON payload contain credentials. Storage-state output
uses a separate `0600` file and is encrypted immediately by the caller. Secret-bearing browser form
values use typed `Browser.type/3` calls and are never interpolated into JavaScript source. Logs,
errors, run metadata, and `Inspect` output must contain only redacted values and non-sensitive audit
metadata.

BidNet credential testing is a real provider login, not a generic form heuristic. A successful test
creates a valid encrypted browser session before marking the credential verified. Invalid credentials
fail without retry; transient browser failures retry at most twice. Listing extraction asks the BidNet
provider boundary for access: valid sessions are reused, expired sessions are cleared and refreshed,
and missing, pending, or invalid credentials are returned as distinct blocked states. Public BidNet
sources may still use the cookie-free HTML path when login is not required.

## Releases

Build the runtime package with:

```bash
nix build .#agent-browser
```

Set `GNOME_GARDEN_BROWSER_PATH` to the resulting immutable `bin/agent-browser` path in the
release environment. The variable configures the Jido Browser adapter used by the Garden facade
and the staged retrieval policy.
