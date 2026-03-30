# Plan: Sales CRM Domain

**Feature:** Build CRM resources for the Sales domain
**Complexity:** Medium (5 resources, 8+ relationships)
**Created:** 2026-03-28

## Overview

Implement the CRM portion of the Sales domain with Company, Contact, Industry, Activity, and Note resources following existing Agents domain patterns.

## Tasks

### Phase 1: Domain & Core Resources

- [ ] **P1-T1: Create Sales domain module**
  - File: `lib/gnome_garden/sales.ex`
  - Pattern: Follow `GnomeGarden.Agents` structure
  - Include AshAdmin.Domain extension

- [ ] **P1-T2: Create Industry resource**
  - File: `lib/gnome_garden/sales/industry.ex`
  - Attributes: name, code (NAICS)
  - Simple lookup table, no relationships yet
  - Seed with target industries from docs

- [ ] **P1-T3: Create Company resource**
  - File: `lib/gnome_garden/sales/company.ex`
  - Attributes per docs: name, legal_name, company_type, status, website, phone, address, city, state, postal_code
  - Relationships: belongs_to Industry
  - company_type: :prospect, :customer, :partner, :vendor
  - status: :active, :inactive, :churned

- [ ] **P1-T4: Create Contact resource**
  - File: `lib/gnome_garden/sales/contact.ex`
  - Attributes: first_name, last_name, email (ci_string), phone, mobile, title, department, role, is_primary
  - Relationships: belongs_to Company
  - role: :decision_maker, :influencer, :champion, :technical, :user

### Phase 2: Activity & Notes

- [ ] **P2-T1: Create Activity resource**
  - File: `lib/gnome_garden/sales/activity.ex`
  - Attributes: activity_type, subject, description, occurred_at, duration_minutes
  - Relationships: belongs_to Company (optional), belongs_to Contact (optional)
  - activity_type: :call, :email, :meeting, :site_visit, :demo
  - Note: user_id deferred until Management domain exists

- [ ] **P2-T2: Create Note resource (polymorphic)**
  - File: `lib/gnome_garden/sales/note.ex`
  - Attributes: content, pinned, notable_type, notable_id
  - Polymorphic pattern: notable_type + notable_id
  - user_id deferred until Management domain exists

### Phase 3: Migrations & Verification

- [ ] **P3-T1: Generate migrations**
  - Run `mix ash.codegen create_sales_domain`
  - Review generated SQL
  - Run `mix ash.migrate`

- [ ] **P3-T2: Verify compilation**
  - Run `mix compile --warnings-as-errors`
  - Fix any issues

- [ ] **P3-T3: Test resources in IEx**
  - Create Industry records
  - Create Company with industry
  - Create Contact for company
  - Create Activity and Note

## Dependencies

- No external dependencies required
- Uses existing AshPostgres, AshAdmin

## Deferred

- **owner_id / user_id fields**: Require Management.User which doesn't exist yet
- **Pipeline resources**: Opportunity, Proposal, Contract (separate plan)
- **Cross-domain relationships**: Projects.Project, Engineering.Plant, Finance.Retainer

## Iron Laws Checklist

- [ ] No `:float` for money (N/A - no money fields in CRM)
- [ ] Polymorphic Note uses string type + uuid, not atom
- [ ] All public attributes marked `public?: true`
- [ ] Use `ci_string` for email (case-insensitive)

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
