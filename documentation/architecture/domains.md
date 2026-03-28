# Domains Overview (CSIA-Aligned)

## All 10 Domains at a Glance

| # | Domain | Module | CSIA Area | Resources | Status |
|---|--------|--------|-----------|-----------|--------|
| 1 | Management | `GnomeHub.Management` | General Management | 3 | 🆕 New |
| 2 | HR | `GnomeHub.HR` | Human Resources | 3 | 🆕 New |
| 3 | Finance | `GnomeHub.Finance` | Financial Management | 4 | 🆕 New |
| 4 | Projects | `GnomeHub.Projects` | Project Management | 6 | 🆕 New |
| 5 | Engineering | `GnomeHub.Engineering` | System Development | 8 | 🆕 New |
| 6 | Sales | `GnomeHub.Sales` | Marketing/Sales | 10 | 🆕 New |
| 7 | Quality | `GnomeHub.Quality` | Quality Assurance | 3 | 📋 Phase 2 |
| 8 | Service | `GnomeHub.Service` | Customer Service | 4 | 🆕 New |
| 9 | Agents | `GnomeHub.Agents` | AI Platform | 6 | ✅ Existing |
| 10 | Workspace | `GnomeHub.Workspace` | Personal Productivity | 3 | 🆕 New |

**Total: 50 Resources**

---

## Domain Details

### 1. Management (General Management)
**Purpose:** Identity, authentication, company settings

| Resource | Description |
|----------|-------------|
| User | Authenticated users with magic link |
| Role | Permission levels (admin, user, viewer) |
| Setting | Company-wide configuration |

### 2. HR (Human Resources)
**Purpose:** Team management, skills, capacity planning

| Resource | Description |
|----------|-------------|
| Member | Team members (extends User) |
| Skill | Competencies and certifications |
| Certification | Formal certifications with expiry |

### 3. Finance (Financial Management)
**Purpose:** Billing, payments, recurring revenue

| Resource | Description |
|----------|-------------|
| Invoice | Bills to customers |
| InvoiceLine | Line items on invoices |
| Payment | Received payments |
| Retainer | Recurring service agreements |

### 4. Projects (Project Management)
**Purpose:** Project execution, time tracking, expenses

| Resource | Description |
|----------|-------------|
| Project | Work containers |
| Phase | Project milestones |
| Task | Actionable work items |
| TimeEntry | Billable time records |
| Expense | Reimbursable costs |
| Assignment | Resource allocation |

### 5. Engineering (System Development Lifecycle)
**Purpose:** Assets, BOMs, parts catalog, control templates

| Resource | Description |
|----------|-------------|
| Asset | Customer equipment (PLCs, panels) |
| Plant | Customer facilities |
| BOM | Bills of materials |
| BOMItem | BOM line items |
| Part | Master parts catalog |
| Vendor | Suppliers |
| VendorPart | Vendor-specific pricing |
| LogicTemplate | Reusable control code |

### 6. Sales (Marketing/Sales)
**Purpose:** CRM, pipeline, proposals, contracts

**CRM (Relationships)**
| Resource | Description |
|----------|-------------|
| Company | Organizations (customers, partners) |
| Contact | People at companies |
| Industry | Industry classification |
| Activity | Interactions and touchpoints |
| Note | Freeform notes |

**Pipeline**
| Resource | Description |
|----------|-------------|
| Opportunity | Sales pipeline items |
| Proposal | Formal quotes |
| ProposalLine | Line items on proposals |
| Contract | Signed agreements |
| Service | Service catalog items |

### 7. Quality (Quality Assurance)
**Purpose:** Checklists, inspections, non-conformance — *Phase 2*

| Resource | Description |
|----------|-------------|
| Checklist | Reusable check templates |
| Inspection | Completed inspections |
| NCR | Non-conformance reports |

### 8. Service (Customer Service)
**Purpose:** Support tickets, work orders, SLAs

| Resource | Description |
|----------|-------------|
| Ticket | Support requests |
| TicketComment | Ticket responses |
| WorkOrder | Field service requests |
| SLA | Service level agreements |

### 9. Agents (AI Platform)
**Purpose:** AI automation, bid discovery, internal tooling

**Built on Jido framework with 40+ tools and hybrid scanning architecture.**

| Resource | Description |
|----------|-------------|
| Agent | Agent definitions |
| AgentRun | Execution instances |
| AgentMessage | Conversation history |
| Memory | Persistent agent knowledge |
| LeadSource | Bid discovery sources |
| Bid | Discovered opportunities |

**Workers:** Base, Coder, Researcher, BidScanner, SmartScanner, etc.

### 10. Workspace (Personal Productivity)
**Purpose:** Quick capture, inbox, reminders

| Resource | Description |
|----------|-------------|
| Capture | Voice/text quick captures |
| Inbox | Actionable items queue |
| Reminder | Time-based notifications |

---

## Cross-Domain Relationships

```
┌─────────────┐
│ Management  │──────────────────────────────────────────┐
│   (User)    │                                          │
└──────┬──────┘                                          │
       │ extends                                         │
       ▼                                                 │
┌─────────────┐                                          │
│     HR      │                                          │
│  (Member)   │                                          │
└──────┬──────┘                                          │
       │                                                 │
       ▼                                                 │
┌─────────────┐     ┌─────────────┐     ┌─────────────┐ │
│   Sales     │────▶│  Projects   │────▶│   Finance   │ │
│ (CRM+Opps)  │     │ (Delivery)  │     │ (Billing)   │ │
└──────┬──────┘     └──────┬──────┘     └─────────────┘ │
       │                   │                             │
       │                   ▼                             │
       │            ┌─────────────┐                      │
       │            │   Service   │                      │
       │            │  (Support)  │                      │
       │            └──────┬──────┘                      │
       │                   │                             │
       ▼                   ▼                             │
┌─────────────┐     ┌─────────────┐                      │
│ Engineering │◀────│   Quality   │                      │
│(Assets/BOMs)│     │ (Phase 2)   │                      │
└─────────────┘     └─────────────┘                      │
       ▲                                                 │
       │                                                 │
┌──────┴──────┐     ┌─────────────┐                      │
│   Agents    │     │  Workspace  │◀─────────────────────┘
│ (AI/Bids)   │     │  (Capture)  │
└─────────────┘     └─────────────┘
```

---

## File Locations

| Domain | Domain File | Resources Directory |
|--------|-------------|---------------------|
| Management | `lib/gnome_hub/management.ex` | `lib/gnome_hub/management/` |
| HR | `lib/gnome_hub/hr.ex` | `lib/gnome_hub/hr/` |
| Finance | `lib/gnome_hub/finance.ex` | `lib/gnome_hub/finance/` |
| Projects | `lib/gnome_hub/projects.ex` | `lib/gnome_hub/projects/` |
| Engineering | `lib/gnome_hub/engineering.ex` | `lib/gnome_hub/engineering/` |
| Sales | `lib/gnome_hub/sales.ex` | `lib/gnome_hub/sales/` |
| Quality | `lib/gnome_hub/quality.ex` | `lib/gnome_hub/quality/` |
| Service | `lib/gnome_hub/service.ex` | `lib/gnome_hub/service/` |
| Agents | `lib/gnome_hub/agents.ex` | `lib/gnome_hub/agents/` |
| Workspace | `lib/gnome_hub/workspace.ex` | `lib/gnome_hub/workspace/` |
