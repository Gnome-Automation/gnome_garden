---
name: phoenix-framework
description: Phoenix 1.8 and LiveView project rules for GnomeGarden. Use when editing Phoenix routing, LiveViews, HEEx templates, layouts, CoreComponents, JS hooks, Tailwind CSS, forms, or LiveView tests. Apply Phoenix generated AGENTS.md guidance, but defer to ash-framework for Ash-backed domain behavior, data access, migrations, and forms.
---

# Phoenix Framework Rules

Load this skill before touching Phoenix, LiveView, HEEx, routing, JS hooks, CSS,
forms, or LiveView tests.

Phoenix 1.8 generates an `AGENTS.md` by default. This skill captures the parts
that matter for this repo and adapts them to GnomeGarden's Ash-first boundary.

## Precedence

1. `AGENTS.md` and `.pi/skills/ash-framework/SKILL.md` win for Ash resources,
   domain behavior, migrations, data access, and Ash-backed forms.
2. Phoenix generated guidance applies to HEEx syntax, LiveView structure,
   routing, components, JS/CSS, and tests.
3. Do not copy Phoenix's default Ecto context/schema/form advice into Ash-backed
   code. Translate it to Ash code interfaces, Ash actions, and AshPhoenix forms.

## Phoenix 1.8 Defaults

- Wrap LiveView templates with `<Layouts.app flash={@flash} ...>`.
- Do not call `<.flash_group>` outside `layouts.ex`.
- Use the imported `<.icon>` component for hero icons.
- Use `<.input>` for form inputs when available.
- If overriding `<.input class=...>`, fully style it because default classes are
  replaced.
- `Phoenix.View` is obsolete; do not use it.
- Router `scope` blocks can include an alias. Avoid duplicate module prefixes;
  do not add route aliases that the scope already provides.

## HEEx

- Use `~H` or `.html.heex`, never `~E`.
- Use `{...}` for interpolation in attributes and normal tag bodies.
- Use `<%= ... %>` for block constructs inside tag bodies.
- Use HEEx comments: `<%!-- comment --%>`.
- Use list syntax for conditional classes: `class={[..., condition && "..."]}`.
- Do not write `else if` or `elseif`; use `cond` or `case`.
- Do not use raw `<script>` tags in templates.
- For literal `{` or `}` in code examples, add `phx-no-curly-interpolation`.

## LiveView

- Use `<.link navigate={...}>`, `<.link patch={...}>`, `push_navigate/2`, and
  `push_patch/2`; do not use deprecated `live_redirect` or `live_patch`.
- Avoid LiveComponents unless there is a concrete need.
- Name LiveViews with a `Live` suffix.
- Use streams for collections; stream containers need `id` and
  `phx-update="stream"`, and each direct child needs an `id`.
- Do not enumerate `@streams.*`; refetch and `stream(..., reset: true)` for
  filtering, pruning, or refreshing.
- Re-stream an item when assigns change content inside that streamed item.
- Do not use deprecated `phx-update="append"` or `"prepend"`.

## Forms

- For Ash-backed forms, load `ash-framework` and use `AshPhoenix.Form`.
- Render with Phoenix `<.form>` and `<.input>` components.
- Always give forms and key interactive elements stable DOM IDs.
- Do not access changesets directly in templates.

## JavaScript Hooks

- Any element with `phx-hook` must have a unique DOM `id`.
- If the hook owns its DOM, add `phx-update="ignore"`.
- Prefer colocated hooks only where Phoenix supports them, and use names that
  start with `.` for colocated hooks.
- External hooks belong in `assets/js` and must be registered with `LiveSocket`.
- When using `push_event/3`, return or rebind the updated socket.

## CSS and Assets

- Tailwind v4 uses the `@import "tailwindcss" source(none)` plus `@source`
  syntax in `assets/css/app.css`; do not add `tailwind.config.js`.
- Do not use `@apply`.
- Use app-managed JS/CSS bundles; do not add inline scripts or random external
  layout script/link tags.

## Elixir and Tests

- Lists do not support indexed access with `list[i]`; use pattern matching,
  `Enum.at/2`, or `List`.
- Bind the result of `if`, `case`, `cond`, etc. instead of rebinding inside the
  block and expecting outer state to change.
- Do not nest multiple modules in one file.
- Do not use map access syntax on structs unless the struct implements Access.
- Do not call `String.to_atom/1` on user input.
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure.
- Read `mix help <task>` before generators or task options matter.
- Use `start_supervised!/1` in tests.
- Avoid `Process.sleep/1`; prefer monitors or `_ = :sys.get_state(pid)`.
- Test LiveViews with `Phoenix.LiveViewTest`, `LazyHTML`, stable IDs,
  `element/2`, and `has_element?/2` instead of brittle raw HTML assertions.
