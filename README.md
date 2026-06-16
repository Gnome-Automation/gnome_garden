# GnomeGarden

CRM and operations automation platform built with Phoenix, Ash Framework, Oban,
AshLua/AshAI, and `jido_browser` as the browser automation engine.

## Setup

### Prerequisites

The preferred local setup is the Nix dev shell in this repo. It pins:

- Erlang/OTP 29
- Elixir 1.20
- Node.js 22
- PostgreSQL 18 on local port `5433`
- Tailwind CSS 4 and esbuild
- document tooling used by AshStorage analyzers and vendor onboarding flows:
  Poppler (`pdftotext`/`pdfinfo`), Tesseract, ImageMagick, Antiword, and
  LibreOffice

### Installation

```bash
# Enter the pinned VM/dev shell. This initializes .pgdata and starts Postgres.
nix develop

# Install dependencies, prepare the database, and build assets.
mix setup

# Start the server
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) from your browser.

See [`docs/development-vm-setup.md`](docs/development-vm-setup.md) for the full
VM/dev-shell checklist.

### Environment Variables

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

`.env.example` is committed so another workstation can see every supported
variable. `.env` stays ignored because committing real API keys or tokens keeps
them recoverable in Git history even after later edits.

```bash
# AI Models - Z.AI (Zhipu AI) for GLM models
# Get API key from https://open.bigmodel.cn
ZAI_API_KEY=your_zai_api_key

# Optional model provider key
ANTHROPIC_API_KEY=your_anthropic_api_key

# Web Search - Brave Search API
# Get API key from https://brave.com/search/api/
BRAVE_API_KEY=your_brave_api_key

# Mercury banking integration
MERCURY_API_KEY=your_mercury_api_key
MERCURY_SANDBOX=true
MERCURY_WEBHOOK_SECRET=your_mercury_webhook_secret

# Gnome company bootstrap facts
GNOME_COMPANY_FEIN=your_company_fein
GNOME_MERCURY_CHECKING_ACCOUNT_NUMBER=your_account_number

# Procurement source fallbacks
SAM_GOV_API_KEY=your_sam_gov_api_key
PLANETBIDS_USERNAME=your_planetbids_username
PLANETBIDS_PASSWORD=your_planetbids_password
PUBLICPURCHASE_USERNAME=your_publicpurchase_username
PUBLICPURCHASE_PASSWORD=your_publicpurchase_password

# Database (production)
DATABASE_URL=postgres://user:pass@host/database

# Secret key (production)
SECRET_KEY_BASE=your_secret_key
```

### Required Services

| Service | Purpose | Get API Key |
|---------|---------|-------------|
| Z.AI (Zhipu) | LLM for agents (GLM-4.7, GLM-5) | [open.bigmodel.cn](https://open.bigmodel.cn) |
| Brave Search | Web search for research | [brave.com/search/api](https://brave.com/search/api/) |
| PostgreSQL | Database | Local or hosted |

## Browser Automation

The app keeps `jido_browser` as the browser automation engine behind
`GnomeGarden.Browser`. Durable business behavior should live in Ash actions,
Oban jobs, AshLua/AshAI orchestration, or bounded workers.

### Install Browser Backend

```bash
# Install the default agent-browser backend
mix jido_browser.install

# Or install specific backends
mix jido_browser.install agent_browser
mix jido_browser.install vibium
mix jido_browser.install web
```

The browser binary is installed to `_build/jido_browser-{platform}/`.

## Project Structure

```
lib/garden/
  accounts/        # users and auth
  acquisition/     # findings and review workflow
  company/         # reusable Gnome facts, documents, tax, payment data
  commercial/      # discovery, customer onboarding, agreements
  execution/       # projects, tickets, delivery
  finance/         # payments and finance records
  operations/      # orgs, people, tasks, assets
  procurement/     # sources, bids, credentials, scans
lib/garden_web/
  live/            # LiveViews
  components/      # shared UI
  router.ex
```

## Domains

### Company

- Reusable Gnome facts, documents, tax identifiers, payment destinations,
  compliance records, and source review items.

### Commercial

- Discovery records, signals, pursuits, agreements, customer vendor onboarding,
  and customer-specific requirement artifacts.

### Procurement

- Public procurement sources, source credentials, bid review, crawl artifacts,
  and import/scan workflows.

### Acquisition, Operations, Execution, Finance

- Review queue, organizations/people/tasks/assets, delivery records, and
  payment/finance records.

## Admin

Ash Admin is available at [`localhost:4000/admin`](http://localhost:4000/admin) for direct resource management.

## Development

```bash
# Enter the pinned dev shell
nix develop

# Run in IEx for hot reloading
iex -S mix phx.server

# Recompile after changes
recompile()

# Generate Ash migrations
mix ash.codegen migration_name
mix ash.migrate

# Refresh the machine-readable resource map after Ash changes
mix llm.generate_resource_map

# Final broad check before PRs
mix precommit
```

## Production Operations

Run the production environment check before building or deploying:

```bash
MIX_ENV=prod mix gnome_garden.prod_check
```

Inside a release, run migrations and idempotent defaults with:

```bash
bin/gnome_garden eval "GnomeGarden.Release.setup()"
```

To migrate only:

```bash
bin/gnome_garden eval "GnomeGarden.Release.migrate()"
```
