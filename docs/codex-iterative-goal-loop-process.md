# Codex Iterative Goal Loop Process

Date: 2026-06-02
Status: Process document

## Purpose

This document defines how to use Codex Goals to work through the AshLua agent
operating-system plan in many small, evidence-checked iterations.

The source architecture plan is:

- `docs/ash-lua-agent-operating-system-plan.md`

The reusable repo skill is:

- `.agents/skills/iterative-goal-loop/SKILL.md`

## Research Basis

OpenAI's Goals guidance describes a goal as a persistent, thread-scoped
completion contract with a clear outcome, evidence surface, constraints,
iteration policy, and blocked stop condition. The practical pattern is:

```text
work -> check evidence -> continue or complete
```

That is the right shape for the AshLua plan because the project is too large
for one prompt, but each slice can be made concrete and verified.

References:

- https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex
- https://developers.openai.com/codex/skills
- https://developers.openai.com/codex/agents-md

## Operating Rules

- Keep exactly one active Codex goal at a time.
- Never use a single broad goal like "build the agent framework."
- Each goal must produce a durable artifact or behavior.
- Each goal must define verification before implementation starts.
- Finish foundation and governance before broad autonomy.
- Use repo docs and Ash docs before changing Ash resources.
- Complete a goal only when evidence proves it.
- If blocked, preserve the evidence and state the next input needed.

## Goal Shape

Use this structure:

```text
/goal <desired end state>, verified by <specific evidence>, while preserving <constraints>. Use <allowed files, docs, tools, and boundaries>. Between iterations, inspect the latest evidence, make the smallest defensible next change, and record what changed. If blocked or no valid path remains, stop with attempted paths, evidence gathered, blocker, and next input needed.
```

## Roadmap To Goal Backlog

### Goal 0: Implementation Inventory

```text
/goal Produce an implementation inventory for the AshLua agent operating-system plan, verified by a short repo document that maps proposed resources and workflows to existing modules, generated resource-map entries, missing migrations, and first-slice dependencies, while preserving current code behavior. Use AGENTS.md, docs/llm/index.md, docs/llm/generated/resources.json, config/config.exs, and relevant Ash modules. Between iterations, inspect the next most relevant domain or resource and update the inventory. If blocked, report the missing source of truth and the next input needed.
```

Why first: this prevents duplicating existing resources or implementing from
aspirational docs.

Expected artifact:

- `docs/ash-lua-agent-implementation-inventory.md`

Verification:

- inventory references implemented resources from `docs/llm/generated/resources.json`
- no code changes required

### Goal 1: App-Wide MemoryBlock Resource

```text
/goal Add GnomeGarden.Operations.MemoryBlock as the first app-wide governed memory resource, verified by Ash docs lookup, generated Ash migration, applied migration, refreshed resource map, focused tests for propose/activate/reject/archive and active scope reads, and successful compile, while preserving existing Agents.Memory behavior and not introducing a new Knowledge domain yet. Use AGENTS.md, docs/ash-lua-agent-implementation-inventory.md, GnomeGarden.Operations, and Ash code interfaces. Between iterations, inspect compile/test failures and make the smallest resource/action/policy fix. If blocked by authorization or approval semantics, implement conservative admin/operator-readable actions and report the exact policy choice needed.
```

Expected implementation:

- resource under `lib/garden/operations/`
- code interfaces in `GnomeGarden.Operations`
- statuses for draft/proposed/active/rejected/archived
- scope fields so memory can be global, domain scoped, or record scoped
- provenance fields so agent/operator/domain sources can be audited
- migration from `mix ash.codegen`
- resource map refresh

Verification:

- `mix usage_rules.docs Ash.Resource`
- `mix usage_rules.search_docs "code interface" -p ash`
- `mix usage_rules.search_docs "Ash policies" -p ash`
- `mix ash.codegen`
- `mix ash.migrate`
- `mix llm.generate_resource_map`
- focused tests for the resource
- `mix compile --warnings-as-errors`

### Goal 2: Governed Archival Memory

```text
/goal Add or extend app-wide governed archival memory, verified by migration, resource-map refresh, focused tests for propose/approve/reject/expire/recall actions, and no regressions in existing Agents.Memory callers, while preserving current agent memory behavior where callers depend on it. Use GnomeGarden.Operations memory resources and Ash actions rather than helper services. Between iterations, inspect existing callers before changing action names or required fields. If blocked by incompatible existing data, report a migration-safe fallback.
```

Expected implementation:

- review status
- provenance/source fields
- tags or namespace search
- confidence and expiry
- usage tracking

Verification:

- focused memory tests
- compile
- existing agent tests that touch memory

### Goal 3: LearningRecommendation Resource

```text
/goal Add a LearningRecommendation resource that turns agent observations into reviewable company-change proposals, verified by migration, resource-map refresh, tests for propose/approve/reject/apply lifecycle, and compile, while preserving CompanyProfileLearning behavior. Use AshStateMachine if appropriate and keep application of approved changes behind explicit Ash actions. Between iterations, separate recommendation recording from applying business changes. If blocked by unclear target semantics, implement recording/review first and leave apply as explicit future work.
```

Expected implementation:

- target type/id/action
- evidence and proposed change
- risk/confidence/status
- source agent run relationship
- reviewer/apply timestamps

Verification:

- focused resource lifecycle tests
- compile
- resource map refresh

### Goal 4: Memory And Learning Review UI

```text
/goal Build a mobile-friendly operator review surface for pending memory and learning proposals, verified by LiveView/controller tests where available and browser checks at mobile and desktop widths, while preserving existing workspace navigation and shared UI component language. Use shared WorkspaceUI/CoreComponents first. Between iterations, use snapshots and source code to fix broken interactions or layout. If blocked by missing resources, stop and name the prerequisite goal.
```

Expected implementation:

- queue of pending memory proposals
- queue of pending learning recommendations
- approve/reject actions
- detail drawer or detail page

Verification:

- focused web tests
- browser snapshot/interaction checks
- mobile and desktop width checks

### Goal 5: AgentWorkflowDefinition Resource

```text
/goal Add an AgentWorkflowDefinition resource for versioned AshLua workflows, verified by migration, resource-map refresh, validation tests for schemas and allowed tool/action lists, and compile, while preserving existing direct worker execution. Use Ash actions for draft/validate/publish/disable/clone version. Between iterations, keep the runner minimal until the definition resource is stable. If blocked by Lua validation uncertainty, implement metadata/versioning first and leave runtime validation explicit.
```

Expected implementation:

- workflow key/version
- Lua source or module reference
- input/output schemas
- allowed domains/actions/tools
- risk/enabled/published fields

Verification:

- focused resource tests
- compile
- resource map refresh

### Goal 6: First Versioned Procurement Workflow

```text
/goal Port one procurement source-inspection flow into a versioned AshLua workflow path, verified by focused procurement/source pipeline tests and an AgentRun record that captures input, output, and failure metadata, while preserving the existing production worker behavior. Use one narrow source type and one workflow definition. Between iterations, compare old and new outputs for the same fixture/source. If blocked by live credentials or external websites, use local fixtures and label live verification as pending.
```

Expected implementation:

- one workflow definition or seeded workflow module
- runner path that executes AshLua with constrained actions
- structured run output/failure metadata

Verification:

- procurement source pipeline tests
- fixture-based workflow test
- no live credential dependency for test pass

### Goal 7: Narrow AshAI Toolsets

```text
/goal Define narrow AshAI toolsets for the first workflow, verified by tests that allowed actions execute and forbidden actions are unavailable, while preserving Ash policies and actor handling. Use AshAI tool discovery only for explicitly allowed domains/actions. Between iterations, reduce the exposed surface rather than adding broad tool access. If blocked by AshAI API ambiguity, stop with the exact docs/API gap and a proposed toolset shape.
```

Expected implementation:

- workflow-specific allowed tool/action config
- audit metadata for tool calls
- tests for allowed and forbidden actions

Verification:

- AshAI docs lookup
- focused tests
- compile

### Goal 8: Agent Health And Operator Console

```text
/goal Add operator-visible health for agent jobs, failed runs, memory proposals, learning proposals, workflow status, and credential blockers, verified by health endpoint tests and browser checks for the console UI, while preserving existing /ready behavior and Oban dashboard access. Use existing health controller patterns and shared UI components. Between iterations, prioritize accurate status over decorative UI. If blocked by missing data sources, report which metric must wait for a prior resource goal.
```

Expected implementation:

- stale job status
- failed run clusters
- pending memory/learning counts
- workflow disabled/failure counts
- credential blockers

Verification:

- health controller tests
- focused UI tests or browser interaction checks
- compile

### Goal 9: Evaluation Harness

```text
/goal Add an AgentEvalCase and AgentEvalRun harness for testing agent workflows, verified by migrations, resource-map refresh, tests for creating eval cases and recording eval runs, and one fixture-backed procurement eval, while preserving existing runtime behavior. Use Ash resources and code interfaces. Between iterations, keep eval scoring simple and auditable before adding automation. If blocked by uncertain grading criteria, implement structured recording first and leave scoring as manual labels.
```

Expected implementation:

- eval case resource
- eval run resource
- frozen input and expected actions/output
- forbidden actions
- human label/reviewer fields

Verification:

- focused Ash tests
- fixture eval test
- compile
- resource map refresh

## Review After Each Goal

After each goal, update the user with:

- completed outcome
- evidence checked
- files changed
- migrations/codegen/resource-map status
- residual risk
- next recommended goal

Do not roll straight into the next goal unless the user asked for autonomous
continuation or activated a new goal.

## Suggested First Prompt

Use this to start the loop without immediately changing code:

```text
Use $iterative-goal-loop with docs/ash-lua-agent-operating-system-plan.md. Create the Goal 0 implementation inventory and stop with the proposed next active /goal before making resource changes.
```
