{
  description = "Gnome Garden — Elixir/Phoenix CRM + AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        beamPkgs = pkgs.beam.packages.erlang_29;
        elixir = beamPkgs.elixir_1_20;
        erlang = beamPkgs.erlang;
        postgres = pkgs.postgresql_18;
        postgresBin = "${postgres}/bin";
        commonDevTools = [
          elixir
          erlang
          pkgs.nodejs_22
          pkgs.tailwindcss_4
          pkgs.esbuild
          postgres
          pkgs.garage_2
          pkgs.awscli2
          pkgs.antiword
          pkgs.caddy
          pkgs.curl
          pkgs.fd
          pkgs.git
          pkgs.imagemagick
          pkgs.jq
          pkgs.libreoffice
          pkgs.openssl
          pkgs."poppler-utils"
          pkgs.ripgrep
          pkgs.tesseract
        ];
        linuxDevTools = pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.chromium
          pkgs.inotify-tools
          pkgs.xvfb-run
        ];
        devTools = commonDevTools ++ linuxDevTools;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = devTools;

          shellHook = ''
            export MIX_HOME="$PWD/.nix-mix"
            export HEX_HOME="$PWD/.nix-hex"
            export LANG=en_US.UTF-8
            export ERL_AFLAGS="-kernel shell_history enabled"
            export MIX_TAILWIND_PATH="${pkgs.tailwindcss_4}/bin/tailwindcss"
            export MIX_ESBUILD_PATH="${pkgs.esbuild}/bin/esbuild"

            # Load .env if present
            if [ -f .env ]; then
              set -a
              source .env
              set +a
            fi

            export PATH="$MIX_HOME/bin:$HEX_HOME/bin:${pkgs.lib.makeBinPath devTools}:$PATH"

            # Local Postgres — default to 5433 while allowing .env overrides
            export PGDATA="$PWD/.pgdata"
            export PGHOST="$PWD/.pgdata"
            export PGPORT="''${PGPORT:-5433}"

            if [ ! -d "$PGDATA" ]; then
              echo "Initializing local PostgreSQL 18..."
              "${postgresBin}/initdb" --no-locale --encoding=UTF8 -D "$PGDATA" > /dev/null
              echo "unix_socket_directories = '$PGDATA'" >> "$PGDATA/postgresql.conf"
              echo "listen_addresses = 'localhost'" >> "$PGDATA/postgresql.conf"
              echo "port = $PGPORT" >> "$PGDATA/postgresql.conf"
            fi

            if ! "${postgresBin}/pg_isready" -q -h "$PGHOST" -p "$PGPORT" 2>/dev/null; then
              echo "Starting PostgreSQL..."
              "${postgresBin}/pg_ctl" -D "$PGDATA" -l "$PGDATA/server.log" start -o "-k $PGDATA" > /dev/null
              if ! "${postgresBin}/psql" -h "$PGHOST" -p "$PGPORT" -lqt 2>/dev/null | grep -q gnome_garden_dev; then
                "${postgresBin}/createuser" -h "$PGHOST" -p "$PGPORT" -s postgres 2>/dev/null || true
                "${postgresBin}/createdb" -h "$PGHOST" -p "$PGPORT" -U postgres gnome_garden_dev 2>/dev/null || true
                "${postgresBin}/createdb" -h "$PGHOST" -p "$PGPORT" -U postgres gnome_garden_test 2>/dev/null || true
              fi
            fi
            echo "PostgreSQL running on localhost:$PGPORT"
          '';
        };
      }
    );
}
