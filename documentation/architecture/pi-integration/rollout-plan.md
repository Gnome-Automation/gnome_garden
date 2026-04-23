# Pi Rollout Plan

Phased adoption. Each phase is independently valuable. No big-bang migration.

## Phase 0: Foundation (Week 1)

**Goal**: Pi installed, basic configuration, memory seeded.

### Tasks

- [ ] Install Pi globally: `npm install -g @mariozechner/pi-coding-agent`
- [ ] Verify Pi runs in GnomeGarden repo: `cd gnome_garden && pi`
- [ ] Confirm Pi reads existing AGENTS.md and `.pi/settings.json`
- [ ] Symlink for cross-tool compat: `ln -s AGENTS.md CLAUDE.md` (or vice versa)
- [ ] Trim AGENTS.md to ~150 lines (move bulk to ash-framework skill)
- [ ] Set up API key: Anthropic key in `~/.pi/agent/auth.json`
- [ ] Create `.pi/memory/` directory structure (company/, procurement/, commercial/)
- [ ] Seed `.pi/memory/company/icp.md` with ICP and service areas
- [ ] Seed `.pi/memory/company/rejected-patterns.md` from existing targeting rules
- [ ] Seed `.pi/memory/procurement/MEMORY.md` from existing Agents.Memory records
- [ ] Verify Pi can use the ash-framework skill: `/skill:ash-framework`

### Validation

- Pi answers questions about the codebase correctly
- Pi understands Ash patterns from the skill
- Memory files are committed to Git

## Phase 1: Human-Facing Agent (Week 2)

**Goal**: Team can use Pi CLI for coding assistance and codebase questions.

### Tasks

- [ ] Create domain skills (procurement, acquisition, commercial, operations)
- [ ] Create liveview skill (form styling, component conventions)
- [ ] Create cross-domain skill (sync patterns, state machines)
- [ ] Test Pi on real tasks: "add a new attribute to Bid", "explain the finding promotion flow"
- [ ] Compare quality with Claude Code on same tasks
- [ ] Document any gaps or incorrect advice in memory

### Validation

- Pi gives correct Ash-idiomatic advice
- Pi loads the right skill for the task at hand
- Pi doesn't suggest raw Ecto, manual helpers, or other anti-patterns

## Phase 2: Slack Integration (Week 3)

**Goal**: Team can ask questions in Slack via Pi-mom.

### Tasks

- [ ] Deploy pi-mom (Docker container)
- [ ] Create Slack app and configure bot token
- [ ] Set up workspace memory: `~/.pi/mom/MEMORY.md`
- [ ] Configure channel-specific memory for #procurement, #engineering
- [ ] Test: "what sources are approved for scanning?"
- [ ] Test: "how does the finding -> signal promotion work?"
- [ ] Set up sandboxing (pi-mom runs in Docker, limit file access to repo)

### Validation

- Team members can get answers in Slack without CLI access
- Memory persists across conversations
- No sensitive data leaks via Slack

## Phase 3: Bid Scanner Migration (Weeks 4-5)

**Goal**: Bid scanning runs through Pi RPC instead of Jido AI agent.

### Tasks

- [ ] Write Mix tasks: `garden.scan_all`, `garden.scan_source`, `garden.list_sources`
- [ ] Create bid-scanner skill with scripts and analysis instructions
- [ ] Build `GnomeGarden.Agents.PiSession` GenServer (Port management)
- [ ] Modify `DeploymentRunner` to support `:pi_rpc` runtime alongside `:jido`
- [ ] Configure "SoCal Bid Scanner" deployment to use Pi runtime
- [ ] Run both Jido and Pi scanners in parallel for 1-2 weeks
- [ ] Compare: results quality, token cost, failure rate, scan time
- [ ] Switch primary to Pi, keep Jido as fallback
- [ ] After 1 week stable, remove Jido fallback

### Validation

- Pi scanner finds the same (or more) bids as Jido scanner
- Token cost is lower (no orchestration overhead)
- Failure recovery is better (Pi handles exceptions, updates memory)
- Memory files accumulate useful learnings

## Phase 4: Source Discovery Migration (Week 6)

**Goal**: Source discovery runs through Pi RPC.

### Tasks

- [ ] Write Mix task: `garden.discover_sources`
- [ ] Create source-discovery skill
- [ ] Seed region memory files from existing discovery runs
- [ ] Migrate "SoCal Source Discovery" deployment to Pi
- [ ] Validate new source discovery quality

## Phase 5: Target Discovery Migration (Week 7)

**Goal**: Commercial target discovery runs through Pi RPC.

### Tasks

- [ ] Write Mix tasks: `garden.discovery_sweep`, `garden.list_signals`
- [ ] Create target-discovery skill
- [ ] Seed commercial memory from existing discovery runs
- [ ] Migrate "Commercial Target Discovery" deployment to Pi

## Phase 6: Cleanup (Week 8)

**Goal**: Remove unused Jido components, reduce dependency footprint.

### Tasks

- [ ] Remove coding agent workers: Coder, Reviewer, TestRunner, DocsWriter,
      Researcher, Refactorer, Base (replaced by Pi CLI)
- [ ] Remove Jido.Action tool wrappers no longer called
      (keep tools still used by ListingScanner: ScoreBid, SaveBid, etc.)
- [ ] Remove or thin Jido AI dependencies:
      - `jido_ai` — remove if no AI agents remain
      - `jido_shell` — remove (Pi has bash tool)
      - `jido_vfs` — remove (Pi has read/write tools)
      - `jido_skill` — remove (Pi has skills)
      - `jido_mcp` — remove (Pi has extensions)
- [ ] Keep core Jido for signal bus if still used:
      - `jido` — if AshJido needs it
      - `jido_signal` — if signal bus is used for non-agent events
      - `jido_browser` — if browser automation still goes through Elixir
- [ ] Update AGENTS.md to reference Pi instead of Jido
- [ ] Archive old Jido agent documentation

### Dependency Reduction Target

Before (11 Jido packages):
```
jido, jido_ai, jido_action, jido_signal, jido_composer,
jido_browser, ash_jido, jido_shell, jido_vfs, jido_skill, jido_mcp
```

After (2-4 Jido packages):
```
jido, jido_signal, ash_jido, jido_browser (maybe)
```

## Risk Mitigation

### Phase 3 is the riskiest

- Run both scanners in parallel before switching
- Compare results daily for 2 weeks
- Keep Jido scanner as fallback (disable, don't delete)
- If Pi scanner misses bids, investigate before proceeding

### Node.js dependency

- Pi requires Node.js on the server
- Add to Dockerfile / deployment scripts in Phase 3
- Pin Pi version to avoid surprise breakage

### Memory drift

- Schedule weekly memory review (15 min)
- PR-based memory changes for auditability
- Don't let agents auto-write to memory without human review initially

### LLM cost

- Pi defaults to Claude Sonnet (cheaper than Opus)
- Bid scoring is the main cost driver — same regardless of framework
- Orchestration cost drops (from 30+ calls to 1-3)
- Monitor via Pi's built-in usage tracking

## Success Metrics

| Metric | Current (Jido) | Target (Pi) |
|--------|----------------|-------------|
| Bid scanner reliability | Intermittent timeouts | >95% success rate |
| Token cost per scan run | ~50K (orchestration + scoring) | ~20K (analysis + scoring) |
| Scan completion time | 3-5 min (LLM overhead) | 1-2 min (deterministic + analysis) |
| LLM providers available | 1 (Z.AI) | 20+ |
| Team access surfaces | 1 (LiveView) | 3 (CLI, Slack, LiveView) |
| Company knowledge locations | 2 (CLAUDE.md, Postgres) | 1 (Pi memory files) |
| Jido dependencies | 11 packages | 2-4 packages |
