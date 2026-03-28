# Finance Domain

**CSIA Area:** Financial Management
**Module:** `GnomeHub.Finance`
**Purpose:** Invoicing, payments, retainers, cash flow

---

## Overview

The Finance domain handles all monetary aspects: invoicing customers, tracking payments, managing retainer agreements, and providing financial visibility. Key focus on recurring revenue through retainers.

---

## Resources

### Invoice
Bills to customers.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| number | string | yes | Invoice number (auto-generated) |
| status | atom | yes | Invoice status |
| issue_date | date | yes | Invoice date |
| due_date | date | yes | Payment due |
| subtotal | decimal | calc | Sum of lines |
| tax_rate | decimal | no | Tax percentage |
| tax_amount | decimal | calc | Tax amount |
| total | decimal | calc | Final total |
| amount_paid | decimal | calc | Payments received |
| balance_due | decimal | calc | Remaining balance |
| terms | string | no | Payment terms |
| notes | string | no | Invoice notes |
| company_id | uuid | yes | Customer |
| project_id | uuid | no | Related project |
| retainer_id | uuid | no | Related retainer |
| created_by_id | uuid | yes | Author |

**Status Values:**
- `:draft` - Being prepared
- `:sent` - Delivered to customer
- `:partial` - Partially paid
- `:paid` - Fully paid
- `:overdue` - Past due date
- `:void` - Cancelled

**Relationships:**
- `belongs_to :company, Sales.Company`
- `belongs_to :project, Projects.Project`
- `belongs_to :retainer, Finance.Retainer`
- `has_many :lines, Finance.InvoiceLine`
- `has_many :payments, Finance.Payment`

### InvoiceLine
Line items on invoices.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| position | integer | yes | Sort order |
| description | string | yes | Line description |
| quantity | decimal | yes | Quantity |
| unit | string | no | Unit of measure |
| unit_price | decimal | yes | Price per unit |
| line_total | decimal | calc | Extended amount |
| line_type | atom | yes | Type of charge |
| invoice_id | uuid | yes | Parent invoice |

**Line Type Values:**
- `:labor` - Time/labor charges
- `:materials` - Parts/materials
- `:expense` - Reimbursable expenses
- `:retainer` - Retainer fee
- `:discount` - Discount line

### Payment
Received payments.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| amount | decimal | yes | Payment amount |
| payment_date | date | yes | Date received |
| method | atom | yes | Payment method |
| reference | string | no | Check/trans number |
| notes | string | no | Payment notes |
| invoice_id | uuid | yes | Applied to invoice |
| received_by_id | uuid | yes | Who recorded |

**Method Values:**
- `:check` - Check payment
- `:ach` - Bank transfer
- `:wire` - Wire transfer
- `:credit_card` - Card payment

### Retainer
Recurring service agreements (key for recurring revenue).

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Retainer name |
| tier | atom | yes | Service tier |
| status | atom | yes | Retainer status |
| amount | decimal | yes | Monthly fee |
| hours_included | decimal | yes | Hours per month |
| overage_rate | decimal | yes | Rate for extra hours |
| start_date | date | yes | Start date |
| end_date | date | no | End date (if term) |
| next_invoice_date | date | yes | Next billing date |
| company_id | uuid | yes | Customer |
| contract_id | uuid | no | Source contract |

**Tier Values (from retainer-guide.md):**
- `:light` - $2-3K/mo, 10 hrs, next-day response
- `:standard` - $3.5-5K/mo, 20 hrs, same-day response
- `:custom` - Custom terms

**Status Values:**
- `:active` - Currently billing
- `:paused` - Temporarily stopped
- `:cancelled` - Terminated
- `:expired` - Past end date

---

## Billing Flows

### Time & Materials Invoice
```
TimeEntry (Projects)
       ↓
    aggregate by project
       ↓
Invoice (draft)
       ↓
    add lines
       ↓
Invoice (sent)
       ↓
Payment (received)
       ↓
Invoice (paid)
```

### Retainer Billing
```
Retainer (active)
       ↓
    next_invoice_date reached
       ↓
Auto-create Invoice
       ↓
    track hours used
       ↓
Hours exceeded?
    ├── No → wait for next month
    └── Yes → Overage Invoice
```

---

## Key Metrics

| Metric | Formula |
|--------|---------|
| MRR | Sum of active retainer.amount |
| AR Aging | Invoices by days outstanding |
| DSO | Avg days to payment |
| Collection Rate | Payments / Invoices |

---

## UI Routes

| Route | Description |
|-------|-------------|
| `/invoices` | Invoice list |
| `/invoices/:id` | Invoice detail |
| `/invoices/new` | Create invoice |
| `/payments` | Payment history |
| `/retainers` | Retainer management |
| `/reports/financial` | Financial reports |

---

## File Structure

```
lib/gnome_hub/
├── finance.ex
└── finance/
    ├── invoice.ex
    ├── invoice_line.ex
    ├── payment.ex
    └── retainer.ex
```
