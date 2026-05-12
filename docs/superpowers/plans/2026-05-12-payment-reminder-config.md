# Payment Reminder Config UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded `@thresholds [7, 14, 30]` in `PaymentReminderWorker` with a DB-backed `BillingSettings` resource and a LiveView settings page at `/finance/settings` where staff can configure reminder days.

**Architecture:** A singleton `BillingSettings` Ash resource (one row, `scope: "global"` identity) stores `reminder_days` as an integer array. `PaymentReminderWorker` reads from it instead of the module attribute. A new `Finance.BillingSettingsLive` LiveView provides a form to update the values.

**Tech Stack:** Elixir/Phoenix, Ash Framework (AshPostgres), Phoenix LiveView, Tailwind CSS, PostgreSQL

---

## File Structure

### New Files
- `lib/garden/finance/billing_settings.ex` — Ash resource, singleton row with `reminder_days` array
- `lib/garden_web/live/finance/billing_settings_live.ex` — LiveView form at `/finance/settings`
- `test/garden/finance/billing_settings_test.exs` — resource tests
- `test/garden_web/live/finance/billing_settings_live_test.exs` — LiveView tests

### Modified Files
- `lib/garden/finance.ex` — register `BillingSettings` resource + code interfaces
- `lib/garden/finance/payment_reminder_worker.ex` — replace `@thresholds` with `Finance.get_reminder_days()`
- `lib/garden_web/router.ex` — add `/finance/settings` route
- `lib/garden_web/components/rail_nav.ex` — add "Settings" nav entry under Finance
- `test/garden/finance/payment_reminder_worker_test.exs` — update tests to insert settings row

---

## Task 1: BillingSettings Ash Resource + Migration

Add the singleton `BillingSettings` resource to the Finance domain and run the migration.

**Files:**
- Create: `lib/garden/finance/billing_settings.ex`
- Modify: `lib/garden/finance.ex`

- [ ] **Step 1: Create `BillingSettings` resource**

Create `lib/garden/finance/billing_settings.ex`:

```elixir
defmodule GnomeGarden.Finance.BillingSettings do
  @moduledoc """
  Singleton settings for the Finance billing subsystem.

  Always one row in the database. Use Finance.get_billing_settings/0 to read
  and Finance.upsert_billing_settings/1 to update.

  The `scope` field is always "global" — it exists only to give Ash
  a stable identity for the upsert.
  """

  use Ash.Resource,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "billing_settings"
    repo GnomeGarden.Repo
  end

  actions do
    read :read do
      primary? true
    end

    create :upsert do
      accept [:reminder_days]
      upsert? true
      upsert_identity :singleton_scope
      upsert_fields [:reminder_days]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :scope, :string do
      default "global"
      allow_nil? false
      description "Always 'global'. Exists to give the upsert a stable identity."
    end

    attribute :reminder_days, {:array, :integer} do
      default [7, 14, 30]
      allow_nil? false
      description "Days overdue at which payment reminder emails are sent."
      constraints min_length: 1,
                  items: [min: 1, max: 365]
    end

    timestamps()
  end

  identities do
    identity :singleton_scope, [:scope]
  end
end
```

- [ ] **Step 2: Register in Finance domain and add code interfaces**

In `lib/garden/finance.ex`, add inside the `resources do` block (after `CreditNoteLine`):

```elixir
resource GnomeGarden.Finance.BillingSettings do
  define :get_billing_settings, action: :read
  define :upsert_billing_settings, action: :upsert
end
```

- [ ] **Step 3: Generate migration**

```bash
cd /home/bhammoud/gnome_garden_mercury
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.generate_migrations --name add_billing_settings
```

Expected: new file created in `priv/repo/migrations/` with a `billing_settings` table.

- [ ] **Step 4: Run migration**

```bash
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.migrate
```

Expected: `== Running ... AddBillingSettings == ... [up]` with no errors.

- [ ] **Step 5: Write tests**

Create `test/garden/finance/billing_settings_test.exs`:

```elixir
defmodule GnomeGarden.Finance.BillingSettingsTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  test "upsert_billing_settings creates a row on first call" do
    assert {:ok, settings} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    assert settings.reminder_days == [7, 14, 30]
  end

  test "upsert_billing_settings updates the existing row" do
    {:ok, _} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    {:ok, updated} = Finance.upsert_billing_settings(%{reminder_days: [5, 10]})
    assert updated.reminder_days == [5, 10]
  end

  test "get_billing_settings returns all rows (one row after upsert)" do
    {:ok, _} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    {:ok, rows} = Finance.get_billing_settings()
    assert length(rows) == 1
    assert hd(rows).reminder_days == [7, 14, 30]
  end

  test "reminder_days must have at least one item" do
    assert {:error, _} = Finance.upsert_billing_settings(%{reminder_days: []})
  end
end
```

- [ ] **Step 6: Run tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/billing_settings_test.exs --trace
```

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/garden/finance/billing_settings.ex lib/garden/finance.ex priv/repo/migrations/ test/garden/finance/billing_settings_test.exs
git commit -m "feat: add BillingSettings singleton resource with configurable reminder_days"
```

---

## Task 2: Helper Function + Update PaymentReminderWorker

Add a `Finance.get_reminder_days/0` helper and update the worker to read from the DB instead of the module attribute.

**Files:**
- Modify: `lib/garden/finance.ex`
- Modify: `lib/garden/finance/payment_reminder_worker.ex`
- Modify: `test/garden/finance/payment_reminder_worker_test.exs`

- [ ] **Step 1: Add `get_reminder_days/0` helper to Finance domain**

In `lib/garden/finance.ex`, add after the closing `end` of the `resources do` block (not inside it — plain `def` functions already live there alongside helpers like `create_payment_schedule_item/2`):

```elixir
@doc """
Returns the configured reminder threshold days from BillingSettings.
Falls back to [7, 14, 30] if no settings row exists yet.
"""
def get_reminder_days do
  case get_billing_settings() do
    {:ok, [settings | _]} -> settings.reminder_days
    _ -> [7, 14, 30]
  end
end
```

- [ ] **Step 2: Update `PaymentReminderWorker` to read from DB**

In `lib/garden/finance/payment_reminder_worker.ex`, replace the hardcoded `@thresholds` with a dynamic read.

Replace:

```elixir
@thresholds [7, 14, 30]

@impl Oban.Worker
def perform(%Oban.Job{}) do
  today = Date.utc_today()

  Invoice
  |> Ash.Query.for_read(:overdue)
  |> Ash.Query.load(organization: [:billing_contact], agreement: [owner_team_member: [:user]])
  |> Ash.read!(domain: Finance, authorize?: false)
  |> Enum.each(&maybe_send_reminder(&1, today))

  :ok
end

defp maybe_send_reminder(invoice, today) do
  days_overdue = Date.diff(today, invoice.due_on)

  if days_overdue in @thresholds do
    send_reminder(invoice, threshold_atom(days_overdue))
  end
end
```

With:

```elixir
@impl Oban.Worker
def perform(%Oban.Job{}) do
  today = Date.utc_today()
  thresholds = Finance.get_reminder_days()

  Invoice
  |> Ash.Query.for_read(:overdue)
  |> Ash.Query.load(organization: [:billing_contact], agreement: [owner_team_member: [:user]])
  |> Ash.read!(domain: Finance, authorize?: false)
  |> Enum.each(&maybe_send_reminder(&1, today, thresholds))

  :ok
end

defp maybe_send_reminder(invoice, today, thresholds) do
  days_overdue = Date.diff(today, invoice.due_on)

  if days_overdue in thresholds do
    send_reminder(invoice, threshold_atom(days_overdue))
  end
end
```

Also remove the `alias GnomeGarden.Finance.Invoice` duplicate if present (Finance is already aliased).

- [ ] **Step 3: Update `threshold_atom/1` to handle arbitrary days**

The existing `threshold_atom/1` only handles 7, 14, 30. Replace with a general implementation:

Replace:

```elixir
defp threshold_atom(7), do: :day_7
defp threshold_atom(14), do: :day_14
defp threshold_atom(30), do: :day_30
```

With:

```elixir
defp threshold_atom(days), do: :"day_#{days}"
```

- [ ] **Step 4: Update worker tests to insert a settings row**

In `test/garden/finance/payment_reminder_worker_test.exs`, add a `setup` step that inserts a `BillingSettings` row so the worker uses known thresholds:

At the top of the existing `setup do` block, add:

```elixir
# Ensure BillingSettings row exists with known thresholds for test predictability
{:ok, _} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
```

- [ ] **Step 5: Run all reminder worker tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/payment_reminder_worker_test.exs --trace
```

Expected: all tests PASS.

- [ ] **Step 6: Run full test suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 7: Commit**

```bash
git add lib/garden/finance.ex lib/garden/finance/payment_reminder_worker.ex test/garden/finance/payment_reminder_worker_test.exs
git commit -m "feat: read reminder thresholds from BillingSettings DB row instead of hardcoded module attribute"
```

---

## Task 3: BillingSettingsLive — Settings Page

A LiveView at `/finance/settings` with a form to view and update the configured reminder days.

**Files:**
- Create: `lib/garden_web/live/finance/billing_settings_live.ex`
- Modify: `lib/garden_web/router.ex`
- Modify: `lib/garden_web/components/rail_nav.ex`
- Create: `test/garden_web/live/finance/billing_settings_live_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden_web/live/finance/billing_settings_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Finance.BillingSettingsLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  setup :register_and_log_in_user

  setup do
    {:ok, _} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    :ok
  end

  test "renders billing settings page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/settings")
    assert html =~ "Billing Settings"
    assert html =~ "Payment Reminder Days"
  end

  test "shows current reminder days", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/settings")
    assert html =~ "7"
    assert html =~ "14"
    assert html =~ "30"
  end

  test "saves updated reminder days", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/finance/settings")

    html =
      view
      |> form("#billing-settings-form", billing_settings: %{reminder_days: "5, 10, 20"})
      |> render_submit()

    # Success banner is rendered inline in the LiveView (not in the layout flash)
    assert html =~ "Settings saved"

    {:ok, [settings]} = Finance.get_billing_settings()
    assert settings.reminder_days == [5, 10, 20]
  end

  test "shows error for empty reminder days", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/finance/settings")

    html =
      view
      |> form("#billing-settings-form", billing_settings: %{reminder_days: ""})
      |> render_submit()

    # Error banner is rendered inline in the LiveView
    assert html =~ "at least one"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/finance/billing_settings_live_test.exs --trace
```

Expected: FAIL — route and LiveView don't exist yet.

- [ ] **Step 3: Add route**

In `lib/garden_web/router.ex`, inside the authenticated Finance live session block (near `/finance/ar-aging`):

```elixir
live "/finance/settings", Finance.BillingSettingsLive, :index
```

- [ ] **Step 4: Create the LiveView**

Create `lib/garden_web/live/finance/billing_settings_live.ex`.

Per CLAUDE.md, Ash-backed forms use `AshPhoenix.Form`. Because `reminder_days` is `{:array, :integer}` (not a standard scalar), we accept it as a comma-separated text string, parse it before submission, and call `Finance.upsert_billing_settings/1` directly. The form is built with `<.form>` using a plain map changeset for the text input, while Ash handles the actual persistence.

Inline `@save_ok` assign is used for success feedback — `render_submit` in tests only returns the LiveView's rendered HTML (not the full layout), so `put_flash` alone won't be visible in tests. Use an inline banner instead.

```elixir
defmodule GnomeGardenWeb.Finance.BillingSettingsLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @impl true
  def mount(_params, _session, socket) do
    settings = load_settings()

    {:ok,
     socket
     |> assign(:page_title, "Billing Settings")
     |> assign(:reminder_days_input, Enum.join(settings.reminder_days, ", "))
     |> assign(:save_ok, false)
     |> assign(:save_error, nil)}
  end

  @impl true
  def handle_event("save", %{"billing_settings" => %{"reminder_days" => raw}}, socket) do
    case parse_reminder_days(raw) do
      {:ok, days} ->
        case Finance.upsert_billing_settings(%{reminder_days: days}) do
          {:ok, _settings} ->
            {:noreply,
             socket
             |> assign(:reminder_days_input, Enum.join(days, ", "))
             |> assign(:save_ok, true)
             |> assign(:save_error, nil)}

          {:error, error} ->
            {:noreply,
             socket
             |> assign(:save_ok, false)
             |> assign(:save_error, "Could not save: #{inspect(error)}")}
        end

      {:error, msg} ->
        {:noreply,
         socket
         |> assign(:save_ok, false)
         |> assign(:save_error, msg)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        Billing Settings
        <:subtitle>Configure automated billing behaviors.</:subtitle>
      </.page_header>

      <div class="max-w-2xl">
        <.section title="Payment Reminder Days"
          description="Comma-separated list of days overdue at which reminder emails are sent to clients. Example: 7, 14, 30">
          <div class="px-5 pb-5">
            <form id="billing-settings-form" phx-submit="save">
              <div class="mb-4">
                <label class="block text-sm/6 font-medium text-gray-900 dark:text-white mb-1">
                  Reminder Days
                </label>
                <input
                  type="text"
                  name="billing_settings[reminder_days]"
                  value={@reminder_days_input}
                  placeholder="7, 14, 30"
                  class="rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-emerald-600 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-gray-500 dark:focus:outline-emerald-500 w-full"
                />
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  Reminders will be sent at days: <strong>{@reminder_days_input}</strong> overdue
                </p>
              </div>

              <div :if={@save_ok} class="mb-4 rounded-md bg-emerald-50 px-4 py-3 text-sm text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-400">
                Settings saved
              </div>

              <div :if={@save_error} class="mb-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400">
                {@save_error}
              </div>

              <button
                type="submit"
                class="rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-emerald-500 dark:bg-emerald-500"
              >
                Save Settings
              </button>
            </form>
          </div>
        </.section>
      </div>
    </.page>
    """
  end

  defp load_settings do
    case Finance.get_billing_settings() do
      {:ok, [settings | _]} -> settings
      _ -> %{reminder_days: [7, 14, 30]}
    end
  end

  defp parse_reminder_days(raw) do
    parsed =
      raw
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn s ->
        case Integer.parse(s) do
          {n, ""} when n >= 1 -> {:ok, n}
          _ -> {:error, s}
        end
      end)

    errors = Enum.filter(parsed, &match?({:error, _}, &1))
    valid =
      parsed
      |> Enum.flat_map(fn
        {:ok, n} -> [n]
        _ -> []
      end)
      |> Enum.sort()
      |> Enum.uniq()

    cond do
      errors != [] ->
        bad = Enum.map_join(errors, ", ", fn {:error, s} -> s end)
        {:error, "Invalid values: #{bad}. Enter positive whole numbers only."}

      valid == [] ->
        {:error, "Must have at least one reminder day."}

      true ->
        {:ok, valid}
    end
  end
end
```

- [ ] **Step 5: Add nav entry**

In `lib/garden_web/components/rail_nav.ex`, find the Finance section (where `ops-ar-aging` is) and add a Settings entry after it. All fields are required — missing any will cause a `KeyError` at render time:

```elixir
%{
  id: "ops-finance-settings",
  section: "Operations",
  icon: "hero-cog-6-tooth",
  label: "Settings",
  path: "/finance/settings",
  badge: 0,
  hot: false,
  match: ["/finance/settings"]
},
```

- [ ] **Step 6: Run the tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/finance/billing_settings_live_test.exs --trace
```

Expected: all tests PASS.

- [ ] **Step 7: Run full test suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Step 8: Commit**

```bash
git add lib/garden_web/live/finance/billing_settings_live.ex \
        lib/garden_web/router.ex \
        lib/garden_web/components/rail_nav.ex \
        test/garden_web/live/finance/billing_settings_live_test.exs
git commit -m "feat: add BillingSettingsLive at /finance/settings — configure payment reminder days from UI"
```

---

## Final Verification

- [ ] **Run full test suite one last time**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -5
```

Expected: 0 new failures.

- [ ] **Push branch**

```bash
git push
```
