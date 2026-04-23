# Pi Integration — GnomeGarden

Pi is an open-source AI agent toolkit (github.com/badlogic/pi-mono) being evaluated
as the company's unified agent platform: coding assistant, automation runtime,
and organizational memory.

## Documents

| Doc | Purpose |
|-----|---------|
| [rationale.md](rationale.md) | Why Pi, what it replaces, what stays |
| [architecture.md](architecture.md) | How Pi fits into the Elixir/OTP stack |
| [memory-structure.md](memory-structure.md) | Company, domain, and per-project memory layout |
| [bid-scanner-migration.md](bid-scanner-migration.md) | Migrating BidScanner from Jido to Pi RPC |
| [mix-task-bridge.md](mix-task-bridge.md) | Elixir Mix tasks as the tool bridge |
| [skills-layout.md](skills-layout.md) | Pi skills for each GnomeGarden domain |
| [rollout-plan.md](rollout-plan.md) | Phased adoption plan |

## Key Decisions

- Pi communicates with GnomeGarden via **RPC mode** (JSONL over stdin/stdout)
- Elixir owns scheduling, supervision, and Ash data operations
- Pi owns LLM reasoning, context management, and company memory
- ListingScanner and deterministic pipelines stay in Elixir
- Pi replaces Jido's AI agent loop, not the entire Jido ecosystem
