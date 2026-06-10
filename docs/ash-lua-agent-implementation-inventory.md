# AshLua Agent Implementation Inventory

Date: 2026-06-04
Status: Goal 0 checkpoint and memory-scope decision

## Purpose

This document maps the AshLua agent operating-system plan to the currently
implemented GnomeGarden application. It exists to prevent duplicated resources,
unclear memory ownership, or implementation from aspirational architecture docs.

Source plan:

- `docs/ash-lua-agent-operating-system-plan.md`

Authoritative implementation sources checked:

- `AGENTS.md`
- `docs/llm/index.md`
- `docs/llm/generated/resources.json`
- `config/config.exs`
- `lib/garden/agents.ex`
- `lib/garden/agents/*`
- `lib/garden/commercial/company_profile*.ex`
- `lib/garden/procurement/source_pipeline.ex`
- Tidewave Ash resource introspection

## Executive Decision

Memory should be app-wide company knowledge, with agent-specific runtime memory
as one scoped consumer.

Do not make `GnomeGarden.Agents.Memory` the universal source of company memory.
Agents are not the owner of all durable knowledge. They are a runtime and
automation layer that should read, propose, and use company memory through Ash
actions.

Recommended direction:

- Keep `GnomeGarden.Agents.AgentMessage`, `AgentRun`, and `AgentRunOutput` as
  runtime/conversation/history resources.
- Replace or narrow `GnomeGarden.Agents.Memory` into runtime-local memory only,
  or migrate it into a new app-wide domain/resource.
- Introduce app-wide governed memory resources under `GnomeGarden.Operations`
  unless a dedicated `GnomeGarden.Knowledge` domain is intentionally created.
- Let agents propose memories and learning recommendations, but require review
  before important company memory becomes active guidance.

The first implementation slice should add app-wide memory primitives, not a
new agent-only memory block.

## Implemented Domains

`config/config.exs` and the generated resource map currently define these Ash
domains:

- `GnomeGarden.Mercury`
- `GnomeGarden.Accounts`
- `GnomeGarden.Acquisition`
- `GnomeGarden.Agents`
- `GnomeGarden.Commercial`
- `GnomeGarden.Execution`
- `GnomeGarden.Finance`
- `GnomeGarden.Operations`
- `GnomeGarden.Procurement`

There is no implemented `Knowledge`, `Memory`, or `Learning` domain today.

## Implemented Agent Runtime Resources

The `GnomeGarden.Agents` domain currently owns:

- `GnomeGarden.Agents.Agent`
- `GnomeGarden.Agents.AgentDeployment`
- `GnomeGarden.Agents.AgentRun`
- `GnomeGarden.Agents.AgentRunOutput`
- `GnomeGarden.Agents.AgentMessage`
- `GnomeGarden.Agents.Memory`

### `AgentRun`

Implemented role:

- durable run lifecycle
- state machine: `pending`, `running`, `completed`, `failed`, `cancelled`
- run metadata
- result and failure details
- relationships to agent, deployment, messages, outputs, parent/child runs
- failure calculations

Plan fit:

- already fits the agent operating-system plan
- should remain in `GnomeGarden.Agents`
- can later reference workflow definitions, toolsets, memory proposals, and
  evaluation runs

### `AgentMessage`

Implemented role:

- stores conversation and tool-call history per run
- roles include `user`, `assistant`, `system`, `tool_call`, `tool_result`
- stores tool input/result metadata

Plan fit:

- already fits the "conversation recall" part of the memory model
- should remain runtime-scoped
- should not be treated as curated company memory

### `AgentRunOutput`

Implemented role:

- bridges agent runs to durable business outputs
- currently supports `:procurement_source`, `:bid`, and `:finding`
- records event, label, summary, and metadata

Plan fit:

- already fits audit and output history
- should be expanded only as workflows produce new durable business record types

### `Agents.Memory`

Implemented role:

- table: `agent_memories`
- fields: `key`, `content`, `type`, `namespace`, `metadata`
- types: `:fact`, `:pattern`, `:decision`, `:preference`, `:context`
- actions: `remember`, `recall`, `search`, `by_key`, `by_type`
- identity: unique key and namespace

Current usage:

- no direct callers were found outside `lib/garden/agents.ex` and the resource
  module itself

Plan fit:

- useful as a prototype, but too agent-owned for the future memory model
- lacks review status, provenance, confidence, expiry, source record references,
  usage tracking, and active/archive states
- does not distinguish company memory blocks from archival memories or runtime
  conversation recall

Decision:

- do not build the next feature by only adding more fields to this resource
- either migrate it into app-wide memory or leave it as a compatibility wrapper
  around new app-wide memory actions

## Implemented Company Learning

### `CompanyProfile`

Implemented role:

- durable company positioning and targeting profile
- owns core capabilities, adjacent capabilities, target industries,
  disqualifiers, voice guidance, and keyword profile configuration
- exposes primary and by-key reads

Plan fit:

- should remain the canonical business-facing profile
- agents and prompts can read it
- company profile should not be replaced by agent memory

### `CompanyProfileLearning`

Implemented role:

- plain Elixir module in `GnomeGarden.Commercial`
- applies operator feedback back into `CompanyProfile`
- writes learned excludes and feedback history into profile metadata

Current callers:

- acquisition review feedback
- procurement bid review feedback
- procurement targeting UI

Plan fit:

- already proves learning is useful across domains
- too narrow for all future learning because it applies directly to company
  profile state
- should become a consumer or apply target of a broader
  `LearningRecommendation` flow

Decision:

- preserve current behavior
- add a reviewable learning resource before broadening automatic learning
- allow approved recommendations to call `CompanyProfileLearning` or future Ash
  actions explicitly

## Implemented AshLua Workflow Support

### Procurement Source Pipeline

`GnomeGarden.Procurement.SourcePipeline` already uses Lua/AshLua for bounded
workflow orchestration.

Implemented scripts:

- inspect source
- auto-configure source
- scan source

Current shape:

- Lua owns branch decisions
- Elixir/Ash actions own persistence and business behavior
- actor and context are passed into AshLua
- scanner/browser work remains behind procurement-shaped modules

Plan fit:

- this is the strongest existing implementation pattern
- future `AgentWorkflowDefinition` should generalize this shape instead of
  replacing it

### Procurement Resources With AshLua

The generated resource map and source files show several procurement resources
with `AshLua.Resource`, including:

- `ProcurementSource`
- `Bid`
- `CrawlRun`
- `CrawlPage`
- `CrawlEdge`
- `PageArtifact`
- `ExtractionCandidate`
- `SourceCredential`
- `SourceSearchFilter`
- `SourceSearchFilterFeedback`

Plan fit:

- procurement is already the best first domain for versioned AshLua workflows
- it has real source scanning, browser inspection, credentials, extraction, and
  acquisition handoff behavior

## Implemented Runtime Boundary

Current runtime is direct-worker based:

- `GnomeGarden.Agents.Templates` has only `procurement_source_scan`
- `GnomeGarden.Agents.DeploymentRunner` launches direct workers that expose
  `execute_run/1`
- open-ended Jido runtime has been removed from production paths
- `jido_browser` remains only as browser automation behind app modules

Plan fit:

- matches `AGENTS.md`
- keep this boundary
- future workflows should run through AshLua/Ash actions/direct workers, not
  through a new Jido agent runtime

## Missing Planned Resources

The following plan resources are not implemented today:

- app-wide `MemoryBlock` / `CompanyMemoryBlock`
- governed archival `Memory` / `CompanyMemory`
- `LearningRecommendation`
- `AgentWorkflowDefinition`
- workflow-specific AshAI toolset registry
- tool-call audit resource, unless handled through `AgentMessage`
- `AgentEvalCase`
- `AgentEvalRun`

## Memory Scope Decision

### Option A: Keep Memory Only In Agents

Rejected for the primary future model.

Pros:

- smallest schema change
- existing resource already present
- natural for run-local memories

Cons:

- makes agents the owner of company knowledge
- does not fit human/operator memories
- awkward for procurement, commercial, finance, execution, and operations
  learnings
- encourages app domains to reach into the agent runtime for business guidance

### Option B: Create A Dedicated Knowledge Domain

Viable, but not the recommended first move.

Pros:

- clean conceptual boundary
- reusable across all domains
- can own memory, recommendations, evals, and knowledge review

Cons:

- adds a tenth Ash domain before the model is proven
- requires new domain-level routing and admin surface decisions
- may overlap with `Operations`, which already owns cross-application operator
  state

### Option C: Add App-Wide Memory Under Operations

Recommended first move.

Pros:

- `GnomeGarden.Operations` already owns foundational cross-application operating
  model resources
- `Operations.Task` already represents cross-application operator work
- avoids making agent runtime the owner of company knowledge
- keeps memory available to procurement, acquisition, commercial, finance,
  execution, and agents
- can later be extracted into `GnomeGarden.Knowledge` if the model grows

Cons:

- `Operations` will need careful naming so memory does not feel like generic
  helpers
- agent-specific code interfaces must remain thin and scoped

Decision:

- implement app-wide governed memory in `GnomeGarden.Operations`
- keep agent conversation and run history in `GnomeGarden.Agents`
- do not add a separate `Knowledge` domain until the memory/recommendation model
  proves it needs a domain of its own

## Recommended First Resource Slice

Replace the original "AgentMemoryBlock first" goal with:

```text
Goal 1: App-Wide Memory Blocks
```

Proposed resources:

- `GnomeGarden.Operations.MemoryBlock`
- optionally `GnomeGarden.Operations.MemoryEntry` if archival memory should be
  separate in the same slice

Recommended starting with one resource:

```text
GnomeGarden.Operations.MemoryBlock
```

Reason:

- it establishes the app-wide ownership decision
- it gives operators and agents always-visible memory blocks
- it can model Letta-style memory blocks without committing to embeddings or
  semantic search yet
- archival/search memory can follow as Goal 2

Candidate fields:

- `id`
- `key`
- `label`
- `description`
- `content`
- `scope`
- `scope_type`
- `scope_id`
- `memory_type`
- `status`
- `visibility`
- `read_only?`
- `source_type`
- `source_id`
- `confidence`
- `metadata`
- `approved_by_user_id`
- `approved_at`
- timestamps

Candidate statuses:

- `draft`
- `proposed`
- `active`
- `rejected`
- `archived`

Candidate actions:

- `propose`
- `activate`
- `reject`
- `archive`
- `update_content`
- `active_for_scope`
- `by_key`

Recommended code interfaces:

- `propose_memory_block`
- `activate_memory_block`
- `reject_memory_block`
- `archive_memory_block`
- `list_active_memory_blocks_for_scope`
- `get_memory_block_by_key`

## Updated Goal Backlog

### Goal 1: App-Wide MemoryBlock

Add `GnomeGarden.Operations.MemoryBlock` as the first governed company memory
resource.

Verification:

- Ash docs lookup before implementation
- `mix ash.codegen`
- `mix ash.migrate`
- `mix llm.generate_resource_map`
- focused resource tests
- `mix compile --warnings-as-errors`

### Goal 2: Governed Archival Memory

Add app-wide archival memory entries, or extend memory blocks if the inventory
proves one table is enough.

Goal 2 should decide between:

- `GnomeGarden.Operations.MemoryEntry`
- enhancing `MemoryBlock` with search-oriented fields
- migrating/replacing `GnomeGarden.Agents.Memory`

### Goal 3: LearningRecommendation

Add reviewable learning recommendations, preferably app-wide.

Recommended home:

- `GnomeGarden.Operations.LearningRecommendation`

Reason:

- it can target any domain record
- it can create operator tasks later
- agents are one producer, not the owner

### Goal 4: Review UI

Build operator review UI for memory blocks and learning recommendations.

### Goal 5: AgentWorkflowDefinition

Add versioned workflow definitions after memory/learning governance exists.

Recommended home:

- `GnomeGarden.Agents.AgentWorkflowDefinition`

Reason:

- workflow runtime still belongs to agents/automation
- memory and learning remain app-wide

### Goal 6: First Versioned Procurement Workflow

Port one procurement source pipeline path into the workflow definition model.

### Goal 7: Narrow AshAI Toolsets

Expose workflow-specific toolsets instead of broad domain-wide tools.

### Goal 8: Health And Operator Console

Expose agent/job/workflow/memory/learning health.

### Goal 9: Evaluation Harness

Add eval cases and eval runs after the first workflow exists.

## Next Active Goal Recommendation

This section is historical. Many of the original goals are now implemented.
For the current operator workflow and milestone state, use:

- `docs/agent-operating-system-runbook.md`

The original next-goal prompt from this checkpoint was:

```text
/goal Add GnomeGarden.Operations.MemoryBlock as the first app-wide governed memory resource, verified by Ash docs lookup, generated Ash migration, applied migration, refreshed resource map, focused tests for propose/activate/reject/archive and active scope reads, and successful compile, while preserving existing Agents.Memory behavior and not introducing a new Knowledge domain yet. Use AGENTS.md, docs/ash-lua-agent-implementation-inventory.md, GnomeGarden.Operations, and Ash code interfaces. Between iterations, inspect compile/test failures and make the smallest resource/action/policy fix. If blocked by authorization or approval semantics, implement conservative admin/operator-readable actions and report the exact policy choice needed.
```

## Current Worktree Note

At the time this inventory was written, unrelated earlier work remained modified
in:

- `config/config.exs`
- `lib/garden_web/components/workspace_ui.ex`
- `lib/garden_web/controllers/health_controller.ex`
- `lib/garden_web/controllers/page_html/home.html.heex`

Do not revert those changes as part of the memory implementation goal.
