# Agent Operating System Runbook

Date: 2026-06-08
Status: Implemented operator workflow

## Purpose

This runbook explains how to operate the implemented agent foundation in
GnomeGarden. It covers the current Phoenix/Ash/Oban/AshLua/AshAI system, not the
older planning model.

Use this when checking whether agent work is healthy, deciding what needs human
attention, or preparing the next implementation slice.

## Primary Routes

- `/console/agents` - main operating health, deployments, runs, runtime cache,
  and template registry.
- `/console/agents/attention` - failed agent runs, failed eval runs, and
  follow-up task creation.
- `/console/agents/evals` - eval cases, recent eval runs, runnable fixture
  actions, and eval sweep health.
- `/console/agents/workflows` - workflow definitions and version state.
- `/operations/review` - pending memory and learning review.
- `/oban` - low-level Oban job inspection.

## Daily Operator Check

Start at `/console/agents`.

1. Check `Running Now`.
   - If nonzero for a long time, inspect Recent Runs and `/oban`.
   - Active runs should be `pending` or `running`; completed work should leave
     that count quickly.

2. Check `Needs Attention`.
   - Open `Agent Attention` when this is nonzero.
   - Failed runs should either get a follow-up Operations task, a credential fix,
     or a workflow/eval update.

3. Check `Agent Operating Health`.
   - `Failed Runs`: recent failed `AgentRun` records.
   - `Memory Review`: pending memory blocks and archival memory entries.
   - `Learning Review`: pending learning recommendations.
   - `Eval Coverage`: runnable active eval cases over active eval cases.
   - `Eval Sweeps`: scheduled eval sweep state and next run time.
   - `Workflows`: published workflow definitions.
   - `Credentials`: approved procurement sources blocked by login.

4. Open `/operations/review` if memory or learning review is nonzero.
   - Approve only memory/learning that should become active company guidance.
   - Reject proposals that are speculative, duplicated, stale, or unsafe.

## Eval Workflow

Use `/console/agents/evals`.

### Seed And Prepare Fixtures

- `Seed Inspection Eval` creates the procurement source inspection eval cases.
- `Prepare Local Fixture` creates local fixture-backed inputs so cases become
  runnable.
- `Run Local Checks` prepares and runs all local procurement inspection fixture
  cases.

### Run Evals

- `Run Eval` executes one runnable case.
- `Run Runnable Evals` executes all active runnable cases synchronously.
- `Queue Local Sweep` prepares all local procurement inspection fixtures and queues
  a scoped background eval sweep for those cases.
- `Queue Eval Sweep` inserts an Oban job for the background sweep path.

### Read Eval Health

- `Active Cases` is the active eval case count.
- `Runnable` is the number with concrete source/deployment input.
- `Passed` is recent passing eval runs.
- `Needs Review` is recent failed or errored eval runs.
- `Sweep Queue` is queued/running background sweeps.
- `Sweep Health` is the higher-level scheduled sweep status:
  - `idle`: no sweep jobs have run yet.
  - `queued`: a sweep job is waiting.
  - `running`: a sweep job is executing.
  - `healthy`: the latest completed sweep is fresh.
  - `stale`: the latest completed sweep is older than the stale threshold.
  - `failed`: the latest sweep is retryable, discarded, or cancelled.
- `Coverage Breakdown` groups active cases by workflow and shows:
  - total cases
  - runnable cases
  - cases that still need input
  - latest passed, failed, errored, and unrun case counts

## Attention Workflow

Use `/console/agents/attention`.

The page groups failed runtime work and failed eval runs so an operator can
turn them into durable work and track resolution.

Recommended process:

1. Start with `Failure Clusters` to find repeated failure reasons.
   - `New`, `Repeated`, and `Recurring` badges summarize how often that
     failure appears in the broader recent trend window.
   - The trend-window count helps distinguish one-off failures from repeated
     operator or workflow problems.
2. Use `View Cluster` when you want to drill into one failure class.
3. Use `Create Missing Tasks` when every item in the cluster should become
   operator work.
4. Filter or group the attention list to the failure class you are handling.
5. Open the related run/eval evidence.
6. If an individual item needs human follow-up, create an Operations task from
   the row.
7. When the follow-up is handled, use `Mark Resolved` or open the task and
   complete it from Operations.
8. Use the `Resolved` filter to confirm completed follow-ups remain visible for
   audit and handoff.
9. If it is a credential blocker, route to the procurement source credential
   workflow.
10. If it is a workflow or eval issue, update the workflow/eval fixture and rerun
   the relevant eval.

Avoid treating a failed run as resolved just because it disappeared from the
current recent window. Create or link a task when the failure needs work.

## Workflow Governance

Implemented workflow governance lives in `GnomeGarden.Agents`.

- `AgentWorkflowDefinition` stores versioned workflow source, schemas, allowed
  actions, allowed tools, status, and risk level.
- Published workflows are what operator surfaces should treat as active.
- The `WorkflowToolset` enforcement layer dispatches only explicitly supported
  and allow-listed actions.
- The AshAI tool surface is intentionally narrow and domain declared.

Current AshAI tools expose only selected governed actions for:

- agent run and eval reads
- published workflow lookup
- active memory block reads
- archival memory recall
- agent follow-up task creation

Do not add broad all-domain AshAI tool exposure. New tool exposure should be
workflow-specific and backed by tests that prove forbidden actions are absent.

## Memory And Learning Review

Memory and learning are app-wide Operations concerns, not agent-owned state.

- `MemoryBlock` is always-visible governed memory.
- `MemoryEntry` is archival memory.
- `LearningRecommendation` is the reviewable path from observation to behavior
  change.

Agents and workflows may propose memory or learning, but important company
guidance should become active only after operator review.

## Scheduled Jobs

The eval sweep runs through `GnomeGarden.Agents.AgentEvalSweepWorker`.

Current schedule:

- Cron: `17 * * * *`
- Queue: `default`
- Timeout: 60 seconds
- Unique window: 300 seconds by worker

Use `/console/agents` for the summarized health and `/oban` for low-level job
inspection.

If sweeps are stale:

1. Check `/oban` for retryable, discarded, or executing jobs.
2. Check recent eval runs for errors.
3. Run `Queue Eval Sweep` from `/console/agents/evals`.
4. If the sweep still fails, inspect eval case inputs and workflow fixture
   preparation.

## Verification Commands

Focused checks for this area:

```bash
mix test test/garden/agents/agent_eval_sweep_worker_test.exs \
  test/garden/agents/agent_eval_sweep_health_test.exs \
  test/garden/agents/ash_ai_tool_surface_test.exs \
  test/garden/agents/workflow_toolset_test.exs \
  test/garden_web/live/console/agent_attention_live_test.exs \
  test/garden_web/live/console/agent_evals_live_test.exs \
  test/garden_web/live/console/agents_live_test.exs \
  test/garden_web/live/console/agent_workflows_live_test.exs \
  test/garden_web/live/operations_review_live_test.exs
```

Compile check:

```bash
mix compile --warnings-as-errors
```

Run `mix precommit` only when preparing for PR-level validation.

## Current Milestone State

The agent operating-system foundation is now operator-usable:

- governed Operations memory and learning resources exist
- review UI exists
- workflow definitions exist
- workflow memory hydration exists
- eval case/run harness exists
- runnable procurement inspection fixtures exist for credential-gated, public
  bid listing, and irrelevant-page scenarios
- eval console, all-local fixture checks, and workflow coverage breakdown exist
- attention page exists
- failure clustering, trend labels, drill-in, follow-up task creation, and
  resolved task tracking exist
- AshAI tool surface exists
- scheduled eval sweep health exists on both the eval console and Agents Console

The remaining high-value work is broadening coverage and automation:

- add eval fixtures beyond procurement source inspection
- add deeper failure analytics across longer windows
- add more workflow-specific AshAI toolsets only where needed
- expand scheduled health checks beyond eval sweeps
- tighten authorization policies for operator roles
