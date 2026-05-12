# Garage Document Storage

Garage is the S3-compatible blob store behind `AshStorage`.

The application boundary is:

- `GnomeGarden.Acquisition.Document` owns document records, metadata, lifecycle, and relationships.
- `AshStorage` owns attachment/blob behavior from inside the Ash resource.
- Garage owns object bytes only.
- Pi and other automation clients should ask the app/Ash for documents. Do not give Pi Garage credentials or teach it to construct Garage object keys.

## Production Env

The app reads these variables at runtime:

```sh
export GARAGE_ACCESS_KEY="..."
export GARAGE_SECRET_KEY="..."
export GARAGE_BUCKET="gnome-garden-acquisition"
export GARAGE_ENDPOINT_URL="http://127.0.0.1:3900"
export GARAGE_REGION="garage"
export GARAGE_PREFIX="acquisition/"
```

`GARAGE_REGION` and `GARAGE_PREFIX` have defaults. Set them anyway in production so the deployed state is explicit.

## Single-Node Bootstrap

Use this for a small local/Pi deployment. Run it on the host that owns Garage data.

```sh
export GARAGE_CONFIG_FILE=/etc/garage.toml
export GARAGE_BUCKET=gnome-garden-acquisition
export GARAGE_KEY_NAME=gnome-garden-app

garage status
garage bucket create "$GARAGE_BUCKET"
garage key create "$GARAGE_KEY_NAME"
garage bucket allow --read --write "$GARAGE_BUCKET" --key "$GARAGE_KEY_NAME"
garage key info --show-secret "$GARAGE_KEY_NAME"
```

Copy the access key and secret from `garage key info --show-secret` into the app environment as `GARAGE_ACCESS_KEY` and `GARAGE_SECRET_KEY`.

## App Verification

From the app checkout:

```sh
ops/garage/smoke.sh
MIX_ENV=prod mix gnome_garden.prod_check
curl -fsS "https://$PHX_HOST/ready"
```

The smoke script talks directly to Garage because it is an operator storage check. Product code and Pi workflows should go through Ash/app endpoints instead.

## Backup Rule

Back up the Garage bucket/prefix with the matching Postgres backup. A database dump without the corresponding Garage objects is incomplete because Ash document records point at blobs.
