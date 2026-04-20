# UI Components

## Current Component Strategy

The main operator UI uses shared Phoenix function components rather than a third-party component library.

The most important component layers are:
- `GnomeGardenWeb.Components.WorkspaceUI`
- `GnomeGardenWeb.Components.Protocol`
- `GnomeGardenWeb.CoreComponents`

## Workspace Shell Components

Implemented in:
- `lib/garden_web/components/workspace_ui.ex`

Primary components:
- `page`
- `page_header`
- `section`
- `empty_state`
- `stat_card`
- `action_card`
- `form_section`
- `form_actions`
- `tab_button`

These components define the default structure for `index/show/form` pages.

## Protocol-Style Primitives

Implemented in:
- `lib/garden_web/components/protocol.ex`

Representative primitives:
- `resource_card`
- `tag`
- `button`
- `card`
- `hover_card`

These provide the visual language used across the cockpit and resource pages.

## Status and Presentation Semantics

A repo-level rule now applies:
- presentation-facing derived values should prefer Ash calculations/aggregates on the resource
- LiveViews should not own business/status mapping logic when it can live in Ash

That means things like:
- badge variants
- due-state labels
- summary counts

should generally come from Ash calculations or aggregates instead of ad hoc LiveView helper functions.

## Form Pattern

Most resource editing surfaces follow:
- a shared page header
- one or more `form_section` blocks
- shared `form_actions`
- AshPhoenix forms underneath

This keeps the UI consistent even as domains expand.

## What Is No Longer Accurate

The app is no longer primarily defined by:
- DaisyUI cards, drawers, modals, and bottom navigation
- a mobile bottom-nav shell
- old CRM-specific components

Those older patterns have been replaced by the cockpit/domain workspace model.
