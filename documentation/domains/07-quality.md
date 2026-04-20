# Quality Domain

**Status:** Not implemented as a standalone Ash domain

This file remains in place because the older documentation model reserved a separate quality area. That is not how the current platform is implemented.

## Current Reality

There is no `GnomeGarden.Quality` domain in the active Ash domain list.

Quality-adjacent concerns currently live inside other domains:
- `AshStateMachine`-driven lifecycle gates on commercial, execution, and finance records
- service and maintenance workflows in `Execution`
- agreement/service policy expectations in `Commercial`
- operator review queues in the cockpit

## Likely Future Direction

If a standalone quality domain is added later, it would likely include:
- inspections
- commissioning/FAT/SAT artifacts
- reusable checklists
- NCR or exception tracking

But those are roadmap concerns, not current implementation.

## Guidance

Do not model a separate quality layer in new code unless the corresponding Ash resources are added to:
- `config/config.exs`
- `docs/llm/generated/resources.json`
