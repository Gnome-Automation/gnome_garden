# UI Layout

## Current Layout Model

The app is built around a cockpit-first admin workspace, not a mobile bottom-nav app shell.

Current shape:
- persistent sidebar navigation
- large page-shell components
- cockpit cards and queue sections on `/`
- domain-specific `index/show/form` LiveViews

## Primary Layout Pieces

### Root/App Layouts
The standard Phoenix root/app layouts frame the authenticated LiveView surfaces.

### Sidebar Navigation
Implemented in:
- `lib/garden_web/components/nav.ex`

The sidebar is the primary app navigation, grouped by domain:
- Signal Inbox
- Operations
- Commercial
- Execution
- Finance
- Procurement
- Console

### Shared Workspace Shell
Implemented in:
- `lib/garden_web/components/workspace_ui.ex`

This is the common shell for most resource screens and provides:
- `page`
- `page_header`
- `section`
- `empty_state`
- `stat_card`
- `action_card`
- `form_section`
- `form_actions`
- `tab_button`

## Cockpit Layout

The home page uses the workspace shell to present:
- summary stat cards
- queue sections
- action-oriented lists

The cockpit is optimized for:
- queue pressure
- operator review
- exception handling
- quick navigation into deeper domain surfaces

## Styling Direction

The main operator UI uses:
- Tailwind CSS v4
- custom Phoenix components
- Protocol-inspired cards and badges

It does not use DaisyUI as the main design system anymore.

## Resource Screen Convention

Most first-class resource surfaces now follow:
- `Index`
- `Show`
- `Form`

That convention is used across:
- Operations
- Commercial
- Execution
- Finance

This keeps navigation and mental models stable even as the data model expands.
