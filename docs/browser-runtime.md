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

## Releases

Build the runtime package with:

```bash
nix build .#agent-browser
```

Set `GNOME_GARDEN_BROWSER_PATH` to the resulting immutable `bin/agent-browser` path in the
release environment. The variable configures the Jido Browser adapter used by the Garden facade
and the staged retrieval policy.
