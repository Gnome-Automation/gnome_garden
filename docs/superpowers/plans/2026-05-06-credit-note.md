# Credit Note Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a credit note document system that creates a reconcilable mirror document (with negated line items) when a staff member voids an invoice, with a sequential CN-XXXX numbering series and an optional email send to the client.

**Architecture:** Three new Ash resources (`FinanceSequence`, `CreditNote`, `CreditNoteLine`) backed by a single migration. The void flow is unchanged — staff creates the credit note as an explicit second step from the invoice show page. A `Finance.next_sequence_value/1` hand-written function handles atomic SQL-level incrementing. Two new LiveViews (show, index) and one new email module complete the feature.

**Tech Stack:** Elixir/Phoenix, Ash Framework (AshPostgres), Phoenix LiveView, Swoosh email, PostgreSQL

---

## File Structure

### New Files
- `lib/garden/finance/finance_sequence.ex` — Ash resource (schema only); table `finance_sequences` (name PK, last_value)
- `lib/garden/finance/credit_note.ex` — Ash resource; table `credit_notes`; actions: create, issue, update (reason only, draft guard), read
- `lib/garden/finance/credit_note_line.ex` — Ash resource; table `credit_note_lines`; actions: create, read
- `lib/garden/mailer/credit_note_email.ex` — Swoosh email builder; same pattern as `InvoiceEmail`
- `lib/garden_web/live/finance/credit_note_live/show.ex` — credit note detail page; issue & send action
- `lib/garden_web/live/finance/credit_note_live/index.ex` — list all credit notes, sorted by inserted_at desc

### Modified Files
- `lib/garden/finance/invoice.ex` — add `has_one :credit_note, GnomeGarden.Finance.CreditNote`
- `lib/garden/finance.ex` — register 3 new resources + define shortcuts + hand-written `next_sequence_value/1`
- `lib/garden_web/live/finance/invoice_live/show.ex` — add `credit_note: []` to load, add Credit Note card to template, add `handle_event("create_credit_note", ...)`
- `lib/garden_web/router.ex` — add `/finance/credit-notes` and `/finance/credit-notes/:id` routes
- `lib/garden_web/components/nav.ex` — add Credit Notes link to Finance subnav

### Test Files
- `test/garden/finance/finance_sequence_test.exs`
- `test/garden/finance/credit_note_test.exs`
- `test/garden/mailer/credit_note_email_test.exs`
- `test/garden_web/live/finance/credit_note_live_test.exs` — note: place in `test/garden_web/live/finance/` subdirectory

---

## Task 1: Schema — FinanceSequence, CreditNote, CreditNoteLine

**Files:**
- Create: `lib/garden/finance/finance_sequence.ex`
- Create: `lib/garden/finance/credit_note.ex`
- Create: `lib/garden/finance/credit_note_line.ex`
- Modify: `lib/garden/finance/invoice.ex`
- Modify: `lib/garden/finance.ex`

- [ ] **Step 1: Create FinanceSequence resource**

Create `lib/garden/finance/finance_sequence.ex`:

```elixir
defmodule GnomeGarden.Finance.FinanceSequence do
  @moduledoc """
  Atomic sequence counter table. One row per named sequence.

  Do NOT use Ash actions to increment — use Finance.next_sequence_value/1
  which executes a raw atomic SQL UPDATE ... RETURNING.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_sequences"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]
  end

  attributes do
    attribute :name, :string do
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :last_value, :integer do
      default 0
      allow_nil? false
      public? true
    end

    # No timestamps() — FinanceSequence is a counter table; audit trail not needed
    # This also keeps the seed SQL simple (no inserted_at/updated_at columns)
  end
end
```

- [ ] **Step 2: Create CreditNote resource**

Create `lib/garden/finance/credit_note.ex`:

```elixir
defmodule GnomeGarden.Finance.CreditNote do
  @moduledoc """
  Credit note document created when a voided invoice needs a reconcilable trail.

  One credit note per invoice (enforced by UNIQUE index on invoice_id).
  Staff creates this explicitly after voiding — it is never auto-created.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "credit_notes"
    repo GnomeGarden.Repo

    references do
      reference :invoice, on_delete: :restrict
      reference :organization, on_delete: :restrict
    end
  end

  identities do
    identity :unique_credit_note_number, [:credit_note_number]
    identity :one_credit_note_per_invoice, [:invoice_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :credit_note_number,
        :invoice_id,
        :organization_id,
        :total_amount,
        :currency_code,
        :reason
      ]
    end

    update :issue do
      accept []

      # Guard: CreditNote does not use AshStateMachine — enforce draft-only manually
      validate fn changeset, _context ->
        if Ash.Changeset.get_data(changeset, :status) == :draft do
          :ok
        else
          {:error, field: :status, message: "can only issue a draft credit note"}
        end
      end

      change set_attribute(:status, :issued)
      change set_attribute(:issued_on, &Date.utc_today/0)
    end

    update :update do
      accept [:reason]

      validate fn changeset, _context ->
        if Ash.Changeset.get_data(changeset, :status) == :draft do
          :ok
        else
          {:error, field: :status, message: "can only edit a draft credit note"}
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :credit_note_number, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      default :draft
      allow_nil? false
      public? true
      constraints one_of: [:draft, :issued]
    end

    attribute :total_amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :currency_code, :string do
      default "USD"
      allow_nil? false
      public? true
    end

    attribute :issued_on, :date do
      public? true
    end

    attribute :reason, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :invoice, GnomeGarden.Finance.Invoice do
      allow_nil? false
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
    end

    has_many :credit_note_lines, GnomeGarden.Finance.CreditNoteLine do
      sort position: :asc
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 draft: :default,
                 issued: :success
               ],
               default: :default}
  end
end
```

- [ ] **Step 3: Create CreditNoteLine resource**

Create `lib/garden/finance/credit_note_line.ex`:

```elixir
defmodule GnomeGarden.Finance.CreditNoteLine do
  @moduledoc """
  One line on a credit note, mirroring an InvoiceLine with negated amounts.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "credit_note_lines"
    repo GnomeGarden.Repo

    references do
      reference :credit_note, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:credit_note_id, :position, :description, :quantity, :unit_price, :line_total]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :quantity, :decimal do
      public? true
    end

    attribute :unit_price, :decimal do
      public? true
    end

    attribute :line_total, :decimal do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :credit_note, GnomeGarden.Finance.CreditNote do
      allow_nil? false
    end
  end
end
```

- [ ] **Step 4: Add `has_one :credit_note` to Invoice**

In `lib/garden/finance/invoice.ex`, inside the `relationships do` block, add after existing relationships:

```elixir
has_one :credit_note, GnomeGarden.Finance.CreditNote
```

- [ ] **Step 5: Register resources and add shortcuts to Finance domain**

In `lib/garden/finance.ex`:

**Add three new resource blocks** inside `resources do`, following the same `define` pattern as `InvoiceLine`:

```elixir
resource GnomeGarden.Finance.FinanceSequence do
  define :list_finance_sequences, action: :read
end

resource GnomeGarden.Finance.CreditNote do
  define :list_credit_notes, action: :read
  define :get_credit_note, action: :read, get_by: [:id]
  define :create_credit_note, action: :create
  define :issue_credit_note, action: :issue
  define :update_credit_note, action: :update
end

resource GnomeGarden.Finance.CreditNoteLine do
  define :list_credit_note_lines, action: :read
  define :create_credit_note_line, action: :create
end
```

**Add the hand-written shortcut function** at the bottom of the module (after the `use Ash.Domain` block, outside the `resources do` block):

```elixir
@doc """
Atomically increments the named sequence and returns the new integer value.
Uses a raw SQL UPDATE ... RETURNING — safe under concurrency.
"""
def next_sequence_value(name) do
  {:ok, %{rows: [[val]]}} =
    GnomeGarden.Repo.query(
      "UPDATE finance_sequences SET last_value = last_value + 1 WHERE name = $1 RETURNING last_value",
      [name]
    )

  val
end

@doc """
Formats a sequence integer as a credit note number string.
Example: 1 → "CN-0001"
"""
def format_credit_note_number(n) do
  "CN-" <> String.pad_leading("#{n}", 4, "0")
end
```

- [ ] **Step 6: Generate migration**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.generate_migrations --name add_credit_notes
```

Expected: creates a new file in `priv/repo/migrations/`. Inspect it and confirm it includes:
- `finance_sequences` table with `name` as string PK and `last_value` integer
- `credit_notes` table with UNIQUE indexes on `credit_note_number` and `invoice_id`
- `credit_note_lines` table with `on_delete: :delete` FK to `credit_notes`

- [ ] **Step 7: Add seed row to migration**

Open the generated migration file. After the `create table(:credit_note_lines)` block, add:

```elixir
execute(
  "INSERT INTO finance_sequences (name, last_value) VALUES ('credit_notes', 0) ON CONFLICT (name) DO NOTHING",
  "DELETE FROM finance_sequences WHERE name = 'credit_notes'"
)
```

Note: no `inserted_at`/`updated_at` — `FinanceSequence` does not include `timestamps()`.

- [ ] **Step 8: Run migration**

```bash
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.migrate
```

Expected: runs cleanly with no errors.

- [ ] **Step 9: Write tests**

Create `test/garden/finance/finance_sequence_test.exs`:

```elixir
defmodule GnomeGarden.Finance.FinanceSequenceTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Finance

  test "next_sequence_value increments sequentially" do
    v1 = Finance.next_sequence_value("credit_notes")
    v2 = Finance.next_sequence_value("credit_notes")
    assert v2 == v1 + 1
  end

  test "format_credit_note_number pads to 4 digits" do
    assert Finance.format_credit_note_number(1) == "CN-0001"
    assert Finance.format_credit_note_number(42) == "CN-0042"
    assert Finance.format_credit_note_number(1000) == "CN-1000"
  end
end
```

Create `test/garden/finance/credit_note_test.exs`:

```elixir
defmodule GnomeGarden.Finance.CreditNoteTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-TEST-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("1000.00"),
        balance_amount: Decimal.new("1000.00")
      })

    %{org: org, invoice: invoice}
  end

  test "creates a credit note with negated amount", %{org: org, invoice: invoice} do
    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    assert cn.credit_note_number == "CN-0001"
    assert cn.status == :draft
    assert Decimal.equal?(cn.total_amount, Decimal.new("-1000.00"))
  end

  test "issue transitions draft to issued", %{org: org, invoice: invoice} do
    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    {:ok, issued} = Finance.issue_credit_note(cn)
    assert issued.status == :issued
    assert issued.issued_on == Date.utc_today()
  end

  test "rejects duplicate credit note for same invoice", %{org: org, invoice: invoice} do
    {:ok, _} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    assert {:error, _} =
             Finance.create_credit_note(%{
               credit_note_number: "CN-#{System.unique_integer([:positive])}",
               invoice_id: invoice.id,
               organization_id: org.id,
               total_amount: Decimal.new("-1000.00"),
               currency_code: "USD"
             })
  end

  test "update reason is allowed on draft", %{org: org, invoice: invoice} do
    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    {:ok, updated} = Finance.update_credit_note(cn, %{reason: "Duplicate invoice"})
    assert updated.reason == "Duplicate invoice"
  end

  test "update reason is rejected on issued credit note", %{org: org, invoice: invoice} do
    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-1000.00"),
        currency_code: "USD"
      })

    {:ok, issued} = Finance.issue_credit_note(cn)
    assert {:error, _} = Finance.update_credit_note(issued, %{reason: "Changed"})
  end
end
```

- [ ] **Step 10: Run tests to confirm they pass**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/finance_sequence_test.exs test/garden/finance/credit_note_test.exs --trace 2>&1
```

Expected: all tests PASS.

- [ ] **Step 11: Commit**

```bash
git add lib/garden/finance/finance_sequence.ex \
        lib/garden/finance/credit_note.ex \
        lib/garden/finance/credit_note_line.ex \
        lib/garden/finance/invoice.ex \
        lib/garden/finance.ex \
        priv/repo/migrations/ \
        priv/resource_snapshots/ \
        test/garden/finance/finance_sequence_test.exs \
        test/garden/finance/credit_note_test.exs
git commit -m "feat: add FinanceSequence, CreditNote, CreditNoteLine schema + Finance shortcuts"
```

---

## Task 2: CreditNoteEmail module

**Files:**
- Create: `lib/garden/mailer/credit_note_email.ex`
- Create: `test/garden/mailer/credit_note_email_test.exs`

- [ ] **Step 1: Write the failing test first**

Create `test/garden/mailer/credit_note_email_test.exs`:

```elixir
defmodule GnomeGarden.Mailer.CreditNoteEmailTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mailer.CreditNoteEmail
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Acme Corp #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Bill",
        last_name: "Payer",
        email: "bill@acme.com"
      })

    Operations.create_organization_affiliation(%{
      organization_id: org.id,
      person_id: person.id
    })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-EMAIL-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("500.00"),
        balance_amount: Decimal.new("500.00")
      })

    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: "CN-EMAIL-#{System.unique_integer([:positive])}",
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-500.00"),
        currency_code: "USD",
        reason: "Test reason"
      })

    {:ok, cn_line} =
      Finance.create_credit_note_line(%{
        credit_note_id: cn.id,
        position: 1,
        description: "Engineering hours",
        quantity: Decimal.new("5"),
        unit_price: Decimal.new("-100.00"),
        line_total: Decimal.new("-500.00")
      })

    # Load with all required associations
    {:ok, loaded_cn} =
      Finance.get_credit_note(cn.id,
        load: [:credit_note_lines, :invoice, organization: [:billing_contact]]
      )

    %{org: org, cn: loaded_cn}
  end

  test "build/1 returns a Swoosh email struct", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert %Swoosh.Email{} = email
  end

  test "subject includes CN number and invoice number", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert email.subject =~ cn.credit_note_number
    assert email.subject =~ cn.invoice.invoice_number
  end

  test "sends to affiliated person when no billing_contact", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert {"", "bill@acme.com"} in email.to
  end

  test "body includes reason when set", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert email.html_body =~ "Test reason"
  end

  test "body includes negated line total", %{cn: cn} do
    email = CreditNoteEmail.build(cn)
    assert email.html_body =~ "-500"
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mailer/credit_note_email_test.exs --trace 2>&1
```

Expected: compile error — `CreditNoteEmail` does not exist yet.

- [ ] **Step 3: Create CreditNoteEmail**

Create `lib/garden/mailer/credit_note_email.ex`:

```elixir
defmodule GnomeGarden.Mailer.CreditNoteEmail do
  @moduledoc """
  Builds branded credit note emails.

  Usage:
    credit_note |> CreditNoteEmail.build() |> GnomeGarden.Mailer.deliver()

  `credit_note` must have loaded:
    - :credit_note_lines
    - :invoice (for invoice_number)
    - organization: [:billing_contact]
  """

  import Swoosh.Email

  alias GnomeGarden.Mailer.InvoiceEmail

  @spec build(map()) :: Swoosh.Email.t()
  def build(credit_note) do
    org = credit_note.organization
    contact_email = InvoiceEmail.find_billing_email(org || %{})
    invoice_number = (credit_note.invoice && credit_note.invoice.invoice_number) || "N/A"
    org_name = (org && org.name) || "Client"

    new()
    |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
    |> to(contact_email || "billing@gnomeautomation.io")
    |> subject("Credit Note #{credit_note.credit_note_number} — Invoice #{invoice_number} has been credited")
    |> html_body(build_html(credit_note, org_name, invoice_number))
  end

  defp build_html(credit_note, org_name, invoice_number) do
    lines_html =
      (credit_note.credit_note_lines || [])
      |> Enum.map(fn line ->
        """
        <tr>
          <td style="padding:10px 16px;border-bottom:1px solid #e2e8f0;">#{line.description}</td>
          <td style="padding:10px 16px;border-bottom:1px solid #e2e8f0;text-align:right;">#{format_amount(line.line_total)}</td>
        </tr>
        """
      end)
      |> Enum.join("")

    reason_html =
      if credit_note.reason do
        """
        <p style="margin:0 0 16px;color:#1e293b;"><strong>Reason:</strong> #{credit_note.reason}</p>
        """
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
                <p style="margin:0;font-size:18px;font-weight:700;color:#ffffff;">Gnome Automation</p>
                <p style="margin:4px 0 0;font-size:13px;color:#94a3b8;">Credit Note #{credit_note.credit_note_number}</p>
              </td>
            </tr>
            <tr>
              <td style="padding:36px 40px;">
                <p style="margin:0 0 16px;color:#1e293b;">Dear #{org_name},</p>
                <p style="margin:0 0 16px;color:#1e293b;">Please find your credit note below, issued against invoice <strong>#{invoice_number}</strong>.</p>
                #{reason_html}
                <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #e2e8f0;border-radius:8px;overflow:hidden;margin-bottom:24px;">
                  <thead>
                    <tr style="background:#f1f5f9;">
                      <th style="padding:10px 16px;text-align:left;font-size:12px;font-weight:600;color:#64748b;text-transform:uppercase;">Description</th>
                      <th style="padding:10px 16px;text-align:right;font-size:12px;font-weight:600;color:#64748b;text-transform:uppercase;">Amount</th>
                    </tr>
                  </thead>
                  <tbody>#{lines_html}</tbody>
                  <tfoot>
                    <tr style="background:#f8fafc;">
                      <td style="padding:12px 16px;font-weight:700;color:#0f172a;">Credit Total</td>
                      <td style="padding:12px 16px;text-align:right;font-weight:700;color:#dc2626;font-size:16px;">#{credit_note.currency_code} #{format_amount(credit_note.total_amount)}</td>
                    </tr>
                  </tfoot>
                </table>
                <p style="margin:0;color:#64748b;font-size:13px;">Questions? Contact billing@gnomeautomation.io</p>
              </td>
            </tr>
            <tr>
              <td style="background:#f8fafc;padding:20px 40px;border-top:1px solid #e2e8f0;">
                <p style="margin:0;font-size:12px;color:#94a3b8;text-align:center;">Gnome Automation LLC · gnomeautomation.io</p>
              </td>
            </tr>
          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mailer/credit_note_email_test.exs --trace 2>&1
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/garden/mailer/credit_note_email.ex test/garden/mailer/credit_note_email_test.exs
git commit -m "feat: CreditNoteEmail module — branded email with negated line items"
```

---

## Task 3: Invoice show page — Credit Note card + create handler

**Files:**
- Modify: `lib/garden_web/live/finance/invoice_live/show.ex`

- [ ] **Step 1: Read the current show.ex**

Read `lib/garden_web/live/finance/invoice_live/show.ex` in full to understand the template structure, existing sections, and the `load_invoice!/2` function (around line 221).

- [ ] **Step 2: Add `credit_note: []` to the load**

In `load_invoice!/2` (around line 221), add `credit_note: []` to the `load:` list:

```elixir
defp load_invoice!(id, actor) do
  case Finance.get_invoice(
         id,
         actor: actor,
         load: [
           :status_variant,
           :line_count,
           :payment_application_count,
           :line_total_amount,
           :applied_amount,
           :credit_note,           # <-- add this line
           organization: [],
           agreement: [],
           project: [],
           work_order: [],
           invoice_lines: [],      # <-- keep this; required by create_credit_note_lines/3
           payment_applications: [payment: []]
         ]
       ) do
    {:ok, invoice} -> invoice
    {:error, error} -> raise "failed to load invoice #{id}: #{inspect(error)}"
  end
end
```

- [ ] **Step 3: Add Credit Note card to template**

In the `render/1` function, after the closing `</div>` of the `grid gap-6 lg:grid-cols-2` div (or after the last `</.section>` block), add:

```heex
<%!-- Credit Note card — only shown for void invoices --%>
<.section :if={@invoice.status == :void} title="Credit Note">
  <div class="px-5 py-4">
    <%= if @invoice.credit_note do %>
      <p class="text-sm text-zinc-600 mb-3">
        Credit note <strong>{@invoice.credit_note.credit_note_number}</strong>
        has been created
        (<.status_badge status={@invoice.credit_note.status_variant}>
          {format_atom(@invoice.credit_note.status)}
        </.status_badge>).
      </p>
      <.button navigate={~p"/finance/credit-notes/#{@invoice.credit_note.id}"}>
        View Credit Note
      </.button>
    <% else %>
      <p class="text-sm text-zinc-400 italic mb-3">
        No credit note has been created yet. Create one to give the client a reconcilable document.
      </p>
      <.button phx-click="create_credit_note" variant="primary">
        Create Credit Note
      </.button>
    <% end %>
  </div>
</.section>
```

- [ ] **Step 4: Add Finance and Commercial aliases**

At the top of the module, ensure these aliases exist (add if missing):

```elixir
alias GnomeGarden.Finance
```

- [ ] **Step 5: Add handle_event for create_credit_note**

Add after the existing `handle_event("transition", ...)` handler:

```elixir
@impl true
def handle_event("create_credit_note", _params, socket) do
  invoice = socket.assigns.invoice
  actor = socket.assigns.current_user

  n = Finance.next_sequence_value("credit_notes")
  cn_number = Finance.format_credit_note_number(n)

  with {:ok, credit_note} <-
         Finance.create_credit_note(
           %{
             credit_note_number: cn_number,
             invoice_id: invoice.id,
             organization_id: invoice.organization_id,
             total_amount: Decimal.negate(invoice.total_amount || Decimal.new("0")),
             currency_code: invoice.currency_code || "USD"
           },
           actor: actor
         ),
       {:ok, _} <- create_credit_note_lines(credit_note, invoice.invoice_lines, actor) do
    {:noreply,
     socket
     |> push_navigate(to: ~p"/finance/credit-notes/#{credit_note.id}")}
  else
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Could not create credit note: #{inspect(reason)}")}
  end
end

defp create_credit_note_lines(credit_note, invoice_lines, actor) do
  invoice_lines
  |> Enum.with_index(1)
  |> Enum.reduce_while({:ok, []}, fn {line, position}, {:ok, acc} ->
    attrs = %{
      credit_note_id: credit_note.id,
      position: position,
      description: line.description || "",
      quantity: line.quantity,
      unit_price: line.unit_price && Decimal.negate(line.unit_price),
      line_total: Decimal.negate(line.line_total || Decimal.new("0"))
    }

    case Finance.create_credit_note_line(attrs, actor: actor) do
      {:ok, cn_line} -> {:cont, {:ok, [cn_line | acc]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end)
end
```

- [ ] **Step 6: Verify it compiles**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury && GNOME_GARDEN_DB_PORT=5432 mix compile 2>&1
```

Expected: no errors.

- [ ] **Step 7: Run existing invoice tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/finance/ --trace 2>&1 | tail -20
```

Expected: no new failures.

- [ ] **Step 8: Commit**

```bash
git add lib/garden_web/live/finance/invoice_live/show.ex
git commit -m "feat: add Credit Note card and create handler to invoice show page"
```

---

## Task 4: Credit Note LiveViews + routing + nav

**Files:**
- Create: `lib/garden_web/live/finance/credit_note_live/show.ex`
- Create: `lib/garden_web/live/finance/credit_note_live/index.ex`
- Modify: `lib/garden_web/router.ex`
- Modify: `lib/garden_web/components/nav.ex`
- Create: `test/garden_web/live/credit_note_live_test.exs`

- [ ] **Step 1: Read router and nav for patterns**

Read `lib/garden_web/router.ex` (find the Finance live_session block) and `lib/garden_web/components/nav.ex` (find the Finance subnav) before writing any code.

- [ ] **Step 2: Add routes**

In `lib/garden_web/router.ex`, in the Finance live_session block (alongside `/finance/invoices`, `/finance/ar-aging`), add:

```elixir
live "/finance/credit-notes", Finance.CreditNoteLive.Index, :index
live "/finance/credit-notes/:id", Finance.CreditNoteLive.Show, :show
```

- [ ] **Step 3: Add nav link**

In `lib/garden_web/components/nav.ex`, in the Finance subnav section (alongside the AR Aging link), add a Credit Notes link following the exact same pattern as the AR Aging entry.

- [ ] **Step 4: Create the index LiveView**

Create `lib/garden_web/live/finance/credit_note_live/index.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.CreditNoteLive.Index do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    credit_notes = load_credit_notes(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Credit Notes")
     |> assign(:credit_notes, credit_notes)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Credit Notes
        <:subtitle>All credit notes issued against voided invoices.</:subtitle>
      </.page_header>

      <.section>
        <div :if={Enum.empty?(@credit_notes)} class="px-5 py-8 text-sm text-zinc-400 italic text-center">
          No credit notes yet. Void an invoice to create one.
        </div>
        <table :if={not Enum.empty?(@credit_notes)} class="min-w-full divide-y divide-zinc-200 text-sm">
          <thead class="bg-zinc-50">
            <tr>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">CN Number</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Invoice</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Client</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Total</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Status</th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Issued</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200">
            <tr :for={cn <- @credit_notes}>
              <td class="px-5 py-3">
                <.link navigate={~p"/finance/credit-notes/#{cn.id}"} class="font-medium text-emerald-600 hover:underline">
                  {cn.credit_note_number}
                </.link>
              </td>
              <td class="px-5 py-3 text-zinc-600">
                <.link navigate={~p"/finance/invoices/#{cn.invoice_id}"} class="hover:underline">
                  {cn.invoice && cn.invoice.invoice_number}
                </.link>
              </td>
              <td class="px-5 py-3 text-zinc-600">
                {cn.organization && cn.organization.name}
              </td>
              <td class="px-5 py-3 text-right font-medium">
                {cn.currency_code} {format_amount(cn.total_amount)}
              </td>
              <td class="px-5 py-3">
                <.status_badge status={cn.status_variant}>{cn.status}</.status_badge>
              </td>
              <td class="px-5 py-3 text-zinc-600">{cn.issued_on || "—"}</td>
            </tr>
          </tbody>
        </table>
      </.section>
    </.page>
    """
  end

  defp load_credit_notes(actor) do
    query =
      GnomeGarden.Finance.CreditNote
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.load([:status_variant, :invoice, :organization])

    case Finance.list_credit_notes(query: query, actor: actor, authorize?: false) do
      {:ok, cns} -> cns
      _ -> []
    end
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end
```

- [ ] **Step 5: Create the show LiveView**

Create `lib/garden_web/live/finance/credit_note_live/show.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.CreditNoteLive.Show do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.CreditNoteEmail

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    credit_note = load_credit_note!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, credit_note.credit_note_number)
     |> assign(:credit_note, credit_note)}
  end

  @impl true
  def handle_event("issue_and_send", _params, socket) do
    cn = socket.assigns.credit_note
    actor = socket.assigns.current_user

    case Finance.issue_credit_note(cn, actor: actor) do
      {:ok, issued} ->
        loaded = load_credit_note!(issued.id, actor)

        result =
          loaded
          |> CreditNoteEmail.build()
          |> Mailer.deliver()

        flash =
          case result do
            {:ok, _} ->
              {:info,
               "Credit note #{cn.credit_note_number} issued and sent to #{recipient_email(loaded)}"}

            {:error, _} ->
              {:error,
               "Credit note issued but email delivery failed — please resend manually."}
          end

        {level, msg} = flash

        {:noreply,
         socket
         |> assign(:credit_note, loaded)
         |> put_flash(level, msg)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not issue: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("save_reason", %{"reason" => reason}, socket) do
    case Finance.update_credit_note(socket.assigns.credit_note, %{reason: reason},
           actor: socket.assigns.current_user
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:credit_note, updated)
         |> put_flash(:info, "Reason saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save reason")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        {@credit_note.credit_note_number}
        <:subtitle>
          <span class="inline-flex items-center gap-2">
            <.status_badge status={@credit_note.status_variant}>
              {@credit_note.status}
            </.status_badge>
            <span class="text-zinc-400">/</span>
            <.link navigate={~p"/finance/invoices/#{@credit_note.invoice_id}"} class="hover:underline">
              Invoice {@credit_note.invoice && @credit_note.invoice.invoice_number}
            </.link>
          </span>
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/credit-notes"}>
            <.icon name="hero-arrow-left" class="size-4" /> Back
          </.button>
          <.button
            :if={@credit_note.status == :draft}
            phx-click="issue_and_send"
            variant="primary"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Issue & Send
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-6 lg:grid-cols-2">
        <.section title="Details">
          <div class="px-5 py-4 space-y-3 text-sm">
            <div>
              <p class="text-xs font-semibold uppercase tracking-widest text-zinc-400 mb-1">Client</p>
              <p>{@credit_note.organization && @credit_note.organization.name}</p>
            </div>
            <div>
              <p class="text-xs font-semibold uppercase tracking-widest text-zinc-400 mb-1">Total (Credit)</p>
              <p class="font-semibold text-red-600">{@credit_note.currency_code} {format_amount(@credit_note.total_amount)}</p>
            </div>
            <div :if={@credit_note.issued_on}>
              <p class="text-xs font-semibold uppercase tracking-widest text-zinc-400 mb-1">Issued On</p>
              <p>{@credit_note.issued_on}</p>
            </div>
          </div>
        </.section>

        <.section title="Reason">
          <div class="px-5 py-4">
            <form phx-submit="save_reason">
              <textarea
                name="reason"
                rows="3"
                placeholder="Optional — e.g. 'Duplicate invoice', 'Client dispute'"
                class="w-full border border-zinc-300 rounded px-3 py-2 text-sm"
                disabled={@credit_note.status != :draft}
              >{@credit_note.reason}</textarea>
              <button
                :if={@credit_note.status == :draft}
                type="submit"
                class="mt-2 text-sm text-emerald-600 hover:underline"
              >
                Save reason
              </button>
            </form>
          </div>
        </.section>
      </div>

      <.section title="Credit Note Lines" class="mt-6">
        <table class="min-w-full divide-y divide-zinc-200 text-sm">
          <thead class="bg-zinc-50">
            <tr>
              <th class="px-5 py-3 text-left font-medium text-zinc-500">Description</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Qty</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Unit Price</th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500">Line Total</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200">
            <tr :for={line <- @credit_note.credit_note_lines}>
              <td class="px-5 py-3">{line.description}</td>
              <td class="px-5 py-3 text-right">{line.quantity}</td>
              <td class="px-5 py-3 text-right">{format_amount(line.unit_price)}</td>
              <td class="px-5 py-3 text-right text-red-600">{format_amount(line.line_total)}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="bg-zinc-50">
              <td colspan="3" class="px-5 py-3 font-medium">Total</td>
              <td class="px-5 py-3 text-right font-semibold text-red-600">
                {@credit_note.currency_code} {format_amount(@credit_note.total_amount)}
              </td>
            </tr>
          </tfoot>
        </table>
      </.section>
    </.page>
    """
  end

  defp load_credit_note!(id, actor) do
    case Finance.get_credit_note(id,
           actor: actor,
           load: [
             :status_variant,
             :credit_note_lines,
             :invoice,
             organization: [:billing_contact]
           ]
         ) do
      {:ok, cn} -> cn
      {:error, err} -> raise "failed to load credit note #{id}: #{inspect(err)}"
    end
  end

  defp recipient_email(credit_note) do
    GnomeGarden.Mailer.InvoiceEmail.find_billing_email(credit_note.organization || %{}) ||
      "billing@gnomeautomation.io"
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end
```

- [ ] **Step 6: Write tests**

Create `test/garden_web/live/credit_note_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Finance.CreditNoteLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "CN Live Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Bill",
        last_name: "Payer",
        email: "live@acme.com"
      })

    Operations.create_organization_affiliation(%{
      organization_id: org.id,
      person_id: person.id
    })

    {:ok, invoice} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-LIVE-#{System.unique_integer([:positive])}",
        currency_code: "USD",
        total_amount: Decimal.new("750.00"),
        balance_amount: Decimal.new("750.00")
      })

    {:ok, invoice} = Finance.issue_invoice(invoice)
    {:ok, invoice} = Finance.void_invoice(invoice)

    %{org: org, invoice: invoice}
  end

  test "voided invoice show page displays Create Credit Note button", %{conn: conn, invoice: invoice} do
    {:ok, _view, html} = live(conn, ~p"/finance/invoices/#{invoice.id}")
    assert html =~ "Create Credit Note"
  end

  test "clicking Create Credit Note redirects to credit note show page", %{conn: conn, invoice: invoice} do
    {:ok, view, _html} = live(conn, ~p"/finance/invoices/#{invoice.id}")

    # push_navigate triggers a live_redirect — capture it and assert on the path
    {:error, {:live_redirect, %{to: path}}} =
      view |> element("button", "Create Credit Note") |> render_click()

    assert path =~ "/finance/credit-notes/"
  end

  test "credit note show page renders CN number", %{conn: conn, org: org, invoice: invoice} do
    n = Finance.next_sequence_value("credit_notes")
    cn_number = Finance.format_credit_note_number(n)

    {:ok, cn} =
      Finance.create_credit_note(%{
        credit_note_number: cn_number,
        invoice_id: invoice.id,
        organization_id: org.id,
        total_amount: Decimal.new("-750.00"),
        currency_code: "USD"
      })

    {:ok, _view, html} = live(conn, ~p"/finance/credit-notes/#{cn.id}")
    assert html =~ cn_number
  end

  test "credit note index page renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/credit-notes")
    assert html =~ "Credit Notes"
  end
end
```

- [ ] **Step 7: Run tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/credit_note_live_test.exs --trace 2>&1
```

Expected: all tests PASS. If the `assert_redirected` pattern doesn't work (depends on LiveView version), use `follow_redirect` instead.

- [ ] **Step 8: Run full test suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -10
```

Expected: 0 new failures vs baseline.

- [ ] **Step 9: Commit**

```bash
git add lib/garden_web/live/finance/credit_note_live/ \
        lib/garden_web/router.ex \
        lib/garden_web/components/nav.ex \
        test/garden_web/live/finance/credit_note_live_test.exs
git commit -m "feat: CreditNote LiveViews (show + index) + routing + nav link"
```

---

## Final Verification

- [ ] **Push branch**

```bash
git push
```

- [ ] **Smoke test checklist**

Start the dev server (`GNOME_GARDEN_DB_PORT=5432 mix phx.server`) and manually verify:
1. Navigate to a draft or issued invoice → Void it → "Credit Note" section appears with "Create Credit Note" button
2. Click "Create Credit Note" → redirected to `/finance/credit-notes/CN-XXXX`
3. Verify CN number formatted correctly (e.g., `CN-0001`)
4. Verify lines are present with negated amounts
5. Set a reason and save
6. Click "Issue & Send" → status changes to `:issued`, flash shows email sent
7. Navigate to `/finance/credit-notes` → credit note appears in list
8. Navigate to the original invoice → "View Credit Note" link appears instead of "Create" button
9. Click "View Credit Note" → navigates back to credit note show page
