# GnomeGarden

CRM and sales automation platform built with Phoenix, Ash Framework, and Jido AI agents.

## Setup

### Prerequisites

- Elixir 1.15+
- PostgreSQL
- Node.js (for assets)

### Installation

```bash
# Install dependencies
mix setup

# Install browser automation backend (required for agents)
mix jido_browser.install

# Start the server
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) from your browser.

### Environment Variables

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

```bash
# AI Models - Z.AI (Zhipu AI) for GLM models
# Get API key from https://open.bigmodel.cn
ZAI_API_KEY=your_zai_api_key

# Web Search - Brave Search API
# Get API key from https://brave.com/search/api/
BRAVE_API_KEY=your_brave_api_key

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

The agents use `jido_browser` for web automation (scanning bid sites, researching prospects).

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

### Recommended Mix Aliases

Add to `mix.exs` for automatic browser installation:

```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup", "jido_browser.install --if-missing"],
    test: ["jido_browser.install --if-missing", "test"]
  ]
end
```

## Project Structure

```
lib/
├── garden/                 # Business logic
│   ├── accounts/          # User authentication
│   ├── agents/            # AI agent resources (Bid, Prospect, LeadSource)
│   └── sales/             # CRM resources (Company, Contact, Opportunity, Lead, Task)
└── garden_web/            # Web layer
    ├── live/
    │   ├── crm/           # CRM LiveViews
    │   └── agents/sales/  # Agent LiveViews
    └── components/        # Shared components
```

## Domains

### Sales (CRM)
- Companies, Contacts, Opportunities, Leads, Tasks
- Activities, Notes, Addresses

### Agents (Automation)
- **Bids** - Government/public bid opportunities
- **Prospects** - Discovered potential customers
- **LeadSources** - URLs to scan for leads

## Admin

Ash Admin is available at [`localhost:4000/admin`](http://localhost:4000/admin) for direct resource management.

## Development

```bash
# Run in IEx for hot reloading
iex -S mix phx.server

# Recompile after changes
recompile()

# Generate Ash migrations
mix ash.codegen migration_name
mix ash.migrate
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
