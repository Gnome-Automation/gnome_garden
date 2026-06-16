# Development VM Setup

This repo is developed on a Nix-backed Linux VM. Use the flake as the source of
truth for local runtime versions and CLI tools.

## Current Pin

- Nix: verified with Nix 2.27.1 on this VM
- nixpkgs input: `nixpkgs-unstable`
- nixpkgs revision: `9f11f828c213641c2369a9f1fa31fe31557e3156`
- Erlang/OTP: 29
- Elixir: 1.20
- mise fallback: Erlang `29.0.2`, Elixir `1.20.1-otp-29`
- Node.js: 22
- PostgreSQL: 18

## Entering the Shell

```bash
nix develop
```

The shell sets:

- `MIX_HOME=$PWD/.nix-mix`
- `HEX_HOME=$PWD/.nix-hex`
- `MIX_TAILWIND_PATH` to the pinned Tailwind CSS 4 binary
- `MIX_ESBUILD_PATH` to the pinned esbuild binary
- `PGDATA=$PWD/.pgdata`
- `PGHOST=$PWD/.pgdata`
- `PGPORT=5433`

On first entry, the shell initializes `.pgdata`, configures PostgreSQL to listen
on localhost and the local Unix socket directory, starts PostgreSQL, and creates
`gnome_garden_dev` plus `gnome_garden_test` when missing.

## Included CLI Tools

The dev shell includes the project runtime plus operator/debugging tools:

- Elixir/Erlang
- Node.js, Tailwind CSS, esbuild
- PostgreSQL
- Garage, AWS CLI, Caddy
- curl, fd, git, jq, OpenSSL, ripgrep
- Linux browser tooling: Chromium, inotify-tools, xvfb-run

It also includes document tooling used by AshStorage analyzers and vendor
onboarding document workflows:

- Poppler (`pdftotext`, `pdfinfo`, `pdftoppm`)
- Tesseract OCR
- ImageMagick (`identify`)
- Antiword for legacy `.doc`
- LibreOffice for future document conversion/signing flows

## First-Time Project Setup

```bash
nix develop
mix setup
```

`mix setup` fetches dependencies, prepares Ash/Postgres state, installs asset
tools when needed, builds assets, and runs seeds.

Start the app from inside the shell:

```bash
iex -S mix phx.server
```

The app runs at <http://localhost:4000>.

## Keeping The VM Current

Use this when intentionally updating the VM/toolchain pin:

```bash
nix flake update
nix flake check
nix develop --command bash -c 'elixir --version && erl -eval "erlang:display(erlang:system_info(otp_release)), halt()." -noshell'
```

Use `bash -c`, not `bash -lc`, when checking binary resolution from scripts.
Login shells may prepend user profile paths such as `~/.nix-profile/bin` ahead
of the dev shell. The flake shell hook uses explicit PostgreSQL 18 paths for
database initialization and startup, but `bash -c` is the cleanest way to verify
the pinned tools:

```bash
nix develop --command bash -c 'postgres --version && pdftotext -v 2>&1 | head -1 && libreoffice --version'
```

After dependency or toolchain updates, run the project checks that match the
change:

```bash
mix compile --warnings-as-errors
mix ash.codegen --check
mix test
```

Run `mix precommit` before PR-level validation.

## Troubleshooting

If PostgreSQL is already running but the app cannot connect, confirm the shell
environment:

```bash
echo "$PGHOST:$PGPORT"
pg_isready -h "$PGHOST" -p "$PGPORT"
psql -h "$PGHOST" -p "$PGPORT" -U postgres -d postgres -Atc 'show server_version;'
```

If the local database gets wedged during development, stop the local server and
reset through Ash:

```bash
pg_ctl -D "$PGDATA" stop
nix develop
mix ash.reset
```

Do not commit `.pgdata`, `.nix-mix`, `.nix-hex`, or `priv/storage`.
