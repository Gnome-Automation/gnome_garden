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

`config/runtime.exs` applies that path to both `GnomeGarden.Browser` and Jido Browser.

## Releases

Build the runtime package with:

```bash
nix build .#agent-browser
```

Set `GNOME_GARDEN_BROWSER_PATH` to the resulting immutable `bin/agent-browser` path in the
release environment. The same variable configures the current Garden facade and the Jido
Browser adapter used by the staged retrieval migration.
