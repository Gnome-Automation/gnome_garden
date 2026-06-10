---
name: iterative-goal-loop
description: Use when turning a large architecture plan or roadmap into many evidence-checked Codex goals, one active goal at a time, with iterative implementation, verification, review, and handoff between goals.
---

# Iterative Goal Loop

Use this skill to convert a large plan into a sequence of bounded Codex goals.
The purpose is steady implementation of a larger system without losing the
completion standard, repo constraints, or evidence trail between slices.

## Inputs

Start by locating:

- the source plan or roadmap
- the repo rules, especially `AGENTS.md`
- the implemented architecture map when present
- current git status
- relevant tests, health checks, and verification commands

For GnomeGarden, read these first when the goal concerns the AshLua agent plan:

- `docs/ash-lua-agent-operating-system-plan.md`
- `docs/codex-iterative-goal-loop-process.md`
- `docs/llm/index.md`
- `docs/llm/generated/resources.json`
- `AGENTS.md`

## Core Rule

Use one active goal at a time.

Do not create one vague goal for the entire roadmap. Convert the roadmap into a
goal backlog, then activate only the next smallest meaningful goal whose output
can be verified.

## Goal Contract

Every goal must define:

- outcome: what must be true
- evidence: tests, docs, generated files, UI behavior, logs, or command output
- constraints: what must not change or regress
- boundaries: allowed files, domains, tools, and migration scope
- iteration policy: how to choose the next attempt after each result
- blocked condition: when to stop and what input would unblock progress

Preferred template:

```text
/goal <desired end state>, verified by <specific evidence>, while preserving <constraints>. Use <allowed files, docs, tools, and boundaries>. Between iterations, inspect the latest evidence, make the smallest defensible next change, and record what changed. If blocked or no valid path remains, stop with attempted paths, evidence gathered, blocker, and next input needed.
```

## Decomposition Method

1. Inventory the plan.
   - Extract proposed resources, workflows, UIs, health checks, evals, and docs.
   - Mark dependencies between them.
   - Identify which items require migrations or app restarts.

2. Build a goal backlog.
   - Each goal should produce a useful artifact or behavior.
   - Prefer one resource family, one UI surface, or one workflow per goal.
   - Split goals that mix schema, runtime behavior, UI, and evals.

3. Choose the next goal.
   - Prefer foundation before UI.
   - Prefer observable health before autonomy.
   - Prefer read/review actions before write/apply actions.
   - Prefer narrow toolsets before broad tool access.

4. Activate only when explicit.
   - If the user asks for a plan, draft `/goal` commands but do not activate.
   - If the user explicitly asks to start or continue a goal, use the active
     goal tools.
   - If a goal is already active, inspect it before creating another.

5. Work the loop.
   - Read the code and docs first.
   - Make the smallest complete implementation slice.
   - Verify with focused tests and runtime checks.
   - Fix issues for one or two attempts.
   - Mark complete only when evidence proves the goal.

6. Handoff.
   - Summarize files changed, verification run, remaining risk, and next goal.
   - Do not mark a budget-limited or blocked goal as complete.

## GnomeGarden Constraints

For Ash resource work:

- search docs before implementing with `mix usage_rules.docs` or
  `mix usage_rules.search_docs`
- use Ash resources, actions, policies, calculations, and code interfaces
- do not use raw Ecto/Repo for Ash resource behavior
- use `mix ash.codegen` and `mix ash.migrate` for resource schema changes
- refresh `mix llm.generate_resource_map` after Ash domain/resource changes
- keep Jido out of the production agent runtime

For UI work:

- design mobile first
- use shared UI components before page-specific patterns
- verify narrow and wide responsive behavior when UI changes affect layout

For server lifecycle:

- do not restart the app server unless config, deps, or supervision tree changes
  require it
- if a restart is required, state why and let the normal lifecycle apply unless
  the user explicitly asks for it

## Completion Standard

A goal is complete only when:

- the outcome is implemented
- the stated evidence was checked
- tests or runtime checks pass, or any skipped checks are explained
- generated maps/migrations/docs are updated when required
- the final answer names the next recommended goal

Do not complete a goal because the implementation looks plausible.

## Blocked Standard

Stop and report blocked when:

- required credentials, data, or user decisions are unavailable
- the same blocker recurs after repeated attempts
- the verification surface cannot be run and no proxy evidence is defensible
- continuing would require crossing the goal boundary

Report:

- attempted paths
- evidence gathered
- exact blocker
- safest next user decision or input

