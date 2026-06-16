# GnomeGarden Pi Project Rules

This project is a Phoenix + Ash + Oban + AshLua application. Treat `AGENTS.md`
as authoritative project policy.

Before editing or reviewing Elixir, Phoenix, LiveView, Ash, migration, Oban,
Cinder, or AshStorage code:

1. Load `/skill:ash-framework` or read `.pi/skills/ash-framework/SKILL.md`.
2. Load `/skill:phoenix-framework` or read `.pi/skills/phoenix-framework/SKILL.md`
   when touching Phoenix, LiveView, HEEx, JS, CSS, routing, forms, or tests.
3. Read the relevant parts of `AGENTS.md`.
4. Check implemented architecture with `docs/llm/index.md`,
   `docs/llm/generated/resources.json`, and `config/config.exs` under
   `config :gnome_garden, :ash_domains`.
5. Search package docs before implementation with `mix usage_rules.search_docs`
   or `mix usage_rules.docs`.

Ash rules that must not be ignored:

- Start with Ash DSL capabilities before reaching for plain Elixir services,
  LiveView helper logic, raw Ecto, or manual Phoenix forms.
- Do not use `GnomeGarden.Repo` or raw Ecto for Ash resource behavior.
- Use `mix ash.codegen` and `mix ash.migrate` for Ash resource schema changes.
- Run `mix llm.generate_resource_map` after changing any Ash domain or resource.

Ash-first decision ladder for persisted business behavior:

1. Existing domain code interface.
2. Existing resource action, preparation, change, validation, policy,
   calculation, aggregate, relationship, identity, or action hook.
3. New intent-named Ash action exposed through the domain.
4. Domain-local Ash extension module under `changes/`, `preparations/`,
   `calculations/`, `validations/`, or `aggregates/`.
5. Embedded resources or `Ash.Type.Union` for structured, validated,
   resource-like, or variant data that belongs inside another resource instead
   of its own table.
6. AshPhoenix forms, including nested forms and union forms, for Ash-backed UI.
7. Plain Elixir service modules only for external orchestration, transport,
   protocol parsing, LLM/tool coordination, runtime process concerns, or cases
   where Ash's DSL is genuinely the wrong fit.

Default Ash modeling choices:

- Use `actions` for business intents, not generic helper functions.
- Use `preparations` and read action arguments for filtering, sorting,
  pagination, loading, and stable screen/query shapes.
- Use `changes` for create/update behavior, actor relationship management,
  defaults that depend on runtime, and side effects attached to actions.
- Use `validations` and `policies` for data integrity and authorization.
- Use `calculations` for derived display/domain values, including badge
  variants, lifecycle labels, totals, normalized fields, and presentation-facing
  values that belong to the resource.
- Use `aggregates` for counts, sums, existence checks, first/latest related
  values, and lists of related values.
- Use relationships and identities instead of manually managing foreign keys or
  uniqueness in callers.
- Use embedded resources or unions before unstructured maps when nested data has
  fields, validation, variants, or forms.
- Use `AshPhoenix.Form.for_create/for_update`, `AshPhoenix.Form.validate`, and
  `AshPhoenix.Form.submit` for Ash-backed forms. Render them with Phoenix
  `<.form>` and `<.input>`.
- Use `AshOban` triggers/scheduled actions for durable resource-driven jobs.
- Use domain-owned AshStorage document resources for files with business state.

Only fall back to plain Elixir service modules, web-layer shaping, raw Ecto, or
manual Phoenix form handling after briefly stating why the Ash-first option is
not appropriate for the specific case. If Phoenix's default generated AGENTS.md
guidance conflicts with Ash guidance, Ash guidance wins for persisted domain
behavior and Ash-backed forms.
