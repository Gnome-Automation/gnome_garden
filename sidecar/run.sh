#!/bin/bash
# Pi Discovery System for Gnome Automation
#
# Usage:
#   ./run.sh scan      — scan all sources for bids
#   ./run.sh discover  — find new procurement portals
#   ./run.sh hunt      — find commercial targets

set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"

# Load env from parent .env
if [ -f ../.env ]; then
  set -a
  source ../.env
  set +a
fi

if [ -z "${ZAI_API_KEY:-}" ]; then
  echo "Error: ZAI_API_KEY not set. Add it to ../.env"
  exit 1
fi

# Unset Brave to ensure it's never used
unset BRAVE_API_KEY

# Map mode to skill file and prompt
case "$MODE" in
  scan)
    SKILL="skills/scan-bids.md"
    PROMPT="Read sources.json and seen.json. Scan every source for SCADA, PLC, controls, and automation bids. Skip URLs already in seen.json. Score and write qualifying findings to discoveries/bids/. Update seen.json after each finding."
    ;;
  discover)
    SKILL="skills/discover-sources.md"
    PROMPT="Read sources.json to see what's already tracked. Search for new procurement portals across all target regions (Orange County, Los Angeles, Inland Empire, San Diego) and all target agency types (water districts, sanitation districts, municipal utilities, county public works, port authorities, school districts). Work through each region and agency type systematically. Add new sources to sources.json and write findings to discoveries/sources/."
    ;;
  hunt)
    SKILL="skills/discover-targets.md"
    PROMPT="Read seen.json to avoid duplicates. You have a large search budget — use it all. Work through EVERY phase in the skill file systematically:

Phase 1: Check all known prospects for fresh signals (hiring, expansion, legacy pain).
Phase 2: Mine industry directories — ThomasNet, Brewers Association, SQF sites, BIOCOM, PMMI, ACWA.
Phase 3: Search job boards for companies hiring controls/automation engineers in SoCal.
Phase 4: Check partner networks — Rockwell, Ignition integrator lists.
Phase 5: Scan trade pubs for facility announcements and project news.
Phase 6: General web searches across all industry × region combos.

Use the browser tool (node browse.mjs) to read company websites and verify details. Use Brave for discovery searches. After finishing all 6 phases, review your findings — which industries had gaps? Search deeper there. Follow threads — one company points to competitors, suppliers, partners. Keep going until you've thoroughly covered every industry and region. Write findings to discoveries/targets/."
    ;;
  *)
    echo "Usage: ./run.sh <scan|discover|hunt>"
    echo ""
    echo "  scan      Scan all known sources for bids"
    echo "  discover  Find new procurement portals to monitor"
    echo "  hunt      Find commercial targets matching Gnome's ICP"
    exit 1
    ;;
esac

echo "=== Pi Discovery: $MODE ==="
echo "Provider: zai / glm-5"
echo "=========================="
echo ""

xvfb-run --auto-servernum npm exec -- pi \
  --offline \
  --provider zai \
  --model glm-5 \
  --append-system-prompt "$SKILL" \
  -p "$PROMPT"
