# Roadmap Boundary

The files under `documentation/architecture/` and `documentation/domains/` are useful background, but they are not the implemented source of truth.

They may describe:
- planned domains
- planned resources
- target-state relationships
- workflows that do not yet exist in the live Ash DSL

For implemented structure, always prefer:
- `docs/llm/generated/resources.json`
- `config/config.exs`
- `lib/garden/**/*.ex`

If a concept appears in roadmap docs but not in the generated resource map, treat it as non-implemented until the matching Ash module exists.
