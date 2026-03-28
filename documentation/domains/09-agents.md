# Agents Domain

**CSIA Area:** — (GnomeHub Unique)
**Module:** `GnomeHub.Agents`
**Purpose:** AI automation, bid discovery, agent orchestration
**Status:** ✅ Existing (with scaling architecture)

---

## Overview

The Agents domain is GnomeHub's AI platform. It powers automated bid discovery from government sources, conversational agents, and memory persistence. Built on the **Jido agent framework**.

---

## Architecture

### Jido Framework

GnomeHub agents use the Jido framework which provides:

| Component | Purpose |
|-----------|---------|
| `Jido.AI.Agent` | Declarative agent definition (tools, model, streaming) |
| Actions | Tools agents can call (file ops, browser, memory) |
| Directives | Side effects with compensation (external state) |
| Signals | Events for agent communication |
| Strategies | Execution control (chain, parallel, race) |

### Current Implementation

```
┌─────────────────────────────────────────────────────┐
│                Module-Based Agents                   │
│  Workers/*.ex define agent behavior using           │
│  `use Jido.AI.Agent` with hardcoded tools/prompts   │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│              Templates.ex Registry                   │
│  Maps template names → worker modules               │
│  { "coder" => Coder, "bid_scanner" => BidScanner }  │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│              AgentRun (Ash Resource)                │
│  Tracks individual executions, tokens, results      │
└─────────────────────────────────────────────────────┘
```

---

## Hybrid Scanning Architecture

Current bid scanning uses a hybrid LLM + deterministic approach:

```
┌─────────────────────────────────────────────────────┐
│          Phase 1: LLM Discovery (One-Time)          │
│  SmartScanner uses LLM to figure out:               │
│  - Listing page URL                                 │
│  - CSS selectors for table/rows                     │
│  - Pagination pattern                               │
│  Cost: ~$0.05-0.10 per site (done once)            │
└─────────────────────────────────────────────────────┘
         │
         │ saves scrape_config to LeadSource
         ▼
┌─────────────────────────────────────────────────────┐
│       Phase 2: Deterministic Scanning (Recurring)   │
│  DeterministicScanner uses saved config:            │
│  - Browser automation (no LLM)                      │
│  - Extract using known selectors                    │
│  - LLM only for bid scoring (~100 tokens each)     │
│  Cost: ~$0.01-0.02 per scan                        │
└─────────────────────────────────────────────────────┘
```

**Batch Discovery for Known Platforms:**

```elixir
# PlanetBids sites share same structure - auto-discover
GnomeHub.Agents.BatchDiscovery.discover_all_planetbids()

# Scan all ready sources
GnomeHub.Agents.DeterministicScanner.scan_all_ready()
```

---

## Resources

### Agent
Agent definitions stored in database.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Agent identifier |
| template | string | yes | Worker template name |
| description | string | no | Purpose description |
| model | atom | yes | LLM model tier |
| max_iterations | integer | yes | Max iterations |
| tools | array | no | Tool overrides |
| system_prompt | string | no | Prompt override |

### AgentRun
Individual agent execution instances.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| status | atom | yes | Current state |
| input | map | no | Run parameters |
| result | map | no | Execution output |
| token_count | integer | no | Tokens consumed |
| started_at | utc_datetime | no | Execution start |
| completed_at | utc_datetime | no | Execution end |
| agent_id | uuid | yes | Parent agent |
| user_id | uuid | yes | Initiated by |

**State Machine:**
```
pending → running → completed
     ↓        ↓
   failed ← cancelled
```

### AgentMessage
Conversation history for agent runs.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| role | atom | yes | Message role |
| content | string | yes | Message text |
| tool_calls | array | no | Tool invocations |
| agent_run_id | uuid | yes | Parent run |

**Role Values:**
- `:system` - System prompt
- `:user` - User input
- `:assistant` - Agent response
- `:tool` - Tool result

### Memory
Persistent knowledge storage.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| key | string | yes | Memory identifier |
| content | string | yes | Stored info |
| embedding | vector | no | Semantic embedding |
| agent_id | uuid | yes | Owning agent |

**Actions:**
- `store` - Save new memory
- `recall` - Retrieve by key
- `search` - Semantic similarity search

### LeadSource
Bid discovery source configurations.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Source name |
| source_type | atom | yes | Platform type |
| url | string | yes | Source URL |
| external_id | string | no | Platform ID |
| region | atom | yes | Geographic region |
| keywords | array | no | Search terms |
| discovery_status | atom | yes | Discovery state |
| scrape_config | map | no | Saved selectors |
| last_scan_at | utc_datetime | no | Last scan time |
| active | boolean | yes | Enabled |

**Source Type Values:**
- `:planetbids` - PlanetBids platform
- `:opengov` - OpenGov platform
- `:sam` - SAM.gov
- `:custom` - Custom scraper

**Discovery Status:**
- `:pending` - Needs discovery
- `:discovering` - In progress
- `:discovered` - Ready to scan
- `:failed` - Discovery failed

### Bid
Discovered bid opportunities.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| title | string | yes | Bid title |
| description | string | no | Full description |
| url | string | yes | Source link |
| agency | string | no | Issuing agency |
| location | string | no | Geographic location |
| due_at | utc_datetime | no | Submission deadline |
| status | atom | yes | Processing status |
| score_total | integer | no | Total score (0-100) |
| score_tier | atom | calc | hot/warm/cold |
| keywords_matched | array | no | Matched terms |
| lead_source_id | uuid | yes | Source |

**Status Values:**
- `:new` - Just discovered
- `:reviewing` - Under evaluation
- `:pursuing` - Actively bidding
- `:submitted` - Bid submitted
- `:won` - Contract awarded
- `:lost` - Not selected
- `:passed` - Declined to bid

**Score Tier (from target-customers.md):**
- `:hot` - Score ≥ 75 (auto-track)
- `:warm` - Score 50-74 (needs review)
- `:cold` - Score < 50 (archive)

---

## Tools (Organized by Domain)

Workers and tools are organized by the domain they operate on.

### Common Tools (Shared)
Used across all domains.

| Tool | Purpose |
|------|---------|
| ReadFile | Read file contents |
| WriteFile | Create/overwrite files |
| EditFile | Patch existing files |
| ListDirectory | List directory contents |
| SearchCode | Grep-like code search |
| GitStatus | Working tree status |
| GitDiff | Show changes |
| GitCommit | Create commits |
| RunCommand | Execute shell commands |
| WebSearch | Search the web |
| MemoryRemember | Store key-value |
| MemoryRecall | Retrieve by key |
| MemorySearch | Semantic search |
| SpawnAgent | Launch child agent |
| ListAgents | List running agents |
| GetAgentResult | Get agent output |
| KillAgent | Terminate agent |

### Browser Tools (Shared)
Used by any agent needing web automation.

| Tool | Purpose |
|------|---------|
| Navigate | Go to URL |
| Click | Click element |
| Fill | Fill form field |
| Extract | Run JS, get data |
| Snapshot | Capture screenshot |

### Sales Tools
Tools for Sales domain operations.

| Tool | Purpose |
|------|---------|
| ScoreBid | Score bid relevance |
| SaveBid | Persist bid to DB |
| SaveDiscovery | Save scrape config |
| CreateOpportunity | Convert bid to opportunity |

### Engineering Tools (Planned)
Tools for Engineering domain operations.

| Tool | Purpose |
|------|---------|
| LookupPart | Search parts catalog |
| GenerateBOM | Create bill of materials |

### Service Tools (Planned)
Tools for Service domain operations.

| Tool | Purpose |
|------|---------|
| CreateTicket | Create support ticket |
| TriageTicket | Classify and route ticket |

### Workspace Tools (Planned)
Tools for Workspace domain operations.

| Tool | Purpose |
|------|---------|
| RouteCapture | Route capture to correct domain |
| CreateReminder | Create reminder from capture |

---

## Workers (Organized by Domain)

### General Purpose
| Worker | Purpose | Tools |
|--------|---------|-------|
| Base | Full-capability agent | All tools |
| Coder | Code generation | File + Git + Memory |
| Researcher | Codebase analysis | Read-only |
| Reviewer | Code review | Read-only |
| TestRunner | Run tests | ReadFile + RunCommand |

### Sales Workers
| Worker | Purpose | Tools |
|--------|---------|-------|
| BidScanner | Legacy scanner | Browser + Scoring |
| SmartScanner | LLM-driven discovery | Browser + Memory |
| SourceDiscovery | Find new portals | Web + Browser |
| LeadQualifier | Score and qualify leads | Sales + Memory |

### Engineering Workers (Planned)
| Worker | Purpose | Tools |
|--------|---------|-------|
| BOMGenerator | Generate BOMs from specs | Engineering + Memory |
| AssetInspector | Analyze asset documentation | Read + Engineering |

### Service Workers (Planned)
| Worker | Purpose | Tools |
|--------|---------|-------|
| TicketTriager | Auto-classify tickets | Service + Memory |
| SupportAgent | Answer support questions | Read + Service |

### Workspace Workers (Planned)
| Worker | Purpose | Tools |
|--------|---------|-------|
| CaptureRouter | Route captures to domains | Workspace + Memory |

---

## Scoring Algorithm

Based on target-customers.md scoring rubric:

| Category | Points | Criteria |
|----------|--------|----------|
| Service Match | 30 | SCADA/PLC = 30, adjacent = 15 |
| Geography | 20 | SoCal = 20, NorCal = 12 |
| Value | 20 | >$500K = 20, $100-500K = 15 |
| Tech Fit | 15 | Rockwell/Ignition = 15 |
| Industry | 10 | Water/biotech = 10 |
| Opportunity Type | 5 | Direct RFP = 5 |

**Boost Keywords:**
```
scada plc controls automation instrumentation
hmi dcs telemetry monitoring
water wastewater treatment pump
brewery biotech pharmaceutical
```

**Reject Keywords:**
```
hvac mechanical plumbing roofing
janitorial landscaping paving
security guard custodial
```

---

## Bid → Opportunity Conversion

```
Hot Bid (auto or manual)
         ↓
   "Convert to Opportunity"
         ↓
┌─────────────────┐
│ Sales.Opportunity │
│ - source: :bid   │
│ - bid_id: xxx    │
│ - company: (new) │
└─────────────────┘
```

---

## Scheduling

| Task | Schedule | Method |
|------|----------|--------|
| Batch Discovery | On-demand | Manual for new sources |
| Deterministic Scan | Every 4 hours | Oban cron |
| Memory Cleanup | Daily | Oban scheduled |

```elixir
# In config/runtime.exs or application.ex
config :gnome_hub, Oban,
  queues: [agents: 10, scanners: 5],
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 */4 * * *", GnomeHub.Agents.Jobs.ScanAllSources}
    ]}
  ]
```

---

## UI Routes

| Route | Description |
|-------|-------------|
| `/agents` | Agent management |
| `/agents/:id/chat` | Chat interface |
| `/bids` | Bid dashboard |
| `/bids/:id` | Bid detail |
| `/sources` | Lead source config |
| `/sources/:id/discover` | Run discovery |

---

## File Structure

```
lib/gnome_hub/
├── agents.ex                    # Domain module
└── agents/
    ├── agent.ex                 # Agent resource
    ├── agent_run.ex             # Execution tracking
    ├── agent_message.ex         # Conversation history
    ├── memory.ex                # Persistent memory
    ├── lead_source.ex           # Source config
    ├── bid.ex                   # Discovered bids
    ├── templates.ex             # Worker registry
    ├── deterministic_scanner.ex # Fast scanning
    ├── batch_discovery.ex       # PlanetBids auto-discovery
    │
    ├── workers/
    │   ├── base.ex              # General: full-capability
    │   ├── coder.ex             # General: code generation
    │   ├── researcher.ex        # General: read-only exploration
    │   ├── reviewer.ex          # General: code review
    │   ├── test_runner.ex       # General: run tests
    │   │
    │   ├── sales/               # Sales domain workers
    │   │   ├── bid_scanner.ex
    │   │   ├── smart_scanner.ex
    │   │   ├── source_discovery.ex
    │   │   └── lead_qualifier.ex
    │   │
    │   ├── engineering/         # Engineering domain workers
    │   │   ├── bom_generator.ex
    │   │   └── asset_inspector.ex
    │   │
    │   ├── service/             # Service domain workers
    │   │   ├── ticket_triager.ex
    │   │   └── support_agent.ex
    │   │
    │   └── workspace/           # Workspace domain workers
    │       └── capture_router.ex
    │
    └── tools/
        ├── common/              # Shared across domains
        │   ├── read_file.ex
        │   ├── write_file.ex
        │   ├── edit_file.ex
        │   ├── run_command.ex
        │   ├── web_search.ex
        │   ├── memory_remember.ex
        │   ├── memory_recall.ex
        │   ├── memory_search.ex
        │   ├── spawn_agent.ex
        │   ├── list_agents.ex
        │   ├── get_agent_result.ex
        │   └── kill_agent.ex
        │
        ├── browser/             # Browser automation (shared)
        │   ├── navigate.ex
        │   ├── click.ex
        │   ├── fill.ex
        │   ├── extract.ex
        │   └── snapshot.ex
        │
        ├── sales/               # Sales domain tools
        │   ├── score_bid.ex
        │   ├── save_bid.ex
        │   ├── save_discovery.ex
        │   └── create_opportunity.ex
        │
        ├── engineering/         # Engineering domain tools
        │   ├── lookup_part.ex
        │   └── generate_bom.ex
        │
        ├── service/             # Service domain tools
        │   ├── create_ticket.ex
        │   └── triage_ticket.ex
        │
        └── workspace/           # Workspace domain tools
            ├── route_capture.ex
            └── create_reminder.ex
```

---

## Templates Registry

The `Templates` module maps agent names to their worker modules, organized by domain:

```elixir
@templates %{
  # General purpose
  "base" => %{module: Workers.Base, ...},
  "coder" => %{module: Workers.Coder, ...},
  "researcher" => %{module: Workers.Researcher, ...},
  "reviewer" => %{module: Workers.Reviewer, ...},
  "test_runner" => %{module: Workers.TestRunner, ...},

  # Sales
  "bid_scanner" => %{module: Workers.Sales.BidScanner, ...},
  "smart_scanner" => %{module: Workers.Sales.SmartScanner, ...},
  "source_discovery" => %{module: Workers.Sales.SourceDiscovery, ...},
  "lead_qualifier" => %{module: Workers.Sales.LeadQualifier, ...},

  # Engineering
  "bom_generator" => %{module: Workers.Engineering.BOMGenerator, ...},
  "asset_inspector" => %{module: Workers.Engineering.AssetInspector, ...},

  # Service
  "ticket_triager" => %{module: Workers.Service.TicketTriager, ...},
  "support_agent" => %{module: Workers.Service.SupportAgent, ...},

  # Workspace
  "capture_router" => %{module: Workers.Workspace.CaptureRouter, ...}
}
```

---

## Architecture Notes

### Current Approach (Module-Based)
- ✅ Workers defined as Elixir modules with `use Jido.AI.Agent`
- ✅ Templates registry maps names → modules
- ✅ Workers/tools organized by domain they operate on
- ✅ AgentRun tracks executions
- ✅ Hybrid scanning (LLM discovery + deterministic batch)
- Sufficient for internal tooling needs

### Migration Strategy
Existing flat workers can be moved incrementally:
1. Create domain subfolder (e.g., `workers/sales/`)
2. Move worker file
3. Update module name (`Workers.BidScanner` → `Workers.Sales.BidScanner`)
4. Update Templates registry
5. General purpose workers stay at root

**Note:** These agents are internal tools for Gnome Automation, not a product. Keep it simple.
