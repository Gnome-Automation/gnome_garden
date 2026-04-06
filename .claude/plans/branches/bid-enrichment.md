# Branch: feature/bid-enrichment

## Goal
After the DeterministicScanner saves a bid from the listing page, enrich it by visiting the detail URL to scrape description, bid type, due date, and scope of work. No LLM needed — just a second browser navigation + targeted JS extract per bid.

## Problem
Currently bids have empty descriptions because the scanner only scrapes the listing table. The detail page has rich data:
- Full description / scope of work
- Bid type (RFP, RFQ, RFQual, IFB)
- Precise due date with time
- Categories
- Response format
- Contact info

Example: IEUA Cybersecurity bid detail page has "The Inland Empire Utilities Agency seeks proposals for As-Needed Cybersecurity Services..." but the listing only shows the title.

## Approach

### 1. Add enrichment step to DeterministicScanner
After `save_qualifying_bids`, add `enrich_saved_bids` that visits each newly saved bid's URL and extracts detail data.

**File:** `lib/garden/agents/deterministic_scanner.ex`

```elixir
defp enrich_saved_bids(saved_bids) do
  Enum.each(saved_bids, fn bid_result ->
    if bid_result.url && String.contains?(bid_result.url, "bo-detail") do
      enrich_planetbids(bid_result)
    end
  end)
end
```

### 2. PlanetBids detail page extraction
Navigate to the bid URL, wait for load, extract:
```javascript
(function() {
  const text = document.body.innerText;
  const lines = text.split('\n').filter(l => l.trim());
  
  // Find description section
  const descIdx = lines.findIndex(l => l.match(/description|synopsis|scope/i));
  const desc = descIdx > -1 ? lines.slice(descIdx + 1, descIdx + 5).join(' ') : '';
  
  // Find bid type
  const typeIdx = lines.findIndex(l => l.match(/project type/i));
  const bidType = typeIdx > -1 ? lines[typeIdx + 1]?.trim() : '';
  
  // Find due date
  const dueIdx = lines.findIndex(l => l.match(/bid due date/i));
  const dueDate = dueIdx > -1 ? lines[dueIdx + 1]?.trim() : '';
  
  return { description: desc, bid_type: bidType, due_date: dueDate };
})()
```

### 3. Update Bid resource
The `update` action needs to accept `:description` and `:bid_type` for enrichment.

**File:** `lib/garden/agents/bid.ex` — update the `:update` action's accept list.

### 4. Add enrichment for OCWD/utility sites
Different extraction logic for non-PlanetBids sites. OCWD has descriptions inline on the page.

### 5. Rate limiting
Don't hammer portals — add a `Process.sleep(1000)` between detail page visits. Consider running enrichment as a background task separate from the main scan.

## Key Files
- `lib/garden/agents/deterministic_scanner.ex` — main scanner, add enrichment step
- `lib/garden/agents/bid.ex` — update action accept list
- `lib/garden/agents/tools/browser/navigate.ex` — browser navigation
- `lib/garden/agents/tools/browser/extract.ex` — JS extraction

## Testing
1. Run `DeterministicScanner.scan(source_id)` on a PlanetBids source
2. Check that saved bids now have descriptions populated
3. Verify bid cards in review queue show the description
4. Verify bid detail page shows the description
5. Test with OCWD (non-PlanetBids) source
