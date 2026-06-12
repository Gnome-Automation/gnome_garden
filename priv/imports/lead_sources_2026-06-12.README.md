# Lead source imports — 2026-06-12

Source: `gnome-company/03-operations/lead-sources.md`

Generated CSVs:

- `lead_sources_normalized_2026-06-12.csv` — complete normalized inventory of all 127 lead sources/channels from the markdown table. Includes gov portals, directories, job boards, partner programs, associations, forums, news, tools, and events.
- `procurement_sources_import_2026-06-12.csv` — filtered subset of 87 sources that map cleanly to `GnomeGarden.Procurement.ProcurementSource` fields (`source_type`, `region`, `priority`, `api_available`, `requires_login`, etc.). This is the best starting file for database import.
- `google_alert_queries_2026-06-12.csv` — 7 saved search/alert queries from the same source doc.

## Recommended import path

1. Import `procurement_sources_import_2026-06-12.csv` into `GnomeGarden.Procurement.ProcurementSource`.
2. Keep `lead_sources_normalized_2026-06-12.csv` as the master planning inventory for channels that are not yet first-class database resources.
3. Use `google_alert_queries_2026-06-12.csv` either as manual setup checklist data or future saved-search resources.

## Notes

- Login/password cells from the source table were not copied as secrets. The CSV only has `login_status` / `password_status` markers.
- `config_status_hint` is advisory. Actual state transitions should use Ash actions (`queue`, `configure`, `set_manual`, etc.) during import.
- Some source types are mapped to `custom` because `ProcurementSource.source_type` intentionally has a limited enum.
