# Branch: feature/document-pipeline

## Goal
Enable document uploads on bids and opportunities, store in S3-compatible storage (Garage), and use LLM agents to analyze bid documents (PDFs) to extract requirements and suggest next steps.

## Prerequisites
- `feature/review-queue-ux-polish` merged (pursue flow working)
- `feature/bid-enrichment` merged (nice to have, not blocking)

## Architecture

### 1. S3/Garage Storage Setup

**Dev:** Local Garage instance via Docker
```yaml
# docker-compose.yml addition
garage:
  image: dxflrs/garage:v1.0.1
  ports:
    - "3900:3900"  # S3 API
    - "3902:3902"  # Admin API
  volumes:
    - garage_data:/var/lib/garage
  environment:
    - GARAGE_ALLOW_WORLD_READABLE_BUCKETS=true
```

**Prod:** Garage on fly.io or dedicated server, separate bucket namespace.

**Config:**
```elixir
# config/dev.exs
config :gnome_garden, :storage,
  bucket: "gnome-garden-dev",
  endpoint: "http://localhost:3900",
  access_key_id: "...",
  secret_access_key: "..."

# config/runtime.exs
config :gnome_garden, :storage,
  bucket: System.get_env("S3_BUCKET"),
  endpoint: System.get_env("S3_ENDPOINT"),
  access_key_id: System.get_env("S3_ACCESS_KEY"),
  secret_access_key: System.get_env("S3_SECRET_KEY")
```

### 2. Sales.Document Resource

```elixir
defmodule GnomeGarden.Sales.Document do
  # Polymorphic — links to bids, opportunities, companies
  attributes do
    uuid_primary_key :id
    attribute :filename, :string, allow_nil?: false
    attribute :content_type, :string
    attribute :size_bytes, :integer
    attribute :s3_key, :string, allow_nil?: false
    attribute :document_type, :atom  # :rfp, :rfi, :proposal, :contract, :spec, :other
    attribute :subject_type, :string  # "bid", "opportunity", "company"
    attribute :subject_id, :uuid
    attribute :analysis, :map  # LLM-extracted data
    attribute :analyzed_at, :utc_datetime
    timestamps()
  end
end
```

### 3. LiveView File Upload
Use Phoenix LiveView's built-in upload support with S3 external upload.

**On Opportunity show page and Bid detail page:**
- Drop zone or file picker
- Upload to S3 via presigned URL
- Create Document record linking to the entity
- Show uploaded documents in a section

**Reference:** https://hexdocs.pm/phoenix_live_view/uploads-external.html

### 4. LLM Document Analysis
After a PDF is uploaded to a bid:
1. Download from S3
2. Extract text (use a PDF parser or send to LLM directly)
3. Agent analyzes and extracts:
   - Requirements list
   - Scope of work summary
   - Timeline / due dates
   - Minimum qualifications
   - Evaluation criteria
   - Key contacts
4. Save structured data to `Document.analysis` field
5. Surface on the opportunity page as actionable items

### 5. Domain Namespace
```
dev:  dev.docs.gnomegarden.local / localhost:3900
prod: docs.gnomegarden.io (or use path-based: s3.gnomegarden.io/docs/)
```

Bucket structure: `{env}/documents/{subject_type}/{subject_id}/{uuid}/{filename}`

## Key Files to Create
- `lib/garden/sales/document.ex` — Document resource
- `lib/garden/storage.ex` — S3 client wrapper (upload, download, presign)
- `lib/garden_web/live/crm/opportunity_live/show.ex` — add upload section
- `lib/garden_web/live/agents/sales/bid_live/show.ex` — add upload section
- `lib/garden/agents/workers/document_analyzer.ex` — LLM analysis worker

## Dependencies to Add
- `ex_aws` + `ex_aws_s3` — S3 client
- Or `req` with S3 signing — lighter weight

## Testing
1. Start Garage via docker-compose
2. Upload a PDF on a bid page
3. Verify file appears in S3 bucket
4. Verify Document record created and linked
5. Trigger LLM analysis — verify extracted data
6. Verify analysis shows on opportunity page
