# Production Readiness

This app has two unauthenticated platform probes:

- `GET /health` is a cheap liveness check. It returns `ok` without touching dependencies.
- `GET /ready` is a readiness check. It verifies database access, document storage posture, and the Oban background job supervisor.

Run this before deploys or release builds:

```bash
MIX_ENV=prod mix gnome_garden.prod_check
```

Required production environment:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`
- `TOKEN_SIGNING_SECRET`
- `PI_SERVICE_TOKEN`
- `MERCURY_WEBHOOK_SECRET`
- `GARAGE_ACCESS_KEY`
- `GARAGE_SECRET_KEY`
- `GARAGE_BUCKET`
- `GARAGE_ENDPOINT_URL`

Optional agent/search environment:

- `ZAI_API_KEY`
- `BRAVE_API_KEY`

Document storage should be S3-compatible storage through Garage or equivalent. Local disk storage in production requires the explicit emergency escape hatch:

```bash
ALLOW_LOCAL_STORAGE_IN_PROD=true
```

Use that only as a temporary operational decision. The app will not expose the local `/storage` disk-serving route in production unless `:serve_local_storage?` is enabled at compile time.

Garage setup and verification lives in `ops/garage/bootstrap.md`. Garage is only the blob backend for AshStorage; Pi and other automation clients should request documents through the app/Ash boundary, not by using Garage credentials directly.

Deploy smoke path:

```bash
ops/garage/smoke.sh
mix precommit
MIX_ENV=prod mix gnome_garden.prod_check
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
_build/prod/rel/gnome_garden/bin/gnome_garden eval "GnomeGarden.Release.setup()"
curl -fsS https://$PHX_HOST/health
curl -fsS https://$PHX_HOST/ready
```

Operational expectations:

- In production releases, run migrations with `bin/gnome_garden eval "GnomeGarden.Release.migrate()"` or run both migrations and idempotent defaults with `bin/gnome_garden eval "GnomeGarden.Release.setup()"`.
- In local/dev workflows, continue to use `mix ash.migrate`.
- Keep Oban running with the configured queues.
- Treat `/oban`, `/admin`, and `/dev/dashboard` as development or explicitly gated operator routes only.
- Do not launch overlapping manual runs for the same agent deployment; the runner rejects them while a deployment has an active run.

Backup expectations:

- Back up Postgres and acquisition document storage together. A database-only backup is incomplete because `Acquisition.Document` records point at AshStorage blobs.
- Use custom-format Postgres dumps so restores can be targeted and verified:

```bash
pg_dump --format=custom --file=backup/gnome_garden_$(date +%Y%m%d%H%M).dump "$DATABASE_URL"
```

- Back up the configured Garage/S3 bucket or prefix with the storage provider's native snapshot, replication, or object-copy tooling.
- If local storage is temporarily enabled, back up `priv/storage` with the same timestamp as the database dump.

Restore drill:

1. Stop web and worker traffic or put the app in maintenance mode.
2. Restore Postgres into a fresh database:

```bash
pg_restore --clean --if-exists --dbname "$DATABASE_URL" backup/gnome_garden_TIMESTAMP.dump
```

3. Restore the matching Garage/S3 objects or local `priv/storage` snapshot.
4. Run release setup to apply any newer migrations and idempotent defaults:

```bash
bin/gnome_garden eval "GnomeGarden.Release.setup()"
```

5. Start the release and verify `GET /health`, `GET /ready`, sign-in, `/acquisition/findings`, and a known document download.

Agent run failure triage:

- Failed runs are inspected at `/console/agents/runs/:id`.
- `AgentRun.failure_details` is the durable failure payload. New runner failures include `category`, `phase`, `message`, and `retryable`.
- Use the failure category before rerunning:
  - `timeout`: reduce task scope or increase deployment timeout.
  - `runtime_start`: verify runtime startup, API keys, sidecar/service availability, and template configuration.
  - `runtime_exit`: inspect worker or sidecar logs for an unexpected process exit.
  - `tool_error`: inspect the tool result and repair the source, credential, or request input.
  - `authorization`: fix the operator/service token or external credential before retrying.
  - `validation`: repair deployment configuration or task input before retrying.
- The run page shows the category, retryability, recovery hint, persisted messages, live stream output, and business outputs created by the run.
