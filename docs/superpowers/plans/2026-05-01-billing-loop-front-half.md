# Billing Loop Front Half — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the front half of the billing loop: log hours → submit for approval → approve → generate invoice on demand → issue invoice with branded email containing Mercury payment instructions.

**Architecture:** Additive changes to the existing Ash `Agreement` resource (`default_bill_rate`), targeted modifications to two existing LiveViews (TimeEntry index + form), three new files (ApprovalQueueLive, InvoiceLive.Review, InvoiceEmail), a bug fix + refactor of InvoiceSchedulerWorker, and two new router entries plus a nav link.

**Tech Stack:** Elixir/Phoenix LiveView, Ash Framework (AshStateMachine, AshPostgres, AshPhoenix.Form), Swoosh email, Oban

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Modify | `lib/garden/commercial/agreement.ex` | Add `default_bill_rate` decimal attribute |
| Create | `priv/repo/migrations/TIMESTAMP_add_default_bill_rate_to_agreements.exs` | Ash-generated migration |
| Modify | `lib/garden_web/live/finance/time_entry_live/form.ex` | Add `maybe_fill_bill_rate/2` and call in validate handler |
| Modify | `lib/garden_web/live/finance/time_entry_live/index.ex` | Add Submit button column + `handle_event("submit", ...)` |
| Create | `lib/garden_web/live/finance/approval_queue_live.ex` | Approval Queue page |
| Modify | `lib/garden_web/live/commercial/agreement_live/show.ex` | Add Generate Invoice button + handler |
| Create | `lib/garden_web/live/finance/invoice_live/review.ex` | Invoice Review + Issue page |
| Create | `lib/garden/mailer/invoice_email.ex` | Branded email builder with Mercury payment instructions |
| Modify | `lib/garden/mercury/invoice_scheduler_worker.ex` | Fix `line.amount` bug, use InvoiceEmail, remove inline email |
| Modify | `config/runtime.exs` | Add `:mercury_payment_info` config key |
| Modify | `config/dev.exs` | Add test values for `:mercury_payment_info` |
| Modify | `lib/garden_web/router.ex` | Add 2 new routes |
| Modify | `lib/garden_web/components/nav.ex` | Add Approval Queue to Finance subnav |
| Create | `test/garden/commercial/agreement_default_bill_rate_test.exs` | Tests for new attribute |
| Create | `test/garden/mailer/invoice_email_test.exs` | Tests for InvoiceEmail.build/2 |

---

## Context for Implementers

This codebase uses Ash Framework. Key patterns used throughout:

**Domain shortcuts** (the ONLY way to call Ash actions in this project — never use `Ash.create!` / `Ash.update!` directly in application code, only in tests):
```elixir
Finance.submit_time_entry(entry, actor: actor)        # -> {:ok, updated} | {:error, ...}
Finance.approve_time_entry(entry, actor: actor)       # -> {:ok, updated} | {:error, ...}
Finance.create_invoice_from_agreement_sources(agreement_id, actor: actor)  # -> {:ok, invoice} | {:error, ...}
Finance.issue_invoice(invoice, actor: actor)          # -> {:ok, issued} | {:error, ...}
Finance.get_invoice(id, actor: actor, load: [...])    # -> {:ok, invoice} | {:error, ...}
Finance.update_invoice(invoice, %{...}, actor: actor) # -> {:ok, updated} | {:error, ...}
```

**Tests** use `GnomeGarden.DataCase` and call Ash directly (no domain shortcuts in tests):
```elixir
use GnomeGarden.DataCase, async: true
# Create records:
GnomeGarden.Commercial.Agreement
|> Ash.Changeset.for_create(:create, %{...})
|> Ash.create!(domain: GnomeGarden.Commercial)
```

**Working directory for all commands:** `/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury`

---

## Task 1: Add `default_bill_rate` to Agreement

**Files:**
- Modify: `lib/garden/commercial/agreement.ex`
- Create: `priv/repo/migrations/TIMESTAMP_add_default_bill_rate_to_agreements.exs` (Ash-generated)
- Create: `test/garden/commercial/agreement_default_bill_rate_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/garden/commercial/agreement_default_bill_rate_test.exs`:

```elixir
defmodule GnomeGarden.Commercial.AgreementDefaultBillRateTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Rate Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })
      |> Ash.create(domain: Operations)

    %{org: org}
  end

  test "can create agreement with default_bill_rate", %{org: org} do
    {:ok, agreement} =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "T&M Agreement",
        default_bill_rate: Decimal.new("195.00")
      })
      |> Ash.create(domain: Commercial)

    assert Decimal.equal?(agreement.default_bill_rate, Decimal.new("195.00"))
  end

  test "default_bill_rate is optional — nil by default", %{org: org} do
    {:ok, agreement} =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "Fixed Fee Agreement"
      })
      |> Ash.create(domain: Commercial)

    assert is_nil(agreement.default_bill_rate)
  end

  test "can update default_bill_rate on existing agreement", %{org: org} do
    {:ok, agreement} =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "Updatable Agreement"
      })
      |> Ash.create(domain: Commercial)

    {:ok, updated} =
      agreement
      |> Ash.Changeset.for_update(:update, %{default_bill_rate: Decimal.new("245.00")})
      |> Ash.update(domain: Commercial)

    assert Decimal.equal?(updated.default_bill_rate, Decimal.new("245.00"))
  end
end
```

- [ ] **Step 2: Run the test — verify it fails**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix test test/garden/commercial/agreement_default_bill_rate_test.exs
```

Expected: compilation error or `field :default_bill_rate not found`

- [ ] **Step 3: Add `default_bill_rate` attribute to Agreement**

Open `lib/garden/commercial/agreement.ex`. In the `attributes do` block, after the existing `:next_billing_date` attribute (around line 318), add:

```elixir
attribute :default_bill_rate, :decimal do
  public? true
end
```

In the `:create` action `accept` list (around line 70), add `:default_bill_rate` after `:next_billing_date`.

In the `:update` action `accept` list (around line 114), add `:default_bill_rate` after `:next_billing_date`.

- [ ] **Step 4: Generate and run the migration**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix ash_postgres.generate_migrations --name add_default_bill_rate_to_agreements
```

Expected: creates a new file in `priv/repo/migrations/` like `20260501XXXXXX_add_default_bill_rate_to_agreements.exs`

```bash
mix ecto.migrate
```

Expected: `== Running ... AddDefaultBillRateToAgreements == ... [up]`

- [ ] **Step 5: Run the test — verify it passes**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix test test/garden/commercial/agreement_default_bill_rate_test.exs
```

Expected: `3 tests, 0 failures`

- [ ] **Step 6: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden/commercial/agreement.ex priv/repo/migrations/ test/garden/commercial/agreement_default_bill_rate_test.exs && git commit -m "feat: add default_bill_rate to Agreement"
```

---

## Task 2: Bill Rate Auto-Fill in TimeEntry Form

**Files:**
- Modify: `lib/garden_web/live/finance/time_entry_live/form.ex:152-163`

The existing `handle_event("validate", ...)` handler is at lines 152–163. The existing `load_agreements/1` already loads `[:organization]` — `default_bill_rate` is a plain attribute on Agreement, so it loads automatically without explicit load.

- [ ] **Step 1: Add `maybe_fill_bill_rate/2` private helper**

At the bottom of `lib/garden_web/live/finance/time_entry_live/form.ex` (before the final `end`), add:

```elixir
defp maybe_fill_bill_rate(%{"agreement_id" => agreement_id} = params, agreements)
     when is_binary(agreement_id) and agreement_id != "" do
  current_rate = params["bill_rate"]

  if is_nil(current_rate) or current_rate == "" do
    agreement = Enum.find(agreements, &(to_string(&1.id) == agreement_id))

    case agreement && agreement.default_bill_rate do
      nil -> params
      rate -> Map.put(params, "bill_rate", Decimal.to_string(rate))
    end
  else
    params
  end
end

defp maybe_fill_bill_rate(params, _agreements), do: params
```

- [ ] **Step 2: Call `maybe_fill_bill_rate/2` in the validate handler**

The existing `handle_event("validate", ...)` at line 152 looks like:

```elixir
def handle_event("validate", %{"form" => params}, socket) do
  form = AshPhoenix.Form.validate(socket.assigns.form, params)
  selected_project_id = blank_to_nil(params["project_id"])
  ...
```

Change the first two lines to call `maybe_fill_bill_rate` before validation:

```elixir
def handle_event("validate", %{"form" => params}, socket) do
  params = maybe_fill_bill_rate(params, socket.assigns.agreements)
  form = AshPhoenix.Form.validate(socket.assigns.form, params)
  selected_project_id = blank_to_nil(params["project_id"])
  ...
```

Leave everything else in the handler unchanged.

- [ ] **Step 3: Verify compilation**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix compile --warnings-as-errors 2>&1 | grep -E "error|warning" | grep -v "deps/" | head -20
```

Expected: no errors or warnings in project files

- [ ] **Step 4: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden_web/live/finance/time_entry_live/form.ex && git commit -m "feat: auto-fill bill rate from agreement default in time entry form"
```

---

## Task 3: Submit Action on TimeEntry Index

**Files:**
- Modify: `lib/garden_web/live/finance/time_entry_live/index.ex`

The existing index renders a table with 5 columns: Entry, Context, Member, Amounts, Status. We add a 6th "Actions" column with a Submit button for `:draft` entries.

- [ ] **Step 1: Add Actions column header**

In the `<thead>` block (after the Status `<th>` around line 113), add:

```heex
<th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
  Actions
</th>
```

- [ ] **Step 2: Add Submit button in each row**

In the `<tr>` for each entry (after the Status `<td>` around line 157), add:

```heex
<td class="px-5 py-4 align-top">
  <button
    :if={time_entry.status == :draft}
    phx-click="submit"
    phx-value-id={time_entry.id}
    class="text-sm font-medium text-emerald-600 hover:text-emerald-700 dark:text-emerald-400"
  >
    Submit
  </button>
</td>
```

- [ ] **Step 3: Add `handle_event("submit", ...)` handler**

After the `mount/3` or `render/1` function (but before the closing `end` of the module), add:

```elixir
@impl true
def handle_event("submit", %{"id" => id}, socket) do
  actor = socket.assigns.current_user

  case Finance.get_time_entry(id, actor: actor) do
    {:ok, time_entry} ->
      case Finance.submit_time_entry(time_entry, actor: actor) do
        {:ok, updated} ->
          # Load :status_variant — the submit action does not load calculations.
          updated =
            Ash.load!(updated, [:status_variant], actor: actor, domain: GnomeGarden.Finance)

          {:noreply,
           socket
           |> put_flash(:info, "Time entry submitted for approval")
           |> stream_insert(:time_entries, updated)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not submit: #{inspect(reason)}")}
      end

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Time entry not found")}
  end
end
```

- [ ] **Step 4: Verify compilation**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix compile --warnings-as-errors 2>&1 | grep -E "error|warning" | grep -v "deps/" | head -20
```

Expected: no errors

- [ ] **Step 5: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden_web/live/finance/time_entry_live/index.ex && git commit -m "feat: add submit action button to time entry index"
```

---

## Task 4: Approval Queue LiveView

**Files:**
- Create: `lib/garden_web/live/finance/approval_queue_live.ex`
- Modify: `lib/garden_web/router.ex`

- [ ] **Step 1: Create the LiveView file**

Create `lib/garden_web/live/finance/approval_queue_live.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.ApprovalQueueLive do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    entries = load_submitted(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Approval Queue")
     |> assign(:count, length(entries))
     |> stream(:entries, entries)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Approval Queue
        <:subtitle>
          Submitted time entries waiting for manager approval before they can be invoiced.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/time-entries"}>
            <.icon name="hero-arrow-left" class="size-4" /> All Time Entries
          </.button>
        </:actions>
      </.page_header>

      <.section
        title={"Submitted Entries (#{@count})"}
        description="Approving an entry marks it ready for invoicing. Rejecting returns it to draft."
        compact
        body_class="p-0"
      >
        <div :if={@count == 0} class="p-6 sm:p-7">
          <.empty_state
            icon="hero-check-badge"
            title="No entries pending approval"
            description="All submitted time entries have been reviewed."
          />
        </div>

        <div :if={@count > 0} class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
            <thead class="bg-zinc-50 dark:bg-white/[0.03]">
              <tr>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Entry
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Member
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Agreement
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Hours / Rate
                </th>
                <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody
              id="approval-entries"
              phx-update="stream"
              class="divide-y divide-zinc-200 dark:divide-white/10"
            >
              <tr :for={{dom_id, entry} <- @streams.entries} id={dom_id}>
                <td class="px-5 py-4 align-top">
                  <div class="space-y-1">
                    <.link
                      navigate={~p"/finance/time-entries/#{entry}"}
                      class="font-medium text-zinc-900 hover:text-emerald-600 dark:text-white"
                    >
                      {entry.description}
                    </.link>
                    <p class="text-sm text-zinc-500 dark:text-zinc-400">
                      {format_date(entry.work_date)}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {display_email(entry.member_user)}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  {(entry.agreement && entry.agreement.name) || "-"}
                </td>
                <td class="px-5 py-4 align-top text-zinc-600 dark:text-zinc-300">
                  <div class="space-y-1">
                    <p>{format_minutes(entry.minutes)}</p>
                    <p class="text-xs text-zinc-400 dark:text-zinc-500">
                      {if entry.bill_rate, do: "$#{entry.bill_rate}/hr", else: "No rate"}
                    </p>
                  </div>
                </td>
                <td class="px-5 py-4 align-top">
                  <div class="flex gap-3">
                    <button
                      phx-click="approve"
                      phx-value-id={entry.id}
                      class="text-sm font-medium text-emerald-600 hover:text-emerald-700 dark:text-emerald-400"
                    >
                      Approve
                    </button>
                    <button
                      phx-click="reject"
                      phx-value-id={entry.id}
                      class="text-sm font-medium text-red-600 hover:text-red-700 dark:text-red-400"
                    >
                      Reject
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.section>
    </.page>
    """
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, entry} <- Finance.get_time_entry(id, actor: actor),
         {:ok, _updated} <- Finance.approve_time_entry(entry, actor: actor) do
      {:noreply,
       socket
       |> put_flash(:info, "Entry approved")
       |> stream_delete(:entries, entry)
       |> assign(:count, socket.assigns.count - 1)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not approve: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, entry} <- Finance.get_time_entry(id, actor: actor),
         {:ok, _updated} <- Finance.reject_time_entry(entry, actor: actor) do
      {:noreply,
       socket
       |> put_flash(:info, "Entry rejected — returned to draft")
       |> stream_delete(:entries, entry)
       |> assign(:count, socket.assigns.count - 1)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not reject: #{inspect(reason)}")}
    end
  end

  defp load_submitted(actor) do
    case Finance.list_time_entries(
           actor: actor,
           query: [filter: [status: :submitted], sort: [work_date: :asc, inserted_at: :asc]],
           load: [:status_variant, organization: [], agreement: [], project: [], member_user: []]
         ) do
      {:ok, entries} -> entries
      {:error, error} -> raise "failed to load approval queue: #{inspect(error)}"
    end
  end
end
```

- [ ] **Step 2: Add route to router**

In `lib/garden_web/router.ex`, inside the `ash_authentication_live_session :authenticated_routes` block, find the Finance time-entry routes (around line 171–175):

```elixir
# Finance - Time Entries
live "/finance/time-entries", Finance.TimeEntryLive.Index, :index
live "/finance/time-entries/new", Finance.TimeEntryLive.Form, :new
live "/finance/time-entries/:id", Finance.TimeEntryLive.Show, :show
live "/finance/time-entries/:id/edit", Finance.TimeEntryLive.Form, :edit
```

Add the approval queue route **before** `live "/finance/time-entries/:id"` to avoid the `:id` catch-all matching "approval-queue":

```elixir
# Finance - Time Entries
live "/finance/time-entries", Finance.TimeEntryLive.Index, :index
live "/finance/time-entries/new", Finance.TimeEntryLive.Form, :new
live "/finance/time-entries/approval-queue", Finance.ApprovalQueueLive, :index
live "/finance/time-entries/:id", Finance.TimeEntryLive.Show, :show
live "/finance/time-entries/:id/edit", Finance.TimeEntryLive.Form, :edit
```

- [ ] **Step 3: Verify compilation**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix compile --warnings-as-errors 2>&1 | grep -E "error|warning" | grep -v "deps/" | head -20
```

Expected: no errors

- [ ] **Step 4: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden_web/live/finance/approval_queue_live.ex lib/garden_web/router.ex && git commit -m "feat: add approval queue LiveView for submitted time entries"
```

---

## Task 5: Generate Invoice Button on Agreement Show

**Files:**
- Modify: `lib/garden_web/live/commercial/agreement_live/show.ex`

The existing show page already has a "Draft Invoice" button (manual form). We add a separate "Generate Invoice" button that auto-generates from approved unbilled entries.

- [ ] **Step 1: Add the `Finance` alias**

At the top of `lib/garden_web/live/commercial/agreement_live/show.ex`, the existing aliases are:

```elixir
alias GnomeGarden.Commercial
```

Add below it:

```elixir
alias GnomeGarden.Finance
```

- [ ] **Step 2: Add the "Generate Invoice" button**

In `render/1`, inside the `<:actions>` block of `<.page_header>`, the existing buttons are around lines 53–73. After the existing "Draft Invoice" button:

```heex
<.button navigate={~p"/finance/invoices/new?agreement_id=#{@agreement.id}"}>
  <.icon name="hero-receipt-percent" class="size-4" /> Draft Invoice
</.button>
```

Add:

```heex
<.button
  :if={@agreement.status == :active}
  phx-click="generate_invoice"
  variant="primary"
>
  <.icon name="hero-document-plus" class="size-4" /> Generate Invoice
</.button>
```

- [ ] **Step 3: Add `handle_event("generate_invoice", ...)`**

After the existing `handle_event("transition", ...)` handler, add:

```elixir
@impl true
def handle_event("generate_invoice", _params, socket) do
  actor = socket.assigns.current_user
  agreement = socket.assigns.agreement

  case Finance.create_invoice_from_agreement_sources(agreement.id, actor: actor) do
    {:ok, invoice} ->
      {:noreply, push_navigate(socket, to: ~p"/finance/invoices/#{invoice.id}/review")}

    {:error, %Ash.Error.Invalid{errors: errors}} ->
      if Enum.any?(errors, fn
           %{message: msg} when is_binary(msg) -> msg =~ "approved billable source records"
           _ -> false
         end) do
        {:noreply,
         put_flash(socket, :info, "No approved billable entries for this agreement yet.")}
      else
        {:noreply,
         put_flash(socket, :error, "Could not generate invoice: #{inspect(errors)}")}
      end

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Could not generate invoice: #{inspect(reason)}")}
  end
end
```

- [ ] **Step 4: Verify compilation**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix compile --warnings-as-errors 2>&1 | grep -E "error|warning" | grep -v "deps/" | head -20
```

Expected: no errors

- [ ] **Step 5: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden_web/live/commercial/agreement_live/show.ex && git commit -m "feat: add Generate Invoice button to agreement show page"
```

---

## Task 6: Invoice Review Page

**Files:**
- Create: `lib/garden_web/live/finance/invoice_live/review.ex`
- Modify: `lib/garden_web/router.ex`

- [ ] **Step 1: Create the review LiveView**

Create `lib/garden_web/live/finance/invoice_live/review.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.InvoiceLive.Review do
  use GnomeGardenWeb, :live_view

  require Logger

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    invoice = load_invoice!(id, socket.assigns.current_user)
    default_due = Date.add(Date.utc_today(), 30)

    {:ok,
     socket
     |> assign(:page_title, "Review Invoice")
     |> assign(:invoice, invoice)
     |> assign(:due_on, invoice.due_on || default_due)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-4xl" class="pb-8">
      <.page_header eyebrow="Finance">
        Review Invoice
        <:subtitle>
          Review the generated line items, set a due date, then issue to send the invoice email.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/finance/invoices/#{@invoice}"}>
            <.icon name="hero-arrow-left" class="size-4" /> View Invoice
          </.button>
        </:actions>
      </.page_header>

      <.section title="Invoice Summary">
        <div class="grid gap-5 sm:grid-cols-3">
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Client</p>
            <p class="text-sm font-medium text-zinc-900 dark:text-white">
              {(@invoice.organization && @invoice.organization.name) || "-"}
            </p>
          </div>
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Total</p>
            <p class="text-sm font-medium text-zinc-900 dark:text-white">
              {format_amount(@invoice.total_amount)}
            </p>
          </div>
          <div class="space-y-1">
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Status</p>
            <.status_badge status={@invoice.status_variant}>
              {format_atom(@invoice.status)}
            </.status_badge>
          </div>
        </div>
      </.section>

      <.section title="Line Items" compact body_class="p-0">
        <table class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
          <thead class="bg-zinc-50 dark:bg-white/[0.03]">
            <tr>
              <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                Description
              </th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                Qty
              </th>
              <th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
                Rate
              </th>
              <th class="px-5 py-3 text-right font-medium text-zinc-500 dark:text-zinc-400">
                Total
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-200 dark:divide-white/10">
            <tr :for={line <- @invoice.invoice_lines}>
              <td class="px-5 py-4 text-zinc-700 dark:text-zinc-300">{line.description}</td>
              <td class="px-5 py-4 text-zinc-500">{line.quantity}</td>
              <td class="px-5 py-4 text-zinc-500">{format_amount(line.unit_price)}</td>
              <td class="px-5 py-4 text-right font-medium text-zinc-900 dark:text-white">
                {format_amount(line.line_total)}
              </td>
            </tr>
          </tbody>
        </table>
      </.section>

      <.section title="Issue Settings">
        <form phx-submit="issue_invoice" class="space-y-4">
          <div class="max-w-xs">
            <label class="block text-sm font-medium text-zinc-700 dark:text-zinc-300 mb-1">
              Due Date
            </label>
            <input
              type="date"
              name="due_on"
              value={@due_on}
              class="block w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm dark:border-white/10 dark:bg-white/[0.03]"
            />
          </div>
          <button
            :if={@invoice.status == :draft}
            type="submit"
            class="inline-flex items-center gap-2 rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Issue & Send Invoice
          </button>
          <p :if={@invoice.status != :draft} class="text-sm text-zinc-500">
            This invoice has already been issued.
          </p>
        </form>
      </.section>
    </.page>
    """
  end

  @impl true
  def handle_event("issue_invoice", %{"due_on" => due_on_str}, socket) do
    actor = socket.assigns.current_user
    invoice = socket.assigns.invoice

    due_on =
      case Date.from_iso8601(due_on_str) do
        {:ok, d} -> d
        _ -> Date.add(Date.utc_today(), 30)
      end

    with {:ok, updated} <- Finance.update_invoice(invoice, %{due_on: due_on}, actor: actor),
         {:ok, issued} <- Finance.issue_invoice(updated, actor: actor) do
      send_invoice_email(issued)

      {:noreply,
       socket
       |> put_flash(:info, "Invoice issued and sent to client")
       |> push_navigate(to: ~p"/finance/invoices/#{issued}")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not issue invoice: #{inspect(reason)}")}
    end
  end

  defp send_invoice_email(invoice) do
    {:ok, loaded} =
      Finance.get_invoice(invoice.id,
        actor: nil,
        load: [:invoice_lines, :organization]
      )

    mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])

    loaded
    |> InvoiceEmail.build(mercury_info)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("InvoiceLive.Review: email send failed", reason: inspect(reason))
    end
  end

  defp load_invoice!(id, actor) do
    case Finance.get_invoice(id,
           actor: actor,
           load: [:status_variant, :invoice_lines, organization: []]
         ) do
      {:ok, invoice} -> invoice
      {:error, error} -> raise "failed to load invoice #{id}: #{inspect(error)}"
    end
  end
end
```

- [ ] **Step 2: Add route to router**

In `lib/garden_web/router.ex`, find the Finance invoice routes (around line 165–169):

```elixir
# Finance - Invoices
live "/finance/invoices", Finance.InvoiceLive.Index, :index
live "/finance/invoices/new", Finance.InvoiceLive.Form, :new
live "/finance/invoices/:id", Finance.InvoiceLive.Show, :show
live "/finance/invoices/:id/edit", Finance.InvoiceLive.Form, :edit
```

Add the review route between Show and Edit (`:id/review` must come before `:id/edit` is fine since both have a static segment after `:id`):

```elixir
# Finance - Invoices
live "/finance/invoices", Finance.InvoiceLive.Index, :index
live "/finance/invoices/new", Finance.InvoiceLive.Form, :new
live "/finance/invoices/:id", Finance.InvoiceLive.Show, :show
live "/finance/invoices/:id/review", Finance.InvoiceLive.Review, :review
live "/finance/invoices/:id/edit", Finance.InvoiceLive.Form, :edit
```

- [ ] **Step 3: Verify compilation**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix compile --warnings-as-errors 2>&1 | grep -E "error|warning" | grep -v "deps/" | head -20
```

Expected: no errors (InvoiceEmail not defined yet — this will cause a compile error; if so, proceed to Task 7 first and come back)

> **Note:** If compilation fails with `InvoiceEmail not defined`, complete Task 7 (create `lib/garden/mailer/invoice_email.ex`) first, then return to verify here.

- [ ] **Step 4: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden_web/live/finance/invoice_live/review.ex lib/garden_web/router.ex && git commit -m "feat: add invoice review page for on-demand invoice issuance"
```

---

## Task 7: InvoiceEmail Module

**Files:**
- Create: `lib/garden/mailer/invoice_email.ex`
- Create: `test/garden/mailer/invoice_email_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/garden/mailer/invoice_email_test.exs`:

```elixir
defmodule GnomeGarden.Mailer.InvoiceEmailTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mailer.InvoiceEmail
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Acme Corp #{System.unique_integer([:positive])}",
        organization_kind: :business
      })
      |> Ash.create(domain: Operations)

    {:ok, invoice} =
      GnomeGarden.Finance.Invoice
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        invoice_number: "INV-0042",
        currency_code: "USD",
        total_amount: Decimal.new("1950.00"),
        balance_amount: Decimal.new("1950.00")
      })
      |> Ash.create(domain: Finance)

    {:ok, loaded} =
      Finance.get_invoice(invoice.id,
        actor: nil,
        load: [:invoice_lines, :organization]
      )

    %{invoice: loaded, org: org}
  end

  test "build/2 returns a Swoosh.Email struct", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, account_number: "123456789", routing_number: "021000021")

    assert %Swoosh.Email{} = email
  end

  test "email is addressed from Gnome Automation billing", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, [])

    assert {"Gnome Automation Billing", "billing@gnomeautomation.io"} = email.from
  end

  test "subject includes invoice number and total", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, [])

    assert email.subject =~ "INV-0042"
    assert email.subject =~ "1950.00"
  end

  test "html body contains invoice number", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, [])

    assert email.html_body =~ "INV-0042"
  end

  test "html body contains Mercury payment instructions when provided", %{invoice: invoice} do
    email =
      InvoiceEmail.build(invoice,
        account_number: "987654321",
        routing_number: "021000021"
      )

    assert email.html_body =~ "987654321"
    assert email.html_body =~ "021000021"
  end

  test "html body contains total amount", %{invoice: invoice} do
    email = InvoiceEmail.build(invoice, [])

    assert email.html_body =~ "1950.00"
  end
end
```

- [ ] **Step 2: Run the test — verify it fails**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix test test/garden/mailer/invoice_email_test.exs
```

Expected: compilation error — `InvoiceEmail` module not found

- [ ] **Step 3: Create the InvoiceEmail module**

Create `lib/garden/mailer/invoice_email.ex`:

```elixir
defmodule GnomeGarden.Mailer.InvoiceEmail do
  @moduledoc """
  Builds branded invoice emails with Mercury payment instructions.

  Usage:
    invoice |> InvoiceEmail.build(mercury_info) |> Mailer.deliver()

  `invoice` must have `:invoice_lines` and `:organization` loaded.
  `mercury_info` is a keyword list with `:account_number` and `:routing_number`.
  """

  import Swoosh.Email

  @logo_url "https://raw.githubusercontent.com/Gnome-Automation/gnome-company/main/06-templates/assets/gnome-icon-clean.png"

  @spec build(map(), keyword()) :: Swoosh.Email.t()
  def build(invoice, mercury_info \\ []) do
    contact_email = find_contact_email(invoice)
    org_name = (invoice.organization && invoice.organization.name) || "Client"

    new()
    |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
    |> to(contact_email || "billing@gnomeautomation.io")
    |> subject("Invoice #{invoice.invoice_number} — USD #{format_amount(invoice.total_amount)}")
    |> html_body(build_html(invoice, org_name, mercury_info))
  end

  defp find_contact_email(invoice) do
    alias GnomeGarden.Operations

    case Operations.list_people_for_organization(invoice.organization_id, actor: nil) do
      {:ok, people} ->
        Enum.find_value(people, fn person ->
          if person.email && !person.do_not_email, do: to_string(person.email)
        end)

      _ ->
        nil
    end
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2))

  defp build_html(invoice, org_name, mercury_info) do
    account_number = Keyword.get(mercury_info, :account_number, "")
    routing_number = Keyword.get(mercury_info, :routing_number, "")

    lines_html =
      (invoice.invoice_lines || [])
      |> Enum.map(fn line ->
        """
        <tr>
          <td style="padding:10px 16px;border-bottom:1px solid #e2e8f0;">#{line.description}</td>
          <td style="padding:10px 16px;border-bottom:1px solid #e2e8f0;text-align:right;">#{format_amount(line.line_total)}</td>
        </tr>
        """
      end)
      |> Enum.join("")

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
                      <p style="margin:2px 0 0;font-size:12px;color:#94a3b8;">Invoice</p>
                    </td>
                    <td align="right" style="vertical-align:middle;">
                      <p style="margin:0;font-size:22px;font-weight:700;color:#ffffff;">#{invoice.invoice_number}</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:36px 40px;">
                <p style="margin:0 0 24px;color:#1e293b;">Dear #{org_name},</p>
                <p style="margin:0 0 24px;color:#1e293b;">Please find your invoice below. Payment is due by <strong>#{invoice.due_on}</strong>.</p>
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
                      <td style="padding:12px 16px;font-weight:700;color:#0f172a;">Total Due</td>
                      <td style="padding:12px 16px;text-align:right;font-weight:700;color:#0f172a;font-size:16px;">USD #{format_amount(invoice.total_amount)}</td>
                    </tr>
                  </tfoot>
                </table>
                <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:20px;margin-bottom:24px;">
                  <p style="margin:0 0 12px;font-weight:600;color:#0f172a;">Payment Instructions</p>
                  <p style="margin:0 0 8px;color:#1e293b;font-size:14px;">Please remit via wire transfer or ACH:</p>
                  <table cellpadding="0" cellspacing="0" style="font-size:14px;">
                    <tr><td style="padding:2px 0;color:#64748b;min-width:120px;">Bank:</td><td style="color:#0f172a;font-weight:500;">Mercury</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Account #:</td><td style="color:#0f172a;font-weight:500;">#{account_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Routing #:</td><td style="color:#0f172a;font-weight:500;">#{routing_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Reference:</td><td style="color:#0f172a;font-weight:500;">#{invoice.invoice_number}</td></tr>
                  </table>
                </div>
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
end
```

- [ ] **Step 4: Run the tests — verify they pass**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix test test/garden/mailer/invoice_email_test.exs
```

Expected: `6 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden/mailer/invoice_email.ex test/garden/mailer/invoice_email_test.exs && git commit -m "feat: add branded InvoiceEmail module with Mercury payment instructions"
```

---

## Task 8: Fix InvoiceSchedulerWorker + Add Config

**Files:**
- Modify: `lib/garden/mercury/invoice_scheduler_worker.ex`
- Modify: `config/runtime.exs`
- Modify: `config/dev.exs`

The existing scheduler at `lib/garden/mercury/invoice_scheduler_worker.ex` has two problems:
1. `line.amount` on line ~156 — should be `line.line_total`
2. Inline email building with raw `Swoosh.Email` import — should use `InvoiceEmail`

- [ ] **Step 1: Add mercury_payment_info to runtime.exs**

In `config/runtime.exs`, find the section where Mercury env vars are read (look for `MERCURY_API_KEY` or `MERCURY_SANDBOX`). Add after those lines:

```elixir
config :gnome_garden, :mercury_payment_info,
  account_number: System.get_env("MERCURY_ACCOUNT_NUMBER", ""),
  routing_number: System.get_env("MERCURY_ROUTING_NUMBER", "")
```

- [ ] **Step 2: Add test values to dev.exs**

In `config/dev.exs`, at the end of the file, add:

```elixir
config :gnome_garden, :mercury_payment_info,
  account_number: "123456789",
  routing_number: "021000021"
```

- [ ] **Step 3: Remove `import Swoosh.Email` from invoice_scheduler_worker.ex**

Open `lib/garden/mercury/invoice_scheduler_worker.ex`. Remove line 23:

```elixir
import Swoosh.Email
```

- [ ] **Step 4: Add `InvoiceEmail` alias**

After the existing `alias GnomeGarden.Mailer` line, add:

```elixir
alias GnomeGarden.Mailer.InvoiceEmail
```

- [ ] **Step 5: Replace `send_invoice_email/1` and `invoice_email_body/1`**

The existing `send_invoice_email/1` function (lines ~108–150) and `invoice_email_body/1` (lines ~152–171) use inline email building with the `line.amount` bug.

Replace both functions entirely with:

```elixir
defp send_invoice_email(invoice) do
  {:ok, loaded} =
    Ash.get(
      GnomeGarden.Finance.Invoice,
      invoice.id,
      domain: GnomeGarden.Finance,
      load: [:invoice_lines, :organization]
    )

  mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])

  loaded
  |> InvoiceEmail.build(mercury_info)
  |> Mailer.deliver()
  |> case do
    {:ok, _} ->
      :ok

    {:error, reason} ->
      Logger.warning("InvoiceSchedulerWorker: failed to send invoice email",
        invoice_id: invoice.id,
        reason: inspect(reason)
      )
  end
end
```

There is no `invoice_email_body/1` replacement — that function is deleted entirely.

- [ ] **Step 6: Run existing scheduler tests to verify nothing broke**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix test test/garden/mercury/invoice_scheduler_worker_test.exs
```

Expected: `4 tests, 0 failures`

- [ ] **Step 7: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden/mercury/invoice_scheduler_worker.ex config/runtime.exs config/dev.exs && git commit -m "fix: use InvoiceEmail in scheduler, fix line.amount -> line.line_total, add mercury_payment_info config"
```

---

## Task 9: Nav Link

**Files:**
- Modify: `lib/garden_web/components/nav.ex:706-712`

The Finance subnav items are defined in `section_subnav_items(:finance)` (around line 706).

- [ ] **Step 1: Add Approval Queue to Finance subnav**

The current `section_subnav_items(:finance)` returns:

```elixir
defp section_subnav_items(:finance) do
  [
    %{path: ~p"/finance/invoices", label: "Invoices", icon: "hero-receipt-percent"},
    %{path: ~p"/finance/time-entries", label: "Time", icon: "hero-clock"},
    %{path: ~p"/finance/expenses", label: "Expenses", icon: "hero-credit-card"},
    %{path: ~p"/finance/payments", label: "Payments", icon: "hero-banknotes"}
  ]
end
```

Add the Approval Queue entry after Time:

```elixir
defp section_subnav_items(:finance) do
  [
    %{path: ~p"/finance/invoices", label: "Invoices", icon: "hero-receipt-percent"},
    %{path: ~p"/finance/time-entries", label: "Time", icon: "hero-clock"},
    %{path: ~p"/finance/time-entries/approval-queue", label: "Approvals", icon: "hero-check-badge"},
    %{path: ~p"/finance/expenses", label: "Expenses", icon: "hero-credit-card"},
    %{path: ~p"/finance/payments", label: "Payments", icon: "hero-banknotes"}
  ]
end
```

- [ ] **Step 2: Verify compilation**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix compile --warnings-as-errors 2>&1 | grep -E "error|warning" | grep -v "deps/" | head -20
```

Expected: no errors

- [ ] **Step 3: Commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git add lib/garden_web/components/nav.ex && git commit -m "feat: add Approval Queue link to Finance nav"
```

---

## Task 10: Full Test Suite + End-to-End Smoke Test

- [ ] **Step 1: Run all project tests**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix test
```

Expected: all tests pass (the 8 pre-existing LiveView failures unrelated to billing are acceptable — check that no NEW failures appear)

- [ ] **Step 2: Start the dev server**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && mix phx.server
```

- [ ] **Step 3: Smoke test the complete flow**

Verify each step manually in the browser:

1. Go to `/finance/time-entries/new` → select an Agreement that has `default_bill_rate` set → verify "Bill Rate" field auto-fills
2. Create the time entry → go to `/finance/time-entries` → verify new entry shows "Submit" button in the Actions column → click Submit → verify status changes to "Submitted" in place
3. Go to `/finance/time-entries/approval-queue` (or click "Approvals" in the Finance nav) → verify the submitted entry appears → click "Approve" → verify it disappears from the queue
4. Go to `/commercial/agreements/:id` for an active agreement → verify "Generate Invoice" button appears → click it → verify redirect to `/finance/invoices/:id/review`
5. On the Review page: verify line items show (description and `line_total`), set a due date → click "Issue & Send Invoice" → verify redirect to invoice show page with status "Issued"
6. Check the dev mailbox at `/dev/mailbox` → verify the email shows Gnome logo, line items, Mercury account number `123456789`, routing number `021000021`
7. Verify "Approvals" link appears in the Finance section of the left nav

- [ ] **Step 4: Final commit**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git status
```

If there are any uncommitted changes from the smoke test, commit them. Otherwise:

```bash
git log --oneline -10
```

Verify all 8+ feature commits are present on `bassam/mercury-integration`.

- [ ] **Step 5: Push**

```bash
cd "/mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury" && git push
```
