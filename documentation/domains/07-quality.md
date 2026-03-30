# Quality Domain

**CSIA Area:** Quality Assurance Management
**Module:** `GnomeGarden.Quality`
**Purpose:** Checklists, inspections, non-conformance tracking

**Status:** 📋 Phase 2 — Not implemented in initial release

---

## Overview

The Quality domain will handle quality assurance processes: reusable checklists, inspection records, and non-conformance reports. This aligns with CSIA's Quality Assurance Management area and supports FAT/SAT processes.

---

## Resources (Planned)

### Checklist
Reusable check templates.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Checklist name |
| description | string | no | Purpose |
| checklist_type | atom | yes | Type |
| items | array | yes | Check items (embedded) |
| active | boolean | yes | Available for use |
| created_by_id | uuid | yes | Author |

**Checklist Type Values:**
- `:fat` - Factory Acceptance Test
- `:sat` - Site Acceptance Test
- `:commissioning` - Commissioning checklist
- `:maintenance` - PM checklist
- `:safety` - Safety inspection

**ChecklistItem (embedded):**
```
- position: integer
- description: string
- required: boolean
- response_type: atom (:pass_fail, :yes_no, :text, :number)
```

### Inspection
Completed inspections.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| status | atom | yes | Inspection status |
| started_at | utc_datetime | yes | Start time |
| completed_at | utc_datetime | no | Completion time |
| results | array | yes | Item results |
| notes | string | no | General notes |
| checklist_id | uuid | yes | Source checklist |
| project_id | uuid | no | Related project |
| asset_id | uuid | no | Inspected asset |
| inspector_id | uuid | yes | Who inspected |

**Status Values:**
- `:in_progress` - Being completed
- `:passed` - All items passed
- `:failed` - One or more failures
- `:cancelled` - Cancelled

### NCR (Non-Conformance Report)
Issue tracking for quality failures.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| number | string | yes | NCR number |
| title | string | yes | Issue title |
| description | string | yes | Issue details |
| severity | atom | yes | Severity level |
| status | atom | yes | NCR status |
| root_cause | string | no | Root cause analysis |
| corrective_action | string | no | Corrective action |
| inspection_id | uuid | no | Source inspection |
| project_id | uuid | no | Related project |
| reported_by_id | uuid | yes | Who reported |
| assigned_to_id | uuid | no | Assignee |

**Severity Values:**
- `:critical` - Safety/major impact
- `:major` - Significant issue
- `:minor` - Minor issue
- `:observation` - Note for improvement

**Status Values:**
- `:open` - Reported
- `:investigating` - Under investigation
- `:action_required` - Needs correction
- `:resolved` - Fixed
- `:closed` - Verified and closed

---

## Workflows

### FAT Process
```
Create FAT Checklist
       ↓
Schedule FAT (Project Task)
       ↓
Perform Inspection
       ↓
    ┌──┴──┐
    ↓     ↓
 Passed  Failed
    ↓     ↓
    ↓   Create NCR
    ↓     ↓
    ↓   Fix Issues
    ↓     ↓
    ↓   Re-inspect
    ↓     ↓
    └──►──┘
       ↓
FAT Complete → Proceed to SAT
```

---

## Integration Points

| Domain | Integration |
|--------|-------------|
| Projects | Inspections linked to project tasks |
| Engineering | Inspections linked to assets |
| Service | NCRs can generate tickets |

---

## UI Routes (Planned)

| Route | Description |
|-------|-------------|
| `/checklists` | Checklist templates |
| `/inspections` | Inspection list |
| `/inspections/:id` | Inspection detail |
| `/ncrs` | NCR list |
| `/ncrs/:id` | NCR detail |

---

## File Structure (Planned)

```
lib/gnome_garden/
├── quality.ex
└── quality/
    ├── checklist.ex
    ├── inspection.ex
    └── ncr.ex
```

---

## Implementation Notes

This domain is deferred to Phase 2 because:
1. Core business operations (Sales, Projects, Finance) take priority
2. Quality processes can be manual initially (spreadsheets)
3. FAT/SAT becomes more important as project volume grows

Consider implementing when:
- Doing formal FATs for customers
- Need audit trail for commissioning
- Customer requires documented QA process
