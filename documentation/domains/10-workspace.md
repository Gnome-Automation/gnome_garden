# Operator Workspace

**Implemented As:** UI patterns and cockpit surfaces, not a standalone Ash domain

This file keeps the old `10-workspace` slot, but the current app does not implement a separate `Workspace` domain.

## Current Workspace Model

The operator workspace is built from:
- the cockpit at `/`
- domain-first LiveViews under `/operations`, `/commercial`, `/execution`, and `/finance`
- the procurement views under `/procurement`
- the agent console under `/console/agents`

## Shared UI Pattern

The dominant page pattern is:
- `index`
- `show`
- `form`

Shared page-shell components live in:
- `lib/garden_web/components/workspace_ui.ex`

Core reusable visual primitives live in:
- `lib/garden_web/components/protocol.ex`

## Cockpit Role

The home page is now the primary operator workspace.

It surfaces the queues that need attention:
- due discovery programs
- review targets
- open signals
- active pursuits
- due maintenance
- service tickets and work orders
- approved unbilled labor/expenses
- overdue invoices
- unapplied payments
- review bids

## What No Longer Applies

The old idea of a separate personal productivity domain with:
- capture
- inbox
- reminders

is not the implemented app structure today.

If those concepts return later, they should be designed against the current cockpit and domain navigation model rather than the older standalone workspace plan.
