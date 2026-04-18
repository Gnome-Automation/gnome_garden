# LLM Architecture Index

This directory exists to give Codex a low-drift, implemented-only map of the application.

Authoritative for implemented model:
- `docs/llm/generated/resources.json`
- `config/config.exs` under `config :gnome_garden, :ash_domains`
- Ash domain and resource modules under `lib/garden/`

Not authoritative for implementation status:
- `documentation/architecture/*`
- `documentation/domains/*`

Those docs may include planned or aspirational resources. Do not treat a domain or resource as implemented unless it is present in `docs/llm/generated/resources.json`.

Refresh the machine map after changing any Ash domain or resource:

```bash
mix llm.generate_resource_map
```

Use the generated JSON first for lookup. Use the Ash modules as final truth when editing.
