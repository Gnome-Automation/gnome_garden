# AshLua and AshAI interaction patterns

Date: 2026-06-12
Status: design guidance for future agent/exploration work

## Purpose

AshLua and AshAI should be the default pattern for GnomeGarden's agent-assisted exploration work: vendors, leads, procurement sources, catalog enrichment, quote extraction, and operator review packets.

The goal is not to expose every internal action to an LLM. The goal is to give each workflow a small, documented, tenant-aware Lua surface that composes selected Ash actions safely.

## Core pattern

AshLua's recommended AshAI integration is one resource per agent surface using `AshLua.EvalActions`.

Each surface exposes two generic actions:

- `docs` — lets the LLM discover the available Lua/Ash surface
- `eval` — runs a Lua script against only that scoped surface

Then `AshAi` exposes those two actions as MCP tools.

```text
User/operator request
  -> LLM asks docs/search what it can do
  -> LLM fetches focused docs for relevant actions/types
  -> LLM writes Lua composition
  -> AshLua eval runs with current actor/tenant/context
  -> Lua calls only scoped Ash actions
  -> Ash actions enforce policies/validations/state transitions
  -> result is summarized for user or saved as reviewable evidence
```

This pattern is better than one tool per action for multi-step questions because the LLM composes inside Lua in one round trip while Ash still owns authorization and data integrity.

## Design rules

- Create one Lua/AshAI surface per workflow or risk boundary.
- Expose read-only surfaces first; add write actions only when the workflow has review/approval semantics.
- Use `docs` and `eval` as the main LLM tools, not a giant unrestricted catalog of direct action tools.
- Keep destructive actions out of Lua surfaces unless they are workflow-specific, policy-guarded, and audited.
- Every `eval` must run with actor, tenant, and context from the current Ash scope.
- Lua can coordinate and branch; persisted mutations must happen through intent-named Ash actions.
- Agent-discovered facts should include source URL, captured_at, confidence, review_status, and stale_after context.
- Prefer returning structured maps/lists from Lua, not prose. Let the LLM produce prose from structured results.
- Put browser/network access behind explicit Ash actions or tool functions; do not give Lua raw filesystem/network access.

## Surface naming convention

Use small resources under `GnomeGarden.Agents.Surfaces` or similar:

```text
GnomeGarden.Agents.Surfaces.LeadDiscovery
GnomeGarden.Agents.Surfaces.ProcurementSourceResearch
GnomeGarden.Agents.Surfaces.VendorResearch
GnomeGarden.Agents.Surfaces.CatalogEnrichment
GnomeGarden.Agents.Surfaces.SupplierQuoteExtraction
GnomeGarden.Agents.Surfaces.PlantServiceAssistant
```

Expose tools with names like:

```text
lead_discovery_docs
lead_discovery_eval
procurement_source_docs
procurement_source_eval
vendor_research_docs
vendor_research_eval
catalog_enrichment_docs
catalog_enrichment_eval
supplier_quote_docs
supplier_quote_eval
plant_service_docs
plant_service_eval
```

## Example resource shape

Conceptual shape for one surface:

```elixir
defmodule GnomeGarden.Agents.Surfaces.VendorResearch do
  use Ash.Resource,
    domain: GnomeGarden.Agents,
    extensions: [AshLua.EvalActions]

  eval_actions do
    docs_action_name :docs
    eval_action_name :eval

    resource GnomeGarden.Operations.Organization,
      actions: [:read, :by_website_domain]

    resource GnomeGarden.Commercial.DiscoveryRecord,
      actions: [:read, :create_prospect, :resolve_identity]

    resource GnomeGarden.Agents.AgentRunOutput,
      actions: [:create]
  end
end
```

Then in `GnomeGarden.Agents`:

```elixir
tools do
  tool :vendor_research_docs, GnomeGarden.Agents.Surfaces.VendorResearch, :docs
  tool :vendor_research_eval, GnomeGarden.Agents.Surfaces.VendorResearch, :eval
end
```

Exact resource/action lists should be decided per workflow. The key is that `eval_actions` is the source of truth for what the LLM can call.

## Interaction pattern 1: lead discovery triage

Purpose: evaluate candidate private-company leads and turn good candidates into reviewable discovery records/signals.

Surface should include:

- read company profile and ICP criteria
- read existing organizations/discovery records/signals to dedupe
- create discovery records or candidate findings
- create agent run output/evidence
- maybe promote to signal only through a separate review action, not direct LLM write

Example Lua result shape:

```lua
local existing = assert(operations.organization.read({
  filter = { website_domain = candidate.website_domain },
  limit = 1,
  fields = { "id", "name", "relationship_roles" }
}))

if #existing > 0 then
  return { ok = true, mode = "duplicate", organization_id = existing[1].id }
end

local record = assert(commercial.discovery_record.create_prospect({
  company_name = candidate.company_name,
  website = candidate.website,
  source_url = candidate.source_url,
  evidence_summary = candidate.evidence_summary,
  confidence = candidate.confidence
}))

return { ok = true, mode = "created_discovery_record", id = record.id }
```

Recommended guardrails:

- LLM can create discovery records, not active pursuits, unless reviewed.
- Deduplication reads should be exposed and documented.
- Promotion to signal/pursuit should require operator review or a narrow high-confidence action.

## Interaction pattern 2: procurement source inspection

Purpose: inspect public bid/procurement sources, classify access requirements, and recommend setup/scan actions.

Surface should include:

- read procurement source
- update source inspection/configuration status through explicit actions
- create crawl runs/pages/artifacts only through pipeline actions
- read source credentials status markers, not secrets
- create review outputs

Current repo already has a bounded procurement `SourcePipeline` and `procurement_source_inspection` workflow runner. Future work should move more of this into published `AgentWorkflowDefinition` records and the `docs`/`eval` AshLua-EvalActions pattern.

Recommended Lua modes:

```text
inspected
credentials_needed
page_unavailable
blocked_by_terms
ready_for_scan
scan_completed
scan_failed
```

Guardrails:

- No credential values in Lua context.
- Lua receives credential status only: missing/configured/blocked/expired.
- Any login/test action must be an explicit Ash action/tool with audit output.

## Interaction pattern 3: vendor/distributor research

Purpose: research vendors, distributors, and manufacturers, enrich organization records, and identify sourcing relevance.

Surface should include:

- read/create/update organizations through controlled actions
- read organization affiliations/contacts where appropriate
- create discovery evidence or research output records
- lookup existing vendor roles and website domains
- later: create `VendorOffer` candidates only as reviewable records

Example questions this surface should answer:

- Is this company a manufacturer, distributor, installer, or service partner?
- Does it sell automation-relevant parts or services?
- Which brands/product categories does it carry?
- What region does it cover?
- Is it worth adding as a preferred vendor candidate?

Recommended output shape:

```json
{
  "organization": {"name": "...", "website_domain": "..."},
  "roles": ["distributor", "vendor"],
  "covered_categories": ["VFD", "PLC", "pump"],
  "covered_regions": ["Southern California"],
  "recommended_action": "create_vendor_candidate",
  "confidence": "medium",
  "sources": [{"url": "...", "evidence": "..."}]
}
```

Guardrails:

- Do not let the LLM directly mark vendors preferred.
- Preferred vendor status should be a human-reviewed action with criteria.
- Keep researched facts distinct from approved master data.

## Interaction pattern 4: supplier catalog enrichment

Purpose: turn distributor pages, manufacturer pages, CSVs, and datasheets into canonical part/offer/price candidates.

Surface should include future actions around:

- `CatalogPart` read/create candidate/upsert by manufacturer + MPN
- `PartIdentifier` read/create
- `VendorOffer` read/create candidate/upsert by vendor + SKU
- `VendorOfferPrice` record price observation
- `SupplierQuote`/`SupplierQuoteLine` read/create candidate
- AshStorage attachment/document lookup for datasheets

Recommended Lua phases:

```text
normalize_identifiers
match_existing_part
create_or_update_part_candidate
create_or_update_vendor_offer_candidate
record_price_observation
return_review_packet
```

Guardrails:

- Price observations are append-only evidence.
- Public/list/web/quoted prices must remain separate.
- Canonical part changes should be conservative and dedupe by manufacturer + MPN.
- Human review required before merging uncertain duplicate parts.

## Interaction pattern 5: supplier quote/document extraction

Purpose: extract structured quote lines from PDFs, emails, portal pages, or screenshots.

Surface should include:

- read supplier quote and attached documents through AshStorage-backed host resources
- create quote line candidates
- record extracted identifiers, prices, lead time, expiration, freight/tax, and source confidence
- link candidate lines to known parts/offers when confidence is high

Recommended result shape:

```json
{
  "quote_number": "Q-12345",
  "vendor": "Local Distributor",
  "received_at": "2026-06-12",
  "expires_at": "2026-06-19",
  "currency_code": "USD",
  "lines": [
    {
      "line_number": "1",
      "manufacturer_part_number": "...",
      "vendor_sku": "...",
      "description": "...",
      "quantity": "2",
      "unit_price": "1180.00",
      "lead_time_days": 3,
      "confidence": "high"
    }
  ]
}
```

Guardrails:

- Quote extraction creates draft/candidate quote lines, not approved purchasing commitments.
- Always snapshot vendor/manufacturer identifiers from the document.
- Attach the source document via AshStorage and keep extraction provenance.

## Interaction pattern 6: plant service assistant

Purpose: help a technician or operator answer questions while scoped to a customer/plant tenant.

Surface should include tenant-scoped read actions for:

- sites/plants
- managed systems
- assets
- work orders
- material usage
- maintenance plans
- tenant-visible documents/photos/manuals

It may also include global read actions for:

- catalog parts
- public datasheets/manuals
- compatible replacements
- vendor offers

Example questions:

- What assets at this plant have open work orders?
- Which VFD was replaced last time?
- What parts have we used on this pump before?
- Are there known compatible replacements?
- Which documents/photos are attached to this asset?

Guardrails:

- Always run with current tenant scope.
- Tenant-private records must not leak across customer accounts.
- Global catalog lookup is allowed, but tenant-private work order/asset lookup is scoped.

## Interaction pattern 7: job costing and margin assistant

Purpose: answer internal Gnome questions about project/work-order profitability.

Surface should include Gnome-only actions/calculations around:

- time entries
- expenses
- material usage
- invoices/invoice lines
- future vendor bills
- proposals and agreements

Example questions:

- What is the unbilled cost on this work order?
- Which projects are margin-negative?
- Which expenses are approved but not billed?
- Which supplier quotes are driving estimate variance?

Guardrails:

- Customer users should not see internal margin/cost unless explicitly allowed.
- Use field policies or separate Gnome-only surfaces for cost/margin actions.
- Return structured numbers; let the LLM explain.

## Interaction pattern 8: memory and learning review

Purpose: let agents propose updates to durable memory, company profile, source rules, and vendor knowledge without silent self-modification.

Surface should include:

- read active memory blocks by scope
- recall memory entries by scope
- create learning recommendations
- create memory proposal records
- mark recommendations reviewed/accepted/rejected only through human/operator actions

Guardrails:

- Agents propose memory changes; humans or strict policy actions approve.
- Read-only memory blocks should not be mutated through Lua.
- Memory updates must include source and reason.

## Direct tools versus Lua eval

Use direct AshAI tools when the operation is simple and single-step:

- create a task
- get one record
- update a status through one action
- start one scan

Use AshLua docs/eval when the operation is compositional:

- search several sources and dedupe
- compute aggregate summaries
- compare vendors/prices/lead times
- prepare a review packet
- run a multi-step inspection workflow
- transform many candidate rows into normalized action inputs

Both should coexist.

## Workflow definition integration

For repeatable workflows, store Lua scripts in `AgentWorkflowDefinition` instead of hardcoding all scripts.

A workflow definition should specify:

- key
- version
- Lua source
- input schema
- output schema
- allowed domains/actions/tools
- risk level
- review requirements
- owner
- status: draft/validated/published/disabled/archived

Execution should create an `AgentRun`, attach memory/context, run the published Lua script, record structured output, and then either complete, fail, or create review tasks.

## Proposed build phases

### Phase 1: Documented surfaces

- Add explicit EvalActions resources for one read-only surface.
- Wire two AshAI tools: docs/eval.
- Start with procurement source or commercial discovery because current code already has the pattern.

### Phase 2: Vendor research surface

- Add read/dedupe/create-candidate actions for organizations and discovery evidence.
- Return vendor research packets as structured output.
- Require human review before preferred-vendor or master-data promotion.

### Phase 3: Catalog enrichment surface

- Add catalog/offer/price candidate resources or actions.
- Allow Lua to match and propose; require review for uncertain merges.

### Phase 4: Document extraction surface

- Use AshStorage attachments as source documents.
- Extract quote lines/datasheet facts into draft/candidate resources.

### Phase 5: Tenant-aware plant assistant

- Add plant/work-order/asset read-only Lua surface with tenant scope.
- Add customer-safe and Gnome-internal variants as separate surfaces.

## Open questions

- Should surfaces live under `GnomeGarden.Agents.Surfaces` or each business domain?
- Should all Lua evals require an `AgentRun`, or can ad hoc console evals exist in dev/admin mode?
- Which actions are safe enough for write access without operator review?
- How should token/cost limits be enforced per workflow?
- Should Lua scripts be stored only in `AgentWorkflowDefinition`, or can resource-owned scripts exist for user-configurable dashboards later?
- How should AshStorage document access be exposed to Lua without leaking raw storage keys?
