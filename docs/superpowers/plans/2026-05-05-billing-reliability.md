# Billing Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add billing contact on Organization, flexible payment schedule on Agreement (installment billing), AR Aging Report LiveView, and automated payment reminder emails.

**Architecture:** Four independent reliability features layered on top of the existing billing loop. All DB schema changes (Organization billing_contact, Agreement payment_terms_days, PaymentScheduleItem table) are generated from Ash resource definitions and applied in a single migration. Invoice generation is extended with a separate fixed-fee path that reads the payment schedule; the T&M path is unchanged. Two new Oban workers (PaymentReminderWorker) and one new LiveView (ArAgingLive) complete the feature.

**Tech Stack:** Elixir/Phoenix, Ash Framework (AshPostgres, AshStateMachine), Oban, Phoenix LiveView, Swoosh email, PostgreSQL

---

## File Structure

### New Files
- `lib/garden/finance/payment_schedule_item.ex` — Ash resource, one installment in a fixed-fee payment schedule
- `lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex` — Ash change, generates one draft invoice per schedule item
- `lib/garden_web/live/finance/ar_aging_live.ex` — AR Aging Report LiveView
- `lib/garden/finance/payment_reminder_worker.ex` — Oban worker, sends overdue reminders at day 7/14/30
- `lib/garden/mailer/payment_reminder_email.ex` — Swoosh email builder for payment reminders

### Modified Files
- `lib/garden/operations/organization.ex` — add `billing_contact` belongs_to (→ Person)
- `lib/garden/commercial/agreement.ex` — add `payment_terms_days` integer attribute, `has_many :payment_schedule_items`
- `lib/garden/finance/invoice.ex` — add `:create_from_fixed_fee_schedule` create action
- `lib/garden/mailer/invoice_email.ex` — extract `find_billing_email/1` helper (checks billing_contact first)
- `lib/garden_web/live/commercial/agreement_live/show.ex` — add Payment Schedule section (fixed-fee only)
- `lib/garden_web/live/operations/organization_live/show.ex` — add Billing Contact picker
- `lib/garden_web/components/nav.ex` — add AR Aging link to Finance subnav
- `lib/garden_web/router.ex` — add `/finance/ar-aging` route
- `config/config.exs` — add `finance` Oban queue and `PaymentReminderWorker` cron entry

### Test Files
- `test/garden/finance/payment_schedule_item_test.exs` — new
- `test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs` — new
- `test/garden/finance/payment_reminder_worker_test.exs` — new
- `test/garden_web/live/finance/ar_aging_live_test.exs` — new

---

## Task 1: Schema — Organization, Agreement, PaymentScheduleItem

Add all new DB columns and the new resource by updating Ash resource files, then generating and running the migration.

**Files:**
- Modify: `lib/garden/operations/organization.ex`
- Modify: `lib/garden/commercial/agreement.ex`
- Create: `lib/garden/finance/payment_schedule_item.ex`
- Modify: `lib/garden/finance.ex` (domain — register new resource)

- [ ] **Step 1: Add `billing_contact_id` to Organization**

In `lib/garden/operations/organization.ex`, add inside the `relationships do` block (after existing belongs_to entries):

```elixir
belongs_to :billing_contact, GnomeGarden.Operations.Person do
  attribute_type :uuid
  allow_nil? true
  attribute_writable? true
end
```

- [ ] **Step 2: Add `payment_terms_days` to Agreement**

In `lib/garden/commercial/agreement.ex`, add inside the `attributes do` block (after `default_bill_rate`):

```elixir
attribute :payment_terms_days, :integer do
  default 30
  allow_nil? false
  description "Days after invoice issue date when payment is due (default: 30)."
end
```

Also add inside the `accept` list of the `:update` action and any `:create` action that currently lists `default_bill_rate`:

```elixir
:payment_terms_days
```

- [ ] **Step 3: Create PaymentScheduleItem resource**

Create `lib/garden/finance/payment_schedule_item.ex`:

```elixir
defmodule GnomeGarden.Finance.PaymentScheduleItem do
  @moduledoc """
  One installment in a fixed-fee payment schedule on an Agreement.

  A schedule is valid only when its items' percentages sum to 100.
  Items are ordered by `position` (1, 2, 3...) and each generates
  one draft Invoice when invoice generation is triggered.
  """

  use Ash.Resource,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  alias GnomeGarden.Finance.PaymentScheduleItem

  postgres do
    table "payment_schedule_items"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:agreement_id, :position, :label, :percentage, :due_days]
      validate PaymentScheduleItem.Validations.PercentageSumNotExceeded
    end

    update :update do
      accept [:position, :label, :percentage, :due_days]
      validate PaymentScheduleItem.Validations.PercentageSumNotExceeded
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      description "Display order within the schedule (1, 2, 3...)."
    end

    attribute :label, :string do
      allow_nil? false
      description "Human label shown on invoice notes (e.g. 'Deposit', 'Milestone 1')."
    end

    attribute :percentage, :decimal do
      allow_nil? false
      description "Percentage of contract_value billed for this installment (e.g. 25.0)."
    end

    attribute :due_days, :integer do
      default 30
      allow_nil? false
      description "Days after invoice creation date when this installment is due."
    end

    timestamps()
  end

  relationships do
    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      allow_nil? false
    end
  end
end
```

- [ ] **Step 4: Create the percentage validation module**

Create `lib/garden/finance/payment_schedule_item/validations/percentage_sum_not_exceeded.ex`:

```elixir
defmodule GnomeGarden.Finance.PaymentScheduleItem.Validations.PercentageSumNotExceeded do
  @moduledoc """
  Validates that adding/updating this item will not push the schedule's
  total percentage above 100.

  Note: enforces <= 100 (not == 100) so items can be added incrementally.
  The complete-schedule check (sum == 100) is enforced at invoice generation time.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias GnomeGarden.Finance.PaymentScheduleItem

  @impl true
  def validate(changeset, _opts, _context) do
    agreement_id = Ash.Changeset.get_attribute(changeset, :agreement_id)
    new_pct = Ash.Changeset.get_attribute(changeset, :percentage) || Decimal.new("0")
    item_id = changeset.data && changeset.data.id

    existing_sum =
      PaymentScheduleItem
      |> Ash.Query.filter(agreement_id == ^agreement_id)
      |> then(fn q ->
        if item_id, do: Ash.Query.filter(q, id != ^item_id), else: q
      end)
      |> Ash.read!(domain: GnomeGarden.Finance)
      |> Enum.reduce(Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.percentage)
      end)

    total = Decimal.add(existing_sum, new_pct)

    if Decimal.compare(total, Decimal.new("100")) == :gt do
      {:error,
       field: :percentage,
       message: "would push schedule total to %{total}% (max 100%)",
       vars: %{total: Decimal.to_string(total)}}
    else
      :ok
    end
  end
end
```

- [ ] **Step 5: Add `has_many :payment_schedule_items` to Agreement**

In `lib/garden/commercial/agreement.ex`, inside the `relationships do` block (after existing has_many entries):

```elixir
has_many :payment_schedule_items, GnomeGarden.Finance.PaymentScheduleItem do
  sort position: :asc
end
```

- [ ] **Step 6: Register PaymentScheduleItem in Finance domain**

In `lib/garden/finance.ex`, add to the `resources do` block:

```elixir
resource GnomeGarden.Finance.PaymentScheduleItem
```

- [ ] **Step 7: Generate migration**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.generate_migrations --name add_billing_reliability
```

Expected: creates a new file in `priv/repo/migrations/` — inspect it to confirm it includes `billing_contact_id` on organizations, `payment_terms_days` on agreements, and the full `payment_schedule_items` table.

- [ ] **Step 8: Run migration**

```bash
GNOME_GARDEN_DB_PORT=5432 mix ash_postgres.migrate
```

Expected: `== Running ... AddBillingReliability == ... [up]` with no errors.

- [ ] **Step 9: Run existing test suite to confirm nothing broken**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/ --trace 2>&1 | tail -20
```

Expected: same pass/fail count as before (0 new failures).

- [ ] **Step 10: Commit**

```bash
git add lib/garden/finance/payment_schedule_item.ex \
        lib/garden/finance/payment_schedule_item/ \
        lib/garden/finance.ex \
        lib/garden/operations/organization.ex \
        lib/garden/commercial/agreement.ex \
        priv/repo/migrations/
git commit -m "feat: add billing_contact, payment_terms_days, PaymentScheduleItem schema"
```

---

## Task 2: Refactor InvoiceEmail — extract find_billing_email/1

The existing `find_contact_email/1` in `InvoiceEmail` doesn't check `billing_contact`. Extract a shared `find_billing_email/1` that checks billing_contact first, then falls back to any affiliated person. `InvoiceEmail` and the upcoming `PaymentReminderEmail` will both use it.

**Files:**
- Modify: `lib/garden/mailer/invoice_email.ex`

- [ ] **Step 1: Write the failing test**

Create `test/garden/mailer/invoice_email_test.exs`:

```elixir
defmodule GnomeGarden.Mailer.InvoiceEmailTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mailer.InvoiceEmail
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Acme Corp #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, billing_person} =
      Operations.create_person(%{
        first_name: "Billing",
        last_name: "Contact",
        email: "billing@acme.com"
      })

    {:ok, other_person} =
      Operations.create_person(%{
        first_name: "Other",
        last_name: "Person",
        email: "other@acme.com"
      })

    # Affiliate other_person with org (but not billing_person yet)
    Operations.create_organization_affiliation(%{
      organization_id: org.id,
      person_id: other_person.id
    })

    %{org: org, billing_person: billing_person, other_person: other_person}
  end

  test "find_billing_email returns billing_contact email when set", %{
    org: org,
    billing_person: billing_person
  } do
    {:ok, _} =
      Operations.update_organization(org, %{billing_contact_id: billing_person.id})

    {:ok, loaded_org} =
      Operations.get_organization(org.id, load: [:billing_contact])

    assert InvoiceEmail.find_billing_email(loaded_org) == "billing@acme.com"
  end

  test "find_billing_email falls back to affiliated person when no billing_contact", %{
    org: org
  } do
    {:ok, loaded_org} =
      Operations.get_organization(org.id, load: [:billing_contact])

    assert InvoiceEmail.find_billing_email(loaded_org) == "other@acme.com"
  end

  test "find_billing_email skips billing_contact when do_not_email is true", %{
    org: org,
    billing_person: billing_person,
    other_person: other_person
  } do
    {:ok, _} = Operations.update_person(billing_person, %{do_not_email: true})

    {:ok, _} =
      Operations.update_organization(org, %{billing_contact_id: billing_person.id})

    {:ok, loaded_org} =
      Operations.get_organization(org.id, load: [:billing_contact])

    # Should fall back to other_person
    assert InvoiceEmail.find_billing_email(loaded_org) == to_string(other_person.email)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mailer/invoice_email_test.exs --trace
```

Expected: FAIL — `find_billing_email/1` is not defined yet.

- [ ] **Step 3: Implement find_billing_email/1 in InvoiceEmail**

In `lib/garden/mailer/invoice_email.ex`, replace the private `find_contact_email/1` function with a public `find_billing_email/1`:

```elixir
@doc """
Returns the best available email address for an organization.

Priority:
1. organization.billing_contact.email (if set and do_not_email is false)
2. Any affiliated person with a valid email (existing find_contact_email logic)
3. nil if no email found
"""
@spec find_billing_email(map()) :: String.t() | nil
def find_billing_email(organization) do
  with_billing_contact(organization) || find_affiliated_email(organization)
end

defp with_billing_contact(%{billing_contact: %{email: email, do_not_email: false}})
     when not is_nil(email),
     do: to_string(email)

defp with_billing_contact(_), do: nil

defp find_affiliated_email(organization) do
  case Operations.list_people_for_organization(organization.id, actor: nil) do
    {:ok, people} ->
      Enum.find_value(people, fn person ->
        if person.email && !person.do_not_email, do: to_string(person.email)
      end)

    _ ->
      nil
  end
end
```

Also update `build/2` to use the new helper. The invoice's organization must be loaded with `:billing_contact`:

```elixir
def build(invoice, mercury_info \\ []) do
  contact_email = find_billing_email(invoice.organization)
  # rest of function unchanged
end
```

Remove the now-replaced private `find_contact_email/1` function.

- [ ] **Step 4: Run test to verify it passes**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/mailer/invoice_email_test.exs --trace
```

Expected: all tests PASS.

- [ ] **Step 5: Run full test suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/ --trace 2>&1 | tail -20
```

Expected: no new failures.

- [ ] **Step 6: Commit**

```bash
git add lib/garden/mailer/invoice_email.ex test/garden/mailer/invoice_email_test.exs
git commit -m "feat: extract find_billing_email/1 helper — billing_contact-aware email lookup"
```

---

## Task 3: Billing Contact picker on Organization show

Add a "Billing Contact" person picker to the Organization show/edit page.

**Files:**
- Modify: `lib/garden_web/live/operations/organization_live/show.ex`

- [ ] **Step 1: Read the current Organization show LiveView**

Read `lib/garden_web/live/operations/organization_live/show.ex` to understand the existing layout and form pattern.

- [ ] **Step 2: Load billing_contact in mount**

Wherever the organization is loaded, add `:billing_contact` to the load list:

```elixir
load: [...existing..., :billing_contact]
```

- [ ] **Step 3: Add Billing Contact display and edit to the template**

In the organization details section, add:

```heex
<.data_list>
  <%!-- existing fields --%>
  <:item title="Billing Contact">
    <%= if @org.billing_contact do %>
      <.link navigate={~p"/operations/people/#{@org.billing_contact}"}>
        {@org.billing_contact.first_name} {@org.billing_contact.last_name}
        <span class="text-zinc-400 ml-1 text-sm">({@org.billing_contact.email})</span>
      </.link>
    <% else %>
      <span class="text-zinc-400 italic">Not set — invoice will go to any affiliated contact</span>
    <% end %>
  </:item>
</.data_list>
```

If the show page has an inline edit form, add a billing_contact_id field. If edits go through a separate edit LiveView, make the same change there.

- [ ] **Step 4: Wire up the billing_contact_id update**

Add an event handler (or form field) that calls:

```elixir
Operations.update_organization(org, %{billing_contact_id: person_id}, actor: actor)
```

The simplest approach: if the page has existing `phx-submit` for editing, add `billing_contact_id` to the accepted fields. If not, add a simple select dropdown populated with affiliated people for the org.

- [ ] **Step 5: Verify it works in the browser**

Start the server, navigate to an Organization show page. Confirm Billing Contact is displayed. Set it to a person and save. Reload to confirm it persists.

```bash
GNOME_GARDEN_DB_PORT=5432 mix phx.server
```

- [ ] **Step 6: Commit**

```bash
git add lib/garden_web/live/operations/organization_live/
git commit -m "feat: add billing contact picker to organization show"
```

---

## Task 4: Fixed-fee invoice generation

Create the change module and Invoice action for generating draft installment invoices from a payment schedule.

**Files:**
- Create: `lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex`
- Modify: `lib/garden/finance/invoice.ex`
- Modify: `lib/garden/finance.ex`
- Create: `test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs`:

```elixir
defmodule GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeScheduleTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        name: "Fixed Fee Project",
        organization_id: org.id,
        agreement_type: :project,
        billing_model: :fixed_fee,
        contract_value: Decimal.new("10000.00"),
        currency_code: "USD",
        status: :active
      })

    %{org: org, agreement: agreement}
  end

  test "generates one draft invoice per schedule item with correct amounts", %{
    agreement: agreement
  } do
    {:ok, _} =
      Finance.create_payment_schedule_item(%{
        agreement_id: agreement.id,
        position: 1,
        label: "Deposit",
        percentage: Decimal.new("25"),
        due_days: 0
      })

    {:ok, _} =
      Finance.create_payment_schedule_item(%{
        agreement_id: agreement.id,
        position: 2,
        label: "Milestone 1",
        percentage: Decimal.new("25"),
        due_days: 30
      })

    {:ok, _} =
      Finance.create_payment_schedule_item(%{
        agreement_id: agreement.id,
        position: 3,
        label: "Final Payment",
        percentage: Decimal.new("50"),
        due_days: 30
      })

    {:ok, invoices} = Finance.create_invoices_from_fixed_fee_schedule(agreement.id)

    assert length(invoices) == 3

    [deposit, milestone, final] = Enum.sort_by(invoices, & &1.notes)

    assert Decimal.equal?(deposit.total_amount, Decimal.new("2500.00"))
    assert deposit.status == :draft
    assert deposit.notes == "Deposit"

    assert Decimal.equal?(milestone.total_amount, Decimal.new("2500.00"))
    assert milestone.notes == "Milestone 1"

    assert Decimal.equal?(final.total_amount, Decimal.new("5000.00"))
    assert final.notes == "Final Payment"
  end

  test "returns error when percentages do not sum to 100", %{agreement: agreement} do
    {:ok, _} =
      Finance.create_payment_schedule_item(%{
        agreement_id: agreement.id,
        position: 1,
        label: "Partial",
        percentage: Decimal.new("60"),
        due_days: 30
      })

    assert {:error, _} = Finance.create_invoices_from_fixed_fee_schedule(agreement.id)
  end

  test "returns error when agreement has no contract_value" do
    {:ok, org} =
      Operations.create_organization(%{
        name: "No Value Org",
        organization_kind: :business
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        name: "No Contract Value",
        organization_id: org.id,
        agreement_type: :project,
        billing_model: :fixed_fee,
        currency_code: "USD",
        status: :active
      })

    {:ok, _} =
      Finance.create_payment_schedule_item(%{
        agreement_id: agreement.id,
        position: 1,
        label: "Full Payment",
        percentage: Decimal.new("100"),
        due_days: 30
      })

    assert {:error, _} = Finance.create_invoices_from_fixed_fee_schedule(agreement.id)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs --trace
```

Expected: FAIL — `Finance.create_invoices_from_fixed_fee_schedule/1` not defined.

- [ ] **Step 3: Create the change module**

Create `lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex`:

```elixir
defmodule GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule do
  @moduledoc """
  Generates one draft Invoice per PaymentScheduleItem for a fixed-fee Agreement.

  Called via Finance.create_invoices_from_fixed_fee_schedule/1.

  Pre-conditions:
  - Agreement must have billing_model: :fixed_fee
  - Agreement must have a non-nil contract_value
  - Schedule items must exist and sum to exactly 100%

  Returns {:ok, [Invoice.t()]} or {:error, reason}.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.PaymentScheduleItem

  require Ash.Query

  def generate(agreement_id) do
    with {:ok, agreement} <- load_agreement(agreement_id),
         :ok <- validate_contract_value(agreement),
         {:ok, items} <- load_schedule_items(agreement_id) do
      case validate_items_present(items) do
        :no_schedule ->
          # No schedule: single invoice for full contract_value
          generate_single_invoice(agreement)

        :ok ->
          with :ok <- validate_percentage_sum(items) do
            create_invoices(agreement, items)
          end
      end
    end
  end

  defp generate_single_invoice(agreement) do
    attrs = %{
      organization_id: agreement.organization_id,
      agreement_id: agreement.id,
      invoice_number: generate_invoice_number(agreement, %{position: 1}),
      currency_code: agreement.currency_code || "USD",
      subtotal: agreement.contract_value,
      tax_total: Decimal.new("0"),
      total_amount: agreement.contract_value,
      balance_amount: agreement.contract_value,
      due_on: Date.add(Date.utc_today(), agreement.payment_terms_days),
      notes: "Full payment"
    }

    case Finance.create_invoice(attrs) do
      {:ok, invoice} -> {:ok, [invoice]}
      error -> error
    end
  end

  defp load_agreement(agreement_id) do
    Commercial.get_agreement(agreement_id)
  end

  defp validate_contract_value(%{contract_value: nil}),
    do: {:error, "agreement must have a contract_value set before generating fixed-fee invoices"}

  defp validate_contract_value(_), do: :ok

  defp load_schedule_items(agreement_id) do
    PaymentScheduleItem
    |> Ash.Query.filter(agreement_id == ^agreement_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read(domain: Finance)
  end

  defp validate_items_present([]), do: :no_schedule
  defp validate_items_present(_items), do: :ok

  defp validate_percentage_sum(items) do
    total =
      Enum.reduce(items, Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.percentage)
      end)

    if Decimal.equal?(total, Decimal.new("100")) do
      :ok
    else
      {:error, "payment schedule percentages sum to #{total}%, must equal 100%"}
    end
  end

  defp create_invoices(agreement, items) do
    today = Date.utc_today()

    invoices =
      Enum.reduce_while(items, [], fn item, acc ->
        amount =
          agreement.contract_value
          |> Decimal.mult(Decimal.div(item.percentage, Decimal.new("100")))
          |> Decimal.round(2)

        attrs = %{
          organization_id: agreement.organization_id,
          agreement_id: agreement.id,
          invoice_number: generate_invoice_number(agreement, item),
          currency_code: agreement.currency_code || "USD",
          subtotal: amount,
          tax_total: Decimal.new("0"),
          total_amount: amount,
          balance_amount: amount,
          due_on: Date.add(today, item.due_days),
          notes: item.label
        }

        case Finance.create_invoice(attrs) do
          {:ok, invoice} -> {:cont, [invoice | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case invoices do
      {:error, reason} -> {:error, reason}
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp generate_invoice_number(agreement, item) do
    ref = agreement.reference_number || String.slice(agreement.id, 0, 8)
    "#{ref}-#{item.position}"
  end
end
```

- [ ] **Step 4: Add Finance domain function and action**

In `lib/garden/finance.ex`, add a domain-level action:

```elixir
# In the Finance domain, add alongside other actions:
action :create_invoices_from_fixed_fee_schedule, {:array, :struct} do
  argument :agreement_id, :uuid, allow_nil?: false
  run fn input, _context ->
    GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule.generate(
      input.arguments.agreement_id
    )
  end
end
```

Then expose it as a domain shortcut function. In `lib/garden/finance.ex` (or wherever domain shortcuts are defined, following the pattern of other shortcut functions):

```elixir
def create_invoices_from_fixed_fee_schedule(agreement_id, opts \\ []) do
  GnomeGarden.Finance.Changes.CreateInvoiceFromFixedFeeSchedule.generate(agreement_id)
end
```

Also add Finance domain shortcut for PaymentScheduleItem CRUD:
```elixir
def create_payment_schedule_item(attrs, opts \\ []) do
  GnomeGarden.Finance.PaymentScheduleItem
  |> Ash.Changeset.for_create(:create, attrs)
  |> Ash.create(domain: __MODULE__, authorize?: false)
end

def list_payment_schedule_items_for_agreement(agreement_id, opts \\ []) do
  GnomeGarden.Finance.PaymentScheduleItem
  |> Ash.Query.filter(agreement_id == ^agreement_id)
  |> Ash.Query.sort(position: :asc)
  |> Ash.read(domain: __MODULE__, authorize?: false)
end

def get_payment_schedule_item(id, opts \\ []) do
  GnomeGarden.Finance.PaymentScheduleItem
  |> Ash.get(id, domain: __MODULE__, authorize?: false)
end

def delete_payment_schedule_item(item, opts \\ []) do
  Ash.destroy(item, domain: __MODULE__, authorize?: false)
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/changes/create_invoice_from_fixed_fee_schedule_test.exs --trace
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/garden/finance/changes/create_invoice_from_fixed_fee_schedule.ex \
        lib/garden/finance/invoice.ex \
        lib/garden/finance.ex \
        test/garden/finance/changes/
git commit -m "feat: fixed-fee invoice generation from payment schedule"
```

---

## Task 5: Payment Schedule UI on Agreement show

Add an inline Payment Schedule section to the Agreement show LiveView, visible only for fixed-fee agreements.

**Files:**
- Modify: `lib/garden_web/live/commercial/agreement_live/show.ex`

- [ ] **Step 1: Read the current Agreement show LiveView**

Read `lib/garden_web/live/commercial/agreement_live/show.ex` to understand mount, assigns, and template structure.

- [ ] **Step 2: Load payment_schedule_items in mount**

Wherever the agreement is loaded in `mount/3`, add to the load list:

```elixir
load: [...existing..., :payment_schedule_items]
```

Also add a socket assign for the new item form:

```elixir
|> assign(:new_schedule_item, %{label: "", percentage: "", due_days: "30"})
|> assign(:schedule_pct_total, compute_pct_total(agreement.payment_schedule_items))
```

Where `compute_pct_total` is a private helper:

```elixir
defp compute_pct_total(items) do
  Enum.reduce(items, Decimal.new("0"), fn item, acc ->
    Decimal.add(acc, item.percentage)
  end)
end
```

- [ ] **Step 3: Add Payment Schedule section to template**

Inside the `~H"""` template, add a new section after the existing agreement details — only rendered when `billing_model == :fixed_fee`:

```heex
<div :if={@agreement.billing_model == :fixed_fee}>
  <.section title="Payment Schedule" description="Installment invoices generated from this schedule. Percentages must sum to 100%.">
    <div class="px-4 pb-4">
      <%!-- Total indicator --%>
      <p class={[
        "text-sm font-medium mb-3",
        if(Decimal.equal?(@schedule_pct_total, Decimal.new("100")),
          do: "text-emerald-600",
          else: "text-amber-600"
        )
      ]}>
        Total: <%= @schedule_pct_total %>%
        <%= if not Decimal.equal?(@schedule_pct_total, Decimal.new("100")) do %>
          (must equal 100% before generating invoices)
        <% end %>
      </p>

      <%!-- Existing items --%>
      <table :if={length(@agreement.payment_schedule_items) > 0} class="min-w-full text-sm mb-4">
        <thead>
          <tr class="text-left text-zinc-500">
            <th class="pr-4 pb-2 font-medium">#</th>
            <th class="pr-4 pb-2 font-medium">Label</th>
            <th class="pr-4 pb-2 font-medium">%</th>
            <th class="pr-4 pb-2 font-medium">Due (days after issue)</th>
            <th class="pb-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={item <- @agreement.payment_schedule_items} class="border-t border-zinc-100">
            <td class="pr-4 py-2 text-zinc-500">{item.position}</td>
            <td class="pr-4 py-2">{item.label}</td>
            <td class="pr-4 py-2">{item.percentage}%</td>
            <td class="pr-4 py-2">{item.due_days} days</td>
            <td class="py-2">
              <button
                phx-click="delete_schedule_item"
                phx-value-id={item.id}
                class="text-red-500 hover:text-red-700 text-xs"
              >
                Remove
              </button>
            </td>
          </tr>
        </tbody>
      </table>

      <%!-- Add item form --%>
      <form phx-submit="add_schedule_item" class="flex gap-3 items-end flex-wrap">
        <div>
          <label class="block text-xs text-zinc-500 mb-1">Label</label>
          <input
            type="text"
            name="label"
            placeholder="e.g. Deposit"
            class="border border-zinc-300 rounded px-2 py-1 text-sm w-32"
            required
          />
        </div>
        <div>
          <label class="block text-xs text-zinc-500 mb-1">Percentage</label>
          <input
            type="number"
            name="percentage"
            placeholder="25"
            min="1"
            max="100"
            step="0.01"
            class="border border-zinc-300 rounded px-2 py-1 text-sm w-24"
            required
          />
        </div>
        <div>
          <label class="block text-xs text-zinc-500 mb-1">Due (days)</label>
          <input
            type="number"
            name="due_days"
            value="30"
            min="0"
            class="border border-zinc-300 rounded px-2 py-1 text-sm w-20"
            required
          />
        </div>
        <button
          type="submit"
          class="bg-emerald-600 text-white text-sm px-3 py-1.5 rounded hover:bg-emerald-700"
        >
          Add Item
        </button>
      </form>
    </div>
  </.section>
</div>
```

- [ ] **Step 4: Add event handlers**

```elixir
@impl true
def handle_event("add_schedule_item", %{"label" => label, "percentage" => pct, "due_days" => days}, socket) do
  agreement = socket.assigns.agreement
  next_position = length(agreement.payment_schedule_items) + 1

  attrs = %{
    agreement_id: agreement.id,
    position: next_position,
    label: label,
    percentage: Decimal.new(pct),
    due_days: String.to_integer(days)
  }

  case Finance.create_payment_schedule_item(attrs) do
    {:ok, _item} ->
      {:ok, refreshed} =
        Commercial.get_agreement(agreement.id,
          load: [...existing loads..., :payment_schedule_items]
        )

      {:noreply,
       socket
       |> assign(:agreement, refreshed)
       |> assign(:schedule_pct_total, compute_pct_total(refreshed.payment_schedule_items))
       |> put_flash(:info, "Item added")}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Could not add item: #{inspect(reason)}")}
  end
end

@impl true
def handle_event("delete_schedule_item", %{"id" => id}, socket) do
  case Finance.get_payment_schedule_item(id) do
    {:ok, item} ->
      Finance.delete_payment_schedule_item(item)
      {:ok, refreshed} =
        Commercial.get_agreement(socket.assigns.agreement.id,
          load: [...existing loads..., :payment_schedule_items]
        )

      {:noreply,
       socket
       |> assign(:agreement, refreshed)
       |> assign(:schedule_pct_total, compute_pct_total(refreshed.payment_schedule_items))
       |> put_flash(:info, "Item removed")}

    _ ->
      {:noreply, put_flash(socket, :error, "Item not found")}
  end
end
```

Also add `Finance.get_payment_schedule_item/1` and `Finance.delete_payment_schedule_item/1` to `lib/garden/finance.ex` if not already added in Task 4.

- [ ] **Step 5: Update the "Generate Invoice" button to handle fixed-fee**

Find the existing `handle_event("generate_invoice", ...)` handler. Add a branch:

```elixir
def handle_event("generate_invoice", _params, socket) do
  agreement = socket.assigns.agreement
  actor = socket.assigns.current_user

  result =
    case agreement.billing_model do
      :fixed_fee ->
        Finance.create_invoices_from_fixed_fee_schedule(agreement.id)

      _ ->
        Finance.create_invoice_from_agreement_sources(agreement.id, actor: actor)
        |> case do
          {:ok, invoice} -> {:ok, [invoice]}
          error -> error
        end
    end

  case result do
    {:ok, invoices} ->
      count = length(List.wrap(invoices))
      {:noreply, put_flash(socket, :info, "#{count} invoice(s) created")}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Could not generate invoice: #{inspect(reason)}")}
  end
end
```

- [ ] **Step 6: Smoke test in browser**

Start the server. Navigate to a fixed-fee Agreement. Add schedule items (25/25/50). Confirm total turns green at 100%. Click Generate Invoice. Confirm 3 draft invoices appear in `/finance/invoices`.

- [ ] **Step 7: Commit**

```bash
git add lib/garden_web/live/commercial/agreement_live/
git commit -m "feat: payment schedule UI on agreement show + fixed-fee generate invoice"
```

---

## Task 6: AR Aging Report LiveView

**Files:**
- Create: `lib/garden_web/live/finance/ar_aging_live.ex`
- Modify: `lib/garden_web/router.ex`
- Modify: `lib/garden_web/components/nav.ex`
- Create: `test/garden_web/live/finance/ar_aging_live_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden_web/live/finance/ar_aging_live_test.exs`:

```elixir
defmodule GnomeGardenWeb.Finance.ArAgingLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  setup :register_and_log_in_user

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "AR Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    today = Date.utc_today()

    # Current invoice (not yet due)
    {:ok, current} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-CURRENT",
        currency_code: "USD",
        total_amount: Decimal.new("1000"),
        balance_amount: Decimal.new("1000"),
        due_on: Date.add(today, 10)
      })

    {:ok, current} = Finance.issue_invoice(current)

    # 15-day overdue invoice
    {:ok, overdue_15} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-15",
        currency_code: "USD",
        total_amount: Decimal.new("2000"),
        balance_amount: Decimal.new("2000"),
        due_on: Date.add(today, -15)
      })

    {:ok, overdue_15} = Finance.issue_invoice(overdue_15)

    # 45-day overdue invoice
    {:ok, overdue_45} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-45",
        currency_code: "USD",
        total_amount: Decimal.new("3000"),
        balance_amount: Decimal.new("3000"),
        due_on: Date.add(today, -45)
      })

    {:ok, overdue_45} = Finance.issue_invoice(overdue_45)

    %{org: org, current: current, overdue_15: overdue_15, overdue_45: overdue_45}
  end

  test "renders AR aging page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/ar-aging")
    assert html =~ "AR Aging"
  end

  test "shows current invoice in Current bucket", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/ar-aging")
    assert html =~ "INV-CURRENT"
  end

  test "shows 15-day overdue invoice in 1-30 bucket", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/ar-aging")
    assert html =~ "INV-15"
  end

  test "shows 45-day overdue invoice in 31-60 bucket", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/ar-aging")
    assert html =~ "INV-45"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/finance/ar_aging_live_test.exs --trace
```

Expected: FAIL — route and LiveView don't exist yet.

- [ ] **Step 3: Add route**

In `lib/garden_web/router.ex`, inside the authenticated Finance scope (where approval-queue is), add:

```elixir
live "/finance/ar-aging", Finance.ArAgingLive, :index
```

- [ ] **Step 4: Add nav link**

In `lib/garden_web/components/nav.ex`, in the Finance subnav (near the existing Approvals link):

```elixir
<.subnav_item navigate={~p"/finance/ar-aging"} active={@current_path =~ "/finance/ar-aging"}>
  AR Aging
</.subnav_item>
```

- [ ] **Step 5: Create the AR Aging LiveView**

Create `lib/garden_web/live/finance/ar_aging_live.ex`:

```elixir
defmodule GnomeGardenWeb.Finance.ArAgingLive do
  use GnomeGardenWeb, :live_view

  alias GnomeGarden.Finance

  @buckets [
    {0, :current, "Current"},
    {1, :days_1_30, "1–30 days"},
    {31, :days_31_60, "31–60 days"},
    {61, :days_61_90, "61–90 days"},
    {91, :days_91_plus, "90+ days"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    invoices = load_invoices(socket.assigns.current_user)
    bucketed = bucket_invoices(invoices)

    {:ok,
     socket
     |> assign(:page_title, "AR Aging")
     |> assign(:bucketed, bucketed)
     |> assign(:grand_total, compute_grand_total(invoices))
     |> assign(:show_all, false)
     |> assign(:org_filter, nil)}
  end

  @impl true
  def handle_event("toggle_show_all", _params, socket) do
    show_all = !socket.assigns.show_all
    invoices = load_invoices(socket.assigns.current_user, show_all: show_all)
    bucketed = bucket_invoices(invoices)

    {:noreply,
     socket
     |> assign(:show_all, show_all)
     |> assign(:bucketed, bucketed)
     |> assign(:grand_total, compute_grand_total(invoices))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page class="pb-8">
      <.page_header eyebrow="Finance">
        AR Aging
        <:subtitle>
          Outstanding invoices grouped by how overdue they are.
        </:subtitle>
        <:actions>
          <label class="flex items-center gap-2 text-sm text-zinc-600 cursor-pointer">
            <input
              type="checkbox"
              phx-click="toggle_show_all"
              checked={@show_all}
              class="rounded"
            />
            Show paid/void
          </label>
        </:actions>
      </.page_header>

      <div class="space-y-6">
        <%= for {_min, key, label} <- @buckets do %>
          <% bucket = Map.get(@bucketed, key, []) %>
          <.section title={"#{label} (#{length(bucket)})"} compact body_class="p-0">
            <div :if={Enum.empty?(bucket)} class="px-5 py-4 text-sm text-zinc-400 italic">
              No invoices
            </div>
            <table :if={not Enum.empty?(bucket)} class="min-w-full divide-y divide-zinc-200 text-sm dark:divide-white/10">
              <thead class="bg-zinc-50 dark:bg-white/[0.03]">
                <tr>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500">Invoice</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500">Client</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500">Due</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500">Days Overdue</th>
                  <th class="px-5 py-3 text-right font-medium text-zinc-500">Balance Due</th>
                  <th class="px-5 py-3 text-left font-medium text-zinc-500">Status</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-zinc-200 dark:divide-white/10">
                <tr :for={inv <- bucket}>
                  <td class="px-5 py-3">
                    <.link navigate={~p"/finance/invoices/#{inv}"} class="font-medium text-emerald-600 hover:underline">
                      {inv.invoice_number}
                    </.link>
                  </td>
                  <td class="px-5 py-3 text-zinc-600">
                    <.link navigate={~p"/operations/organizations/#{inv.organization}"} class="hover:underline">
                      {inv.organization && inv.organization.name}
                    </.link>
                  </td>
                  <td class="px-5 py-3 text-zinc-600">{inv.due_on}</td>
                  <td class="px-5 py-3 text-zinc-600">
                    {days_overdue(inv.due_on)}
                  </td>
                  <td class="px-5 py-3 text-right font-medium">
                    USD {format_amount(inv.balance_amount)}
                  </td>
                  <td class="px-5 py-3">
                    <.badge variant={status_variant(inv.status)}>{inv.status}</.badge>
                  </td>
                </tr>
              </tbody>
              <tfoot>
                <tr class="bg-zinc-50 dark:bg-white/[0.03]">
                  <td colspan="4" class="px-5 py-3 text-sm font-medium text-zinc-700 dark:text-zinc-300">
                    Subtotal
                  </td>
                  <td class="px-5 py-3 text-right text-sm font-semibold text-zinc-900 dark:text-white">
                    USD {format_amount(bucket_subtotal(bucket))}
                  </td>
                  <td></td>
                </tr>
              </tfoot>
            </table>
          </.section>
        <% end %>

        <div class="flex justify-end px-1">
          <p class="text-sm font-semibold text-zinc-900 dark:text-white">
            Grand Total Outstanding: USD {format_amount(@grand_total)}
          </p>
        </div>
      </div>
    </.page>
    """
  end

  defp load_invoices(actor, opts \\ []) do
    show_all = Keyword.get(opts, :show_all, false)

    query_opts =
      if show_all do
        [query: [sort: [due_on: :asc]], load: [:organization]]
      else
        [
          query: [filter: [status: [in: [:issued, :partial]]], sort: [due_on: :asc]],
          load: [:organization]
        ]
      end

    case Finance.list_invoices(Keyword.merge(query_opts, actor: actor)) do
      {:ok, invoices} -> invoices
      {:error, _} -> []
    end
  end

  defp bucket_subtotal(invoices) do
    invoices
    |> Enum.filter(&(&1.status in [:issued, :partial]))
    |> Enum.reduce(Decimal.new("0"), fn inv, acc ->
      Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
    end)
  end

  defp bucket_invoices(invoices) do
    today = Date.utc_today()

    Enum.group_by(invoices, fn inv ->
      days = if inv.due_on, do: Date.diff(today, inv.due_on), else: 0

      cond do
        days <= 0 -> :current
        days <= 30 -> :days_1_30
        days <= 60 -> :days_31_60
        days <= 90 -> :days_61_90
        true -> :days_91_plus
      end
    end)
  end

  defp compute_grand_total(invoices) do
    invoices
    |> Enum.filter(&(&1.status in [:issued, :partial]))
    |> Enum.reduce(Decimal.new("0"), fn inv, acc ->
      Decimal.add(acc, inv.balance_amount || Decimal.new("0"))
    end)
  end

  defp days_overdue(nil), do: "—"

  defp days_overdue(due_on) do
    days = Date.diff(Date.utc_today(), due_on)
    if days > 0, do: "#{days}", else: "—"
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)

  defp status_variant(:issued), do: :info
  defp status_variant(:partial), do: :warning
  defp status_variant(:paid), do: :success
  defp status_variant(_), do: :neutral
end
```

- [ ] **Step 6: Run tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden_web/live/finance/ar_aging_live_test.exs --trace
```

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/garden_web/live/finance/ar_aging_live.ex \
        lib/garden_web/router.ex \
        lib/garden_web/components/nav.ex \
        test/garden_web/live/finance/ar_aging_live_test.exs
git commit -m "feat: AR Aging Report LiveView at /finance/ar-aging"
```

---

## Task 7: PaymentReminderEmail module

**Files:**
- Create: `lib/garden/mailer/payment_reminder_email.ex`

- [ ] **Step 1: Create PaymentReminderEmail**

Create `lib/garden/mailer/payment_reminder_email.ex`:

```elixir
defmodule GnomeGarden.Mailer.PaymentReminderEmail do
  @moduledoc """
  Builds payment reminder emails for overdue invoices.

  Usage:
    PaymentReminderEmail.build(invoice, :day_7) |> Mailer.deliver()
    PaymentReminderEmail.build(invoice, :day_30, cc: "owner@gnomeautomation.io") |> Mailer.deliver()

  `invoice` must have `:organization` loaded (with `:billing_contact`).
  """

  import Swoosh.Email

  alias GnomeGarden.Mailer.InvoiceEmail

  @spec build(map(), :day_7 | :day_14 | :day_30, keyword()) :: Swoosh.Email.t()
  def build(invoice, threshold, opts \\ []) do
    org = invoice.organization
    contact_email = InvoiceEmail.find_billing_email(org)
    days_overdue = days_since(invoice.due_on)

    email =
      new()
      |> from({"Gnome Automation Billing", "billing@gnomeautomation.io"})
      |> to(contact_email || "billing@gnomeautomation.io")
      |> subject(subject_for(threshold, invoice.invoice_number, days_overdue))
      |> html_body(body_for(threshold, invoice, days_overdue))

    case Keyword.get(opts, :cc) do
      nil -> email
      cc_email -> cc(email, cc_email)
    end
  end

  defp subject_for(:day_7, number, days),
    do: "Friendly reminder: Invoice #{number} was due #{days} days ago"

  defp subject_for(:day_14, number, days),
    do: "Follow-up: Invoice #{number} is #{days} days overdue"

  defp subject_for(:day_30, number, days),
    do: "URGENT: Invoice #{number} is #{days} days overdue — immediate payment required"

  defp body_for(threshold, invoice, days_overdue) do
    org_name = (invoice.organization && invoice.organization.name) || "Client"
    mercury_info = Application.get_env(:gnome_garden, :mercury_payment_info, [])
    account_number = Keyword.get(mercury_info, :account_number, "")
    routing_number = Keyword.get(mercury_info, :routing_number, "")

    tone =
      case threshold do
        :day_7 -> "This is a friendly reminder that"
        :day_14 -> "We wanted to follow up as"
        :day_30 -> "This is an urgent notice that"
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
              <td style="background:#0f172a;padding:24px 40px;">
                <p style="margin:0;font-size:16px;font-weight:700;color:#ffffff;">Gnome Automation — Payment Reminder</p>
              </td>
            </tr>
            <tr>
              <td style="padding:32px 40px;">
                <p style="margin:0 0 16px;color:#1e293b;">Dear #{org_name},</p>
                <p style="margin:0 0 16px;color:#1e293b;">#{tone} invoice <strong>#{invoice.invoice_number}</strong> for <strong>USD #{format_amount(invoice.balance_amount)}</strong> is now <strong>#{days_overdue} days overdue</strong> (original due date: #{invoice.due_on}).</p>
                <p style="margin:0 0 24px;color:#1e293b;">Please remit payment at your earliest convenience using the instructions below:</p>
                <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:20px;margin-bottom:24px;">
                  <p style="margin:0 0 12px;font-weight:600;color:#0f172a;">Payment Instructions (ACH / Wire)</p>
                  <table cellpadding="0" cellspacing="0" style="font-size:14px;">
                    <tr><td style="padding:2px 0;color:#64748b;min-width:120px;">Bank:</td><td style="color:#0f172a;font-weight:500;">Mercury</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Account #:</td><td style="color:#0f172a;font-weight:500;">#{account_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Routing #:</td><td style="color:#0f172a;font-weight:500;">#{routing_number}</td></tr>
                    <tr><td style="padding:2px 0;color:#64748b;">Reference:</td><td style="color:#0f172a;font-weight:500;">#{invoice.invoice_number}</td></tr>
                  </table>
                </div>
                <p style="margin:0;color:#64748b;font-size:13px;">Questions? Reply to billing@gnomeautomation.io</p>
              </td>
            </tr>
          </table>
        </td></tr>
      </table>
    </body>
    </html>
    """
  end

  defp days_since(nil), do: 0
  defp days_since(due_on), do: Date.diff(Date.utc_today(), due_on)

  defp format_amount(nil), do: "0.00"
  defp format_amount(d), do: Decimal.to_string(Decimal.round(d, 2), :normal)
end
```

- [ ] **Step 2: Run compile to verify no errors**

```bash
GNOME_GARDEN_DB_PORT=5432 mix compile
```

Expected: compiles cleanly.

- [ ] **Step 3: Commit**

```bash
git add lib/garden/mailer/payment_reminder_email.ex
git commit -m "feat: PaymentReminderEmail module (day 7/14/30 overdue reminders)"
```

---

## Task 8: PaymentReminderWorker + Oban config

**Files:**
- Create: `lib/garden/finance/payment_reminder_worker.ex`
- Modify: `config/config.exs`
- Create: `test/garden/finance/payment_reminder_worker_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/garden/finance/payment_reminder_worker_test.exs`:

```elixir
defmodule GnomeGarden.Finance.PaymentReminderWorkerTest do
  use GnomeGarden.DataCase, async: true

  import Swoosh.TestAssertions

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.PaymentReminderWorker
  alias GnomeGarden.Operations

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Reminder Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, person} =
      Operations.create_person(%{
        first_name: "Bill",
        last_name: "Payer",
        email: "billpayer@client.com"
      })

    Operations.create_organization_affiliation(%{
      organization_id: org.id,
      person_id: person.id
    })

    today = Date.utc_today()

    # Invoice 7 days overdue
    {:ok, inv_7} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-7",
        currency_code: "USD",
        total_amount: Decimal.new("1000"),
        balance_amount: Decimal.new("1000"),
        due_on: Date.add(today, -7)
      })

    {:ok, inv_7} = Finance.issue_invoice(inv_7)

    # Invoice 14 days overdue
    {:ok, inv_14} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-14",
        currency_code: "USD",
        total_amount: Decimal.new("2000"),
        balance_amount: Decimal.new("2000"),
        due_on: Date.add(today, -14)
      })

    {:ok, inv_14} = Finance.issue_invoice(inv_14)

    # Invoice 10 days overdue — no threshold, should NOT send
    {:ok, inv_10} =
      Finance.create_invoice(%{
        organization_id: org.id,
        invoice_number: "INV-10",
        currency_code: "USD",
        total_amount: Decimal.new("500"),
        balance_amount: Decimal.new("500"),
        due_on: Date.add(today, -10)
      })

    {:ok, inv_10} = Finance.issue_invoice(inv_10)

    %{org: org, inv_7: inv_7, inv_14: inv_14, inv_10: inv_10}
  end

  test "sends reminder for invoice exactly 7 days overdue", %{inv_7: inv_7} do
    PaymentReminderWorker.perform(%Oban.Job{args: %{}})
    assert_email_sent(subject: ~r/Invoice INV-7/)
  end

  test "sends reminder for invoice exactly 14 days overdue" do
    PaymentReminderWorker.perform(%Oban.Job{args: %{}})
    assert_email_sent(subject: ~r/Invoice INV-14/)
  end

  test "does not send reminder for non-threshold day (10 days)" do
    PaymentReminderWorker.perform(%Oban.Job{args: %{}})
    refute_email_sent(subject: ~r/Invoice INV-10/)
  end

  test "skips invoices where billing_contact has do_not_email true", %{org: org} do
    {:ok, dne_person} =
      Operations.create_person(%{
        first_name: "No",
        last_name: "Email",
        email: "noemail@client.com",
        do_not_email: true
      })

    {:ok, dne_org} =
      Operations.create_organization(%{
        name: "DNE Org",
        organization_kind: :business
      })

    Operations.update_organization(dne_org, %{billing_contact_id: dne_person.id})

    today = Date.utc_today()

    {:ok, inv} =
      Finance.create_invoice(%{
        organization_id: dne_org.id,
        invoice_number: "INV-DNE-7",
        currency_code: "USD",
        total_amount: Decimal.new("1000"),
        balance_amount: Decimal.new("1000"),
        due_on: Date.add(today, -7)
      })

    {:ok, _} = Finance.issue_invoice(inv)

    PaymentReminderWorker.perform(%Oban.Job{args: %{}})
    refute_email_sent(subject: ~r/INV-DNE-7/)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/payment_reminder_worker_test.exs --trace
```

Expected: FAIL — `PaymentReminderWorker` doesn't exist.

- [ ] **Step 3: Create the worker**

Create `lib/garden/finance/payment_reminder_worker.ex`:

```elixir
defmodule GnomeGarden.Finance.PaymentReminderWorker do
  @moduledoc """
  Oban cron worker that sends payment reminder emails for overdue invoices.

  Runs daily at 8am UTC. For each issued or partial invoice past its due_on:
  - Day 7 overdue  → reminder to billing contact
  - Day 14 overdue → follow-up to billing contact
  - Day 30 overdue → urgent notice to billing contact + CC to agreement owner

  Only fires on exact day matches to avoid duplicate sends.
  Skips invoices where the recipient has do_not_email: true.
  """

  use Oban.Worker, queue: :finance, max_attempts: 3

  require Logger
  require Ash.Query

  alias GnomeGarden.Finance.Invoice
  alias GnomeGarden.Mailer
  alias GnomeGarden.Mailer.PaymentReminderEmail

  @thresholds [7, 14, 30]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    Invoice
    |> Ash.Query.filter(status in [:issued, :partial] and not is_nil(due_on) and due_on < ^today)
    |> Ash.Query.load([
      :agreement,
      organization: [:billing_contact],
      agreement: [:owner_user]
    ])
    |> Ash.read!(domain: GnomeGarden.Finance)
    |> Enum.each(&maybe_send_reminder(&1, today))

    :ok
  end

  defp maybe_send_reminder(invoice, today) do
    days_overdue = Date.diff(today, invoice.due_on)

    if days_overdue in @thresholds do
      threshold = threshold_atom(days_overdue)
      send_reminder(invoice, threshold, days_overdue)
    end
  end

  defp threshold_atom(7), do: :day_7
  defp threshold_atom(14), do: :day_14
  defp threshold_atom(30), do: :day_30

  defp send_reminder(invoice, threshold, days_overdue) do
    org = invoice.organization

    # Check if billing_contact (or fallback) has do_not_email
    recipient = GnomeGarden.Mailer.InvoiceEmail.find_billing_email(org)

    if is_nil(recipient) do
      Logger.warning("PaymentReminderWorker: no valid recipient for invoice #{invoice.invoice_number}, skipping")
    else
      opts = build_opts(invoice, threshold)

      invoice
      |> PaymentReminderEmail.build(threshold, opts)
      |> Mailer.deliver()
      |> case do
        {:ok, _} ->
          Logger.info("PaymentReminderWorker: sent #{threshold} reminder for #{invoice.invoice_number}")

        {:error, reason} ->
          Logger.warning("PaymentReminderWorker: failed to send reminder",
            invoice_number: invoice.invoice_number,
            reason: inspect(reason)
          )
      end
    end
  end

  defp build_opts(invoice, :day_30) do
    owner_email =
      invoice.agreement &&
        invoice.agreement.owner_user &&
        invoice.agreement.owner_user.email

    if owner_email, do: [cc: to_string(owner_email)], else: []
  end

  defp build_opts(_invoice, _threshold), do: []
end
```

- [ ] **Step 4: Add finance queue and cron to config**

In `config/config.exs`, find the Oban config block and add the `finance` queue:

```elixir
# Find the existing queues list, add :finance
queues: [
  # ... existing queues ...
  finance: 5
]
```

And add the cron entry:

```elixir
# Find the existing cron list, add PaymentReminderWorker
cron: [
  # ... existing entries ...
  {"0 8 * * *", GnomeGarden.Finance.PaymentReminderWorker}
]
```

- [ ] **Step 5: Run tests**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test test/garden/finance/payment_reminder_worker_test.exs --trace
```

Expected: all tests PASS.

- [ ] **Step 6: Run full test suite**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test --trace 2>&1 | tail -30
```

Expected: 0 new failures vs baseline.

- [ ] **Step 7: Commit**

```bash
git add lib/garden/finance/payment_reminder_worker.ex \
        config/config.exs \
        test/garden/finance/payment_reminder_worker_test.exs
git commit -m "feat: PaymentReminderWorker — automated overdue invoice reminders at day 7/14/30"
```

---

## Final Verification

- [ ] **Run full test suite one last time**

```bash
GNOME_GARDEN_DB_PORT=5432 mix test 2>&1 | tail -10
```

- [ ] **Push branch**

```bash
git push
```
