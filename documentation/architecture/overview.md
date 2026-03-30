# Architecture Overview

## System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GnomeGarden Platform (CSIA-Aligned)                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │  Management  │  │      HR      │  │   Finance    │  │   Projects   │    │
│  │              │  │              │  │              │  │              │    │
│  │ User, Role   │  │ Member,Skill │  │Invoice,Pay   │  │ Task, Time   │    │
│  │ Setting      │  │ Cert         │  │Retainer      │  │ Expense      │    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
│         │                 │                 │                 │            │
│  ┌──────┴─────────────────┴─────────────────┴─────────────────┴───────┐    │
│  │                        PostgreSQL Database                          │    │
│  └──────┬─────────────────┬─────────────────┬─────────────────┬───────┘    │
│         │                 │                 │                 │            │
│  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐    │
│  │    Sales     │  │ Engineering  │  │   Service    │  │   Quality    │    │
│  │              │  │              │  │              │  │              │    │
│  │ CRM,Pipeline │  │ Asset,Part   │  │ Ticket,WO    │  │ Checklist    │    │
│  │ Contract     │  │ BOM,Vendor   │  │ SLA          │  │ (Phase 2)    │    │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘    │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     Agents + Workspace                                │   │
│  │                                                                       │   │
│  │    Bid Scanning, AI Automation, Voice Capture, Personal Productivity │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## CSIA Alignment

GnomeGarden domains map directly to [CSIA Best Practices](https://controlsys.org/) management areas:

| CSIA Area | GnomeGarden Domain | Key Focus |
|-----------|-----------------|-----------|
| General Management | Management | Users, roles, company settings |
| Human Resources | HR | Team, skills, capacity |
| Financial Management | Finance | Billing, payments, cash flow |
| Project Management | Projects | Delivery, time tracking |
| System Development Lifecycle | Engineering | Assets, BOMs, parts |
| Marketing/Sales | Sales | CRM, pipeline, contracts |
| Quality Assurance | Quality | Checklists, inspections |
| Customer Service | Service | Support, work orders |

## Tech Stack

### Backend
| Technology | Purpose |
|------------|---------|
| **Elixir 1.19** | Functional programming language |
| **Phoenix 1.7** | Web framework |
| **Ash 3.x** | Resource-oriented domain modeling |
| **AshPostgres** | PostgreSQL data layer |
| **AshAuthentication** | Magic link authentication |
| **AshStateMachine** | State machine support |
| **AshAdmin** | Auto-generated admin panel |
| **Oban** | Background job processing |

### Frontend
| Technology | Purpose |
|------------|---------|
| **Phoenix LiveView** | Real-time, server-rendered UI |
| **DaisyUI** | Component library |
| **Tailwind CSS** | Utility-first styling |
| **Alpine.js** | Client-side interactivity |

### AI Platform
| Technology | Purpose |
|------------|---------|
| **Jido** | Agent orchestration framework |
| **ReqLLM** | LLM API integration |
| **Jido.Browser** | Browser automation (bid scanning) |

### Infrastructure
| Technology | Purpose |
|------------|---------|
| **PostgreSQL** | Primary database |
| **Oban** | Job queue with persistence |

## Domain Relationships

```
Management ←────────────────────────────────────────────────────────────┐
    │                                                                   │
    │ extends                                                           │
    ▼                                                                   │
   HR ──────────────────────────────────────┐                          │
    │                                       │                          │
    │ staff                                 │                          │
    ▼                                       ▼                          │
 Sales ──────────────► Projects ──────────► Finance                    │
    │                      │                   │                       │
    │ customers            │ work              │                       │
    ▼                      ▼                   │                       │
Service ◄─────────── Engineering              │                        │
    │                      │                   │                       │
    │                      │ quality           │                       │
    ▼                      ▼                   │                       │
Quality ◄──────────────────┘                   │                       │
                                               │                       │
Agents ──────────────────────────────────────►│                       │
    │                                          │                       │
    │ bids → opportunities                     │                       │
    └──────────────────────────────────────────┘                       │
                                                                       │
Workspace ◄────────────────────────────────────────────────────────────┘
    │
    │ routes to all domains
    └──────────────────────────────────────────────────────────────────
```

## External Integrations

### Current
- **PlanetBids** - Bid scraping and discovery
- **LLM Providers** - AI inference (Claude, OpenAI)

### Planned
- **QuickBooks** - Accounting sync (Finance)
- **Twilio** - Voice capture (Workspace)
- **CAD Systems** - BOM import (Engineering)
- **Email/Calendar** - Activity sync (Sales)

## Security Model

- **Magic Link Authentication** - Passwordless login via email
- **Token-based API Access** - For integrations
- **Role-based Permissions** - Admin, User, Viewer
- **Tenant Isolation** - Multi-tenant ready (future)

## Key Design Principles

1. **CSIA-Aligned** - Domains match industry best practices
2. **Resource-Oriented** - Ash resources are the source of truth
3. **Event-Driven** - State machines for complex workflows
4. **AI-Native** - Agents deeply integrated, not bolted on
5. **Mobile-First** - DaisyUI responsive design
6. **Recurring Revenue Focus** - Retainers as first-class citizens
