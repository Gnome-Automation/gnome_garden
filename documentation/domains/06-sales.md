# Sales Domain

**CSIA Area:** Marketing/Business Development/Sales Management
**Module:** `GnomeHub.Sales`
**Purpose:** CRM, pipeline, proposals, contracts, services

---

## Overview

The Sales domain combines CRM (relationship management) and sales pipeline into one cohesive domain. It manages companies, contacts, opportunities, proposals, and contracts — the full journey from lead to signed deal.

---

## CRM (Relationships)

### Company
Organizations — customers, partners, prospects.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Company name |
| legal_name | string | no | Legal entity name |
| company_type | atom | yes | Relationship type |
| status | atom | yes | Account status |
| website | string | no | Company URL |
| phone | string | no | Main phone |
| address | string | no | Full address |
| city | string | no | City |
| state | string | no | State |
| postal_code | string | no | ZIP |
| industry_id | uuid | no | Industry |
| owner_id | uuid | no | Account owner (Member) |

**Company Type Values:**
- `:prospect` - Potential customer
- `:customer` - Paying customer
- `:partner` - Business partner
- `:vendor` - Supplier (cross-ref to Engineering.Vendor)

**Status Values:**
- `:active` - Current relationship
- `:inactive` - Dormant
- `:churned` - Former customer

**Relationships:**
- `has_many :contacts, Sales.Contact`
- `has_many :opportunities, Sales.Opportunity`
- `has_many :contracts, Sales.Contract`
- `has_many :projects, Projects.Project`
- `has_many :plants, Engineering.Plant`
- `has_many :retainers, Finance.Retainer`

### Contact
People at companies.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| first_name | string | yes | First name |
| last_name | string | yes | Last name |
| email | ci_string | no | Email address |
| phone | string | no | Direct phone |
| mobile | string | no | Mobile phone |
| title | string | no | Job title |
| department | string | no | Department |
| role | atom | no | Decision role |
| is_primary | boolean | no | Primary contact |
| company_id | uuid | yes | Parent company |

**Role Values:**
- `:decision_maker` - Budget authority
- `:influencer` - Influences decisions
- `:champion` - Internal advocate
- `:technical` - Technical evaluator
- `:user` - End user

### Industry
Industry classification.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Industry name |
| code | string | no | NAICS code |

**Target Industries (from target-customers.md):**
```
Food & Beverage  | High priority
Biotech          | High priority
Water/Wastewater | Medium (needs PE)
Packaging        | High priority
Warehousing      | High priority
```

### Activity
Interactions and touchpoints.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| activity_type | atom | yes | Activity type |
| subject | string | yes | Summary |
| description | string | no | Details |
| occurred_at | utc_datetime | yes | When |
| duration_minutes | integer | no | Length |
| company_id | uuid | no | Related company |
| contact_id | uuid | no | Related contact |
| opportunity_id | uuid | no | Related opportunity |
| user_id | uuid | yes | Performed by |

**Activity Type Values:**
- `:call` - Phone call
- `:email` - Email
- `:meeting` - Meeting
- `:site_visit` - On-site visit
- `:demo` - Product demo

### Note
Freeform notes on any record.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| content | string | yes | Note text |
| pinned | boolean | no | Pinned to top |
| notable_type | string | yes | Parent type |
| notable_id | uuid | yes | Parent ID |
| user_id | uuid | yes | Author |

---

## Pipeline

### Opportunity
Sales pipeline items.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Opportunity name |
| description | string | no | Details |
| stage | atom | yes | Pipeline stage |
| probability | integer | calc | Win probability % |
| amount | decimal | no | Expected value |
| close_date | date | no | Expected close |
| source | atom | no | Lead source |
| lost_reason | string | no | Why lost |
| company_id | uuid | yes | Account |
| contact_id | uuid | no | Primary contact |
| owner_id | uuid | yes | Sales rep (Member) |
| bid_id | uuid | no | Source bid (from Agents) |

**Stage Values (with probability):**
- `:qualification` - 10% - Initial discovery
- `:discovery` - 25% - Needs analysis
- `:proposal` - 50% - Proposal sent
- `:negotiation` - 75% - Terms discussion
- `:won` - 100% - Deal won
- `:lost` - 0% - Deal lost

**Source Values:**
- `:bid` - From Agents bid scanning
- `:referral` - Customer referral
- `:website` - Website inquiry
- `:outbound` - Cold outreach
- `:existing` - Existing customer

### Proposal
Formal quotes.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| number | string | yes | Proposal number (auto) |
| name | string | yes | Proposal title |
| status | atom | yes | Proposal status |
| valid_until | date | yes | Expiration date |
| subtotal | decimal | calc | Before tax |
| tax_rate | decimal | no | Tax percentage |
| total | decimal | calc | Final total |
| terms | string | no | Terms & conditions |
| notes | string | no | Internal notes |
| opportunity_id | uuid | yes | Parent opportunity |
| company_id | uuid | yes | Customer |
| created_by_id | uuid | yes | Author |

**Status Values:**
- `:draft` - Being prepared
- `:sent` - Delivered
- `:accepted` - Customer accepted
- `:rejected` - Customer declined
- `:expired` - Past valid date

### ProposalLine
Line items on proposals.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| position | integer | yes | Sort order |
| line_type | atom | yes | Type of line |
| description | string | yes | Description |
| quantity | decimal | yes | Quantity |
| unit | string | no | Unit |
| unit_price | decimal | yes | Price per unit |
| line_total | decimal | calc | Extended |
| proposal_id | uuid | yes | Parent proposal |
| service_id | uuid | no | Service reference |
| part_id | uuid | no | Part reference |

**Line Type Values:**
- `:labor` - Labor/services
- `:materials` - Parts/materials
- `:expense` - Travel/expenses
- `:discount` - Discount line

### Contract
Signed agreements.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| number | string | yes | Contract number |
| name | string | yes | Contract title |
| contract_type | atom | yes | Contract type |
| status | atom | yes | Contract status |
| start_date | date | yes | Effective date |
| end_date | date | no | Expiration date |
| value | decimal | yes | Total value |
| signed_at | utc_datetime | no | Signature date |
| opportunity_id | uuid | no | Source opportunity |
| proposal_id | uuid | no | Source proposal |
| company_id | uuid | yes | Customer |

**Contract Type Values:**
- `:project` - One-time project
- `:retainer` - Support retainer
- `:maintenance` - Maintenance agreement

**Status Values:**
- `:draft` - Being prepared
- `:sent` - Awaiting signature
- `:active` - In effect
- `:completed` - Fulfilled
- `:cancelled` - Terminated

### Service
Service catalog items (for proposals).

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Service name |
| description | string | no | Details |
| category | atom | yes | Category |
| billing_type | atom | yes | How billed |
| default_rate | decimal | yes | Standard rate |
| unit | string | yes | Unit (hour, day, etc.) |
| active | boolean | yes | Available |

**Category Values (from services.md):**
- `:programming` - PLC/HMI programming
- `:scada` - SCADA development
- `:integration` - System integration
- `:commissioning` - Startup/commissioning
- `:support` - Remote support
- `:consulting` - Consulting/PM

**Billing Type Values:**
- `:hourly` - Per hour
- `:daily` - Per day
- `:fixed` - Fixed price
- `:monthly` - Monthly retainer

---

## Pipeline Flow

```
┌───────────────┐
│ Qualification │ 10%
└───────┬───────┘
        ↓
┌───────────────┐
│   Discovery   │ 25%
└───────┬───────┘
        ↓
┌───────────────┐
│   Proposal    │ 50%  ──→ Proposal created
└───────┬───────┘
        ↓
┌───────────────┐
│  Negotiation  │ 75%
└───────┬───────┘
        ↓
   ┌────┴────┐
   ↓         ↓
┌──────┐  ┌──────┐
│ Won  │  │ Lost │
└──────┘  └──────┘
   ↓
Contract + Project
```

---

## Key Metrics

| Metric | Description |
|--------|-------------|
| Pipeline Value | Sum of open opportunity.amount × probability |
| Win Rate | Won / (Won + Lost) |
| Avg Deal Size | Total won value / Won count |
| Sales Cycle | Avg days from qualification to won |

---

## UI Routes

| Route | Description |
|-------|-------------|
| `/companies` | Company list |
| `/companies/:id` | Company detail |
| `/contacts` | Contact list |
| `/opportunities` | Pipeline board |
| `/opportunities/:id` | Opportunity detail |
| `/proposals` | Proposal list |
| `/proposals/:id` | Proposal detail |
| `/contracts` | Contract list |
| `/services` | Service catalog |

---

## File Structure

```
lib/gnome_hub/
├── sales.ex
└── sales/
    ├── company.ex
    ├── contact.ex
    ├── industry.ex
    ├── activity.ex
    ├── note.ex
    ├── opportunity.ex
    ├── proposal.ex
    ├── proposal_line.ex
    ├── contract.ex
    └── service.ex
```
