# Lead source imports — 2026-06-12

Source: `gnome-company/03-operations/lead-sources.md`

Generated CSVs:

- `lead_sources_normalized_2026-06-12.csv` — complete normalized inventory of all 127 lead sources/channels from the markdown table. Includes gov portals, directories, job boards, partner programs, associations, forums, news, tools, and events.
- `google_alert_queries_2026-06-12.csv` — 7 saved search/alert queries from the same source doc.

## Recommended refinement path

1. Use `lead_sources_normalized_2026-06-12.csv` as planning context only.
2. Refine existing `GnomeGarden.Procurement.ProcurementSource` records directly through Ash actions, Tidewave, or the operator UI.
3. Use `google_alert_queries_2026-06-12.csv` either as manual setup checklist data or future saved-search resources.

## Notes

- Login/password cells from the source table were not copied as secrets. The CSV only has `login_status` / `password_status` markers.
- `config_status_hint` is advisory. Actual state transitions should use Ash actions (`queue`, `configure`, `set_manual`, etc.) during refinement.
- Some source types are mapped to `custom` because `ProcurementSource.source_type` intentionally has a limited enum.
