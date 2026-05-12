#!/usr/bin/env bash
set -euo pipefail

host="${GARDEN_DEPLOY_HOST:-root@garden}"
checkout="${GARDEN_DEPLOY_CHECKOUT:-/srv/gnome_garden}"
release_dir="${GARDEN_DEPLOY_RELEASE:-/opt/gnome-garden}"
service="${GARDEN_DEPLOY_SERVICE:-gnome-garden}"
branch="${GARDEN_DEPLOY_BRANCH:-main}"

ssh "$host" "BRANCH='$branch' CHECKOUT='$checkout' RELEASE_DIR='$release_dir' SERVICE='$service' bash -s" <<'REMOTE'
set -euo pipefail

cd "$CHECKOUT"

echo "Preparing Nix development environment..."
dev_env="$(mktemp)"
chmod 644 "$dev_env"
sudo -u gnome_garden nix print-dev-env > "$dev_env"

git_script="$(mktemp)"
cat > "$git_script" <<'GIT'
set -euo pipefail

set +u
. "$DEV_ENV"
set -u

cd "$CHECKOUT"
git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"
GIT
chmod 644 "$git_script"

echo "Fetching $BRANCH..."
sudo -u gnome_garden env CHECKOUT="$CHECKOUT" BRANCH="$BRANCH" DEV_ENV="$dev_env" bash "$git_script"

build_script="$(mktemp)"
cat > "$build_script" <<'BUILD'
set -euo pipefail

cd "$CHECKOUT"

set +u
. "$DEV_ENV"
set -u

export MIX_HOME="$CHECKOUT/.nix-mix"
export HEX_HOME="$CHECKOUT/.nix-hex"
export LANG=en_US.UTF-8
export MIX_ENV=prod

mix deps.get --only prod
mix assets.deploy
mix release --overwrite
BUILD
chmod 644 "$build_script"

echo "Building release..."
sudo -u gnome_garden env CHECKOUT="$CHECKOUT" DEV_ENV="$dev_env" bash "$build_script"

stamp="$(date +%Y%m%d%H%M%S)"
previous="${RELEASE_DIR}.prev-${stamp}"

echo "Installing release..."
systemctl stop "$SERVICE"
mv "$RELEASE_DIR" "$previous"
cp -a "$CHECKOUT/_build/prod/rel/gnome_garden" "$RELEASE_DIR"
chown -R gnome_garden:gnome_garden "$RELEASE_DIR"

echo "Starting $SERVICE..."
systemctl start "$SERVICE"
systemctl is-active "$SERVICE"

echo "Bootstrapping admins..."
systemd-run --wait --pipe --collect \
  --service-type=exec \
  --property=User=gnome_garden \
  --property=Group=gnome_garden \
  --property=WorkingDirectory="$RELEASE_DIR" \
  --property=EnvironmentFile=/var/lib/secrets/garden.env \
  --setenv=PATH=/run/current-system/sw/bin \
  --setenv=PHX_SERVER=false \
  --setenv=PHX_HOST=garden.tail6f3b43.ts.net \
  --setenv=PORT=4000 \
  --setenv=DATABASE_URL=ecto://gnome_garden_prod@localhost/gnome_garden_prod \
  --setenv=RELEASE_DISTRIBUTION=none \
  --setenv=LANG=en_US.UTF-8 \
  "$RELEASE_DIR/bin/gnome_garden" eval "GnomeGarden.Release.bootstrap_admins()"

echo "Admin audit..."
systemd-run --wait --pipe --collect \
  --service-type=exec \
  --property=User=gnome_garden \
  --property=Group=gnome_garden \
  --property=WorkingDirectory="$RELEASE_DIR" \
  --property=EnvironmentFile=/var/lib/secrets/garden.env \
  --setenv=PATH=/run/current-system/sw/bin \
  --setenv=PHX_SERVER=false \
  --setenv=PHX_HOST=garden.tail6f3b43.ts.net \
  --setenv=PORT=4000 \
  --setenv=DATABASE_URL=ecto://gnome_garden_prod@localhost/gnome_garden_prod \
  --setenv=RELEASE_DISTRIBUTION=none \
  --setenv=LANG=en_US.UTF-8 \
  "$RELEASE_DIR/bin/gnome_garden" eval "GnomeGarden.Release.audit_admins()"

echo "HTTP checks..."
for attempt in $(seq 1 30); do
  if curl -k -fsSI https://garden.tail6f3b43.ts.net:4443/sign-in >/dev/null; then
    break
  fi

  if [ "$attempt" = "30" ]; then
    echo "Garden did not become ready at /sign-in after 30 seconds." >&2
    exit 1
  fi

  sleep 1
done

if curl -k -fs https://garden.tail6f3b43.ts.net:4443/register >/dev/null; then
  echo "Unexpected /register response." >&2
  exit 1
fi

echo "Deploy complete. Previous release: $previous"
REMOTE
