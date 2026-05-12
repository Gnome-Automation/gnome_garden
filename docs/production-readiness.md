# Production Readiness

This app has two unauthenticated platform probes:

- `GET /health` is a cheap liveness check. It returns `ok` without touching dependencies.
- `GET /ready` is a readiness check. It verifies database access and document storage posture.

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

Deploy smoke path:

```bash
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
