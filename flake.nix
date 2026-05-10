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
        beamPkgs = pkgs.beam.packages.erlang_28;
        elixir = beamPkgs.elixir_1_19;
        erlang = beamPkgs.erlang;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            elixir
            erlang
            pkgs.nodejs_22
            pkgs.postgresql_18
            pkgs.inotify-tools
            pkgs.xvfb-run
          ];

          shellHook = ''
            export MIX_HOME="$PWD/.nix-mix"
            export HEX_HOME="$PWD/.nix-hex"
            export PATH="$MIX_HOME/bin:$HEX_HOME/bin:$PATH"
            export LANG=en_US.UTF-8
            export ERL_AFLAGS="-kernel shell_history enabled"

            # Load .env if present
            if [ -f .env ]; then
              set -a
              source .env
              set +a
            fi

            # Local Postgres — uses port 5433 to match dev/test defaults
            export PGDATA="$PWD/.pgdata"
            export PGHOST="$PWD/.pgdata"
            export PGPORT="5433"

            if [ ! -d "$PGDATA" ]; then
              echo "Initializing local PostgreSQL 18..."
              initdb --no-locale --encoding=UTF8 -D "$PGDATA" > /dev/null
              echo "unix_socket_directories = '$PGDATA'" >> "$PGDATA/postgresql.conf"
              echo "listen_addresses = 'localhost'" >> "$PGDATA/postgresql.conf"
              echo "port = $PGPORT" >> "$PGDATA/postgresql.conf"
            fi

            if ! pg_isready -q -h "$PGHOST" -p "$PGPORT" 2>/dev/null; then
              echo "Starting PostgreSQL..."
              pg_ctl -D "$PGDATA" -l "$PGDATA/server.log" start -o "-k $PGDATA" > /dev/null
              if ! psql -h "$PGHOST" -p "$PGPORT" -lqt 2>/dev/null | grep -q gnome_garden_dev; then
                createuser -h "$PGHOST" -p "$PGPORT" -s postgres 2>/dev/null || true
                createdb -h "$PGHOST" -p "$PGPORT" -U postgres gnome_garden_dev 2>/dev/null || true
                createdb -h "$PGHOST" -p "$PGPORT" -U postgres gnome_garden_test 2>/dev/null || true
              fi
            fi
            echo "PostgreSQL running on localhost:$PGPORT"
          '';
        };
      }
    );
}
