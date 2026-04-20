# Agent Dashboard Assessment

Date: 2026-04-19
Status: Updated to reflect the implemented cockpit and console

## Summary

`gnome_garden` now has two distinct operator surfaces:

- the business cockpit at `/`
- the runtime console under `/console/agents`

That split is the right one.

The cockpit answers:
- what commercial, service, and finance queues need attention now?

The console answers:
- what agents and runs are doing the work?

## What Exists Today

### Cockpit

The home page now surfaces:
- due discovery programs
- review targets
- open signals
- active pursuits
- due maintenance
- open service tickets
- open work orders
- approved unbilled time
- approved unbilled expenses
- overdue invoices
- unapplied payments
- review bids

This makes the home page a real operations view instead of a placeholder dashboard.

### Console

The runtime-facing console now has:
- template/deployment launch surfaces
- run detail pages
- output visibility for discovery runs
- linkage from discovery-program screens into actual run records

### Durable runtime records

The relevant persistent resources are:
- `AgentDeployment`
- `AgentRun`
- `AgentMessage`
- `AgentRunOutput`
- `Memory`

That is a much better shape than the older tracker-centric experiment.

## What Changed From The Earlier Assessment

The earlier dashboard question assumed the main problem was how to build a first useful agent dashboard.

The system now already has:
- a cockpit for business pressure
- a console for agent runtime
- a durable discovery intake workflow

So the question is no longer "should there be a dashboard?"

The question is now:
- how much more runtime depth belongs in the console
- how much more business summarization belongs in the cockpit

## Current Assessment

### What is working well

- business queues are visible in one place
- discovery programs are launchable and schedulable
- agent runs are durable enough to inspect
- procurement and broad discovery both feed the commercial model

### What still needs work

- organization/person matching and merge controls
- deeper filtering and actions in discovery backlogs
- more polished runtime drill-down pages
- stronger auth/policy boundaries

## Recommended Direction

Keep the split:

### Cockpit
Use the cockpit for:
- queue pressure
- operator prioritization
- exception handling
- navigation into business work

### Console
Use the console for:
- agent deployments
- run status
- output timelines
- debugging and operational inspection

Do not collapse those back into one generic “agent dashboard.”

That would blur the difference between:
- runtime state
- business state

which the current architecture is finally separating correctly.
