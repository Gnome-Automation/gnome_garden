# Billing Loop — Front Half Design

**Date:** 2026-04-30
**Status:** Draft
**Branch:** `bassam/mercury-integration`

---

## Goal

Close the front half of the billing loop: log labor hours → submit for approval → approve → generate invoice on demand → issue invoice with branded email containing Mercury payment instructions. The back half (webhook → PaymentMatcherWorker → invoice closed) is already built.

---

## Scope

Seven tasks covering additive changes to existing resources and LiveViews, plus three new files.

| Task | What | Files |
|---|---|---|
| 1 | Add `default_bill_rate` to Agreement | `agreement.ex` + migration |
| 2 | Auto-fill bill rate in TimeEntry form | `time_entry_live/form.ex` (modify) |
| 3 | Submit action on TimeEntry index | `time_entry_live/index.ex` (modify) |
| 4 | Approval Queue LiveView | `approval_queue_live.ex` (new) + router |
| 5 | Generate Invoice on Agreement show + Invoice Review page | `agreement_live/show.ex` (modify), `invoice_live/review.ex` (new) + router |
| 6 | InvoiceEmail module + fix scheduler bug | `invoice_email.ex` (new), `invoice_scheduler_worker.ex` (modify) |
| 7 | Nav link + smoke test | `nav.ex` or sidebar component (modify) |

---

## What Is Already Built

The following exist and must NOT be replaced or recreated:

- `Finance.TimeEntry` state machine: `draft → submitted → approved → billed`
- All Finance domain shortcuts in `lib/garden/finance.ex`:
  - `Finance.list_time_entries/1`, `Finance.submit_time_entry/2`, `Finance.approve_time_entry/2`, `Finance.reject_time_entry/2`
  - `Finance.create_invoice_from_agreement_sources/2` (args: `agreement_id`)
  - `Finance.issue_invoice/2`, `Finance.list_invoices/1`, `Finance.get_invoice/2`
- `Finance.Invoice` state machine already has `:partial`, `:write_off`, `:paid` states
- `Finance.InvoiceLine` has `line_total` field (not `amount`)
- `lib/garden_web/live/finance/time_entry_live/index.ex` — streams-based, existing stat cards
- `lib/garden_web/live/finance/time_entry_live/form.ex` — AshPhoenix.Form, existing `agreement_id` + `bill_rate` fields
- `lib/garden_web/live/commercial/agreement_live/show.ex` — existing "Draft Invoice" button navigating to `/finance/invoices/new?agreement_id=...`
- `GnomeGarden.Mailer` — `use Swoosh.Mailer, otp_app: :gnome_garden`
- `Operations.list_people_for_organization/2` (args: `organization_id`)

---

## Task 1 — Add `default_bill_rate` to Agreement

### Why

Time entries need a suggested rate scoped to the agreement. Without this, every entry requires manual rate entry. The agreement is the natural place to store the default since rates vary by client and contract.

### Changes

**File: `lib/garden/commercial/agreement.ex`**

Add to `attributes` block:

```elixir
attribute :default_bill_rate, :decimal do
  public? true
end
```

Add `:default_bill_rate` to the `accept` list in both the `:create` and `:update` actions.

**File: new migration**

```elixir
defmodule GnomeGarden.Repo.Migrations.AddDefaultBillRateToAgreements do
  use Ecto.Migration

  def change do
    alter table(:commercial_agreements) do
      add :default_bill_rate, :decimal
    end
  end
end
```

Run: `mix ash_postgres.generate_migrations --name add_default_bill_rate_to_agreements && mix ecto.migrate`

---

## Task 2 — Bill Rate Auto-Fill in TimeEntry Form

### Why

When a user picks an agreement on the time entry form, the bill rate should auto-populate from `agreement.default_bill_rate` if the rate field is currently blank. The user can still override it manually.

### Changes

**File: `lib/garden_web/live/finance/time_entry_live/form.ex`** (modify, do not rewrite)

In `load_agreements/1`, agreements already load `[:organization]`. The `default_bill_rate` attribute is a plain attribute on Agreement so it will be present without additional loading.

In `handle_event("validate", %{"form" => params}, socket)`:

After the existing `form = AshPhoenix.Form.validate(socket.assigns.form, params)` line, add a call to `maybe_fill_bill_rate/2`:

```elixir
@impl true
def handle_event("validate", %{"form" => params}, socket) do
  params = maybe_fill_bill_rate(params, socket.assigns.agreements)
  form = AshPhoenix.Form.validate(socket.assigns.form, params)
  selected_project_id = blank_to_nil(params["project_id"])

  {:noreply,
   socket
   |> assign(:selected_project_id, selected_project_id)
   |> assign(
     :project_work_items,
     load_project_work_items(socket.assigns.current_user, selected_project_id)
   )
   |> assign(:form, to_form(form))}
end
```

Add private helper at the bottom of the module:

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

---

## Task 3 — Submit Action on TimeEntry Index

### Why

Currently the index shows entries but has no way to submit a draft entry without navigating to its show page. Adding a Submit button inline reduces friction for the daily logging flow.

### Changes

**File: `lib/garden_web/live/finance/time_entry_live/index.ex`** (modify, do not rewrite)

In the `<tbody>` table row (`<tr :for={{dom_id, time_entry} <- @streams.time_entries} ...>`), add a new `<td>` column for actions after the status column:

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

Add a matching `<th>` header column for "Actions":

```heex
<th class="px-5 py-3 text-left font-medium text-zinc-500 dark:text-zinc-400">
  Actions
</th>
```

Add event handler in the module:

```elixir
@impl true
def handle_event("submit", %{"id" => id}, socket) do
  actor = socket.assigns.current_user

  case Finance.get_time_entry(id, actor: actor) do
    {:ok, time_entry} ->
      case Finance.submit_time_entry(time_entry, actor: actor) do
        {:ok, updated} ->
          # :status_variant is a calculation — state-transition actions don't load it.
          # Load it explicitly so stream_insert has it for the status badge.
          updated = Ash.load!(updated, [:status_variant], actor: actor, domain: GnomeGarden.Finance)

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

The `stream_insert/3` updates the row in-place without a full reload; the submit button disappears because `time_entry.status` is now `:submitted`. The `Ash.load!` call before `stream_insert` is required because the `:submit` state-transition action does not load calculations.

---

## Task 4 — Approval Queue LiveView

### Why

Bassam and Patrick are both founders acting as managers. They need a single page to see all submitted time entries across all agreements and approve or reject them. Without this, approval requires hunting individual entries.

### New File: `lib/garden_web/live/finance/approval_queue_live.ex`

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

### Router

In `lib/garden_web/router.ex`, inside the `ash_authentication_live_session :authenticated_routes` block, add after the existing Finance time-entry routes:

```elixir
live "/finance/time-entries/approval-queue", Finance.ApprovalQueueLive, :index
```

Place it BEFORE the `live "/finance/time-entries/:id"` line to avoid route conflict (the router matches in order).

---

## Task 5 — Generate Invoice on Agreement Show + Invoice Review Page

### Why

The existing "Draft Invoice" button creates a blank invoice via the manual form. A separate "Generate Invoice" button creates a pre-filled draft from all approved unbilled time entries and expenses for that agreement, then sends the user to a review page to confirm line items and set a due date before issuing.

### Changes to `lib/garden_web/live/commercial/agreement_live/show.ex`

Add a "Generate Invoice" button in the `<:actions>` block, after the existing "Draft Invoice" button:

```heex
<.button
  :if={@agreement.status == :active}
  phx-click="generate_invoice"
  variant="primary"
>
  <.icon name="hero-document-plus" class="size-4" /> Generate Invoice
</.button>
```

Add event handler in the module:

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
        {:noreply, put_flash(socket, :info, "No approved billable entries for this agreement yet.")}
      else
        {:noreply, put_flash(socket, :error, "Could not generate invoice: #{inspect(errors)}")}
      end

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Could not generate invoice: #{inspect(reason)}")}
  end
end
```

Add alias at the top: `alias GnomeGarden.Finance`

### New File: `lib/garden_web/live/finance/invoice_live/review.ex`

```elixir
defmodule GnomeGardenWeb.Finance.InvoiceLive.Review do
  use GnomeGardenWeb, :live_view

  import GnomeGardenWeb.Finance.Helpers

  alias GnomeGarden.Finance
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.InvoiceEmail

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    invoice = load_invoice!(id, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Review Invoice")
     |> assign(:invoice, invoice)
     |> assign(:due_on, invoice.due_on || Date.utc_today() |> Date.add(30))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page max_width="max-w-4xl" class="pb-8">
      <.page_header eyebrow="Finance">
        Review Invoice
        <:subtitle>
          Review the generated line items, set a due date, then issue to send the invoice email to the client.
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
        _ -> Date.utc_today() |> Date.add(30)
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

    email = InvoiceEmail.build(loaded, mercury_info)

    case Mailer.deliver(email) do
      {:ok, _} -> :ok
      {:error, reason} ->
        require Logger
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

### Router

In `lib/garden_web/router.ex`, inside the authenticated routes block, add after the existing invoice routes:

```elixir
live "/finance/invoices/:id/review", Finance.InvoiceLive.Review, :review
```

Place it AFTER `live "/finance/invoices/:id", Finance.InvoiceLive.Show, :show` and BEFORE `live "/finance/invoices/:id/edit"`.

---

## Task 6 — InvoiceEmail Module + Fix Scheduler Bug

### InvoiceEmail Module

**New file: `lib/garden/mailer/invoice_email.ex`**

This module builds a branded Swoosh email with Gnome Automation letterhead. Used by both `InvoiceLive.Review` (on-demand) and `InvoiceSchedulerWorker` (scheduled).

```elixir
defmodule GnomeGarden.Mailer.InvoiceEmail do
  @moduledoc """
  Builds branded invoice emails with Mercury payment instructions.
  """

  import Swoosh.Email

  @logo_url "https://raw.githubusercontent.com/Gnome-Automation/gnome-company/main/06-templates/assets/gnome-icon-clean.png"

  @doc """
  Builds a Swoosh.Email struct for the given invoice.

  `mercury_info` is a keyword list with `:account_number` and `:routing_number`.
  """
  def build(invoice, mercury_info \\ []) do
    contact_email = find_contact_email(invoice)
    org_name = (invoice.organization && invoice.organization.name) || "Client"

    new()
    |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
    |> to(contact_email || "billing@gnomeautomation.io")
    |> subject("Invoice #{invoice.invoice_number} — USD #{format_amount(invoice.total_amount)}")
    |> html_body(html_body(invoice, org_name, mercury_info))
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

  defp html_body(invoice, org_name, mercury_info) do
    account_number = Keyword.get(mercury_info, :account_number, "")
    routing_number = Keyword.get(mercury_info, :routing_number, "")

    lines_html =
      invoice.invoice_lines
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

            <!-- Header -->
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

            <!-- Body -->
            <tr>
              <td style="padding:36px 40px;">
                <p style="margin:0 0 24px;color:#1e293b;">Dear #{org_name},</p>
                <p style="margin:0 0 24px;color:#1e293b;">Please find your invoice below. Payment is due by <strong>#{invoice.due_on}</strong>.</p>

                <!-- Line items -->
                <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #e2e8f0;border-radius:8px;overflow:hidden;margin-bottom:24px;">
                  <thead>
                    <tr style="background:#f1f5f9;">
                      <th style="padding:10px 16px;text-align:left;font-size:12px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:0.05em;">Description</th>
                      <th style="padding:10px 16px;text-align:right;font-size:12px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:0.05em;">Amount</th>
                    </tr>
                  </thead>
                  <tbody>
                    #{lines_html}
                  </tbody>
                  <tfoot>
                    <tr style="background:#f8fafc;">
                      <td style="padding:12px 16px;font-weight:700;color:#0f172a;">Total Due</td>
                      <td style="padding:12px 16px;text-align:right;font-weight:700;color:#0f172a;font-size:16px;">USD #{format_amount(invoice.total_amount)}</td>
                    </tr>
                  </tfoot>
                </table>

                <!-- Payment instructions -->
                <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:20px;margin-bottom:24px;">
                  <p style="margin:0 0 12px;font-weight:600;color:#0f172a;">Payment Instructions</p>
                  <p style="margin:0 0 8px;color:#1e293b;font-size:14px;">Please remit via wire transfer or ACH to:</p>
                  <table cellpadding="0" cellspacing="0" style="font-size:14px;">
                    <tr><td style="padding:2px 0;color:#64748b;min-width:120px;">Bank:</td><td style="color:#0f172a;font-weight:500;">Mercury</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Account #:</td><td style="color:#0f172a;font-weight:500;">#{account_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Routing #:</td><td style="color:#0f172a;font-weight:500;">#{routing_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Reference:</td><td style="color:#0f172a;font-weight:500;">#{invoice.invoice_number}</td></tr>
                  </table>
                </div>

                <p style="margin:0;color:#64748b;font-size:13px;">Questions? Reply to this email or contact billing@gnomeautomation.io</p>
              </td>
            </tr>

            <!-- Footer -->
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

### Config Changes

**`config/runtime.exs`** — add under the existing Mercury env section:

```elixir
config :gnome_garden, :mercury_payment_info,
  account_number: System.get_env("MERCURY_ACCOUNT_NUMBER", ""),
  routing_number: System.get_env("MERCURY_ROUTING_NUMBER", "")
```

**`config/dev.exs`** — add test values:

```elixir
config :gnome_garden, :mercury_payment_info,
  account_number: "123456789",
  routing_number: "021000021"
```

### Fix Bug in InvoiceSchedulerWorker

**File: `lib/garden/mercury/invoice_scheduler_worker.ex`** (modify, do not rewrite)

The existing `send_invoice_email/1` uses inline email building with `line.amount` (wrong field — should be `line.line_total`), and imports `Swoosh.Email` at the module level.

Replace the `send_invoice_email/1` and `invoice_email_body/1` private functions with a call to `InvoiceEmail.build/2`:

Remove:
- The `import Swoosh.Email` at line 23
- The `send_invoice_email/1` function (lines 108–150)
- The `invoice_email_body/1` function (lines 152–171)

Add alias: `alias GnomeGarden.Mailer.InvoiceEmail`

Replace `send_invoice_email/1` with:

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

---

## Task 7 — Nav Links + Smoke Test

### Nav Link

The application sidebar or nav component must link to the new Approval Queue. Locate the Finance section in the navigation (check `lib/garden_web/components/layouts/app.html.heex` or a dedicated nav component), and add:

```heex
<.nav_link navigate={~p"/finance/time-entries/approval-queue"} icon="hero-check-badge">
  Approval Queue
</.nav_link>
```

Place it under the existing Time Entries nav link.

### End-to-End Smoke Test

After implementation, verify the full flow manually:

1. Create time entry (any agreement with `default_bill_rate`) → bill_rate auto-fills
2. Click Submit on index → status changes to `:submitted`
3. Go to Approval Queue → entry appears → click Approve → entry disappears
4. Go to Agreement show → click "Generate Invoice" → redirects to Review page
5. Set due date → click "Issue & Send Invoice" → invoice status becomes `:issued` → email logged in dev mailbox (`/dev/mailbox`)
6. Confirm email contains logo, line items, Mercury account/routing numbers

---

## Files Affected

| Action | File |
|---|---|
| Modify | `lib/garden/commercial/agreement.ex` — add `default_bill_rate` attribute |
| Modify | `lib/garden/commercial/agreement.ex` — add `:default_bill_rate` to `:create` and `:update` accept lists |
| Create | `priv/repo/migrations/TIMESTAMP_add_default_bill_rate_to_agreements.exs` |
| Modify | `lib/garden_web/live/finance/time_entry_live/form.ex` — add `maybe_fill_bill_rate/2`, call in validate handler |
| Modify | `lib/garden_web/live/finance/time_entry_live/index.ex` — add Submit button + `handle_event("submit", ...)` |
| Create | `lib/garden_web/live/finance/approval_queue_live.ex` |
| Modify | `lib/garden_web/live/commercial/agreement_live/show.ex` — add "Generate Invoice" button + event handler + `Finance` alias |
| Create | `lib/garden_web/live/finance/invoice_live/review.ex` |
| Create | `lib/garden/mailer/invoice_email.ex` |
| Modify | `lib/garden/mercury/invoice_scheduler_worker.ex` — remove inline email, use `InvoiceEmail`, fix `line.amount` → `line.line_total` |
| Modify | `config/runtime.exs` — add `:mercury_payment_info` |
| Modify | `config/dev.exs` — add test values for `:mercury_payment_info` |
| Modify | `lib/garden_web/router.ex` — add 2 new routes |
| Modify | Nav component — add Approval Queue link |

---

## What Does Not Change

- Finance domain shortcuts (`lib/garden/finance.ex`) — already complete
- TimeEntry state machine — already correct
- Invoice state machine — already has `:partial`, `:write_off`, `:paid`
- Mercury webhook receiver — no modifications
- Existing migrations — no modifications
- Existing Finance LiveViews (invoice, expense, payment) — no modifications
