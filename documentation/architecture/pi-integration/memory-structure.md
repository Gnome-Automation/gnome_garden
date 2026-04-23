# Memory Structure

Pi's memory is file-based, version-controlled, and hierarchical.
GnomeGarden needs memory at three scopes: company-wide, domain-specific,
and per-automation-project.

## Memory Hierarchy

```
.pi/memory/
|
+-- MEMORY.md                              # Index (always loaded, <200 lines)
|
+-- company/                               # Company-wide knowledge
|   +-- icp.md                             # Ideal customer profile
|   +-- service-areas.md                   # SoCal regions, target industries
|   +-- scoring-philosophy.md              # What makes a good bid/lead
|   +-- rejected-patterns.md               # Known false positives, always-skip
|   +-- team-preferences.md               # Working style, review norms
|
+-- procurement/                           # Procurement automation
|   +-- MEMORY.md                          # Cross-source learnings
|   +-- source-types/
|   |   +-- planetbids.md                  # PlanetBids-specific patterns
|   |   +-- sam-gov.md                     # SAM.gov quirks, NAICS insights
|   |   +-- opengov.md                     # OpenGov patterns
|   |   +-- bidnet.md                      # BidNet patterns
|   +-- regions/
|   |   +-- orange-county.md               # OC agencies, coverage gaps
|   |   +-- los-angeles.md                 # LA agencies, patterns
|   |   +-- inland-empire.md
|   |   +-- san-diego.md
|   +-- sources/                           # Per-source knowledge (grows over time)
|       +-- city-of-irvine.md              # CSS quirks, posting cadence
|       +-- ocwd.md                        # Multi-phase bid patterns
|       +-- port-of-long-beach.md          # Dual portal setup
|
+-- commercial/                            # Commercial automation
|   +-- MEMORY.md                          # Discovery patterns
|   +-- industries/
|   |   +-- water-wastewater.md
|   |   +-- industrial-controls.md
|   |   +-- municipal-it.md
|   +-- discovery/
|       +-- false-positives.md             # Companies that look right but aren't
|       +-- signal-quality.md              # What makes a good finding
|
+-- operations/                            # Operational knowledge
|   +-- org-dedup-patterns.md              # Merge gotchas, name variations
|   +-- data-quality.md                    # Known data issues
|
+-- incidents/                             # Post-mortems
|   +-- YYYY-MM-description.md
|
+-- decisions/                             # Architectural decisions
    +-- why-ash-not-ecto.md
    +-- sales-domain-sunset.md
    +-- pi-over-jido.md
```

## Loading Rules (Progressive Disclosure)

Not all memory loads at once. Pi loads memory based on task context:

| When Agent Is Doing | Memory Loaded |
|---------------------|---------------|
| Scanning bids | company/icp.md, company/rejected-patterns.md, procurement/MEMORY.md, relevant source file |
| Discovering sources | company/icp.md, company/service-areas.md, procurement/MEMORY.md, relevant region file |
| Target discovery | company/icp.md, commercial/MEMORY.md, relevant industry file |
| Code work | company/team-preferences.md, relevant decisions/ |
| Answering questions | Whatever matches the question topic |

This is managed via Pi skills. Each skill's SKILL.md tells the agent
which memory files to read for that domain.

## Token Budget

| Layer | When Loaded | Approx Tokens |
|-------|-------------|---------------|
| AGENTS.md | Every session | ~2-3K |
| Active skill | On-demand | ~1-2K per skill |
| Memory files | Context-injected | ~500-1K relevant |
| Session history | Automatic | Managed by compaction |

Compare to current state: AGENTS.md alone is 639 lines (~5K tokens)
loaded into every interaction regardless of relevance.

## Per-Automation-Project Memory

Each deployment accumulates its own operational knowledge:

### Deployment Sessions

```
~/.pi/agent/sessions/
+-- deployments/
|   +-- socal-source-discovery/
|   |   +-- 2026-04-22T09-00.jsonl        # Today's 9am run
|   |   +-- 2026-04-21T09-00.jsonl        # Yesterday's run
|   +-- socal-bid-scanner/
|   |   +-- 2026-04-22T06-00.jsonl
|   |   +-- 2026-04-22T12-00.jsonl
|   +-- commercial-target-discovery/
|       +-- 2026-04-22-manual.jsonl
+-- interactive/                           # Human CLI sessions
    +-- default/
```

### What Each Deployment Learns

**SoCal Source Discovery** (`agents.source_discovery.socal`):
- Which cities/districts have been checked
- Which portal types each agency uses
- Geographic coverage gaps
- Sources that returned errors or moved

**SoCal Bid Scanner** (`agents.bid_scanner.socal`):
- Keyword patterns that always get rejected
- Sources with unusual posting cadences
- False positive patterns per source type
- Score distribution trends

**Commercial Target Discovery** (`agents.target_discovery.commercial`):
- Company name patterns that are false positives
- Industry segments with highest conversion
- LinkedIn URL reliability patterns

### Namespace Mapping (Jido -> Pi)

Current Jido memory namespaces map to Pi memory directories:

| Jido Namespace | Pi Memory Path |
|---|---|
| `agents.source_discovery.socal` | `.pi/memory/procurement/regions/` |
| `agents.bid_scanner.socal` | `.pi/memory/procurement/` |
| `agents.target_discovery.commercial` | `.pi/memory/commercial/discovery/` |
| `global` | `.pi/memory/company/` |

## Ash Memory Resource: Still Useful

The existing `Agents.Memory` Ash resource (Postgres) stays for ephemeral
runtime facts that are too granular for markdown files:

- "Scanned source X at 14:32, found 3 new bids" (operational checkpoint)
- "Source Y returned 403, skip for this cycle" (transient state)
- "Run #abc already processed pages 1-3" (resumption checkpoint)

Durable learnings graduate from Postgres to Pi's file memory after validation.

## Maintenance

### Human Curation

Research shows LLM-generated context files reduce task success by ~3% and
increase inference cost by 20%+. Memory should be human-curated:

- Review agent-written memories weekly
- Delete stale entries (sources that no longer exist, patterns that changed)
- Consolidate duplicate observations into concise rules
- Keep each file under 150 lines

### Version Control

All `.pi/memory/` files are committed to Git:
- Changes are reviewable in PRs
- History shows how knowledge evolved
- Can revert if an agent writes bad memories
- Branching allows experimental memory changes

### Growth Strategy

Start simple, add complexity only when needed:

1. **Now**: Basic text search (grep) — sufficient under 1,000 files
2. **Later**: BM25 full-text search if memory grows past 1,000 entries
3. **Much later**: Hybrid vector+BM25 if semantic search becomes necessary

Don't build a RAG pipeline until you actually need one.
