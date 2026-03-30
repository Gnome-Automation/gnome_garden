# Service Domain

**CSIA Area:** Customer Service
**Module:** `GnomeGarden.Service`
**Purpose:** Support tickets, work orders, SLAs

---

## Overview

The Service domain handles post-sale customer support: tickets for remote issues, work orders for on-site dispatches, and SLA tracking. Critical for retainer customers and recurring revenue.

---

## Resources

### Ticket
Support requests from customers.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| number | string | yes | Ticket number (auto) |
| subject | string | yes | Issue summary |
| description | string | yes | Issue details |
| status | atom | yes | Ticket status |
| priority | atom | yes | Priority level |
| category | atom | yes | Issue category |
| channel | atom | yes | How submitted |
| first_response_at | utc_datetime | no | First reply time |
| resolved_at | utc_datetime | no | Resolution time |
| company_id | uuid | yes | Customer |
| contact_id | uuid | no | Submitting contact |
| assignee_id | uuid | no | Assigned member |
| asset_id | uuid | no | Related asset |
| retainer_id | uuid | no | Related retainer |
| sla_id | uuid | no | Applicable SLA |

**Status Values:**
- `:new` - Just submitted
- `:open` - Awaiting assignment
- `:in_progress` - Being worked
- `:waiting_customer` - Need info from customer
- `:resolved` - Issue fixed
- `:closed` - Ticket complete

**Priority Values (from retainer-guide.md):**
- `:critical` - Production down, 1hr response
- `:high` - Major impact, 4hr response
- `:normal` - Standard issue, same-day
- `:low` - Minor issue, next business day

**Category Values:**
- `:hardware` - Equipment issues
- `:software` - PLC/HMI/SCADA
- `:connectivity` - Network/comms
- `:programming` - Logic issues
- `:training` - How-to questions

**Channel Values:**
- `:email` - Email
- `:phone` - Phone call
- `:portal` - Web portal
- `:internal` - Staff created

### TicketComment
Responses and updates on tickets.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| content | string | yes | Comment text |
| is_internal | boolean | yes | Internal note |
| is_resolution | boolean | no | Resolution note |
| author_type | atom | yes | Who commented |
| ticket_id | uuid | yes | Parent ticket |
| author_id | uuid | yes | Comment author |

**Author Type Values:**
- `:staff` - Our team
- `:customer` - Customer
- `:system` - Automated

### WorkOrder
Field service / on-site dispatch requests.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| number | string | yes | WO number (auto) |
| title | string | yes | Work summary |
| description | string | no | Work details |
| status | atom | yes | WO status |
| priority | atom | yes | Priority |
| work_type | atom | yes | Type of work |
| scheduled_date | date | no | Planned date |
| scheduled_time | time | no | Planned time |
| completed_at | utc_datetime | no | Completion time |
| resolution | string | no | Resolution notes |
| company_id | uuid | yes | Customer |
| plant_id | uuid | no | Site location |
| asset_id | uuid | no | Related asset |
| ticket_id | uuid | no | Source ticket |
| assignee_id | uuid | no | Assigned member |

**Status Values:**
- `:draft` - Being created
- `:scheduled` - Date set
- `:dispatched` - Tech assigned
- `:in_progress` - On-site
- `:completed` - Work done
- `:cancelled` - Cancelled

**Work Type Values:**
- `:troubleshooting` - Diagnose issue
- `:repair` - Fix equipment
- `:maintenance` - Preventive maintenance
- `:upgrade` - Upgrade/modification
- `:commissioning` - Startup

### SLA
Service level agreements.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | SLA name |
| description | string | no | SLA details |
| priority | atom | yes | Applied to priority |
| first_response_hours | integer | yes | Target first response |
| resolution_hours | integer | yes | Target resolution |
| business_hours_only | boolean | yes | Exclude nights/weekends |
| company_id | uuid | no | Company-specific SLA |

**Default SLAs (from retainer-guide.md):**

| Priority | First Response | Resolution |
|----------|---------------|------------|
| Critical | 1 hour | 4 hours |
| High | 4 hours | 8 hours |
| Normal | 8 hours | 24 hours |
| Low | 24 hours | 72 hours |

---

## Support Flow

```
Customer reports issue
         ↓
    ┌────┴────┐
    ↓         ↓
  Email     Phone
    ↓         ↓
    └────┬────┘
         ↓
   Ticket created
         ↓
   Check SLA (if retainer)
         ↓
   Assign to member
         ↓
   ┌─────┴─────┐
   ↓           ↓
Remote?    On-site?
   ↓           ↓
Resolve    Create WorkOrder
   ↓           ↓
   ↓        Dispatch
   ↓           ↓
   ↓        Resolve
   ↓           ↓
   └─────┬─────┘
         ↓
   Close ticket
         ↓
   Bill time (if billable)
```

---

## SLA Tracking

```
Ticket Created → SLA clock starts
        ↓
First Response Timer
        ↓
    Response given
        ↓
Resolution Timer
        ↓
   Ticket resolved
        ↓
SLA Report: Met / Breached
```

**Metrics:**
- First Response Time
- Resolution Time
- SLA Compliance %
- Tickets by Priority
- Tickets by Category

---

## Retainer Integration

Tickets from retainer customers:
1. Link to Retainer record
2. Time tracked against retainer hours
3. Overage auto-calculated
4. Prioritized by retainer tier

---

## UI Routes

| Route | Description |
|-------|-------------|
| `/tickets` | Ticket queue |
| `/tickets/:id` | Ticket detail |
| `/tickets/new` | Create ticket |
| `/work-orders` | Work order list |
| `/work-orders/:id` | WO detail |
| `/slas` | SLA management |
| `/reports/service` | Service reports |

---

## File Structure

```
lib/gnome_garden/
├── service.ex
└── service/
    ├── ticket.ex
    ├── ticket_comment.ex
    ├── work_order.ex
    └── sla.ex
```
