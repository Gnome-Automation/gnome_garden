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
        agentBrowserVersion = "0.20.2";
        agentBrowserArtifact = {
          x86_64-linux = {
            name = "agent-browser-linux-x64";
            hash = "sha256-xmlyDhCW5xV+ZviOGn9Hl4NVpX+XQKFAOU+MhUcrgHE=";
          };
          aarch64-linux = {
            name = "agent-browser-linux-arm64";
            hash = "sha256-wifi646hgfYJA2EsfnGyxmtqNEL4DlX+gQc4iTaZVJE=";
          };
          x86_64-darwin = {
            name = "agent-browser-darwin-x64";
            hash = "sha256-q+I8YVtUo4GSJWEchtB/GTnBkUhrKEUYl0y8Kd8puKs=";
          };
          aarch64-darwin = {
            name = "agent-browser-darwin-arm64";
            hash = "sha256-a4YX9CIrBu8WCq/ldA6Jr1O3cEKGoKG6SoHYHSPmT0U=";
          };
        }.${system};
        agentBrowser = pkgs.stdenvNoCC.mkDerivation {
          pname = "agent-browser";
          version = agentBrowserVersion;

          src = pkgs.fetchurl {
            url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/${agentBrowserArtifact.name}";
            inherit (agentBrowserArtifact) hash;
          };

          dontUnpack = true;
          nativeBuildInputs = [ pkgs.makeWrapper ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.patchelf ];

          installPhase = ''
            runHook preInstall
            install -Dm755 "$src" "$out/libexec/agent-browser"
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              patchelf \
                --set-interpreter "${pkgs.stdenv.cc.bintools.dynamicLinker}" \
                --set-rpath "${pkgs.glibc}/lib" \
                "$out/libexec/agent-browser"
            ''}
            makeWrapper "$out/libexec/agent-browser" "$out/bin/agent-browser" \
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''--set-default AGENT_BROWSER_EXECUTABLE_PATH "${pkgs.chromium}/bin/chromium"''}
            runHook postInstall
          '';

          doInstallCheck = true;
          installCheckPhase = ''
            "$out/bin/agent-browser" --version | grep -F "agent-browser ${agentBrowserVersion}"
          '';

          meta = {
            description = "Browser automation binary pinned by Jido Browser";
            homepage = "https://github.com/vercel-labs/agent-browser";
            license = pkgs.lib.licenses.asl20;
            mainProgram = "agent-browser";
            platforms = [ system ];
          };
        };
        commonDevTools = builtins.filter
          (package: pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform package)
          [
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
          agentBrowser
          ];
        linuxDevTools = pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.chromium
          pkgs.inotify-tools
          pkgs.xvfb-run
        ];
        devTools = commonDevTools ++ linuxDevTools;
      in
      {
        packages.agent-browser = agentBrowser;

        devShells.default = pkgs.mkShell {
          buildInputs = devTools;

          shellHook = ''
            export MIX_HOME="$PWD/.nix-mix"
            export HEX_HOME="$PWD/.nix-hex"
            export LANG=en_US.UTF-8
            export ERL_AFLAGS="-kernel shell_history enabled"
            export MIX_TAILWIND_PATH="${pkgs.tailwindcss_4}/bin/tailwindcss"
            export MIX_ESBUILD_PATH="${pkgs.esbuild}/bin/esbuild"
            export GNOME_GARDEN_BROWSER_PATH="${agentBrowser}/bin/agent-browser"

            # Load .env if present
            if [ -f .env ]; then
              set -a
              source .env
              set +a
            fi

            codex_shell_path="$HOME/.local/bin:$MIX_HOME/bin:$HEX_HOME/bin:${pkgs.lib.makeBinPath devTools}:$PATH"
            clean_path=""
            old_ifs="$IFS"
            IFS=:
            for path_entry in $codex_shell_path; do
              case "$path_entry" in
                /nix/store/*-codex-*/bin) continue ;;
              esac

              if [ -z "$clean_path" ]; then
                clean_path="$path_entry"
              else
                clean_path="$clean_path:$path_entry"
              fi
            done
            IFS="$old_ifs"
            export PATH="$clean_path"
            unset codex_shell_path clean_path old_ifs path_entry

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
