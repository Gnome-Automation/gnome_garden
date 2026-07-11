# Acquisition Baseline

The acquisition baseline is a read-only Ash action that measures the current
maturity, yield, spend, and failure state of procurement and commercial
discovery.

Run it with:

```bash
mix acquisition.baseline
```

The command prints versioned JSON and performs all reads through
`GnomeGarden.Acquisition` code interfaces. It does not use `Repo`, issue
provider requests, launch workers, or change persisted state.

## Maturity Interpretation

The baseline deliberately distinguishes the two implemented execution paths:

- Procurement routes persisted sources to live API or browser-backed scanners.
- Scheduled commercial discovery uses the preview-safe Exa candidate path. It
  persists lead-preview runs and candidates without creating findings or
  downstream commercial records. Production scheduling remains disabled until
  shared budget controls and durable Oban execution are implemented.

`GnomeGarden.Commercial.DiscoveryPipeline.execution_profile/0` is the runtime
descriptor behind this distinction.

## Failure Categories

Detailed provider diagnoses remain in source metadata. The baseline also maps
them into stable categories through
`GnomeGarden.Acquisition.FailureTaxonomy`:

- `api`
- `http`
- `selectors`
- `credentials`
- `browser_runtime`
- `extraction`
- `scoring`
- `dedupe`
- `promotion`
- `unknown`

These categories are the shared vocabulary for later telemetry, budgeting,
source routing, and operational alerts. Unknown diagnoses remain visible rather
than being guessed into a more specific category.
