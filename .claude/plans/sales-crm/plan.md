# Plan: Sales CRM Domain

**Feature:** Build CRM resources for the Sales domain
**Complexity:** Medium (5 resources, 8+ relationships)
**Created:** 2026-03-28

## Overview

Implement the CRM portion of the Sales domain with Company, Contact, Industry, Activity, and Note resources following existing Agents domain patterns.

## Tasks

### Phase 1: Domain & Core Resources

- [x] **P1-T1: Create Sales domain module** — `lib/garden/sales.ex` with AshAdmin + AshPhoenix extensions
- [x] **P1-T2: Create Industry resource** — `lib/garden/sales/industry.ex` with name, code (NAICS), unique identity
- [x] **P1-T3: Create Company resource** — `lib/garden/sales/company.ex` with all attrs, belongs_to Industry, owner, primary_contact + extra resources (Address, CompanyRelationship, Employment)
- [x] **P1-T4: Create Contact resource** — `lib/garden/sales/contact.ex` with ci_string email, employment-based company relationship, aggregates for current_title/role

### Phase 2: Activity & Notes

- [x] **P2-T1: Create Activity resource** — `lib/garden/sales/activity.ex` with direction, outcome attrs, belongs_to owner (Accounts.User)
- [x] **P2-T2: Create Note resource (polymorphic)** — `lib/garden/sales/note.ex` with string notable_type + uuid notable_id, pin/unpin actions

### Phase 3: Migrations & Verification

- [x] **P3-T1: Generate migrations** — all migrations already existed and ran successfully on fresh DB
- [x] **P3-T2: Verify compilation** — compiles with warnings (pre-existing, not from this plan)
- [x] **P3-T3: Test resources in IEx** — DB connected, all 23 tables verified present

## Dependencies

- No external dependencies required
- Uses existing AshPostgres, AshAdmin

## Deferred

- **owner_id / user_id fields**: Require Management.User which doesn't exist yet
- **Pipeline resources**: Opportunity, Proposal, Contract (separate plan)
- **Cross-domain relationships**: Projects.Project, Engineering.Plant, Finance.Retainer

## Iron Laws Checklist

- [x] No `:float` for money — annual_revenue uses :decimal
- [x] Polymorphic Note uses string type + uuid, not atom
- [x] All public attributes marked `public?: true`
- [x] Use `ci_string` for email (case-insensitive)

## File Structure

```
lib/gnome_garden/
├── sales.ex                # Domain module
└── sales/
    ├── industry.ex         # Lookup table
    ├── company.ex          # Core CRM entity
    ├── contact.ex          # People at companies
    ├── activity.ex         # Interactions
    └── note.ex             # Polymorphic notes
```
