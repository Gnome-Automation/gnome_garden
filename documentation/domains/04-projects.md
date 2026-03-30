# Projects Domain

**CSIA Area:** Project Management + Project Delivery
**Module:** `GnomeGarden.Projects`
**Purpose:** Project execution, task management, time tracking, expenses

---

## Overview

The Projects domain manages project delivery from contract through completion. It handles project structure, task management, time tracking, expenses, and resource assignments.

---

## Resources

### Project
Work containers linked to contracts.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| number | string | yes | Project number (auto) |
| name | string | yes | Project name |
| description | string | no | Scope description |
| status | atom | yes | Project status |
| priority | atom | yes | Priority level |
| project_type | atom | yes | Type of work |
| start_date | date | no | Planned start |
| end_date | date | no | Planned end |
| budget_hours | decimal | no | Budgeted hours |
| budget_amount | decimal | no | Budgeted cost |
| company_id | uuid | yes | Customer |
| contract_id | uuid | no | Source contract |
| manager_id | uuid | yes | Project manager (Member) |

**Status Values:**
- `:planning` - Being scoped
- `:approved` - Ready to start
- `:active` - In progress
- `:on_hold` - Paused
- `:completed` - Finished
- `:cancelled` - Terminated

**Project Type Values:**
- `:programming` - Remote programming
- `:integration` - System integration
- `:commissioning` - On-site startup
- `:support` - Support/retainer work
- `:internal` - Internal project

**Relationships:**
- `belongs_to :company, Sales.Company`
- `belongs_to :contract, Sales.Contract`
- `belongs_to :manager, HR.Member`
- `has_many :phases, Projects.Phase`
- `has_many :tasks, Projects.Task`
- `has_many :time_entries, Projects.TimeEntry`
- `has_many :expenses, Projects.Expense`
- `has_many :assignments, Projects.Assignment`

### Phase
Project milestones/phases.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Phase name |
| description | string | no | Phase scope |
| position | integer | yes | Sort order |
| status | atom | yes | Phase status |
| start_date | date | no | Planned start |
| end_date | date | no | Planned end |
| project_id | uuid | yes | Parent project |

**Status Values:**
- `:not_started` - Waiting
- `:active` - In progress
- `:completed` - Done
- `:skipped` - Bypassed

### Task
Actionable work items.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| title | string | yes | Task title |
| description | string | no | Task details |
| status | atom | yes | Task status |
| priority | atom | yes | Priority |
| task_type | atom | yes | Type of work |
| estimated_hours | decimal | no | Estimate |
| due_date | date | no | Due date |
| project_id | uuid | yes | Parent project |
| phase_id | uuid | no | Parent phase |
| assignee_id | uuid | no | Assigned member |
| parent_id | uuid | no | Parent task |

**Status Values:**
- `:backlog` - Not scheduled
- `:todo` - Ready to start
- `:in_progress` - Being worked
- `:review` - Needs review
- `:done` - Completed

**Task Type Values:**
- `:design` - Design/engineering
- `:programming` - PLC/HMI code
- `:testing` - FAT/SAT
- `:documentation` - Docs
- `:meeting` - Meetings
- `:admin` - Administrative

### TimeEntry
Billable time records.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| date | date | yes | Work date |
| hours | decimal | yes | Hours worked |
| description | string | yes | Work description |
| billable | boolean | yes | Is billable |
| billed | boolean | no | Has been invoiced |
| rate | decimal | no | Override rate |
| project_id | uuid | yes | Project |
| task_id | uuid | no | Task |
| member_id | uuid | yes | Who worked |
| invoice_line_id | uuid | no | Billed on |

### Expense
Reimbursable costs.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| description | string | yes | Expense description |
| category | atom | yes | Expense category |
| amount | decimal | yes | Amount |
| expense_date | date | yes | Date incurred |
| billable | boolean | yes | Charge to customer |
| receipt_url | string | no | Receipt image |
| vendor | string | no | Vendor name |
| project_id | uuid | yes | Project |
| member_id | uuid | yes | Who incurred |

**Category Values:**
- `:travel` - Travel
- `:lodging` - Hotels
- `:meals` - Meals
- `:materials` - Job materials
- `:equipment` - Equipment rental
- `:software` - Software/licenses

### Assignment
Resource allocation to projects.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| start_date | date | yes | Assignment start |
| end_date | date | no | Assignment end |
| hours_per_week | decimal | yes | Allocated hours |
| role | string | no | Role on project |
| project_id | uuid | yes | Project |
| member_id | uuid | yes | Team member |

---

## Task Board (Kanban)

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ Backlog  │ → │   Todo   │ → │ Progress │ → │  Review  │ → │   Done   │
├──────────┤   ├──────────┤   ├──────────┤   ├──────────┤   ├──────────┤
│ Task A   │   │ Task D   │   │ Task F   │   │ Task H   │   │ Task J   │
│ Task B   │   │ Task E   │   │ Task G   │   │          │   │ Task K   │
│ Task C   │   │          │   │          │   │          │   │          │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
```

---

## Project Metrics

| Metric | Formula |
|--------|---------|
| Budget Burn | actual_hours / budget_hours |
| Schedule Variance | actual_end - planned_end |
| Billable Ratio | billable_hours / total_hours |
| Margin | (revenue - cost) / revenue |

---

## UI Routes

| Route | Description |
|-------|-------------|
| `/projects` | Project list |
| `/projects/:id` | Project detail |
| `/projects/:id/board` | Kanban view |
| `/tasks` | All tasks |
| `/time` | Timesheet |
| `/time/week` | Weekly timesheet |
| `/expenses` | Expense tracker |

---

## File Structure

```
lib/gnome_garden/
├── projects.ex
└── projects/
    ├── project.ex
    ├── phase.ex
    ├── task.ex
    ├── time_entry.ex
    ├── expense.ex
    └── assignment.ex
```
