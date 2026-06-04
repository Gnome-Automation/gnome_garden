# Company Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Company Documents system where staff can view, search, version-track, download, and email business documents (W9, etc.) to clients, with a full send log.

**Architecture:** New `GnomeGarden.Documents` Ash domain with `CompanyDocument` and `DocumentSendLog` resources. Single Documents LiveView at `/finance/documents` with inline modals for send, bulk send, and version history. Swoosh email with PDF attachment. Send button duplicated on org show page for quick access. W9 PDF already at `priv/static/documents/w9-gnome-automation-signed.pdf`.

**Tech Stack:** Elixir/Phoenix LiveView, Ash Framework 3.x, AshPostgres, Swoosh (PDF attachment), Oban (bulk send worker), Tailwind/DaisyUI.

---

## File Map

**New files:**
- `lib/garden/documents.ex` — GnomeGarden.Documents Ash domain + code interface
- `lib/garden/documents/company_document.ex` — CompanyDocument Ash resource
- `lib/garden/documents/document_send_log.ex` — DocumentSendLog Ash resource
- `lib/garden/mailer/document_email.ex` — Swoosh email builder with PDF attachment
- `lib/garden/documents/document_send_worker.ex` — Oban worker for bulk send jobs
- `lib/garden_web/live/documents/documents_live.ex` — LiveView: table, search, modals, send log
- `test/garden/documents/company_document_test.exs`
- `test/garden/documents/document_send_log_test.exs`
- `test/garden/mailer/document_email_test.exs`
- `test/garden_web/live/documents/documents_live_test.exs`

**Modified files:**
- `config/config.exs` — add `GnomeGarden.Documents` to ash_domains list
- `lib/garden_web/router.ex` — add `/finance/documents` routes
- `lib/garden_web/components/rail_nav.ex` — add "Documents" nav item under Finance section
- `lib/garden_web/live/operations/organization_live/show.ex` — add "Send Document" button + inline modal
- `priv/repo/seeds.exs` — seed W9 CompanyDocument

---

## Codebase Context

Key patterns used throughout:
- Ash resources: `use Ash.Resource, otp_app: :gnome_garden, domain: GnomeGarden.X, data_layer: AshPostgres.DataLayer`
- Domain code interface: `define :fn_name, action: :action_name` inside `resources do resource X do ... end end`
- Migration: write Ash resources → run `mix ash.codegen <name>` (generates both snapshot + migration) → run `mix ecto.migrate`
- Mailer: `import Swoosh.Email`, `new() |> from(...) |> to(...) |> subject(...) |> html_body(...) |> attachment(path)`, deliver with `GnomeGarden.Mailer.deliver(email)`
- Tests: `use GnomeGarden.DataCase, async: false` for DB tests, `use GnomeGardenWeb.ConnCase, async: true` + `import Phoenix.LiveViewTest` for LiveView tests
- LiveView test auth: `setup :register_and_log_in_user`
- LiveView flash: check with `assert html =~ "some text"` after action
- Policies: `bypass always() do authorize_if always() end` is standard for internal resources

---

## Task 1: CompanyDocument + DocumentSendLog Ash resources

**Files:**
- Create: `lib/garden/documents/company_document.ex`
- Create: `lib/garden/documents/document_send_log.ex`
- Create: `lib/garden/documents.ex`
- Modify: `config/config.exs`
- Test: `test/garden/documents/company_document_test.exs`
- Test: `test/garden/documents/document_send_log_test.exs`

- [ ] **Step 1: Write failing tests for CompanyDocument**

Create `test/garden/documents/company_document_test.exs`:

```elixir
defmodule GnomeGarden.Documents.CompanyDocumentTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Documents

  test "creates a company document" do
    {:ok, doc} =
      Documents.create_document(%{
        name: "W9 Form",
        category: :tax,
        version: "2024",
        file_path: "documents/w9-gnome-automation-signed.pdf",
        status: :active
      })

    assert doc.name == "W9 Form"
    assert doc.category == :tax
    assert doc.version == "2024"
    assert doc.status == :active
  end

  test "lists only active documents" do
    {:ok, _} =
      Documents.create_document(%{
        name: "Active Doc",
        category: :tax,
        version: "1.0",
        file_path: "documents/test.pdf",
        status: :active
      })

    {:ok, _} =
      Documents.create_document(%{
        name: "Old Doc",
        category: :tax,
        version: "0.9",
        file_path: "documents/test.pdf",
        status: :superseded
      })

    {:ok, docs} = Documents.list_active_documents()
    names = Enum.map(docs, & &1.name)
    assert "Active Doc" in names
    refute "Old Doc" in names
  end

  test "lists all documents including superseded" do
    {:ok, _} =
      Documents.create_document(%{
        name: "Superseded Doc",
        category: :legal,
        version: "0.1",
        file_path: "documents/test.pdf",
        status: :superseded
      })

    {:ok, docs} = Documents.list_all_documents()
    names = Enum.map(docs, & &1.name)
    assert "Superseded Doc" in names
  end

  test "updates document status" do
    {:ok, doc} =
      Documents.create_document(%{
        name: "To Update",
        category: :compliance,
        version: "1.0",
        file_path: "documents/test.pdf",
        status: :active
      })

    {:ok, updated} = Documents.update_document(doc, %{status: :superseded})
    assert updated.status == :superseded
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/bhammoud/gnome_garden_mercury
mix test test/garden/documents/company_document_test.exs
```

Expected: compile error — module not found.

- [ ] **Step 3: Create the CompanyDocument resource**

Create `lib/garden/documents/company_document.ex`:

```elixir
defmodule GnomeGarden.Documents.CompanyDocument do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Documents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "company_documents"
    repo GnomeGarden.Repo
  end

  policies do
    bypass always() do
      authorize_if always()
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :description, :category, :version, :file_path, :status, :expiry_date, :supersedes_id]
    end

    update :update do
      primary? true
      accept [:name, :description, :category, :version, :file_path, :status, :expiry_date, :supersedes_id]
    end

    read :active do
      filter expr(status == :active)
      prepare build(sort: [name: :asc])
    end

    read :all_versions do
      prepare build(sort: [name: :asc, inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    attribute :category, :atom do
      allow_nil? false
      default :other
      public? true
      constraints one_of: [:tax, :legal, :compliance, :hr, :other]
    end

    attribute :version, :string do
      allow_nil? false
      default "1.0"
      public? true
    end

    attribute :file_path, :string do
      allow_nil? false
      public? true
      description "Relative path from priv/static/, e.g. documents/w9.pdf"
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :superseded, :expired]
    end

    attribute :expiry_date, :date do
      allow_nil? true
      public? true
    end

    attribute :supersedes_id, :uuid do
      allow_nil? true
      public? true
      description "UUID of the previous version this document supersedes"
    end

    timestamps()
  end
end
```

- [ ] **Step 4: Create the DocumentSendLog resource**

Create `lib/garden/documents/document_send_log.ex`:

```elixir
defmodule GnomeGarden.Documents.DocumentSendLog do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Documents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "document_send_logs"
    repo GnomeGarden.Repo

    references do
      reference :company_document, on_delete: :delete
    end
  end

  policies do
    bypass always() do
      authorize_if always()
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :company_document_id,
        :organization_id,
        :sent_to_email,
        :sent_by_user_id,
        :message,
        :sent_at
      ]
    end

    read :by_document do
      argument :document_id, :uuid, allow_nil?: false
      filter expr(company_document_id == ^arg(:document_id))
      prepare build(sort: [sent_at: :desc], load: [:company_document])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :company_document_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :organization_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :sent_to_email, :string do
      allow_nil? false
      public? true
    end

    attribute :sent_by_user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :message, :string do
      allow_nil? true
      public? true
    end

    attribute :sent_at, :utc_datetime do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :company_document, GnomeGarden.Documents.CompanyDocument do
      source_attribute :company_document_id
      define_attribute? false
      public? true
    end
  end
end
```

- [ ] **Step 5: Create the Documents domain**

Create `lib/garden/documents.ex`:

```elixir
defmodule GnomeGarden.Documents do
  use Ash.Domain,
    otp_app: :gnome_garden

  resources do
    resource GnomeGarden.Documents.CompanyDocument do
      define :list_active_documents, action: :active
      define :list_all_documents, action: :all_versions
      define :get_document, action: :read, get_by: [:id]
      define :create_document, action: :create
      define :update_document, action: :update
      define :destroy_document, action: :destroy
    end

    resource GnomeGarden.Documents.DocumentSendLog do
      define :log_send, action: :create
      define :list_send_logs, action: :read
      define :list_send_logs_for_document,
        action: :by_document,
        args: [:document_id]
    end
  end
end
```

- [ ] **Step 6: Register domain in config**

Open `config/config.exs`. Find the `ash_domains:` list and add `GnomeGarden.Documents`:

```elixir
ash_domains: [
  GnomeGarden.Mercury,
  GnomeGarden.Accounts,
  GnomeGarden.Acquisition,
  GnomeGarden.Agents,
  GnomeGarden.Commercial,
  GnomeGarden.Documents,     # <-- add this line
  GnomeGarden.Execution,
  GnomeGarden.Finance,
  GnomeGarden.Operations,
  GnomeGarden.Procurement
],
```

- [ ] **Step 7: Generate migration + snapshots via ash.codegen**

```bash
cd /home/bhammoud/gnome_garden_mercury
mix ash.codegen create_company_documents
```

Expected: generates `priv/repo/migrations/TIMESTAMP_create_company_documents.exs` and two snapshot files under `priv/resource_snapshots/repo/`.

- [ ] **Step 8: Run the migration**

```bash
mix ecto.migrate
```

Expected: `== Running ... CreateCompanyDocuments == already up` (or runs it if not yet).

- [ ] **Step 9: Add DocumentSendLog test**

Create `test/garden/documents/document_send_log_test.exs`:

```elixir
defmodule GnomeGarden.Documents.DocumentSendLogTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Documents

  defp create_doc do
    {:ok, doc} =
      Documents.create_document(%{
        name: "Test Doc #{System.unique_integer([:positive])}",
        category: :tax,
        version: "1.0",
        file_path: "documents/test.pdf",
        status: :active
      })
    doc
  end

  test "logs a document send" do
    doc = create_doc()
    user_id = Ecto.UUID.generate()

    {:ok, log} =
      Documents.log_send(%{
        company_document_id: doc.id,
        sent_to_email: "client@example.com",
        sent_by_user_id: user_id
      })

    assert log.sent_to_email == "client@example.com"
    assert log.company_document_id == doc.id
    assert log.sent_at != nil
  end

  test "lists send logs for a document" do
    doc = create_doc()
    user_id = Ecto.UUID.generate()

    {:ok, _} =
      Documents.log_send(%{
        company_document_id: doc.id,
        sent_to_email: "a@example.com",
        sent_by_user_id: user_id
      })

    {:ok, _} =
      Documents.log_send(%{
        company_document_id: doc.id,
        sent_to_email: "b@example.com",
        sent_by_user_id: user_id
      })

    {:ok, logs} = Documents.list_send_logs_for_document(doc.id)
    assert length(logs) == 2
    emails = Enum.map(logs, & &1.sent_to_email)
    assert "a@example.com" in emails
    assert "b@example.com" in emails
  end
end
```

- [ ] **Step 10: Run all document resource tests**

```bash
mix test test/garden/documents/
```

Expected: all tests pass.

- [ ] **Step 11: Commit**

```bash
git add \
  lib/garden/documents.ex \
  lib/garden/documents/company_document.ex \
  lib/garden/documents/document_send_log.ex \
  config/config.exs \
  test/garden/documents/ \
  priv/repo/migrations/ \
  priv/resource_snapshots/
git commit -m "feat: add CompanyDocument and DocumentSendLog Ash resources"
```

---

## Task 2: DocumentEmail mailer with PDF attachment

**Files:**
- Create: `lib/garden/mailer/document_email.ex`
- Test: `test/garden/mailer/document_email_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/garden/mailer/document_email_test.exs`:

```elixir
defmodule GnomeGarden.Mailer.DocumentEmailTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Mailer.DocumentEmail

  defp w9_doc do
    %{
      name: "W9 Form",
      category: :tax,
      version: "2024",
      file_path: "documents/w9-gnome-automation-signed.pdf",
      status: :active,
      description: "IRS Form W-9"
    }
  end

  test "builds email with correct to, subject, and attachment" do
    email = DocumentEmail.build(w9_doc(), "client@example.com")

    assert email.to == [{"", "client@example.com"}]
    assert email.subject == "Gnome Automation — W9 Form"
    assert email.html_body =~ "W9 Form"

    attachment = List.first(email.attachments)
    assert attachment != nil
    assert attachment.content_type == "application/pdf"
    assert String.ends_with?(attachment.filename, ".pdf")
  end

  test "includes optional message in body" do
    email = DocumentEmail.build(w9_doc(), "client@example.com", message: "Please review and keep for your records.")
    assert email.html_body =~ "Please review"
  end

  test "includes org name in greeting when provided" do
    email = DocumentEmail.build(w9_doc(), "client@example.com", org_name: "Acme Corp")
    assert email.html_body =~ "Acme Corp"
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
mix test test/garden/mailer/document_email_test.exs
```

Expected: compile error.

- [ ] **Step 3: Create DocumentEmail module**

Create `lib/garden/mailer/document_email.ex`:

```elixir
defmodule GnomeGarden.Mailer.DocumentEmail do
  @moduledoc """
  Builds a branded email that delivers a company document (PDF attachment) to a client.

  Usage:
    DocumentEmail.build(document, "client@example.com")
    DocumentEmail.build(document, "client@example.com", org_name: "Acme Corp", message: "Please keep for your records.")
    |> GnomeGarden.Mailer.deliver()
  """

  import Swoosh.Email

  @logo_url "https://gnomeautomation.com/images/gnome-icon-clean-192.png"

  @spec build(map(), String.t(), keyword()) :: Swoosh.Email.t()
  def build(document, to_email, opts \\ []) do
    org_name = Keyword.get(opts, :org_name, "")
    message = Keyword.get(opts, :message, nil)
    file_path = Path.join(Application.app_dir(:gnome_garden, "priv/static"), document.file_path)
    filename = build_filename(document)

    new()
    |> from({"Gnome Automation", "billing@gnomeautomation.io"})
    |> to(to_email)
    |> subject("Gnome Automation — #{document.name}")
    |> html_body(build_html(document, org_name, message))
    |> attachment(%Swoosh.Attachment{
         path: file_path,
         filename: filename,
         content_type: "application/pdf"
       })
  end

  defp build_filename(document) do
    base = document.name |> String.replace(~r/[^a-zA-Z0-9]/, "-") |> String.trim("-")
    "Gnome-Automation-#{base}-#{document.version}.pdf"
  end

  defp build_html(document, org_name, message) do
    greeting = if org_name != "", do: "Dear #{org_name},", else: "Hello,"
    message_block =
      if message do
        "<p style=\"margin:0 0 16px;color:#1e293b;\">#{message}</p>"
      else
        ""
      end

    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="UTF-8"></head>
    <body style="margin:0;padding:0;background:#f8fafc;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background:#f8fafc;padding:40px 20px;">
        <tr><td align="center">
          <table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;border:1px solid #e2e8f0;overflow:hidden;">
            <tr>
              <td style="background:#0f172a;padding:28px 40px;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td>
                      <img src="#{@logo_url}" width="36" height="36" alt="Gnome Automation" style="display:block;border-radius:6px;">
                    </td>
                    <td style="padding-left:12px;vertical-align:middle;">
                      <p style="margin:0;font-size:18px;font-weight:700;color:#ffffff;">Gnome Automation</p>
                      <p style="margin:2px 0 0;font-size:12px;color:#94a3b8;">Document Delivery</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:32px 40px;">
                <p style="margin:0 0 16px;color:#1e293b;">#{greeting}</p>
                <p style="margin:0 0 16px;color:#1e293b;">Please find attached: <strong>#{document.name}</strong> (v#{document.version}).</p>
                #{message_block}
                <p style="margin:24px 0 0;color:#64748b;font-size:13px;">Questions? Reply to billing@gnomeautomation.io</p>
              </td>
            </tr>
          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/garden/mailer/document_email_test.exs
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/garden/mailer/document_email.ex test/garden/mailer/document_email_test.exs
git commit -m "feat: add DocumentEmail mailer with PDF attachment"
```

---

## Task 3: DocumentSendWorker (bulk send Oban job)

**Files:**
- Create: `lib/garden/documents/document_send_worker.ex`

The worker handles one (document_id, org_id) pair — bulk send enqueues N jobs, one per pair.

- [ ] **Step 1: Create the worker**

Create `lib/garden/documents/document_send_worker.ex`:

```elixir
defmodule GnomeGarden.Documents.DocumentSendWorker do
  @moduledoc """
  Oban worker that sends a company document to one organization.

  Enqueued by DocumentsLive for bulk send operations.
  Each job handles one (document_id, organization_id) pair.

  Args:
    - document_id: UUID of CompanyDocument
    - organization_id: UUID of Organization
    - sent_by_user_id: UUID of the staff user who triggered the send
    - message: optional message string (may be nil)
    - subject: optional subject override (may be nil)
  """

  use Oban.Worker, queue: :default

  alias GnomeGarden.Documents
  alias GnomeGarden.Operations
  alias GnomeGarden.Mailer.DocumentEmail
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    document_id = args["document_id"]
    org_id = args["organization_id"]
    sent_by_user_id = args["sent_by_user_id"]
    message = args["message"]

    with {:ok, document} <- Documents.get_document(document_id),
         {:ok, org} <- Operations.get_organization(org_id) do
      loaded_org = Ash.load!(org, [:billing_contact], authorize?: false)
      to_email = InvoiceEmail.find_billing_email(loaded_org) || "billing@gnomeautomation.io"

      email =
        DocumentEmail.build(document, to_email,
          org_name: org.name,
          message: message
        )

      case Mailer.deliver(email) do
        {:ok, _} ->
          Documents.log_send(%{
            company_document_id: document.id,
            organization_id: org.id,
            sent_to_email: to_email,
            sent_by_user_id: sent_by_user_id,
            message: message
          })
          :ok

        {:error, reason} ->
          Logger.error("DocumentSendWorker: failed to deliver email to #{to_email}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("DocumentSendWorker: could not load document or org: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

- [ ] **Step 2: Verify it compiles**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/garden/documents/document_send_worker.ex
git commit -m "feat: add DocumentSendWorker Oban job for bulk document sending"
```

---

## Task 4: Documents LiveView

**Files:**
- Create: `lib/garden_web/live/documents/documents_live.ex`
- Modify: `lib/garden_web/router.ex`
- Modify: `lib/garden_web/components/rail_nav.ex`
- Test: `test/garden_web/live/documents/documents_live_test.exs`

This is the main page. It has:
1. Table of active documents with search + category filter + "show all versions" toggle
2. Download button per row (static file link)
3. Send modal (single send with email, subject, message)
4. Version history modal per document
5. Bulk send modal (pick orgs, send selected docs)
6. Send log section (toggled below table)

- [ ] **Step 1: Add routes to router**

Open `lib/garden_web/router.ex`. Find the `ash_authentication_live_session :authenticated_routes` block. After the Finance — Bank Rules section, add:

```elixir
      # Company Documents
      live "/finance/documents", GnomeGardenWeb.Documents.DocumentsLive, :index
```

Use the fully qualified module name `GnomeGardenWeb.Documents.DocumentsLive` — this is required because the router scope does not auto-alias modules under `GnomeGardenWeb.Documents`.

- [ ] **Step 2: Add nav item to rail_nav**

Open `lib/garden_web/components/rail_nav.ex`. Find the `fin-billing-reminders` entry (last Finance item). After it, add:

```elixir
    %{
      id: "fin-documents",
      section: "Finance",
      icon: "hero-document-text",
      label: "Documents",
      tooltip: "Company documents — W9, legal, compliance files. Send to clients with full send log.",
      path: "/finance/documents",
      badge: 0,
      hot: false,
      match: ["/finance/documents"]
    },
```

- [ ] **Step 3: Write failing LiveView tests**

Create `test/garden_web/live/documents/documents_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Documents.DocumentsLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Documents

  setup :register_and_log_in_user

  defp create_w9 do
    {:ok, doc} =
      Documents.create_document(%{
        name: "W9 Form",
        category: :tax,
        version: "2024",
        file_path: "documents/w9-gnome-automation-signed.pdf",
        status: :active
      })
    doc
  end

  test "renders documents page", %{conn: conn} do
    create_w9()
    {:ok, _view, html} = live(conn, ~p"/finance/documents")
    assert html =~ "Company Documents"
    assert html =~ "W9 Form"
  end

  test "search filters documents by name", %{conn: conn} do
    create_w9()

    {:ok, doc2} =
      Documents.create_document(%{
        name: "NDA Agreement",
        category: :legal,
        version: "1.0",
        file_path: "documents/nda.pdf",
        status: :active
      })

    {:ok, view, _html} = live(conn, ~p"/finance/documents")

    html = render_keyup(view, "search", %{"value" => "W9"})
    assert html =~ "W9 Form"
    refute html =~ "NDA Agreement"
  end

  test "send modal opens when send button clicked", %{conn: conn} do
    create_w9()
    {:ok, view, _html} = live(conn, ~p"/finance/documents")

    html = view |> element("[phx-click='open_send_modal']") |> render_click()
    assert html =~ "Send Document"
    assert html =~ "To"
  end

  test "send document creates send log", %{conn: conn, current_user: user} do
    doc = create_w9()
    {:ok, view, _html} = live(conn, ~p"/finance/documents")

    view |> element("[phx-click='open_send_modal'][phx-value-doc-id='#{doc.id}']") |> render_click()

    view
    |> form("#send-document-form",
        send_doc: %{
          to: "client@example.com",
          subject: "Gnome Automation — W9 Form",
          message: ""
        }
      )
    |> render_submit()

    {:ok, logs} = Documents.list_send_logs_for_document(doc.id)
    assert Enum.any?(logs, &(&1.sent_to_email == "client@example.com"))
  end

  test "send log section shows recent sends", %{conn: conn, current_user: user} do
    doc = create_w9()

    {:ok, _} =
      Documents.log_send(%{
        company_document_id: doc.id,
        sent_to_email: "previous@example.com",
        sent_by_user_id: user.id
      })

    {:ok, view, _html} = live(conn, ~p"/finance/documents")
    html = view |> element("[phx-click='toggle_send_log']") |> render_click()
    assert html =~ "previous@example.com"
  end
end
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
mix test test/garden_web/live/documents/documents_live_test.exs
```

Expected: compile error — DocumentsLive not defined.

- [ ] **Step 5: Create DocumentsLive**

Create `lib/garden_web/live/documents/documents_live.ex`:

```elixir
defmodule GnomeGardenWeb.Documents.DocumentsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Documents
  alias GnomeGarden.Documents.DocumentSendWorker
  alias GnomeGarden.Operations
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.DocumentEmail
  alias GnomeGarden.Mailer.InvoiceEmail

  @impl true
  def mount(_params, _session, socket) do
    {:ok, docs} = Documents.list_active_documents()

    {:ok,
     socket
     |> assign(:page_title, "Company Documents")
     |> assign(:docs, docs)
     |> assign(:all_docs, docs)
     |> assign(:show_all_versions, false)
     |> assign(:search, "")
     |> assign(:category_filter, "all")
     |> assign(:send_modal_open, false)
     |> assign(:send_doc, nil)
     |> assign(:send_to, "")
     |> assign(:send_subject, "")
     |> assign(:send_message, "")
     |> assign(:send_org_id, nil)
     |> assign(:send_ok, false)
     |> assign(:send_error, nil)
     |> assign(:history_modal_open, false)
     |> assign(:history_doc, nil)
     |> assign(:history_versions, [])
     |> assign(:bulk_modal_open, false)
     |> assign(:selected_doc_ids, [])
     |> assign(:bulk_orgs, [])
     |> assign(:bulk_selected_org_ids, [])
     |> assign(:bulk_message, "")
     |> assign(:bulk_ok, false)
     |> assign(:bulk_error, nil)
     |> assign(:show_send_log, false)
     |> assign(:send_logs, [])
     |> assign(:send_log_org_names, %{})}
  end

  @impl true
  def handle_event("search", %{"value" => value}, socket) do
    {:noreply, socket |> assign(:search, value) |> apply_filters()}
  end

  @impl true
  def handle_event("filter_category", %{"category" => cat}, socket) do
    {:noreply, socket |> assign(:category_filter, cat) |> apply_filters()}
  end

  @impl true
  def handle_event("toggle_all_versions", _params, socket) do
    show_all = !socket.assigns.show_all_versions

    docs =
      if show_all do
        {:ok, all} = Documents.list_all_documents()
        all
      else
        {:ok, active} = Documents.list_active_documents()
        active
      end

    {:noreply,
     socket
     |> assign(:show_all_versions, show_all)
     |> assign(:all_docs, docs)
     |> assign(:docs, docs)
     |> apply_filters()}
  end

  @impl true
  def handle_event("toggle_doc_select", %{"doc-id" => doc_id}, socket) do
    selected = socket.assigns.selected_doc_ids

    updated =
      if doc_id in selected do
        List.delete(selected, doc_id)
      else
        [doc_id | selected]
      end

    {:noreply, assign(socket, :selected_doc_ids, updated)}
  end

  @impl true
  def handle_event("open_send_modal", %{"doc-id" => doc_id}, socket) do
    doc = Enum.find(socket.assigns.all_docs, &(&1.id == doc_id))

    {:noreply,
     socket
     |> assign(:send_modal_open, true)
     |> assign(:send_doc, doc)
     |> assign(:send_to, "")
     |> assign(:send_subject, "Gnome Automation — #{doc.name}")
     |> assign(:send_message, "")
     |> assign(:send_ok, false)
     |> assign(:send_error, nil)}
  end

  @impl true
  def handle_event("close_send_modal", _params, socket) do
    {:noreply, assign(socket, :send_modal_open, false)}
  end

  @impl true
  def handle_event("send_document", %{"send_doc" => params}, socket) do
    to = Map.get(params, "to", "") |> String.trim()
    message = Map.get(params, "message", "") |> String.trim()
    doc = socket.assigns.send_doc
    user = socket.assigns.current_user

    if to == "" do
      {:noreply, assign(socket, :send_error, "Email address is required")}
    else
      email = DocumentEmail.build(doc, to, message: if(message == "", do: nil, else: message))

      case Mailer.deliver(email) do
        {:ok, _} ->
          Documents.log_send(%{
            company_document_id: doc.id,
            organization_id: socket.assigns.send_org_id,
            sent_to_email: to,
            sent_by_user_id: user.id,
            message: if(message == "", do: nil, else: message)
          })

          {:noreply,
           socket
           |> assign(:send_modal_open, false)
           |> assign(:send_ok, true)
           |> put_flash(:info, "Document sent to #{to}")}

        {:error, reason} ->
          {:noreply, assign(socket, :send_error, "Failed to send: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("open_history_modal", %{"doc-id" => doc_id}, socket) do
    # Load all versions and build chain via supersedes_id
    {:ok, all} = Documents.list_all_documents()
    doc = Enum.find(all, &(&1.id == doc_id))
    versions = build_version_chain(doc, all)

    {:noreply,
     socket
     |> assign(:history_modal_open, true)
     |> assign(:history_doc, doc)
     |> assign(:history_versions, versions)}
  end

  @impl true
  def handle_event("close_history_modal", _params, socket) do
    {:noreply, assign(socket, :history_modal_open, false)}
  end

  @impl true
  def handle_event("open_bulk_modal", _params, socket) do
    orgs = Operations.list_organizations!(actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:bulk_modal_open, true)
     |> assign(:bulk_orgs, orgs)
     |> assign(:bulk_selected_org_ids, [])
     |> assign(:bulk_message, "")
     |> assign(:bulk_ok, false)
     |> assign(:bulk_error, nil)}
  end

  @impl true
  def handle_event("close_bulk_modal", _params, socket) do
    {:noreply, assign(socket, :bulk_modal_open, false)}
  end

  @impl true
  def handle_event("toggle_bulk_org", %{"org-id" => org_id}, socket) do
    selected = socket.assigns.bulk_selected_org_ids

    updated =
      if org_id in selected do
        List.delete(selected, org_id)
      else
        [org_id | selected]
      end

    {:noreply, assign(socket, :bulk_selected_org_ids, updated)}
  end

  @impl true
  def handle_event("bulk_send", %{"bulk" => params}, socket) do
    org_ids = socket.assigns.bulk_selected_org_ids
    doc_ids = socket.assigns.selected_doc_ids
    message = Map.get(params, "message", "") |> String.trim()
    user = socket.assigns.current_user

    if Enum.empty?(org_ids) do
      {:noreply, assign(socket, :bulk_error, "Select at least one organization")}
    else
      jobs =
        for doc_id <- doc_ids, org_id <- org_ids do
          DocumentSendWorker.new(%{
            document_id: doc_id,
            organization_id: org_id,
            sent_by_user_id: user.id,
            message: if(message == "", do: nil, else: message)
          })
        end

      Oban.insert_all(jobs)

      total = length(jobs)
      {:noreply,
       socket
       |> assign(:bulk_modal_open, false)
       |> assign(:selected_doc_ids, [])
       |> put_flash(:info, "Sending to #{total} recipient(s) in the background")}
    end
  end

  @impl true
  def handle_event("toggle_send_log", _params, socket) do
    show = !socket.assigns.show_send_log

    {logs, org_names} =
      if show do
        {:ok, raw_logs} = Documents.list_send_logs()
        logs = Ash.load!(raw_logs, [:company_document], authorize?: false)

        # Build org_id => org_name map for logs that have an organization_id
        org_ids = logs |> Enum.map(& &1.organization_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

        org_names =
          if Enum.empty?(org_ids) do
            %{}
          else
            Operations.list_organizations!(actor: socket.assigns.current_user)
            |> Enum.filter(&(&1.id in org_ids))
            |> Map.new(&{&1.id, &1.name})
          end

        {logs, org_names}
      else
        {[], %{}}
      end

    {:noreply,
     socket
     |> assign(:show_send_log, show)
     |> assign(:send_logs, logs)
     |> assign(:send_log_org_names, org_names)}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Company Documents
        <:subtitle>Internal documents sent to clients — W9, legal forms, compliance files.</:subtitle>
        <:actions>
          <.button
            :if={length(@selected_doc_ids) > 0}
            phx-click="open_bulk_modal"
            variant="primary"
          >
            Send Selected ({length(@selected_doc_ids)})
          </.button>
        </:actions>
      </.page_header>

      <%# --- Controls --- %>
      <div class="mb-4 flex flex-wrap items-center gap-3">
        <input
          type="text"
          placeholder="Search documents..."
          phx-keyup="search"
          name="search"
          value={@search}
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
        />

        <select
          phx-change="filter_category"
          name="category"
          class="rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 appearance-none"
        >
          <option value="all">All Categories</option>
          <option value="tax" selected={@category_filter == "tax"}>Tax</option>
          <option value="legal" selected={@category_filter == "legal"}>Legal</option>
          <option value="compliance" selected={@category_filter == "compliance"}>Compliance</option>
          <option value="hr" selected={@category_filter == "hr"}>HR</option>
          <option value="other" selected={@category_filter == "other"}>Other</option>
        </select>

        <label class="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-300 cursor-pointer">
          <input
            type="checkbox"
            phx-click="toggle_all_versions"
            checked={@show_all_versions}
            class="h-4 w-4 rounded border-gray-300 text-emerald-600 focus:ring-emerald-600"
          />
          Show all versions
        </label>
      </div>

      <%# --- Documents Table --- %>
      <div class="rounded-lg border border-gray-200 bg-white dark:border-white/10 dark:bg-white/5 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
          <thead class="bg-gray-50 dark:bg-white/5">
            <tr>
              <th class="w-8 px-4 py-3"></th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Name</th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Category</th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Version</th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Status</th>
              <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Expires</th>
              <th class="px-4 py-3 text-right font-medium text-gray-500 dark:text-gray-400">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100 dark:divide-white/5">
            <tr :for={doc <- @docs} class="hover:bg-gray-50 dark:hover:bg-white/5">
              <td class="px-4 py-3">
                <input
                  type="checkbox"
                  phx-click="toggle_doc_select"
                  phx-value-doc-id={doc.id}
                  checked={doc.id in @selected_doc_ids}
                  class="h-4 w-4 rounded border-gray-300 text-emerald-600 focus:ring-emerald-600"
                />
              </td>
              <td class="px-4 py-3 font-medium text-gray-900 dark:text-white">{doc.name}</td>
              <td class="px-4 py-3">
                <span class={"inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{category_badge_class(doc.category)}"}>
                  {String.capitalize(to_string(doc.category))}
                </span>
              </td>
              <td class="px-4 py-3 text-gray-600 dark:text-gray-400">{doc.version}</td>
              <td class="px-4 py-3">
                <span class={"inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{status_badge_class(doc.status)}"}>
                  {String.capitalize(to_string(doc.status))}
                </span>
              </td>
              <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                {doc.expiry_date || "—"}
              </td>
              <td class="px-4 py-3 text-right">
                <div class="flex items-center justify-end gap-2">
                  <a
                    href={"/" <> doc.file_path}
                    download
                    target="_blank"
                    class="rounded px-2 py-1 text-xs font-medium text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-white/10"
                  >
                    Download
                  </a>
                  <button
                    type="button"
                    phx-click="open_send_modal"
                    phx-value-doc-id={doc.id}
                    class="rounded px-2 py-1 text-xs font-medium text-emerald-600 hover:bg-emerald-50 dark:hover:bg-emerald-900/20"
                  >
                    Send
                  </button>
                  <button
                    type="button"
                    phx-click="open_history_modal"
                    phx-value-doc-id={doc.id}
                    class="rounded px-2 py-1 text-xs font-medium text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-white/10"
                  >
                    History
                  </button>
                </div>
              </td>
            </tr>
            <tr :if={Enum.empty?(@docs)}>
              <td colspan="7" class="px-4 py-8 text-center text-sm text-gray-500 dark:text-gray-400">
                No documents found.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%# --- Send Log Toggle --- %>
      <div class="mt-6">
        <button
          type="button"
          phx-click="toggle_send_log"
          class="text-sm font-medium text-emerald-600 hover:text-emerald-500 dark:text-emerald-400"
        >
          {if @show_send_log, do: "Hide Send Log", else: "Show Send Log"}
        </button>

        <div :if={@show_send_log} class="mt-4 rounded-lg border border-gray-200 bg-white dark:border-white/10 dark:bg-white/5 overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10 text-sm">
            <thead class="bg-gray-50 dark:bg-white/5">
              <tr>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Date Sent</th>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Document</th>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Version</th>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Org</th>
                <th class="px-4 py-3 text-left font-medium text-gray-500 dark:text-gray-400">Sent To</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100 dark:divide-white/5">
              <tr :for={log <- @send_logs} class="hover:bg-gray-50 dark:hover:bg-white/5">
                <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                  {Calendar.strftime(log.sent_at, "%b %d, %Y %H:%M")}
                </td>
                <td class="px-4 py-3 text-gray-900 dark:text-white">
                  {log.company_document && log.company_document.name}
                </td>
                <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                  {log.company_document && log.company_document.version}
                </td>
                <td class="px-4 py-3 text-gray-600 dark:text-gray-400">
                  {Map.get(@send_log_org_names, log.organization_id, "—")}
                </td>
                <td class="px-4 py-3 text-gray-600 dark:text-gray-400">{log.sent_to_email}</td>
              </tr>
              <tr :if={Enum.empty?(@send_logs)}>
                <td colspan="5" class="px-4 py-6 text-center text-sm text-gray-500 dark:text-gray-400">
                  No sends recorded yet.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%# --- Send Modal --- %>
      <div
        :if={@send_modal_open}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
        phx-click="close_send_modal"
      >
        <div class="w-full max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900" phx-click-away="close_send_modal">
          <h2 class="mb-4 text-base font-semibold text-gray-900 dark:text-white">
            Send Document
          </h2>

          <div :if={@send_doc} class="mb-4 rounded-md bg-gray-50 px-3 py-2 text-sm text-gray-700 dark:bg-white/5 dark:text-gray-300">
            <strong>{@send_doc.name}</strong> — v{@send_doc.version}
          </div>

          <form id="send-document-form" phx-submit="send_document">
            <div class="space-y-4">
              <div>
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
                <input
                  type="email"
                  name="send_doc[to]"
                  value={@send_to}
                  required
                  placeholder="client@example.com"
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
                />
              </div>

              <div>
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Subject</label>
                <input
                  type="text"
                  name="send_doc[subject]"
                  value={@send_subject}
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
                />
              </div>

              <div>
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Message (optional)</label>
                <textarea
                  name="send_doc[message]"
                  rows="3"
                  placeholder="Please keep this on file for your records."
                  class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
                ></textarea>
              </div>
            </div>

            <div :if={@send_error} class="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
              {@send_error}
            </div>

            <div class="mt-5 flex justify-end gap-3">
              <button type="button" phx-click="close_send_modal" class="text-sm/6 font-semibold text-gray-900 dark:text-white">
                Cancel
              </button>
              <button
                type="submit"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
              >
                Send
              </button>
            </div>
          </form>
        </div>
      </div>

      <%# --- Version History Modal --- %>
      <div
        :if={@history_modal_open}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
        phx-click="close_history_modal"
      >
        <div class="w-full max-w-lg rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              Version History — {@history_doc && @history_doc.name}
            </h2>
            <button type="button" phx-click="close_history_modal" class="text-gray-400 hover:text-gray-600">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <table class="min-w-full text-sm">
            <thead>
              <tr class="border-b border-gray-200 dark:border-white/10">
                <th class="py-2 text-left font-medium text-gray-500 dark:text-gray-400">Version</th>
                <th class="py-2 text-left font-medium text-gray-500 dark:text-gray-400">Status</th>
                <th class="py-2 text-left font-medium text-gray-500 dark:text-gray-400">Added</th>
                <th class="py-2 text-left font-medium text-gray-500 dark:text-gray-400">Expires</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={v <- @history_versions} class="border-b border-gray-100 dark:border-white/5">
                <td class="py-2 font-medium text-gray-900 dark:text-white">{v.version}</td>
                <td class="py-2">
                  <span class={"inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{status_badge_class(v.status)}"}>
                    {String.capitalize(to_string(v.status))}
                  </span>
                </td>
                <td class="py-2 text-gray-600 dark:text-gray-400">
                  {Calendar.strftime(v.inserted_at, "%b %d, %Y")}
                </td>
                <td class="py-2 text-gray-600 dark:text-gray-400">{v.expiry_date || "—"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%# --- Bulk Send Modal --- %>
      <div
        :if={@bulk_modal_open}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      >
        <div class="w-full max-w-lg rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-base font-semibold text-gray-900 dark:text-white">
              Bulk Send ({length(@selected_doc_ids)} document(s))
            </h2>
            <button type="button" phx-click="close_bulk_modal" class="text-gray-400 hover:text-gray-600">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <p class="mb-3 text-sm text-gray-600 dark:text-gray-400">
            Select the organizations to send to. Each org will receive all selected documents.
          </p>

          <form id="bulk-send-form" phx-submit="bulk_send">
            <div class="mb-4 max-h-48 overflow-y-auto rounded-md border border-gray-200 dark:border-white/10 p-2 space-y-1">
              <label :for={org <- @bulk_orgs} class="flex items-center gap-2 rounded px-2 py-1 hover:bg-gray-50 dark:hover:bg-white/5 cursor-pointer text-sm text-gray-900 dark:text-white">
                <input
                  type="checkbox"
                  phx-click="toggle_bulk_org"
                  phx-value-org-id={org.id}
                  checked={org.id in @bulk_selected_org_ids}
                  class="h-4 w-4 rounded border-gray-300 text-emerald-600 focus:ring-emerald-600"
                />
                {org.name}
              </label>
            </div>

            <div>
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Message (optional)</label>
              <textarea
                name="bulk[message]"
                rows="2"
                class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
              ></textarea>
            </div>

            <div :if={@bulk_error} class="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
              {@bulk_error}
            </div>

            <div class="mt-5 flex justify-end gap-3">
              <button type="button" phx-click="close_bulk_modal" class="text-sm/6 font-semibold text-gray-900 dark:text-white">
                Cancel
              </button>
              <button
                type="submit"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
              >
                Send to {length(@bulk_selected_org_ids)} org(s)
              </button>
            </div>
          </form>
        </div>
      </div>
    </.page>
    """
  end

  # --- Private helpers ---

  defp apply_filters(socket) do
    search = String.downcase(socket.assigns.search)
    cat = socket.assigns.category_filter

    filtered =
      socket.assigns.all_docs
      |> Enum.filter(fn doc ->
        name_match = search == "" or String.contains?(String.downcase(doc.name), search)
        cat_match = cat == "all" or to_string(doc.category) == cat
        name_match and cat_match
      end)

    assign(socket, :docs, filtered)
  end

  defp build_version_chain(doc, all_docs) do
    # Walk supersedes_id chain backward from this doc to find all related versions
    # Group by name (simple approach: same name = same document family)
    Enum.filter(all_docs, &(&1.name == doc.name))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp category_badge_class(:tax), do: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"
  defp category_badge_class(:legal), do: "bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400"
  defp category_badge_class(:compliance), do: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400"
  defp category_badge_class(:hr), do: "bg-pink-100 text-pink-700 dark:bg-pink-900/30 dark:text-pink-400"
  defp category_badge_class(_), do: "bg-gray-100 text-gray-600 dark:bg-white/10 dark:text-gray-400"

  defp status_badge_class(:active), do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400"
  defp status_badge_class(:superseded), do: "bg-gray-100 text-gray-500 dark:bg-white/10 dark:text-gray-400"
  defp status_badge_class(:expired), do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-500 dark:bg-white/10 dark:text-gray-400"
end
```

- [ ] **Step 6: Run LiveView tests**

```bash
mix test test/garden_web/live/documents/documents_live_test.exs
```

Expected: 5 tests pass.

- [ ] **Step 7: Smoke test in browser**

Start server, visit `/finance/documents`. Confirm:
- Page renders with "Company Documents" header
- W9 row shows if seeds were run (see Task 5)
- Send button opens modal
- History button opens version history modal
- "Show Send Log" toggle works

- [ ] **Step 8: Commit**

```bash
git add \
  lib/garden_web/live/documents/documents_live.ex \
  lib/garden_web/router.ex \
  lib/garden_web/components/rail_nav.ex \
  test/garden_web/live/documents/
git commit -m "feat: add Company Documents LiveView with search, send modal, bulk send, and send log"
```

---

## Task 5: Seed W9 document

**Files:**
- Modify: `priv/repo/seeds.exs`

- [ ] **Step 1: Add W9 seed to seeds.exs**

Open `priv/repo/seeds.exs`. Add at the end:

```elixir
# --- Company Documents ---
# Upsert W9 — idempotent, safe to re-run
existing_w9 =
  case GnomeGarden.Documents.list_active_documents() do
    {:ok, docs} -> Enum.find(docs, &(&1.name == "W9 Form"))
    _ -> nil
  end

unless existing_w9 do
  {:ok, _} =
    GnomeGarden.Documents.create_document(%{
      name: "W9 Form",
      description: "IRS Form W-9 — Request for Taxpayer Identification Number and Certification",
      category: :tax,
      version: "2024",
      file_path: "documents/w9-gnome-automation-signed.pdf",
      status: :active
    })

  IO.puts("Seeded: W9 Form (2024)")
end
```

- [ ] **Step 2: Run seeds**

```bash
mix run priv/repo/seeds.exs
```

Expected: `Seeded: W9 Form (2024)` (or silent if already seeded).

- [ ] **Step 3: Verify in iex**

```bash
iex -S mix
```

```elixir
GnomeGarden.Documents.list_active_documents()
```

Expected: `{:ok, [%GnomeGarden.Documents.CompanyDocument{name: "W9 Form", ...}]}`

- [ ] **Step 4: Commit**

```bash
git add priv/repo/seeds.exs
git commit -m "feat: seed W9 Form company document"
```

---

## Task 6: Org show page — Send Document button

**Files:**
- Modify: `lib/garden_web/live/operations/organization_live/show.ex`

Add a "Send Document" button on the org show page that opens an inline send modal pre-filled with the org's billing email.

- [ ] **Step 1: Add assigns to mount/0 in OrganizationLive.Show**

Open `lib/garden_web/live/operations/organization_live/show.ex`.

In `mount/3`, after existing assigns, add:

```elixir
|> assign(:org_send_modal_open, false)
|> assign(:org_send_docs, [])
|> assign(:org_send_doc_id, nil)
|> assign(:org_send_to, "")
|> assign(:org_send_subject, "Gnome Automation — Document")
|> assign(:org_send_message, "")
|> assign(:org_send_error, nil)
```

Also add at the top of the file:
```elixir
alias GnomeGarden.Documents
alias GnomeGarden.Mailer
alias GnomeGarden.Mailer.DocumentEmail
alias GnomeGarden.Mailer.InvoiceEmail
```

- [ ] **Step 2: Add handle_event handlers**

Add after the existing `handle_event` functions:

```elixir
@impl true
def handle_event("open_send_doc_modal", _params, socket) do
  {:ok, docs} = Documents.list_active_documents()
  org = socket.assigns.organization
  loaded_org = Ash.load!(org, [:billing_contact], authorize?: false)
  billing_email = InvoiceEmail.find_billing_email(loaded_org) || ""

  first_doc = List.first(docs)
  subject = if first_doc, do: "Gnome Automation — #{first_doc.name}", else: "Gnome Automation — Document"

  {:noreply,
   socket
   |> assign(:org_send_modal_open, true)
   |> assign(:org_send_docs, docs)
   |> assign(:org_send_doc_id, first_doc && first_doc.id)
   |> assign(:org_send_to, billing_email)
   |> assign(:org_send_subject, subject)
   |> assign(:org_send_message, "")
   |> assign(:org_send_error, nil)}
end

@impl true
def handle_event("close_send_doc_modal", _params, socket) do
  {:noreply, assign(socket, :org_send_modal_open, false)}
end

@impl true
def handle_event("org_send_doc_changed", %{"doc_id" => doc_id}, socket) do
  doc = Enum.find(socket.assigns.org_send_docs, &(&1.id == doc_id))
  subject = if doc, do: "Gnome Automation — #{doc.name}", else: socket.assigns.org_send_subject
  {:noreply, socket |> assign(:org_send_doc_id, doc_id) |> assign(:org_send_subject, subject)}
end

@impl true
def handle_event("send_document_from_org", %{"org_send" => params}, socket) do
  doc_id = Map.get(params, "doc_id") || socket.assigns.org_send_doc_id
  to = Map.get(params, "to", "") |> String.trim()
  message = Map.get(params, "message", "") |> String.trim()
  user = socket.assigns.current_user
  org = socket.assigns.organization

  with doc when not is_nil(doc) <- Enum.find(socket.assigns.org_send_docs, &(&1.id == doc_id)),
       false <- to == "" do
    email =
      DocumentEmail.build(doc, to,
        org_name: org.name,
        message: if(message == "", do: nil, else: message)
      )

    case Mailer.deliver(email) do
      {:ok, _} ->
        Documents.log_send(%{
          company_document_id: doc.id,
          organization_id: org.id,
          sent_to_email: to,
          sent_by_user_id: user.id,
          message: if(message == "", do: nil, else: message)
        })

        {:noreply,
         socket
         |> assign(:org_send_modal_open, false)
         |> put_flash(:info, "#{doc.name} sent to #{to}")}

      {:error, reason} ->
        {:noreply, assign(socket, :org_send_error, "Failed to send: #{inspect(reason)}")}
    end
  else
    nil -> {:noreply, assign(socket, :org_send_error, "Select a document")}
    true -> {:noreply, assign(socket, :org_send_error, "Email address is required")}
  end
end
```

- [ ] **Step 3: Add Send Document button in the render/1 template**

In the render template, find the actions area (look for buttons like "Edit" or "Archive" near the page header). Add a "Send Document" button alongside them:

```heex
<.button phx-click="open_send_doc_modal">
  Send Document
</.button>
```

- [ ] **Step 4: Add the send modal at the bottom of the render template (before the closing `</.page>` tag)**

```heex
<%# --- Send Document Modal --- %>
<div
  :if={@org_send_modal_open}
  class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
>
  <div class="w-full max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-900">
    <div class="mb-4 flex items-center justify-between">
      <h2 class="text-base font-semibold text-gray-900 dark:text-white">Send Document</h2>
      <button type="button" phx-click="close_send_doc_modal" class="text-gray-400 hover:text-gray-600">
        <.icon name="hero-x-mark" class="size-5" />
      </button>
    </div>

    <form id="org-send-doc-form" phx-submit="send_document_from_org">
      <div class="space-y-4">
        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Document</label>
          <select
            name="org_send[doc_id]"
            phx-change="org_send_doc_changed"
            class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 appearance-none"
          >
            <option :for={doc <- @org_send_docs} value={doc.id} selected={doc.id == @org_send_doc_id}>
              {doc.name} (v{doc.version})
            </option>
          </select>
        </div>

        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">To</label>
          <input
            type="email"
            name="org_send[to]"
            value={@org_send_to}
            required
            class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
          />
        </div>

        <div>
          <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Message (optional)</label>
          <textarea
            name="org_send[message]"
            rows="3"
            class="mt-1 block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10"
          ></textarea>
        </div>
      </div>

      <div :if={@org_send_error} class="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
        {@org_send_error}
      </div>

      <div class="mt-5 flex justify-end gap-3">
        <button type="button" phx-click="close_send_doc_modal" class="text-sm/6 font-semibold text-gray-900 dark:text-white">
          Cancel
        </button>
        <button
          type="submit"
          class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
        >
          Send
        </button>
      </div>
    </form>
  </div>
</div>
```

- [ ] **Step 5: Verify compilation**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 6: Smoke test in browser**

Visit an org page (e.g. `/operations/organizations/:id`). Confirm "Send Document" button appears and opens the modal with the org's billing email pre-filled.

- [ ] **Step 7: Commit**

```bash
git add lib/garden_web/live/operations/organization_live/show.ex
git commit -m "feat: add Send Document button and modal to org show page"
```

---

## Final: Run full test suite

- [ ] **Step 1: Run all tests**

```bash
mix test
```

Expected: all pass (or only pre-existing failures).

- [ ] **Step 2: Commit memory update**

Update `finance_roadmap.md` memory to mark Company Documents as done.

---

## Testing Checklist

- [ ] `/finance/documents` renders table with W9 row
- [ ] Search input filters by name (real-time)
- [ ] Category filter works
- [ ] "Show all versions" toggle shows superseded/expired docs
- [ ] Download button downloads the PDF (new tab)
- [ ] Send modal opens, pre-fills subject, sends email, creates send log
- [ ] "Show Send Log" shows sent records
- [ ] Version history modal shows doc lineage
- [ ] Bulk send: check 1+ docs → open bulk modal → select orgs → submit → flash success
- [ ] Org show page: "Send Document" button → modal → pre-filled email → send → flash + log created
- [ ] Nav item "Documents" in Finance sidebar links to page correctly
