# Vendor outreach target import — 2026-06-12

CSV: `vendor_outreach_targets_2026-06-12.csv`

This file combines:

- Prior prospect research from `gnome-company/03-operations/prospects.md`
- Targeting criteria from `gnome-company/03-operations/target-customers.md`
- Current public web/Exa research from 2026-06-12 for Orange County, San Diego, and Southern California private-company vendor-list entry points

## Suggested GnomeGarden mapping

One CSV row represents one outreach entry point. Multiple rows may share the same organization when there are multiple contact paths.

- `organization_*`, `website`, `phone`, `address`, `city`, `county`, `state`, `primary_region`, `industry`, `vertical`, `company_size`, `trigger_signal`, `pain_signal` -> `GnomeGarden.Operations.Organization` plus notes/metadata
- `contact_first_name`, `contact_last_name`, `contact_email`, `contact_phone`, `contact_linkedin_url` -> `GnomeGarden.Operations.Person` when a named contact exists
- `affiliation_title`, `department`, `contact_roles`, `is_primary_contact` -> `GnomeGarden.Operations.OrganizationAffiliation`
- `signal_*`, `source_channel`, `source_url`, `source_confidence`, `source_mix` -> `GnomeGarden.Commercial.Signal`
- `pursuit_type`, `delivery_model`, `billing_model`, `target_value_band`, `probability`, `fit_tier`, `fit_score`, `priority_rank` -> `GnomeGarden.Commercial.Pursuit` or pursuit metadata
- `outreach_angle`, `vendor_onboarding_ask`, `next_action`, `status_notes` -> pursuit notes/tasks/follow-up queue

## Priority guidance

Start with rows where `fit_tier=HOT`, ordered by `priority_rank`:

1. Harbinger Motors
2. Robinson Pharma
3. Tomorrow Water
4. B. Braun Medical
5. Masimo
6. Applied Medical
7. Balt USA
8. IMI Process Automation
9. Intellian Technologies USA
10. PCI Pharma Services

Rows with named contacts from third-party/public profiles should be verified before outreach; see `source_confidence`.
