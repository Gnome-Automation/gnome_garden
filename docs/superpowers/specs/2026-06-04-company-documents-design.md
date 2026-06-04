# Company Documents Design

## Goal

Build a Company Documents system that stores internal business documents (starting with the W9), supports version control and search, and lets staff send any document to a client via email with a send log for tracking.

## Architecture

New `GnomeGarden.Documents` Ash domain with two resources: `CompanyDocument` and `DocumentSendLog`. LiveView at `/documents` with inline modals for send, bulk send, and version history. Swoosh email with PDF attachment. Send button also exposed on the org show page (pre-fills recipient email). No file upload in this phase — file paths are stored as static paths under `priv/static/documents/`.

## Tech Stack

Elixir/Phoenix, Ash Framework 3.x, AshPostgres, LiveView, Swoosh (PDF attachment via `Swoosh.Attachment`), Tailwind/DaisyUI, Oban (for bulk send jobs).

---

## Data Model

### `GnomeGarden.Documents.CompanyDocument`

Table: `company_documents`

| Field | Type | Notes |
|---|---|---|
| id | uuid | PK |
| name | string | e.g. "W9 Form" |
| description | string, nullable | Short description |
| category | atom | `:tax`, `:legal`, `:compliance`, `:hr`, `:other` |
| version | string | e.g. "1.0", "2025" |
| file_path | string | Relative to `priv/static/`, e.g. `documents/w9-gnome-automation-signed.pdf` |
| status | atom | `:active`, `:superseded`, `:expired` |
| expiry_date | date, nullable | Optional — for certs/insurance that go stale |
| supersedes_id | uuid, nullable | FK to previous CompanyDocument version |
| inserted_at, updated_at | timestamps | |

Actions: `:create`, `:read`, `:update`, `:destroy`, `:list_active` (filter status == :active), `:list_all` (no filter).

### `GnomeGarden.Documents.DocumentSendLog`

Table: `document_send_logs`

| Field | Type | Notes |
|---|---|---|
| id | uuid | PK |
| company_document_id | uuid | FK to CompanyDocument |
| organization_id | uuid, nullable | FK to Organization — nil if sent to ad-hoc email |
| sent_to_email | string | Actual recipient email address |
| sent_by_user_id | uuid | FK to User (the staff user who sent it) |
| message | string, nullable | Optional message body included in email |
| sent_at | utc_datetime | When the email was dispatched |
| inserted_at, updated_at | timestamps | |

Actions: `:create`, `:read`, `:list_by_document` (filter by company_document_id).

### `GnomeGarden.Documents` domain

Code interface defines:
- `list_active_documents/0`
- `list_all_documents/0`
- `get_document!/1`
- `create_document/1`
- `update_document/2`
- `log_send/1`
- `list_send_logs/0`

---

## Seeding

`priv/repo/seeds.exs` seeds the W9 on first run (upsert by name + version):

```elixir
GnomeGarden.Documents.create_document(%{
  name: "W9 Form",
  description: "IRS Form W-9 — Request for Taxpayer Identification Number",
  category: :tax,
  version: "2024",
  file_path: "documents/w9-gnome-automation-signed.pdf",
  status: :active
})
```

---

## Mailer

`GnomeGarden.Mailer.DocumentEmail`

```
build(document, to_email, opts \\ [])
  opts: message: string, org_name: string
```

- From: `{"Gnome Automation", "billing@gnomeautomation.io"}`
- Subject: `"Gnome Automation — #{document.name}"`
- HTML body: branded header, greeting, optional message, PDF note
- Attachment: `Swoosh.Attachment` pointing to `Path.join(Application.app_dir(:gnome_garden, "priv/static"), document.file_path)`
- After send: calls `Documents.log_send/1` to write a `DocumentSendLog` record

---

## Routes

```
/finance/documents               DocumentsLive.Index  :index
/finance/documents/new           DocumentsLive.Form   :new   (stub — file upload not wired yet)
/finance/documents/:id/edit      DocumentsLive.Form   :edit
```

Routes live under `/finance/` to stay consistent with the existing Finance section in the sidebar nav. No separate show page — all interaction (send, version history, send log) is modal-based on the index page.

---

## Documents Index LiveView (`/documents`)

### Table (active docs only by default)

Columns: Name, Category badge, Version, Status badge, Expiry date, Actions

Actions per row:
- **Download** — `<a href={~p"/priv/static/#{doc.file_path}"} download>` (served as static file via Plug.Static; alternatively a controller endpoint)
- **Send** — opens send modal pre-filled with this document
- **History** — opens version history modal for this document's lineage

### Controls above table

- Search input (live filter by name, client-side `phx-keyup`)
- Category filter dropdown
- "Show all versions" toggle (switches between `:list_active_documents` and `:list_all_documents`)
- Bulk select column + "Send Selected (N)" button when any docs checked

### Send Modal

Fields:
- Document: dropdown (pre-selected if opened from row), shows name + version
- To: text input (pre-filled from org billing email if triggered from org page, else blank)
- Subject: text input (pre-filled `"Gnome Automation — #{doc.name}"`, editable)
- Message: optional textarea
- Send button → calls `DocumentEmail.build/3 |> Mailer.deliver()` → writes `DocumentSendLog`
- On success: flash "Document sent to {email}", modal closes, send log refreshes

### Bulk Send Modal

Opened when "Send Selected (N)" clicked.

Fields:
- Selected Documents: read-only list of checked docs with names + versions
- Recipients: searchable multi-select of organizations (loads from `Operations.list_organizations`)
- Subject: pre-filled, editable
- Message: optional textarea
- Send button → enqueues one `DocumentSendWorker` Oban job per (document × org) pair
  - Worker: fetches org billing email, calls `DocumentEmail.build`, delivers, logs send
  - Queue: `:default`, no uniqueness constraint
- On submit: flash "Sending to N organizations", modal closes

### Version History Modal

Opened from History button on any row.

Shows: version, date added (inserted_at), status badge, current/superseded label, file_path (for reference), expiry_date if set.

"Upload New Version" button → links to `/documents/:id/edit` (stub for now — just shows the form; actual upload wiring is future work).

### Send Log Section

Tab or section below the main table (toggle button "Show Send Log").

Table columns: Date Sent, Document, Version, Sent To, Org, Sent By
Filters: date range pickers (from/to), document dropdown
Sorted: newest first, limit 100

---

## Org Show Page Integration

On `OrganizationLive.Show`, add a "Send Document" button in the actions area or contact section.

Clicking it navigates to `/documents` with a query param `?org_id={org.id}&email={billing_email}` (or uses a JS redirect to open the send modal directly).

Simpler approach: just navigate to `/documents` and let the user pick — but this loses the pre-fill. Better: mount the send modal on the org show page directly (copy the modal component, populate assigns from org, handle `send_document` event inline on that LiveView). This keeps UX tight without cross-LiveView communication.

**Decision: duplicate send modal on org show page.** Same fields, same mailer call, same log write. No shared component needed — just copy the template block.

---

## Download

Static files under `priv/static/documents/` are served by Plug.Static (already configured for `priv/static`). Download link:

```elixir
"/#{document.file_path}"  # e.g. "/documents/w9-gnome-automation-signed.pdf"
```

Use `download` HTML attribute + `target="_blank"`. No controller needed.

---

## Version Control Flow

When uploading a new version of an existing doc (future):
1. Create new `CompanyDocument` with `supersedes_id = old_doc.id`
2. Update old doc's `status` to `:superseded`
3. Only the new doc has `status: :active`

The version history modal walks the `supersedes_id` chain to show full history.

---

## Testing Plan

- `test/garden/documents/company_document_test.exs`: create, list_active, list_all, seeds
- `test/garden/documents/document_send_log_test.exs`: create log, list by document
- `test/garden/mailer/document_email_test.exs`: builds email with correct subject, to, attachment filename
- `test/garden_web/live/documents/documents_live_test.exs`: renders table, search filters, send modal submit creates log + flash, bulk send enqueues jobs

---

## Out of Scope

- Actual file upload wiring (stub UI only — `file_path` set manually or via seeds)
- Client portal access to documents
- Download tracking (we log sends, not views)
- Email open/click tracking
- Document expiry notifications (no worker for now)
- Role-based access to documents
