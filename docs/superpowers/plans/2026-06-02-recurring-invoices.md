# Recurring Invoices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add recurring invoice templates that auto-generate and optionally auto-issue fixed-amount invoices on a configurable schedule (daily/weekly/monthly/quarterly/semi-annually/annually).

**Architecture:** Two new Ash resources (`RecurringInvoice` + `RecurringInvoiceLine`) store templates. An Oban worker runs daily and generates real `Finance.Invoice` + `Finance.InvoiceLine` records from active templates. Four LiveView files handle list/form/show UI. The existing `GLPoster` notifier fires automatically when auto-issued invoices are created — no GL changes needed.

**Tech Stack:** Elixir/Phoenix, Ash Framework, AshPostgres, Oban (worker scheduling), LiveView, Tailwind CSS (emerald theme)

---

## File Structure

**New files:**
- `lib/garden/finance/recurring_invoice.ex` — Ash resource: schedule template
- `lib/garden/finance/recurring_invoice_line.ex` — Ash resource: line item template
- `lib/garden/finance/recurring_invoice_worker.ex` — Oban daily worker
- `lib/garden_web/live/finance/recurring_invoice_live/index.ex` — list all templates
- `lib/garden_web/live/finance/recurring_invoice_live/form.ex` — create/edit template
- `lib/garden_web/live/finance/recurring_invoice_live/show.ex` — view template + generated invoices
- `test/garden/finance/recurring_invoice_worker_test.exs` — worker unit tests
- `test/garden_web/live/finance/recurring_invoice_live_test.exs` — LiveView smoke tests

**Modified files:**
- `lib/garden_web/live/finance/helpers.ex` — add `format_currency/1`
- `lib/garden_web/live/finance/dashboard_live.ex` — remove duplicate `defp format_currency`, import from helpers
- `lib/garden/finance/invoice.ex` — add `recurring_invoice_id` attribute
- `lib/garden/finance.ex` — register new resources + define code interfaces
- `lib/garden_web/router.ex` — add 4 routes
- `lib/garden_web/components/rail_nav.ex` — add `fin-recurring` nav entry
- `config/config.exs` — add cron entry for RecurringInvoiceWorker
- `lib/garden_web/live/operations/organization_live/show.ex` — add "Set up recurring invoice" button

---

## Task 1: Extract format_currency/1 to shared Finance.Helpers

**Files:**
- Modify: `lib/garden_web/live/finance/helpers.ex`
- Modify: `lib/garden_web/live/finance/dashboard_live.ex`

The `format_currency/1` function currently lives as a `defp` in `DashboardLive`. It needs to be shared across all recurring invoice LiveViews. Move it to the shared helpers module.

- [ ] **Step 1: Add format_currency/1 to helpers.ex**

Open `lib/garden_web/live/finance/helpers.ex`. After the `format_amount/1` functions, add:

```elixir
def format_currency(nil), do: "—"
def format_currency(%Decimal{} = amount) do
  rounded = Decimal.round(amount, 2) |> Decimal.to_string()
  [integer_part, decimal_part] = String.split(rounded, ".")
  {sign, digits} =
    if String.starts_with?(integer_part, "-"),
      do: {"-", String.slice(integer_part, 1..-1//1)},
      else: {"", integer_part}
  formatted =
    digits
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  "#{sign}$#{formatted}.#{decimal_part}"
end
```

- [ ] **Step 2: Update dashboard_live.ex to use the shared helper**

In `lib/garden_web/live/finance/dashboard_live.ex`:

1. Confirm `import GnomeGardenWeb.Finance.Helpers` is at the top of the module (or add it after `use GnomeGardenWeb, :live_view`)
2. Remove the two `defp format_currency` clauses (they're now public functions in Helpers)

The existing `format_currency` calls in the template (e.g., `format_currency(@cash_position)`) will continue to work via the import.

- [ ] **Step 3: Compile to verify**

```bash
cd /home/bhammoud/gnome_garden_mercury && mix compile
```

Expected: `Generated gnome_garden app` with no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/garden_web/live/finance/helpers.ex lib/garden_web/live/finance/dashboard_live.ex
git commit -m "refactor: extract format_currency/1 to Finance.Helpers"
```

---

## Task 2: RecurringInvoice + RecurringInvoiceLine Ash resources + migrations

**Files:**
- Create: `lib/garden/finance/recurring_invoice.ex`
- Create: `lib/garden/finance/recurring_invoice_line.ex`
- Modify: `lib/garden/finance/invoice.ex` (add `recurring_invoice_id`)

**Context:** Follow the exact pattern of `lib/garden/finance/invoice.ex` and `lib/garden/finance/invoice_line.ex`. Use `AshPostgres.DataLayer`. The `Finance` domain is `GnomeGarden.Finance`.

- [ ] **Step 1: Create recurring_invoice.ex**

Create `lib/garden/finance/recurring_invoice.ex`:

```elixir
defmodule GnomeGarden.Finance.RecurringInvoice do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_recurring_invoices"
    repo GnomeGarden.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:active, :paused, :stopped]
      default :active
      allow_nil? false
    end

    attribute :interval, :atom do
      constraints one_of: [:daily, :weekly, :monthly, :quarterly, :semi_annually, :annually]
      allow_nil? false
    end

    attribute :net_terms_days, :integer do
      default 30
      allow_nil? false
    end

    attribute :start_date, :date, allow_nil?: false
    attribute :end_date, :date, allow_nil?: true
    attribute :next_generation_date, :date, allow_nil?: false

    attribute :delivery_mode, :atom do
      constraints one_of: [:auto_issue, :draft]
      default :auto_issue
      allow_nil? false
    end

    attribute :tax_rate, :decimal do
      default Decimal.new(0)
      allow_nil? false
    end

    attribute :notes, :string, allow_nil?: true

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
    end

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      allow_nil? true
    end

    has_many :recurring_invoice_lines, GnomeGarden.Finance.RecurringInvoiceLine
    has_many :invoices, GnomeGarden.Finance.Invoice
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :status, :interval, :net_terms_days, :start_date, :end_date,
        :next_generation_date, :delivery_mode, :tax_rate, :notes,
        :organization_id, :agreement_id
      ]
    end

    update :update do
      accept [
        :status, :interval, :net_terms_days, :start_date, :end_date,
        :next_generation_date, :delivery_mode, :tax_rate, :notes,
        :organization_id, :agreement_id
      ]
    end

    update :pause do
      accept []
      change set_attribute(:status, :paused)
    end

    update :resume do
      accept []
      change set_attribute(:status, :active)
    end

    update :stop do
      accept []
      change set_attribute(:status, :stopped)
    end

    update :advance_schedule do
      accept [:next_generation_date, :status]
    end
  end
end
```

- [ ] **Step 2: Create recurring_invoice_line.ex**

Create `lib/garden/finance/recurring_invoice_line.ex`:

```elixir
defmodule GnomeGarden.Finance.RecurringInvoiceLine do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_recurring_invoice_lines"
    repo GnomeGarden.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :line_number, :integer do
      default 1
      allow_nil? false
    end

    attribute :line_kind, :atom do
      constraints one_of: [:labor, :expense, :material, :service, :adjustment, :tax, :other]
      default :service
      allow_nil? false
    end

    attribute :description, :string, allow_nil?: false
    attribute :quantity, :decimal, allow_nil?: false
    attribute :unit_price, :decimal, allow_nil?: false
    attribute :line_total, :decimal, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :recurring_invoice, GnomeGarden.Finance.RecurringInvoice do
      allow_nil? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:line_number, :line_kind, :description, :quantity, :unit_price, :line_total, :recurring_invoice_id]
    end

    update :update do
      accept [:line_number, :line_kind, :description, :quantity, :unit_price, :line_total]
    end
  end
end
```

- [ ] **Step 3: Add recurring_invoice_id to Invoice**

Open `lib/garden/finance/invoice.ex`. In the `attributes do` block, after the last attribute (before `timestamps()`), add:

```elixir
attribute :recurring_invoice_id, :uuid, allow_nil?: true
```

Also add it to the `create` and `update` action `accept` lists so it can be set when generating from a template.

Find the `create` action's `accept` list and add `:recurring_invoice_id`. Find the `update` action's `accept` list and add `:recurring_invoice_id`.

- [ ] **Step 4: Generate and run migrations**

```bash
cd /home/bhammoud/gnome_garden_mercury && mix ash.codegen recurring_invoices
```

Review the generated migration file in `priv/repo/migrations/` — it should create two new tables and add one column to `finance_invoices`.

```bash
mix ash.migrate
```

Expected: migration runs cleanly.

- [ ] **Step 5: Compile to verify**

```bash
mix compile
```

Expected: clean compile, no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/garden/finance/recurring_invoice.ex lib/garden/finance/recurring_invoice_line.ex lib/garden/finance/invoice.ex priv/repo/migrations/
git commit -m "feat: add RecurringInvoice and RecurringInvoiceLine Ash resources"
```

---

## Task 3: Finance domain registration

**Files:**
- Modify: `lib/garden/finance.ex`

The `Finance` domain module at `lib/garden/finance.ex` must register both new resources and expose code interfaces. Without this, the resources can't be queried through the domain.

- [ ] **Step 1: Register RecurringInvoice in the domain**

Open `lib/garden/finance.ex`. In the `resources do` block, add after the existing `Invoice` resource block:

```elixir
resource GnomeGarden.Finance.RecurringInvoice do
  define :list_recurring_invoices, action: :read
  define :get_recurring_invoice, action: :read, get_by: [:id]
  define :create_recurring_invoice, action: :create
  define :update_recurring_invoice, action: :update
  define :pause_recurring_invoice, action: :pause
  define :resume_recurring_invoice, action: :resume
  define :stop_recurring_invoice, action: :stop
  define :advance_recurring_invoice_schedule, action: :advance_schedule
end

resource GnomeGarden.Finance.RecurringInvoiceLine do
  define :list_recurring_invoice_lines, action: :read
  define :create_recurring_invoice_line, action: :create
  define :update_recurring_invoice_line, action: :update
  define :destroy_recurring_invoice_line, action: :destroy
end
```

- [ ] **Step 2: Compile to verify domain loads**

```bash
mix compile
```

Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add lib/garden/finance.ex
git commit -m "feat: register RecurringInvoice resources in Finance domain"
```

---

## Task 4: RecurringInvoiceWorker + cron registration

**Files:**
- Create: `lib/garden/finance/recurring_invoice_worker.ex`
- Modify: `config/config.exs`
- Create: `test/garden/finance/recurring_invoice_worker_test.exs`

**Pattern to follow:** `lib/garden/finance/payment_reminder_worker.ex` — same queue, same Oban.Worker pattern.

- [ ] **Step 1: Write worker tests first**

Create `test/garden/finance/recurring_invoice_worker_test.exs`:

```elixir
defmodule GnomeGarden.Finance.RecurringInvoiceWorkerTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Finance.RecurringInvoiceWorker

  describe "advance_date/2" do
    test "daily advances by 1 day" do
      date = ~D[2026-06-01]
      assert RecurringInvoiceWorker.advance_date(date, :daily) == ~D[2026-06-02]
    end

    test "weekly advances by 7 days" do
      date = ~D[2026-06-01]
      assert RecurringInvoiceWorker.advance_date(date, :weekly) == ~D[2026-06-08]
    end

    test "monthly advances by 1 month" do
      date = ~D[2026-01-31]
      assert RecurringInvoiceWorker.advance_date(date, :monthly) == ~D[2026-02-28]
    end

    test "quarterly advances by 3 months" do
      date = ~D[2026-03-01]
      assert RecurringInvoiceWorker.advance_date(date, :quarterly) == ~D[2026-06-01]
    end

    test "semi_annually advances by 6 months" do
      date = ~D[2026-01-01]
      assert RecurringInvoiceWorker.advance_date(date, :semi_annually) == ~D[2026-07-01]
    end

    test "annually advances by 1 year" do
      date = ~D[2026-06-01]
      assert RecurringInvoiceWorker.advance_date(date, :annually) == ~D[2027-06-01]
    end
  end

  describe "compute_totals/2" do
    test "computes subtotal, tax_total, total_amount correctly" do
      lines = [
        %{quantity: Decimal.new("2"), unit_price: Decimal.new("100.00")},
        %{quantity: Decimal.new("1"), unit_price: Decimal.new("50.00")}
      ]
      tax_rate = Decimal.new("10")
      result = RecurringInvoiceWorker.compute_totals(lines, tax_rate)
      assert Decimal.equal?(result.subtotal, Decimal.new("250.00"))
      assert Decimal.equal?(result.tax_total, Decimal.new("25"))
      assert Decimal.equal?(result.total_amount, Decimal.new("275"))
    end

    test "zero tax rate produces zero tax_total" do
      lines = [%{quantity: Decimal.new("1"), unit_price: Decimal.new("500.00")}]
      result = RecurringInvoiceWorker.compute_totals(lines, Decimal.new("0"))
      assert Decimal.equal?(result.tax_total, Decimal.new("0"))
      assert Decimal.equal?(result.total_amount, Decimal.new("500.00"))
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/garden/finance/recurring_invoice_worker_test.exs --no-start 2>&1 | tail -5
```

Expected: compilation error (module doesn't exist yet).

- [ ] **Step 3: Create the worker**

Create `lib/garden/finance/recurring_invoice_worker.ex`:

```elixir
defmodule GnomeGarden.Finance.RecurringInvoiceWorker do
  @moduledoc """
  Oban cron worker that generates invoices from active recurring invoice templates.

  Runs daily at 7am UTC. For each active RecurringInvoice where next_generation_date
  <= today, creates a Finance.Invoice (and its lines), optionally issues it, then
  advances next_generation_date by the template's interval.

  If an end_date is set and the new next_generation_date exceeds it, sets status :stopped.
  """

  use Oban.Worker, queue: :finance, max_attempts: 3

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringInvoice

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    RecurringInvoice
    |> Ash.Query.filter(status == :active)
    |> Ash.Query.filter(next_generation_date <= ^today)
    |> Ash.Query.load([:recurring_invoice_lines])
    |> Ash.read!(domain: Finance, authorize?: false)
    |> Enum.each(&generate_invoice(&1, today))

    :ok
  end

  defp generate_invoice(template, today) do
    lines = template.recurring_invoice_lines
    totals = compute_totals(lines, template.tax_rate)
    due_on = Date.add(today, template.net_terms_days)

    invoice_attrs = %{
      organization_id: template.organization_id,
      agreement_id: template.agreement_id,
      tax_rate: template.tax_rate,
      notes: template.notes,
      due_on: due_on,
      recurring_invoice_id: template.id,
      subtotal: totals.subtotal,
      tax_total: totals.tax_total,
      total_amount: totals.total_amount
    }

    case Finance.create_invoice(invoice_attrs, authorize?: false) do
      {:ok, invoice} ->
        create_lines(invoice, lines)
        maybe_issue(invoice, template.delivery_mode)
        advance_schedule(template, today)

      {:error, reason} ->
        Logger.error(
          "RecurringInvoiceWorker: failed to create invoice for template #{template.id}: #{inspect(reason)}"
        )
    end
  end

  defp create_lines(invoice, lines) do
    Enum.each(lines, fn line ->
      attrs = %{
        invoice_id: invoice.id,
        organization_id: invoice.organization_id,
        description: line.description,
        quantity: line.quantity,
        unit_price: line.unit_price,
        line_total: line.line_total,
        line_kind: line.line_kind,
        line_number: line.line_number
      }

      case Finance.create_invoice_line(attrs, authorize?: false) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.error("RecurringInvoiceWorker: failed to create line: #{inspect(reason)}")
      end
    end)
  end

  defp maybe_issue(invoice, :auto_issue) do
    case Finance.issue_invoice(invoice, authorize?: false) do
      {:ok, _} ->
        Logger.info("RecurringInvoiceWorker: issued invoice #{invoice.id}")
      {:error, reason} ->
        Logger.error("RecurringInvoiceWorker: failed to issue invoice #{invoice.id}: #{inspect(reason)}")
    end
  end

  defp maybe_issue(_invoice, :draft), do: :ok

  defp advance_schedule(template, today) do
    new_date = advance_date(template.next_generation_date, template.interval)

    new_status =
      if template.end_date && Date.compare(new_date, template.end_date) == :gt,
        do: :stopped,
        else: template.status

    Finance.advance_recurring_invoice_schedule(template,
      %{next_generation_date: new_date, status: new_status},
      authorize?: false
    )
  end

  # Public so it can be unit-tested without a database
  def advance_date(date, :daily), do: Date.add(date, 1)
  def advance_date(date, :weekly), do: Date.add(date, 7)
  def advance_date(date, :monthly), do: Date.shift(date, month: 1)
  def advance_date(date, :quarterly), do: Date.shift(date, month: 3)
  def advance_date(date, :semi_annually), do: Date.shift(date, month: 6)
  def advance_date(date, :annually), do: Date.shift(date, year: 1)

  def compute_totals(lines, tax_rate) do
    subtotal =
      Enum.reduce(lines, Decimal.new("0"), fn line, acc ->
        Decimal.add(acc, Decimal.mult(line.quantity, line.unit_price))
      end)

    tax_total = Decimal.mult(subtotal, Decimal.div(tax_rate, Decimal.new("100")))
    total_amount = Decimal.add(subtotal, tax_total)

    %{subtotal: subtotal, tax_total: tax_total, total_amount: total_amount}
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/garden/finance/recurring_invoice_worker_test.exs --no-start 2>&1 | tail -10
```

Expected: all tests pass (these are pure unit tests, no DB needed).

- [ ] **Step 5: Add cron entry to config/config.exs**

Find the `crontab:` list in `config/config.exs` (around line 120). Add after the PaymentReminderWorker line:

```elixir
{"0 7 * * *", GnomeGarden.Finance.RecurringInvoiceWorker}
```

- [ ] **Step 6: Compile to verify**

```bash
mix compile
```

Expected: clean compile.

- [ ] **Step 7: Commit**

```bash
git add lib/garden/finance/recurring_invoice_worker.ex config/config.exs test/garden/finance/recurring_invoice_worker_test.exs
git commit -m "feat: add RecurringInvoiceWorker with daily cron schedule"
```

---

## Task 5: Routes + Nav entry

**Files:**
- Modify: `lib/garden_web/router.ex`
- Modify: `lib/garden_web/components/rail_nav.ex`

- [ ] **Step 1: Add routes to router.ex**

Open `lib/garden_web/router.ex`. After the `# Finance - Dashboard` block (after line with `Finance.DashboardLive`), add:

```elixir
# Finance - Recurring Invoices
live "/finance/recurring-invoices", Finance.RecurringInvoiceLive.Index, :index
live "/finance/recurring-invoices/new", Finance.RecurringInvoiceLive.Form, :new
live "/finance/recurring-invoices/:id", Finance.RecurringInvoiceLive.Show, :show
live "/finance/recurring-invoices/:id/edit", Finance.RecurringInvoiceLive.Form, :edit
```

- [ ] **Step 2: Add nav entry to rail_nav.ex**

Open `lib/garden_web/components/rail_nav.ex`. After the `fin-dashboard` map (around line 312), add:

```elixir
%{
  id: "fin-recurring",
  section: "Finance",
  icon: "hero-arrow-path",
  label: "Recurring",
  tooltip: "Recurring invoice templates — auto-generate invoices on a schedule",
  path: "/finance/recurring-invoices",
  badge: 0,
  hot: false,
  match: ["/finance/recurring-invoices"]
},
```

- [ ] **Step 3: Compile to verify**

```bash
mix compile
```

Expected: warnings about undefined modules (LiveView files don't exist yet) but no hard errors — Phoenix routes compile lazily.

- [ ] **Step 4: Commit**

```bash
git add lib/garden_web/router.ex lib/garden_web/components/rail_nav.ex
git commit -m "feat: add recurring invoices routes and nav entry"
```

---

## Task 6: Index LiveView

**Files:**
- Create: `lib/garden_web/live/finance/recurring_invoice_live/index.ex`

**Pattern:** Follow `lib/garden_web/live/finance/invoice_live/index.ex` for structure. No Cinder needed — simple list with no complex filtering.

- [ ] **Step 1: Create index.ex**

Create `lib/garden_web/live/finance/recurring_invoice_live/index.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.RecurringInvoiceLive.Index do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringInvoice

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    templates = load_templates()

    {:ok,
     socket
     |> assign(:page_title, "Recurring Invoices")
     |> assign(:templates, templates)}
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    template = Ash.get!(RecurringInvoice, id, domain: Finance, authorize?: false)
    Finance.pause_recurring_invoice(template, authorize?: false)
    {:noreply, assign(socket, :templates, load_templates())}
  end

  @impl true
  def handle_event("resume", %{"id" => id}, socket) do
    template = Ash.get!(RecurringInvoice, id, domain: Finance, authorize?: false)
    Finance.resume_recurring_invoice(template, authorize?: false)
    {:noreply, assign(socket, :templates, load_templates())}
  end

  defp load_templates do
    RecurringInvoice
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load([:organization, :recurring_invoice_lines])
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  defp template_amount(template) do
    template.recurring_invoice_lines
    |> Enum.reduce(Decimal.new(0), fn line, acc -> Decimal.add(acc, line.line_total) end)
  end

  defp interval_label(:daily), do: "Daily"
  defp interval_label(:weekly), do: "Weekly"
  defp interval_label(:monthly), do: "Monthly"
  defp interval_label(:quarterly), do: "Quarterly"
  defp interval_label(:semi_annually), do: "Semi-annually"
  defp interval_label(:annually), do: "Annually"

  defp status_variant(:active), do: "success"
  defp status_variant(:paused), do: "warning"
  defp status_variant(:stopped), do: "default"

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Recurring Invoices
        <:subtitle>
          Templates that auto-generate invoices on a schedule. Active templates run daily.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/recurring-invoices/new"} variant="primary">
            New Recurring Invoice
          </.button>
        </:actions>
      </.page_header>

      <%= if Enum.empty?(@templates) do %>
        <.empty_state
          icon="hero-arrow-path"
          title="No recurring invoices yet"
          description="Set one up to auto-bill clients on a schedule."
        >
          <:action>
            <.button navigate={~p"/finance/recurring-invoices/new"} variant="primary">
              New Recurring Invoice
            </.button>
          </:action>
        </.empty_state>
      <% else %>
        <.table>
          <:col :let={t} label="Client">
            <.link navigate={~p"/finance/recurring-invoices/#{t.id}"} class="font-medium text-base-content hover:underline">
              {(t.organization && t.organization.name) || "—"}
            </.link>
          </:col>
          <:col :let={t} label="Interval">{interval_label(t.interval)}</:col>
          <:col :let={t} label="Amount per invoice">{format_currency(template_amount(t))}</:col>
          <:col :let={t} label="Next invoice">
            <%= if t.status in [:stopped, :paused] do %>
              <span class="text-base-content/40">—</span>
            <% else %>
              {format_date(t.next_generation_date)}
            <% end %>
          </:col>
          <:col :let={t} label="Status">
            <.status_badge variant={status_variant(t.status)}>{format_atom(t.status)}</.status_badge>
          </:col>
          <:col :let={t} label="">
            <div class="flex gap-2 justify-end">
              <.button navigate={~p"/finance/recurring-invoices/#{t.id}/edit"} size="sm">Edit</.button>
              <%= if t.status == :active do %>
                <.button phx-click="pause" phx-value-id={t.id} size="sm">Pause</.button>
              <% end %>
              <%= if t.status == :paused do %>
                <.button phx-click="resume" phx-value-id={t.id} size="sm" variant="primary">Resume</.button>
              <% end %>
              <.button navigate={~p"/finance/recurring-invoices/#{t.id}"} size="sm">View</.button>
            </div>
          </:col>
        </.table>
      <% end %>
    </.page>
    """
  end
end
```

- [ ] **Step 2: Compile to verify**

```bash
mix compile
```

Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add lib/garden_web/live/finance/recurring_invoice_live/index.ex
git commit -m "feat: add RecurringInvoiceLive.Index list page"
```

---

## Task 7: Form LiveView (new + edit)

**Files:**
- Create: `lib/garden_web/live/finance/recurring_invoice_live/form.ex`

**Key patterns:**
- Lines are managed as in-memory assigns (list of maps), same pattern as `journal_entry_live/new.ex`
- On save: create/update the template record, then delete all existing lines and recreate from form state
- `params["organization_id"]` pre-selects client when coming from org show page
- Hints below dropdowns use `class="mt-1.5 text-xs text-base-content/50"` with emerald link

- [ ] **Step 1: Create form.ex**

Create `lib/garden_web/live/finance/recurring_invoice_live/form.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.RecurringInvoiceLive.Form do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringInvoice
  alias GnomeGarden.Finance.RecurringInvoiceLine
  alias GnomeGarden.Operations

  require Ash.Query

  @empty_line %{
    "description" => "",
    "quantity" => "1",
    "unit_price" => "",
    "line_kind" => "service"
  }

  @impl true
  def mount(params, _session, socket) do
    organizations = Operations.list_organizations!(authorize?: false)

    {template, lines, title} =
      case params["id"] do
        nil ->
          {nil, [@empty_line], "New Recurring Invoice"}

        id ->
          t =
            RecurringInvoice
            |> Ash.Query.load([:recurring_invoice_lines])
            |> Ash.get!(id, domain: Finance, authorize?: false)

          existing_lines =
            Enum.map(t.recurring_invoice_lines, fn l ->
              %{
                "description" => l.description,
                "quantity" => Decimal.to_string(l.quantity),
                "unit_price" => Decimal.to_string(l.unit_price),
                "line_kind" => to_string(l.line_kind)
              }
            end)

          {t, existing_lines, "Edit Recurring Invoice"}
      end

    return_to = params["return_to"] || ~p"/finance/recurring-invoices"

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:template, template)
     |> assign(:lines, lines)
     |> assign(:organizations, organizations)
     |> assign(:return_to, return_to)
     |> assign(:errors, [])
     |> maybe_preselect_org(params["organization_id"])}
  end

  defp maybe_preselect_org(socket, nil), do: socket

  defp maybe_preselect_org(socket, org_id),
    do: assign(socket, :preselected_org_id, org_id)

  @impl true
  def handle_event("add_line", _params, socket) do
    {:noreply, assign(socket, :lines, socket.assigns.lines ++ [@empty_line])}
  end

  @impl true
  def handle_event("remove_line", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    new_lines = List.delete_at(socket.assigns.lines, idx)
    {:noreply, assign(socket, :lines, new_lines)}
  end

  @impl true
  def handle_event("save", %{"template" => params, "lines" => lines_params}, socket) do
    lines = normalize_lines(lines_params)

    with {:ok, template} <- save_template(socket.assigns.template, params, socket.assigns),
         :ok <- save_lines(template, lines) do
      {:noreply,
       socket
       |> put_flash(:info, "Recurring invoice saved.")
       |> push_navigate(to: socket.assigns.return_to)}
    else
      {:error, errors} ->
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  defp normalize_lines(nil), do: []
  defp normalize_lines(lines) when is_list(lines), do: lines
  defp normalize_lines(lines) when is_map(lines) do
    lines
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_, v} -> v end)
  end

  defp save_template(nil, params, assigns) do
    # Set next_generation_date = start_date on create
    start_date = parse_date(params["start_date"])
    attrs = build_attrs(params) |> Map.put(:next_generation_date, start_date)

    case Finance.create_recurring_invoice(attrs, authorize?: false) do
      {:ok, t} -> {:ok, t}
      {:error, err} -> {:error, [inspect(err)]}
    end
  end

  defp save_template(template, params, _assigns) do
    attrs = build_attrs(params)

    case Finance.update_recurring_invoice(template, attrs, authorize?: false) do
      {:ok, t} -> {:ok, t}
      {:error, err} -> {:error, [inspect(err)]}
    end
  end

  defp build_attrs(params) do
    %{
      organization_id: params["organization_id"],
      agreement_id: blank_to_nil(params["agreement_id"]),
      interval: String.to_existing_atom(params["interval"]),
      net_terms_days: String.to_integer(params["net_terms_days"] || "30"),
      start_date: parse_date(params["start_date"]),
      end_date: parse_date(params["end_date"]),
      delivery_mode: String.to_existing_atom(params["delivery_mode"]),
      status: String.to_existing_atom(params["status"]),
      tax_rate: parse_decimal(params["tax_rate"]),
      notes: blank_to_nil(params["notes"])
    }
  end

  defp save_lines(template, lines) do
    # Delete existing lines first (on edit)
    existing =
      RecurringInvoiceLine
      |> Ash.Query.filter(recurring_invoice_id == ^template.id)
      |> Ash.read!(domain: Finance, authorize?: false)

    Enum.each(existing, &Ash.destroy!(&1, domain: Finance, authorize?: false))

    # Create new lines
    lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, idx} ->
      qty = parse_decimal(line["quantity"])
      price = parse_decimal(line["unit_price"])
      total = Decimal.mult(qty, price)

      Finance.create_recurring_invoice_line(
        %{
          recurring_invoice_id: template.id,
          line_number: idx,
          description: line["description"],
          quantity: qty,
          unit_price: price,
          line_total: total,
          line_kind: String.to_existing_atom(line["line_kind"] || "service")
        },
        authorize?: false
      )
    end)

    :ok
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str), do: Date.from_iso8601!(str)

  defp parse_decimal(nil), do: Decimal.new(0)
  defp parse_decimal(""), do: Decimal.new(0)
  defp parse_decimal(str), do: Decimal.new(str)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp compute_subtotal(lines) do
    Enum.reduce(lines, Decimal.new(0), fn line, acc ->
      qty = parse_decimal(line["quantity"])
      price = parse_decimal(line["unit_price"])
      Decimal.add(acc, Decimal.mult(qty, price))
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        {@page_title}
        <:actions>
          <.button navigate={@return_to}>Cancel</.button>
        </:actions>
      </.page_header>

      <form phx-submit="save" class="space-y-8">
        <%!-- Section 1: Schedule --%>
        <div class="border-b border-gray-900/10 pb-12 dark:border-white/10">
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Schedule</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">Who to bill, how often, and when.</p>

          <div class="mt-6 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
            <%!-- Client --%>
            <div class="sm:col-span-3">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Client <span class="text-red-500">*</span>
              </label>
              <div class="mt-2">
                <select name="template[organization_id]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="">Select client…</option>
                  <%= for org <- @organizations do %>
                    <option value={org.id} selected={selected_org?(@template, org.id, assigns[:preselected_org_id])}>{org.name}</option>
                  <% end %>
                </select>
              </div>
              <p class="mt-1.5 text-xs text-base-content/50">
                Organization not in the list?
                <.link navigate={~p"/operations/organizations/new?return_to=#{~p"/finance/recurring-invoices/new"}"} class="underline text-emerald-600 dark:text-emerald-400">Create one first</.link>.
              </p>
            </div>

            <%!-- Agreement --%>
            <div class="sm:col-span-3">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Agreement <span class="text-gray-400 font-normal">(optional)</span>
              </label>
              <div class="mt-2">
                <select name="template[agreement_id]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="">None</option>
                </select>
              </div>
              <p class="mt-1.5 text-xs text-base-content/50">
                No agreement yet?
                <.link navigate={~p"/commercial/agreements/new?return_to=#{~p"/finance/recurring-invoices/new"}"} class="underline text-emerald-600 dark:text-emerald-400">Create one first</.link>.
              </p>
            </div>

            <%!-- Interval --%>
            <div class="sm:col-span-2">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Repeats <span class="text-red-500">*</span>
              </label>
              <div class="mt-2">
                <select name="template[interval]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="daily" selected={selected_interval?(@template, :daily)}>Daily</option>
                  <option value="weekly" selected={selected_interval?(@template, :weekly)}>Weekly</option>
                  <option value="monthly" selected={selected_interval?(@template, :monthly)}>Monthly</option>
                  <option value="quarterly" selected={selected_interval?(@template, :quarterly)}>Quarterly</option>
                  <option value="semi_annually" selected={selected_interval?(@template, :semi_annually)}>Semi-annually</option>
                  <option value="annually" selected={selected_interval?(@template, :annually)}>Annually</option>
                </select>
              </div>
            </div>

            <%!-- Net Terms --%>
            <div class="sm:col-span-2">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Net Terms</label>
              <div class="mt-2">
                <select name="template[net_terms_days]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="15" selected={selected_net_terms?(@template, 15)}>Net 15</option>
                  <option value="30" selected={selected_net_terms?(@template, 30)}>Net 30</option>
                  <option value="45" selected={selected_net_terms?(@template, 45)}>Net 45</option>
                  <option value="60" selected={selected_net_terms?(@template, 60)}>Net 60</option>
                  <option value="90" selected={selected_net_terms?(@template, 90)}>Net 90</option>
                </select>
              </div>
            </div>

            <%!-- Delivery mode --%>
            <div class="sm:col-span-2">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">When generated</label>
              <div class="mt-2">
                <select name="template[delivery_mode]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="auto_issue" selected={selected_delivery?(@template, :auto_issue)}>Auto-issue & send</option>
                  <option value="draft" selected={selected_delivery?(@template, :draft)}>Save as draft</option>
                </select>
              </div>
            </div>

            <%!-- First Invoice Date --%>
            <div class="sm:col-span-3">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                First Invoice Date <span class="text-red-500">*</span>
              </label>
              <div class="mt-2">
                <input
                  type="date"
                  name="template[start_date]"
                  value={date_value(@template && @template.start_date)}
                  class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                />
              </div>
            </div>

            <%!-- End Date --%>
            <div class="sm:col-span-3">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                End Date <span class="text-gray-400 font-normal">(optional)</span>
              </label>
              <div class="mt-2">
                <input
                  type="date"
                  name="template[end_date]"
                  value={date_value(@template && @template.end_date)}
                  class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                />
              </div>
            </div>

            <%!-- Status --%>
            <div class="sm:col-span-2">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">Status</label>
              <div class="mt-2">
                <select name="template[status]" class="block w-full appearance-none rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500">
                  <option value="active" selected={selected_status?(@template, :active)}>Active</option>
                  <option value="paused" selected={selected_status?(@template, :paused)}>Paused</option>
                </select>
              </div>
            </div>
          </div>
        </div>

        <%!-- Section 2: Line Items --%>
        <div>
          <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Line Items</h2>
          <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">Same items will appear on every generated invoice.</p>

          <div class="mt-6 overflow-hidden rounded-lg border border-gray-200 dark:border-white/10">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-white/10">
              <thead>
                <tr class="bg-gray-50 dark:bg-white/5">
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">Description</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400 w-24">Qty</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400 w-32">Unit Price</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400 w-32">Total</th>
                  <th class="w-10"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100 dark:divide-white/5">
                <%= for {line, idx} <- Enum.with_index(@lines) do %>
                  <tr>
                    <td class="px-4 py-2">
                      <input type="text" name={"lines[#{idx}][description]"} value={line["description"]} placeholder="Description" class="block w-full rounded-md bg-white px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500" />
                      <input type="hidden" name={"lines[#{idx}][line_kind]"} value={line["line_kind"] || "service"} />
                    </td>
                    <td class="px-4 py-2">
                      <input type="number" name={"lines[#{idx}][quantity]"} value={line["quantity"]} step="0.01" class="block w-full rounded-md bg-white px-3 py-1.5 text-sm text-right text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500" />
                    </td>
                    <td class="px-4 py-2">
                      <input type="number" name={"lines[#{idx}][unit_price]"} value={line["unit_price"]} step="0.01" placeholder="0.00" class="block w-full rounded-md bg-white px-3 py-1.5 text-sm text-right text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500" />
                    </td>
                    <td class="px-4 py-2 text-right text-sm text-gray-900 dark:text-white">
                      {format_currency(Decimal.mult(parse_decimal_assign(line["quantity"]), parse_decimal_assign(line["unit_price"])))}
                    </td>
                    <td class="px-4 py-2 text-center">
                      <.button type="button" phx-click="remove_line" phx-value-index={idx} size="sm" class="text-red-500 hover:text-red-700">✕</.button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
            <div class="px-4 py-3 border-t border-gray-100 dark:border-white/5">
              <.button type="button" phx-click="add_line">+ Add line</.button>
            </div>
          </div>

          <%!-- Tax + Total --%>
          <div class="mt-4 flex items-end justify-between gap-6">
            <div class="w-48">
              <label class="block text-sm/6 font-medium text-gray-900 dark:text-white">
                Tax Rate <span class="text-gray-400 font-normal">(optional %)</span>
              </label>
              <div class="mt-2">
                <input
                  type="number"
                  name="template[tax_rate]"
                  value={@template && Decimal.to_string(@template.tax_rate) || "0"}
                  step="0.01"
                  min="0"
                  max="100"
                  class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus:outline-emerald-500"
                />
              </div>
            </div>
            <div class="text-right">
              <div class="text-sm text-gray-500 dark:text-gray-400">Total per invoice</div>
              <div class="text-2xl font-bold text-gray-900 dark:text-white">
                {format_currency(compute_subtotal(@lines))}
              </div>
            </div>
          </div>
        </div>

        <%!-- Schedule Preview --%>
        <p class="mt-3 text-sm text-gray-500 dark:text-gray-400">
          Next invoice: <strong class="text-gray-700 dark:text-gray-300">{format_date(@template && @template.next_generation_date)}</strong>
          {schedule_preview(@template && @template.next_generation_date, @template && @template.interval)}
        </p>

        <%!-- Actions --%>
        <div class="flex justify-end gap-4 pt-4 border-t border-gray-200 dark:border-white/10">
          <.button navigate={@return_to}>Cancel</.button>
          <.button type="submit" variant="primary">Save Recurring Invoice</.button>
        </div>
      </form>
    </.page>
    """
  end

  # Helpers for template value binding
  defp selected_org?(nil, _org_id, preselected), do: preselected != nil and preselected == _org_id
  defp selected_org?(template, org_id, _pre), do: to_string(template.organization_id) == to_string(org_id)

  defp selected_interval?(nil, :monthly), do: true
  defp selected_interval?(nil, _), do: false
  defp selected_interval?(t, interval), do: t.interval == interval

  defp selected_net_terms?(nil, 30), do: true
  defp selected_net_terms?(nil, _), do: false
  defp selected_net_terms?(t, days), do: t.net_terms_days == days

  defp selected_delivery?(nil, :auto_issue), do: true
  defp selected_delivery?(nil, _), do: false
  defp selected_delivery?(t, mode), do: t.delivery_mode == mode

  defp selected_status?(nil, :active), do: true
  defp selected_status?(nil, _), do: false
  defp selected_status?(t, status), do: t.status == status

  defp date_value(nil), do: ""
  defp date_value(%Date{} = d), do: Date.to_iso8601(d)

  defp parse_decimal_assign(nil), do: Decimal.new(0)
  defp parse_decimal_assign(""), do: Decimal.new(0)
  defp parse_decimal_assign(s) do
    case Decimal.parse(s) do
      {d, ""} -> d
      _ -> Decimal.new(0)
    end
  end

  defp schedule_preview(nil, _interval), do: ""
  defp schedule_preview(_date, nil), do: ""
  defp schedule_preview(date, interval) do
    next1 = GnomeGarden.Finance.RecurringInvoiceWorker.advance_date(date, interval)
    next2 = GnomeGarden.Finance.RecurringInvoiceWorker.advance_date(next1, interval)
    " → #{format_date(next1)} → #{format_date(next2)} → …"
  end
end
```

- [ ] **Step 2: Compile to verify**

```bash
mix compile
```

Expected: clean compile. Fix any warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/garden_web/live/finance/recurring_invoice_live/form.ex
git commit -m "feat: add RecurringInvoiceLive.Form new/edit page"
```

---

## Task 8: Show LiveView

**Files:**
- Create: `lib/garden_web/live/finance/recurring_invoice_live/show.ex`

- [ ] **Step 1: Create show.ex**

Create `lib/garden_web/live/finance/recurring_invoice_live/show.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.RecurringInvoiceLive.Show do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.RecurringInvoice
  alias GnomeGarden.Finance.Invoice

  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    template =
      RecurringInvoice
      |> Ash.Query.load([:organization, :agreement, :recurring_invoice_lines])
      |> Ash.get!(id, domain: Finance, authorize?: false)

    generated_invoices = load_generated_invoices(id)

    {:ok,
     socket
     |> assign(:page_title, "Recurring Invoice")
     |> assign(:template, template)
     |> assign(:generated_invoices, generated_invoices)}
  end

  defp load_generated_invoices(recurring_invoice_id) do
    Invoice
    |> Ash.Query.filter(recurring_invoice_id == ^recurring_invoice_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load([:organization])
    |> Ash.read!(domain: Finance, authorize?: false)
  end

  @impl true
  def handle_event("pause", _params, socket) do
    {:ok, updated} = Finance.pause_recurring_invoice(socket.assigns.template, authorize?: false)
    {:noreply, assign(socket, :template, updated)}
  end

  @impl true
  def handle_event("resume", _params, socket) do
    {:ok, updated} = Finance.resume_recurring_invoice(socket.assigns.template, authorize?: false)
    {:noreply, assign(socket, :template, updated)}
  end

  @impl true
  def handle_event("stop", _params, socket) do
    {:ok, updated} = Finance.stop_recurring_invoice(socket.assigns.template, authorize?: false)
    {:noreply, assign(socket, :template, updated)}
  end

  defp status_variant(:active), do: "success"
  defp status_variant(:paused), do: "warning"
  defp status_variant(:stopped), do: "default"

  defp interval_label(:daily), do: "Daily"
  defp interval_label(:weekly), do: "Weekly"
  defp interval_label(:monthly), do: "Monthly"
  defp interval_label(:quarterly), do: "Quarterly"
  defp interval_label(:semi_annually), do: "Semi-annually"
  defp interval_label(:annually), do: "Annually"

  defp template_amount(template) do
    template.recurring_invoice_lines
    |> Enum.reduce(Decimal.new(0), fn line, acc -> Decimal.add(acc, line.line_total) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Recurring Invoice
        <:subtitle>
          {(@template.organization && @template.organization.name) || "—"} · {interval_label(@template.interval)}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/recurring-invoices"}>Back</.button>
          <.button navigate={~p"/finance/recurring-invoices/#{@template.id}/edit"}>Edit</.button>
          <%= if @template.status == :active do %>
            <.button phx-click="pause">Pause</.button>
          <% end %>
          <%= if @template.status == :paused do %>
            <.button phx-click="resume" variant="primary">Resume</.button>
            <.button phx-click="stop">Stop</.button>
          <% end %>
        </:actions>
      </.page_header>

      <%!-- Summary --%>
      <.section title="Template Details">
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Status</div>
            <.status_badge variant={status_variant(@template.status)}>{format_atom(@template.status)}</.status_badge>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Interval</div>
            <div class="text-sm font-medium">{interval_label(@template.interval)}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Next Invoice</div>
            <div class="text-sm font-medium">
              <%= if @template.status in [:stopped, :paused] do %>
                <span class="text-base-content/40">—</span>
              <% else %>
                {format_date(@template.next_generation_date)}
              <% end %>
            </div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Amount</div>
            <div class="text-sm font-medium">{format_currency(template_amount(@template))}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Net Terms</div>
            <div class="text-sm font-medium">Net {@template.net_terms_days}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Delivery</div>
            <div class="text-sm font-medium">{format_atom(@template.delivery_mode)}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">Start Date</div>
            <div class="text-sm font-medium">{format_date(@template.start_date)}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/50 uppercase tracking-wide">End Date</div>
            <div class="text-sm font-medium">{format_date(@template.end_date) || "—"}</div>
          </div>
        </div>
      </.section>

      <%!-- Line Items --%>
      <.section title="Line Items" class="mt-6">
        <.table>
          <:col :let={line} label="Description">{line.description}</:col>
          <:col :let={line} label="Qty">{line.quantity}</:col>
          <:col :let={line} label="Unit Price">{format_currency(line.unit_price)}</:col>
          <:col :let={line} label="Total">{format_currency(line.line_total)}</:col>
        </.table>
        <div class="mt-3 text-right text-sm font-semibold text-gray-900 dark:text-white">
          Total: {format_currency(template_amount(@template))}
        </div>
      </.section>

      <%!-- Generated Invoices --%>
      <.section title="Generated Invoices" class="mt-6">
        <%= if Enum.empty?(@generated_invoices) do %>
          <p class="text-sm text-base-content/50">No invoices generated yet.</p>
        <% else %>
          <.table>
            <:col :let={inv} label="Invoice">
              <.link navigate={~p"/finance/invoices/#{inv.id}?return_to=#{~p"/finance/recurring-invoices/#{@template.id}"}"} class="font-medium hover:underline">
                {inv.invoice_number || "Draft"}
              </.link>
            </:col>
            <:col :let={inv} label="Issued">{format_date(inv.issued_on)}</:col>
            <:col :let={inv} label="Due">{format_date(inv.due_on)}</:col>
            <:col :let={inv} label="Amount">{format_currency(inv.total_amount)}</:col>
            <:col :let={inv} label="Status">
              <.status_badge variant={status_variant(inv.status)}>{format_atom(inv.status)}</.status_badge>
            </:col>
          </.table>
        <% end %>
      </.section>
    </.page>
    """
  end
end
```

- [ ] **Step 2: Compile to verify**

```bash
mix compile
```

Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add lib/garden_web/live/finance/recurring_invoice_live/show.ex
git commit -m "feat: add RecurringInvoiceLive.Show page with generated invoice history"
```

---

## Task 9: Org show page button + smoke tests

**Files:**
- Modify: `lib/garden_web/live/operations/organization_live/show.ex`
- Create: `test/garden_web/live/finance/recurring_invoice_live_test.exs`

- [ ] **Step 1: Add button to org show page**

Open `lib/garden_web/live/operations/organization_live/show.ex`. Find the Finance-related actions section (search for "invoice" in the file). In an appropriate location (near the Invoice/Payment action buttons), add:

```heex
<.button navigate={~p"/finance/recurring-invoices/new?organization_id=#{@organization.id}&return_to=#{~p"/operations/organizations/#{@organization}"}"}>
  Set up recurring invoice
</.button>
```

If there's no obvious Finance section, add it alongside the "New Invoice" or payment buttons. Read the file first to find the right location.

- [ ] **Step 2: Create smoke tests**

Create `test/garden_web/live/finance/recurring_invoice_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Finance.RecurringInvoiceLiveTest do
  use GnomeGardenWeb.ConnCase

  import GnomeGarden.AccountsFixtures

  setup :register_and_log_in_user

  describe "Index" do
    test "renders recurring invoices list page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/finance/recurring-invoices")
      assert html =~ "Recurring Invoices"
      assert html =~ "New Recurring Invoice"
    end
  end

  describe "Form" do
    test "renders new recurring invoice form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/finance/recurring-invoices/new")
      assert html =~ "New Recurring Invoice"
      assert html =~ "Schedule"
      assert html =~ "Line Items"
      assert html =~ "Add line"
    end
  end
end
```

- [ ] **Step 3: Compile to verify**

```bash
mix compile
```

Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add lib/garden_web/live/operations/organization_live/show.ex test/garden_web/live/finance/recurring_invoice_live_test.exs
git commit -m "feat: add recurring invoice button to org show page + smoke tests"
```

---

## Final verification

- [ ] **Run worker unit tests** (no DB needed):

```bash
mix test test/garden/finance/recurring_invoice_worker_test.exs --no-start 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Push to remote**

```bash
git push
```
