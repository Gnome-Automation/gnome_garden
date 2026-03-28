# Data Flow

## Primary Business Flows

### 1. Lead to Cash Flow

The complete journey from discovering an opportunity to receiving payment.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  LeadSource  │────▶│     Bid      │────▶│  Opportunity │
│   (Agents)   │     │   (Agents)   │     │   (Sales)    │
└──────────────┘     └──────────────┘     └──────────────┘
                                                 │
                                                 │ qualifies
                                                 ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Company    │◀────│   Contact    │◀────│  Proposal    │
│   (Sales)    │     │   (Sales)    │     │   (Sales)    │
└──────────────┘     └──────────────┘     └──────────────┘
                                                 │
                                                 │ accepted
                                                 ▼
                     ┌──────────────┐     ┌──────────────┐
                     │   Contract   │────▶│   Project    │
                     │   (Sales)    │     │  (Projects)  │
                     └──────────────┘     └──────────────┘
                                                 │
                                                 │ work done
                                                 ▼
                     ┌──────────────┐     ┌──────────────┐
                     │  TimeEntry   │────▶│   Invoice    │
                     │  (Projects)  │     │  (Finance)   │
                     └──────────────┘     └──────────────┘
                                                 │
                                                 │ paid
                                                 ▼
                                          ┌──────────────┐
                                          │   Payment    │
                                          │  (Finance)   │
                                          └──────────────┘
```

**Key Transitions:**
1. AI discovers bids from LeadSources
2. Bids scored → hot bids become Opportunities
3. Opportunities create Company + Contact records
4. Proposals generated with ProposalLines (using Parts catalog)
5. Accepted Proposals become Contracts
6. Contracts spawn Projects
7. Projects track TimeEntries + Expenses
8. TimeEntries generate Invoices
9. Invoices receive Payments

---

### 2. Bid Import Flow

AI-driven bid discovery and qualification.

```
┌─────────────────┐
│   LeadSource    │
│  (PlanetBids)   │
└────────┬────────┘
         │
         │ agent scans
         ▼
┌─────────────────┐
│   BidScanner    │
│    (Worker)     │
└────────┬────────┘
         │
         │ discovers
         ▼
┌─────────────────┐     ┌─────────────────┐
│      Bid        │────▶│    AI Scorer    │
│   (raw data)    │     │   (enrichment)  │
└─────────────────┘     └────────┬────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    HOT tier     │     │   WARM tier     │     │   COLD tier     │
│   (auto-track)  │     │  (needs review) │     │   (archive)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │
         │ converts
         ▼
┌─────────────────┐
│   Opportunity   │
│    (Sales)      │
└─────────────────┘
```

---

### 3. Proposal Building Flow

Creating proposals with parts and labor.

```
┌─────────────────┐
│   Opportunity   │
└────────┬────────┘
         │
         │ create proposal
         ▼
┌─────────────────┐
│    Proposal     │
└────────┬────────┘
         │
         ├─────────────────────────────────────┐
         │                                     │
         ▼                                     ▼
┌─────────────────┐                   ┌─────────────────┐
│  ProposalLine   │                   │  ProposalLine   │
│    (Labor)      │                   │   (Materials)   │
└────────┬────────┘                   └────────┬────────┘
         │                                     │
         ▼                                     ▼
┌─────────────────┐                   ┌─────────────────┐
│    Service      │                   │      Part       │
│ (rate: $175/hr) │                   │  (Engineering)  │
└─────────────────┘                   └────────┬────────┘
                                               │
                                               ▼
                                      ┌─────────────────┐
                                      │   VendorPart    │
                                      │  (best price)   │
                                      └─────────────────┘
```

---

### 4. Project Execution Flow

Work delivery and billing cycle.

```
┌─────────────────┐
│    Contract     │
│    (signed)     │
└────────┬────────┘
         │
         │ spawns
         ▼
┌─────────────────┐
│    Project      │
│   (active)      │
└────────┬────────┘
         │
         │ contains
         ▼
┌─────────────────┐     ┌─────────────────┐
│     Phase       │────▶│      Task       │
│  (milestone)    │     │   (work item)   │
└─────────────────┘     └────────┬────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Assignment    │     │   TimeEntry     │     │    Expense      │
│  (who + when)   │     │  (hours + $)    │     │  (receipts)     │
└─────────────────┘     └────────┬────────┘     └────────┬────────┘
                                 │                       │
                                 └───────────┬───────────┘
                                             │
                                             │ aggregates
                                             ▼
                                    ┌─────────────────┐
                                    │    Invoice      │
                                    │   (Finance)     │
                                    └─────────────────┘
```

---

### 5. Service & Support Flow

Customer support and field service.

```
┌─────────────────┐
│    Contact      │
│   (customer)    │
└────────┬────────┘
         │
         │ requests help
         ▼
┌─────────────────┐     ┌─────────────────┐
│     Ticket      │────▶│      SLA        │
│   (Service)     │     │  (time rules)   │
└────────┬────────┘     └─────────────────┘
         │
         │ needs on-site?
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌─────────────────┐
│ Remote │ │   WorkOrder     │
│  Fix   │ │  (dispatch)     │
└────────┘ └────────┬────────┘
                    │
                    │ creates
                    ▼
           ┌─────────────────┐
           │    Project      │
           │  (small job)    │
           └────────┬────────┘
                    │
                    ▼
           ┌─────────────────┐
           │   TimeEntry     │
           │  + Invoice      │
           └─────────────────┘
```

---

### 6. Retainer Billing Flow

Recurring revenue from support contracts.

```
┌─────────────────┐
│    Company      │
│   (customer)    │
└────────┬────────┘
         │
         │ signs retainer
         ▼
┌─────────────────┐
│    Retainer     │
│  ($3K/month)    │
└────────┬────────┘
         │
         │ monthly cycle
         ▼
┌─────────────────┐     ┌─────────────────┐
│  Auto-Invoice   │────▶│    Payment      │
│   (Finance)     │     │   (received)    │
└─────────────────┘     └─────────────────┘
         │
         │ tracks usage
         ▼
┌─────────────────┐
│   TimeEntry     │
│ (against hours) │
└─────────────────┘
         │
         │ overage?
         ▼
┌─────────────────┐
│ Overage Invoice │
│  (if exceeded)  │
└─────────────────┘
```

---

### 7. Engineering / BOM Flow

Parts and materials management.

```
┌─────────────────┐
│    Project      │
└────────┬────────┘
         │
         │ needs materials
         ▼
┌─────────────────┐
│      BOM        │
│ (bill of mat'l) │
└────────┬────────┘
         │
         │ contains
         ▼
┌─────────────────┐     ┌─────────────────┐
│    BOMItem      │────▶│      Part       │
│   (qty: 5)      │     │  (1756-L83E)    │
└─────────────────┘     └────────┬────────┘
                                 │
                                 │ sourced from
                                 ▼
                        ┌─────────────────┐
                        │   VendorPart    │
                        │  (best price)   │
                        └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │     Vendor      │
                        │  (Rockwell)     │
                        └─────────────────┘
```

---

### 8. Voice Capture Flow

Quick capture from voice input to actionable items.

```
┌─────────────────┐
│   Voice Input   │
│   (Twilio/Web)  │
└────────┬────────┘
         │
         │ transcribes
         ▼
┌─────────────────┐
│    Capture      │
│   (Workspace)   │
└────────┬────────┘
         │
         │ AI processes
         ▼
┌─────────────────┐
│   AI Parser     │
│ (intent detect) │
└────────┬────────┘
         │
    ┌────┴────┬──────────┬──────────┐
    ▼         ▼          ▼          ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│ Task  │ │ Note  │ │Remind │ │ Inbox │
│(Proj) │ │(Sales)│ │(Wkspc)│ │(Wkspc)│
└───────┘ └───────┘ └───────┘ └───────┘
```

---

## Data Ownership

| Domain | Owns | Referenced By |
|--------|------|---------------|
| Management | User, Role, Setting | All domains |
| HR | Member, Skill, Certification | Projects, Service |
| Sales | Company, Contact, Opportunity, Proposal, Contract | Projects, Finance, Service, Engineering |
| Projects | Project, Phase, Task, TimeEntry, Expense | Finance, Service |
| Finance | Invoice, Payment, Retainer | — |
| Engineering | Asset, Part, Vendor, BOM, Plant | Sales, Projects, Service |
| Service | Ticket, WorkOrder, SLA | Projects |
| Quality | Checklist, Inspection, NCR | Projects, Engineering |
| Agents | Bid, LeadSource, Agent, Memory | Sales |
| Workspace | Capture, Inbox, Reminder | All domains (routing) |
