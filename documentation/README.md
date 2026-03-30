# GnomeGarden Platform Documentation

**Vertical SaaS for Controls Integrators: CRM + PSA + Service + Engineering + AI**

## What is GnomeGarden?

GnomeGarden is a comprehensive business platform designed specifically for building controls integrators. It combines customer relationship management, professional services automation, service management, and specialized engineering tools into a single, AI-powered system.

The domain structure is aligned with [CSIA Best Practices](https://controlsys.org/) — the industry standard for control system integration business management.

## Tech Stack

- **Backend:** Elixir, Phoenix, Ash Framework
- **Database:** PostgreSQL
- **Frontend:** Phoenix LiveView, DaisyUI, Tailwind CSS
- **AI:** Jido Agent Framework, LLM Integration
- **Jobs:** Oban

## Quick Start

```bash
# Install dependencies
mix deps.get

# Setup database
mix ash.setup

# Start server
iex -S mix phx.server
```

## Domain Map (CSIA-Aligned)

| # | Domain | CSIA Area | Purpose | Resources |
|---|--------|-----------|---------|-----------|
| 1 | [Management](domains/01-management.md) | General Management | Identity, auth, settings | 3 |
| 2 | [HR](domains/02-hr.md) | Human Resources | Team, skills, capacity | 3 |
| 3 | [Finance](domains/03-finance.md) | Financial Management | Invoices, payments, retainers | 4 |
| 4 | [Projects](domains/04-projects.md) | Project Management | Projects, tasks, time, expenses | 6 |
| 5 | [Engineering](domains/05-engineering.md) | System Development | Assets, BOMs, parts, vendors | 8 |
| 6 | [Sales](domains/06-sales.md) | Marketing/Sales | CRM, pipeline, contracts | 10 |
| 7 | [Quality](domains/07-quality.md) | Quality Assurance | Checklists, inspections | 3 |
| 8 | [Service](domains/08-service.md) | Customer Service | Tickets, work orders, SLAs | 4 |
| 9 | [Agents](domains/09-agents.md) | AI Platform | Bid scanning, automation | 6 |
| 10 | [Workspace](domains/10-workspace.md) | Personal Productivity | Capture, inbox, reminders | 3 |

**Total: 50 resources across 10 domains**

## Documentation Structure

```
documentation/
├── README.md                    # This file
├── architecture/
│   ├── overview.md              # System diagram, tech stack
│   ├── domains.md               # All 10 domains at a glance
│   └── data-flow.md             # How data moves between domains
├── domains/
│   ├── 01-management.md         # General Management
│   ├── 02-hr.md                 # Human Resources
│   ├── 03-finance.md            # Financial Management
│   ├── 04-projects.md           # Project Management
│   ├── 05-engineering.md        # System Development
│   ├── 06-sales.md              # Marketing/Sales (CRM + Pipeline)
│   ├── 07-quality.md            # Quality Assurance
│   ├── 08-service.md            # Customer Service
│   ├── 09-agents.md             # AI Platform
│   └── 10-workspace.md          # Personal Productivity
└── ui/
    ├── layout.md                # Mobile-first structure
    ├── navigation.md            # Routes + menus
    └── components.md            # DaisyUI patterns
```

## Key Workflows

### Lead to Cash
```
Agents (Bid) → Sales (Opportunity → Proposal → Contract) → Projects → Finance (Invoice)
```

### Service Flow
```
Service (Ticket/WorkOrder) → Projects (Task) → Finance (Invoice)
```

### Voice Capture
```
Workspace (Capture) → AI Processing → Sales/Projects/Service
```

## Admin Access

- **Admin Dashboard:** `/admin`
- **Job Queue:** `/oban`

## References

- [CSIA Best Practices Manual](https://controlsys.org/) - Industry standard for SI business management
- [Gnome Automation Company Docs](https://github.com/Gnome-Automation/gnome-company) - Business operations
