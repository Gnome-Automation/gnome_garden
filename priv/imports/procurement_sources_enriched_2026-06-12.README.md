# Procurement sources enriched import — 2026-06-12

Enriched procurement/vendor-registration research for priority government, city, and water/wastewater sources.

## Files

- `procurement_sources_enriched_2026-06-12.csv`

Duplicate copy is stored in `gnome-company/03-operations/imports/` for business research/versioning.

## Scope

16 priority procurement sources:

- OC San
- Orange County Water District
- IRWD
- County of Orange / OC Public Works
- City of Irvine
- City of Anaheim
- City of Santa Ana
- Santa Margarita Water District
- EMWD
- IEUA
- LADWP
- Metropolitan Water District of Southern California
- County of San Diego
- City of San Diego
- Cal eProcure / California DGS
- SAM.gov

## Columns added beyond the normalized source inventory

- vendor registration URL
- registration requirement
- procurement contact name/email/phone
- technical support contact
- local/small-business preference notes
- recommended categories/codes for PLC/SCADA/controls/instrumentation fit
- automation fit score
- scan priority reason
- next setup action
- research confidence
- source URLs

## Notes

- No credential values are included.
- IEUA has medium confidence because the official page confirmed PlanetBids usage but did not expose a direct procurement contact in the search results.
- Some portals have changed over time. OC San and EMWD had conflicting older/staged references; the CSV favors the current official page discovered during this research pass and calls out the mismatch in notes.
