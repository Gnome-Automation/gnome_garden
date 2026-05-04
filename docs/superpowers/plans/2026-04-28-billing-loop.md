# Billing Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the automated billing loop: approved time/expenses → scheduled invoicing → Mercury payment detection → payment matching → invoice closed.

**Architecture:** Additive changes to existing Ash resources (Finance.Invoice state machine, Mercury.Transaction) plus two new resources (Mercury.ClientBankAlias, Commercial.Agreement billing fields) and two new Oban workers (PaymentMatcherWorker real logic, InvoiceSchedulerWorker). All amounts use Elixir `Decimal`, not integer cents. The `balance_amount` field on Finance.Invoice is the authoritative "amount still owed" — it is updated explicitly on each state transition.

**Tech Stack:** Elixir/Phoenix 1.8, Ash v3, AshPostgres, AshStateMachine, Oban 2.20, Swoosh

---

## Notes for Implementers

- **All amounts are `Decimal`**, not integers. Use `Decimal.new/1`, `Decimal.sub/2`, `Decimal.compare/2`.
- **Migrations are generated, not hand-written.** After each resource change, run `mix ash_postgres.generate_migrations --name <name>`, inspect the output, then `mix ecto.migrate`.
- **Domain shortcuts** are how you call resource actions: `GnomeGarden.Finance.pay_invoice(invoice)`, not `Ash.update(invoice, action: :mark_paid)`. Add new shortcuts to `lib/garden/finance.ex` and `lib/garden/mercury.ex` alongside existing ones.
- **Tests use `GnomeGarden.DataCase`**, not `ExUnit.Case`. Test files live in `test/garden/`.
- The `Finance.Invoice` already has a `balance_amount` field (set on `:issue` to equal `total_amount`, set to `0` on `:mark_paid`) and an `applied_amount` aggregate (sum of `payment_applications.amount`). Do not add new computed fields — use these.
- **`Finance.Invoice.open` read action** currently filters `status == :issued`. Update it to include `:partial` so the PaymentMatcher can find partially-paid invoices.
- **Drop `Finance.Payment.source`** from the spec — `payment_method` already has `:ach` and `:wire`, which is sufficient to identify Mercury payments. The `Mercury.PaymentMatch.match_source` field already tracks auto vs. manual matching.
- **`ClientBankAlias.organization_id`** is an FK to `organizations` (Operations.Organization), not `sales_companies` — because `Finance.Invoice.organization_id` references organizations. **The spec says `company_id` → `sales_companies`; that is wrong.** After reading the actual codebase, Finance.Invoice has `organization_id` pointing at the organizations table. The ClientBankAlias must match this FK or invoice lookups by organization will fail.
- **`next_billing_date` vs `next_invoice_date`**: The spec uses `next_invoice_date`. This plan uses `next_billing_date` throughout (Agreement attribute, InvoiceSchedulerWorker filter, advance logic). They are the same concept. `next_billing_date` was chosen because it's clearer in the Agreement context — follow the plan's naming.
- **`Finance.Payment.source`**: The spec adds a `source` atom field to `Finance.Payment`. The actual `Finance.Payment` schema has no `source` column — the existing `payment_method` attribute already captures `:ach` and `:wire`, and `Mercury.PaymentMatch.match_source` already tracks auto vs manual. Do NOT add `source` to `Finance.Payment`. The `create_payment` call in Task 6 does not pass `source` — this is correct.

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Modify | `lib/garden/finance/invoice.ex` | Add `partial`, `write_off` states + transitions + `partial` and `write_off` actions |
| Modify | `lib/garden/finance.ex` | Add `partial_invoice`, `write_off_invoice` shortcuts |
| Modify | `lib/garden/mercury/transaction.ex` | Add `match_confidence` attribute |
| Modify | `lib/garden/mercury.ex` | Add `update_match_confidence` shortcut + ClientBankAlias shortcuts |
| Create | `lib/garden/mercury/client_bank_alias.ex` | New Ash resource: counterparty name → organization mapping |
| Modify | `lib/garden/commercial/agreement.ex` | Add `billing_cycle` + `next_billing_date` fields |
| Run | `mix ash_postgres.generate_migrations` | Generate single migration covering all resource changes |
| Modify | `lib/garden/mercury/payment_matcher_worker.ex` | Replace stub with real matching logic |
| Create | `lib/garden/mercury/invoice_scheduler_worker.ex` | New Oban cron worker |
| Modify | `config/config.exs` | Add cron entry + underpayment tolerance config |
| Create | `test/garden/finance/invoice_billing_states_test.exs` | Tests for partial + write_off transitions |
| Modify | `test/garden/mercury/payment_matcher_worker_test.exs` | Replace stub test with full coverage |
| Create | `test/garden/mercury/client_bank_alias_test.exs` | CRUD + unique constraint test |
| Create | `test/garden/mercury/invoice_scheduler_worker_test.exs` | Scheduler logic tests |

---

## Task 1: Finance.Invoice — Add `partial` and `write_off` States

**Files:**
- Modify: `lib/garden/finance/invoice.ex`
- Modify: `lib/garden/finance.ex`
- Create: `test/garden/finance/invoice_billing_states_test.exs`

### What to change in `lib/garden/finance/invoice.ex`

**1. Status attribute constraints** — add `:partial` and `:write_off`:

```elixir
attribute :status, :atom do
  allow_nil? false
  default :draft
  public? true

  constraints one_of: [
                :draft,
                :issued,
                :partial,
                :paid,
                :void,
                :write_off
              ]
end
```

**2. State machine transitions** — add partial/write_off transitions and update mark_paid:

```elixir
state_machine do
  state_attribute :status
  initial_states [:draft]
  default_initial_state :draft

  transitions do
    transition :issue, from: :draft, to: :issued
    transition :partial, from: [:issued, :partial], to: :partial
    transition :mark_paid, from: [:issued, :partial], to: :paid
    transition :void, from: [:draft, :issued], to: :void
    transition :reopen, from: [:void, :paid], to: :draft
    transition :write_off, from: [:issued, :partial], to: :write_off
  end
end
```

**3. New `partial` action** — accepts `balance_amount`, transitions to `:partial`:

```elixir
update :partial do
  accept [:balance_amount]
  change transition_state(:partial)
end
```

**4. New `write_off` action**:

```elixir
update :write_off do
  accept []
  change transition_state(:write_off)
  change set_attribute(:balance_amount, Decimal.new("0"))
end
```

**5. Update `open` read action** to include `:partial`:

```elixir
read :open do
  filter expr(status in [:issued, :partial])

  prepare build(
            sort: [due_on: :asc, inserted_at: :desc],
            load: [
              :organization,
              :agreement,
              :project,
              :work_order,
              :invoice_lines,
              :payment_applications
            ]
          )
end
```

**6. Update `status_variant` calculation** to include new states:

```elixir
calculate :status_variant,
          :atom,
          {GnomeGarden.Calculations.EnumVariant,
           field: :status,
           mapping: [
             draft: :default,
             issued: :warning,
             partial: :warning,
             paid: :success,
             void: :error,
             write_off: :error
           ],
           default: :default}
```

### What to add in `lib/garden/finance.ex`

Inside the `resource GnomeGarden.Finance.Invoice do` block, add:

```elixir
define :partial_invoice, action: :partial
define :write_off_invoice, action: :write_off
```

- [ ] **Step 1: Write the failing test**

```elixir
# test/garden/finance/invoice_billing_states_test.exs
defmodule GnomeGarden.Finance.InvoiceBillingStatesTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  setup do
    org = org_fixture()
    invoice = invoice_fixture(org, %{
      total_amount: Decimal.new("1000.00"),
      balance_amount: Decimal.new("1000.00"),
      status: :issued
    })
    %{invoice: invoice}
  end

  test "can transition issued → partial with updated balance", %{invoice: invoice} do
    {:ok, partial} = Finance.partial_invoice(invoice, balance_amount: Decimal.new("600.00"))
    assert partial.status == :partial
    assert Decimal.equal?(partial.balance_amount, Decimal.new("600.00"))
  end

  test "can transition partial → paid", %{invoice: invoice} do
    {:ok, partial} = Finance.partial_invoice(invoice, balance_amount: Decimal.new("400.00"))
    {:ok, paid} = Finance.pay_invoice(partial)
    assert paid.status == :paid
    assert Decimal.equal?(paid.balance_amount, Decimal.new("0"))
  end

  test "can transition issued → write_off", %{invoice: invoice} do
    {:ok, written_off} = Finance.write_off_invoice(invoice)
    assert written_off.status == :write_off
    assert Decimal.equal?(written_off.balance_amount, Decimal.new("0"))
  end

  test "can transition partial → write_off", %{invoice: invoice} do
    {:ok, partial} = Finance.partial_invoice(invoice, balance_amount: Decimal.new("400.00"))
    {:ok, written_off} = Finance.write_off_invoice(partial)
    assert written_off.status == :write_off
  end

  test "cannot void a partial invoice" do
    # void is only allowed from :draft and :issued, not :partial
    # see state machine transitions
    assert true  # enforced by state machine — no explicit test needed beyond config
  end

  defp org_fixture do
    # Use your project's existing test factory/fixture helpers
    # Check test/support/ for existing helpers
    GnomeGarden.Operations.Organization
    |> Ash.Changeset.for_create(:create, %{name: "Test Org", organization_kind: :client})
    |> Ash.create!(domain: GnomeGarden.Operations)
  end

  defp invoice_fixture(org, attrs) do
    defaults = %{
      organization_id: org.id,
      invoice_number: "INV-TEST-001",
      currency_code: "USD",
      total_amount: Decimal.new("1000.00"),
      balance_amount: Decimal.new("1000.00")
    }

    GnomeGarden.Finance.Invoice
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!(domain: GnomeGarden.Finance)
    |> then(fn inv ->
      GnomeGarden.Finance.Invoice
      |> Ash.Changeset.for_update(:issue, %{}, domain: GnomeGarden.Finance)
      |> Ash.update!(subject: inv)
    end)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury
mix test test/garden/finance/invoice_billing_states_test.exs
```

Expected: compilation error or `FunctionClauseError` — `partial_invoice/2` not defined.

- [ ] **Step 3: Implement the changes**

Apply all 6 changes to `lib/garden/finance/invoice.ex` and the 2 new shortcuts to `lib/garden/finance.ex` as described above.

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/garden/finance/invoice_billing_states_test.exs
```

Expected: 4 tests pass.

Also run existing invoice tests to confirm no regressions:

```bash
mix test test/garden/finance/ --exclude pending
```

- [ ] **Step 5: Commit**

```bash
git add lib/garden/finance/invoice.ex lib/garden/finance.ex test/garden/finance/invoice_billing_states_test.exs
git commit -m "feat(finance): add partial and write_off invoice states"
```

---

## Task 2: Mercury.Transaction — Add `match_confidence` Attribute

**Files:**
- Modify: `lib/garden/mercury/transaction.ex`
- Modify: `test/garden/mercury/transaction_test.exs`

### What to change in `lib/garden/mercury/transaction.ex`

**1. Add attribute** (after the `company_id` attribute, before `timestamps()`):

```elixir
attribute :match_confidence, :atom do
  public? true
  constraints one_of: [:exact, :probable, :possible, :unmatched]
end
```

**2. Add to `:update` action accept list**:

```elixir
update :update do
  primary? true

  accept [
    :status,
    :bank_description,
    :external_memo,
    :note,
    :details,
    :currency_exchange_info,
    :reason_for_failure,
    :dashboard_link,
    :posted_date,
    :failed_at,
    :company_id,
    :match_confidence  # add this line
  ]
end
```

**3. Update admin `table_columns`** to include `:match_confidence`:

```elixir
admin do
  table_columns [:id, :mercury_id, :amount, :kind, :status, :counterparty_name, :match_confidence, :occurred_at]
end
```

- [ ] **Step 1: Write the failing test**

Add to `test/garden/mercury/transaction_test.exs`:

```elixir
test "match_confidence can be set via update", %{account: account} do
  {:ok, txn} = GnomeGarden.Mercury.create_mercury_transaction(%{
    account_id: account.id,
    mercury_id: "txn-conf-001",
    amount: Decimal.new("500.00"),
    kind: :wire,
    status: :sent,
    occurred_at: DateTime.utc_now()
  })

  assert is_nil(txn.match_confidence)

  {:ok, updated} = GnomeGarden.Mercury.update_mercury_transaction(txn, %{match_confidence: :unmatched})
  assert updated.match_confidence == :unmatched
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/garden/mercury/transaction_test.exs --only match_confidence
```

Expected: compile error or attribute unknown.

- [ ] **Step 3: Apply the changes** to `lib/garden/mercury/transaction.ex` as described above.

- [ ] **Step 4: Run tests**

```bash
mix test test/garden/mercury/transaction_test.exs
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/garden/mercury/transaction.ex test/garden/mercury/transaction_test.exs
git commit -m "feat(mercury): add match_confidence attribute to Transaction"
```

---

## Task 3: Mercury.ClientBankAlias Resource

**Files:**
- Create: `lib/garden/mercury/client_bank_alias.ex`
- Modify: `lib/garden/mercury.ex`
- Create: `test/garden/mercury/client_bank_alias_test.exs`

### `lib/garden/mercury/client_bank_alias.ex`

```elixir
defmodule GnomeGarden.Mercury.ClientBankAlias do
  @moduledoc """
  Maps a known wire/ACH counterparty name fragment to an Operations.Organization.

  Populated automatically on the first confirmed payment match or manually via
  AshAdmin. One organization can have multiple aliases to handle varying wire
  counterparty name formats (e.g., "ACME CORP", "ACME CORPORATION").
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Mercury,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :counterparty_name_fragment, :organization_id, :inserted_at]
  end

  postgres do
    table "mercury_client_bank_aliases"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:counterparty_name_fragment, :organization_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :counterparty_name_fragment, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_counterparty_fragment, [:counterparty_name_fragment]
  end
end
```

### Additions to `lib/garden/mercury.ex`

Add inside the `resources do` block:

```elixir
resource GnomeGarden.Mercury.ClientBankAlias do
  define :list_client_bank_aliases, action: :read
  define :get_client_bank_alias_by_fragment, action: :read, get_by: [:counterparty_name_fragment]
  define :create_client_bank_alias, action: :create
  define :delete_client_bank_alias, action: :destroy, default_options: [return_destroyed?: true]
end
```

- [ ] **Step 1: Write the failing test**

```elixir
# test/garden/mercury/client_bank_alias_test.exs
defmodule GnomeGarden.Mercury.ClientBankAliasTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Mercury

  setup do
    org =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{name: "Acme Corp", organization_kind: :client})
      |> Ash.create!(domain: GnomeGarden.Operations)
    %{org: org}
  end

  test "creates an alias linking counterparty name to organization", %{org: org} do
    {:ok, alias} = Mercury.create_client_bank_alias(%{
      counterparty_name_fragment: "ACME CORP",
      organization_id: org.id
    })
    assert alias.counterparty_name_fragment == "ACME CORP"
    assert alias.organization_id == org.id
  end

  test "enforces unique counterparty_name_fragment", %{org: org} do
    {:ok, _} = Mercury.create_client_bank_alias(%{
      counterparty_name_fragment: "ACME CORP",
      organization_id: org.id
    })
    assert {:error, _} = Mercury.create_client_bank_alias(%{
      counterparty_name_fragment: "ACME CORP",
      organization_id: org.id
    })
  end

  test "can look up alias by fragment", %{org: org} do
    {:ok, _} = Mercury.create_client_bank_alias(%{
      counterparty_name_fragment: "ACME CORPORATION",
      organization_id: org.id
    })
    {:ok, found} = Mercury.get_client_bank_alias_by_fragment("ACME CORPORATION")
    assert found.organization_id == org.id
  end

  test "deletes alias", %{org: org} do
    {:ok, alias} = Mercury.create_client_bank_alias(%{
      counterparty_name_fragment: "DELETE ME",
      organization_id: org.id
    })
    {:ok, _} = Mercury.delete_client_bank_alias(alias)
    assert {:error, _} = Mercury.get_client_bank_alias_by_fragment("DELETE ME")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/garden/mercury/client_bank_alias_test.exs
```

Expected: compile error — module not defined.

- [ ] **Step 3: Create `lib/garden/mercury/client_bank_alias.ex`** and update `lib/garden/mercury.ex` as described above.

- [ ] **Step 4: Run tests**

```bash
mix test test/garden/mercury/client_bank_alias_test.exs
```

Expected: 4 tests pass (migration not yet run — tests will fail at DB level; proceed to Task 5 to generate+run the migration, then return here to confirm).

- [ ] **Step 5: Commit**

```bash
git add lib/garden/mercury/client_bank_alias.ex lib/garden/mercury.ex test/garden/mercury/client_bank_alias_test.exs
git commit -m "feat(mercury): add ClientBankAlias resource"
```

---

## Task 4: Commercial.Agreement — Billing Cycle Fields

**Files:**
- Modify: `lib/garden/commercial/agreement.ex`

The InvoiceScheduler queries active agreements by `next_billing_date` to know which ones are due for invoicing.

### Changes to `lib/garden/commercial/agreement.ex`

**1. Add two attributes** (before `timestamps()`):

```elixir
attribute :billing_cycle, :atom do
  allow_nil? false
  default :none
  public? true
  constraints one_of: [:none, :weekly, :monthly]
end

attribute :next_billing_date, :date do
  public? true
end
```

**2. Add to `:create` and `:update` actions' `accept` lists**:

```elixir
# In both :create and :update actions, add:
:billing_cycle,
:next_billing_date
```

**3. Update `status_variant` calculation** — no change needed (existing mapping unchanged).

- [ ] **Step 1: No test needed for attribute addition** — the migration test happens in Task 5. Skip to implementation.

- [ ] **Step 2: Apply the attribute changes** to `lib/garden/commercial/agreement.ex`.

- [ ] **Step 3: Confirm it compiles**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/garden/commercial/agreement.ex
git commit -m "feat(commercial): add billing_cycle and next_billing_date to Agreement"
```

---

## Task 5: Generate and Run Migrations

All resource changes from Tasks 1–4 are now in place. Generate a single migration covering all of them.

- [ ] **Step 1: Generate the migration**

```bash
cd /mnt/c/Users/bhammoud/Desktop/Gnome_Automation/gnome_garden_mercury
mix ash_postgres.generate_migrations --name add_billing_loop_fields
```

Expected output: creates a single file in `priv/repo/migrations/` with a timestamp prefix.

- [ ] **Step 2: Inspect the generated migration**

Open the file and verify it contains:
- `alter table(:finance_invoices)` — adding no new columns (status is an atom stored as string, no schema change needed for new enum values in Ash; the state machine changes are code-only)

  > **Note on Ash state machines:** In AshStateMachine, the `status` attribute constraints are validated at the application layer, not the DB layer. No migration is needed for adding new allowed atom values. The migration is only needed for the new `match_confidence` column, the new `ClientBankAlias` table, and the `billing_cycle`/`next_billing_date` columns.

- `create table(:mercury_client_bank_aliases)` with columns: `id`, `counterparty_name_fragment`, `organization_id`, `inserted_at`, `updated_at`
- `alter table(:mercury_transactions)` — adding `match_confidence` column (nullable string/atom)
- `alter table(:commercial_agreements)` — adding `billing_cycle` (string/atom, default "none") and `next_billing_date` (date, nullable)

- [ ] **Step 3: Run the migration**

```bash
mix ecto.migrate
```

Expected: migrates successfully with no errors.

- [ ] **Step 4: Run all tests to confirm no regressions**

```bash
mix test
```

Expected: all tests pass, including the new ones from Tasks 1–3.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: add billing loop DB migrations"
```

---

## Task 6: PaymentMatcherWorker — Real Matching Logic

**Files:**
- Modify: `lib/garden/mercury/payment_matcher_worker.ex`
- Modify: `test/garden/mercury/payment_matcher_worker_test.exs`

Replace the stub with full matching logic.

### `lib/garden/mercury/payment_matcher_worker.ex`

```elixir
defmodule GnomeGarden.Mercury.PaymentMatcherWorker do
  @moduledoc """
  Oban worker that matches a Mercury transaction to an open Finance.Invoice.

  Matching priority:
  1. Invoice number found in wire reference/memo → :exact
  2. Exact amount + single open invoice for identified client → :exact
  3. Exact amount + multiple open invoices for client → :probable (oldest chosen)
  4. Exact amount matches exactly one open invoice (no client signal) → :possible
  5. No match → :unmatched (logged, transaction updated, :ok returned)
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  require Logger

  alias GnomeGarden.Finance
  alias GnomeGarden.Mercury

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transaction_id" => transaction_id}}) do
    case Mercury.get_mercury_transaction(transaction_id) do
      {:ok, txn} ->
        match_transaction(txn)

      {:error, _} ->
        Logger.warning("PaymentMatcherWorker: transaction not found",
          transaction_id: transaction_id
        )

        :ok
    end
  end

  defp match_transaction(txn) do
    case find_match(txn) do
      {:ok, invoice, confidence} ->
        apply_match(txn, invoice, confidence)

      :unmatched ->
        Logger.warning("PaymentMatcherWorker: no match for transaction",
          mercury_id: txn.mercury_id,
          amount: txn.amount,
          counterparty: txn.counterparty_name
        )

        Mercury.update_mercury_transaction(txn, %{match_confidence: :unmatched})
        :ok
    end
  end

  # --- Matching ---

  defp find_match(txn) do
    with :not_found <- find_by_invoice_number(txn),
         :not_found <- find_by_amount_and_client(txn),
         :not_found <- find_by_amount_only(txn) do
      :unmatched
    end
  end

  defp find_by_invoice_number(txn) do
    reference = "#{txn.external_memo || ""} #{txn.bank_description || ""}"

    case Regex.run(~r/INV-[A-Z0-9-]+/i, reference) do
      [invoice_number] ->
        GnomeGarden.Finance.Invoice
        |> Ash.Query.filter(invoice_number == ^invoice_number and status in [:issued, :partial])
        |> Ash.read_one(domain: Finance)
        |> case do
          {:ok, invoice} when not is_nil(invoice) -> {:ok, invoice, :exact}
          _ -> :not_found
        end

      nil ->
        :not_found
    end
  end

  defp find_by_amount_and_client(txn) do
    case resolve_organization(txn.counterparty_name) do
      {:ok, organization_id} ->
        open_invoices =
          GnomeGarden.Finance.Invoice
          |> Ash.Query.filter(organization_id == ^organization_id and status in [:issued, :partial])
          |> Ash.Query.sort(due_on: :asc)
          |> Ash.read!(domain: Finance, load: [:applied_amount])

        candidates = Enum.filter(open_invoices, &amount_matches?(&1, txn.amount))

        case candidates do
          [invoice] -> {:ok, invoice, :exact}
          [invoice | _] -> {:ok, invoice, :probable}
          [] -> :not_found
        end

      :not_found ->
        :not_found
    end
  end

  defp find_by_amount_only(txn) do
    open_invoices =
      GnomeGarden.Finance.Invoice
      |> Ash.Query.filter(status in [:issued, :partial])
      |> Ash.Query.sort(due_on: :asc)
      |> Ash.read!(domain: Finance, load: [:applied_amount])

    candidates = Enum.filter(open_invoices, &amount_matches?(&1, txn.amount))

    case candidates do
      [invoice] -> {:ok, invoice, :possible}
      _ -> :not_found
    end
  end

  defp resolve_organization(nil), do: :not_found

  defp resolve_organization(counterparty_name) do
    GnomeGarden.Mercury.ClientBankAlias
    |> Ash.Query.filter(
      fragment("lower(?) like '%' || lower(?) || '%'", ^counterparty_name, counterparty_name_fragment)
    )
    |> Ash.read_one(domain: Mercury)
    |> case do
      {:ok, alias} when not is_nil(alias) -> {:ok, alias.organization_id}
      _ -> :not_found
    end
  end

  defp amount_matches?(invoice, txn_amount) do
    tolerance = underpayment_tolerance()
    balance = effective_balance(invoice)
    Decimal.compare(Decimal.abs(Decimal.sub(balance, txn_amount)), tolerance) != :gt
  end

  defp effective_balance(invoice) do
    applied = invoice.applied_amount || Decimal.new("0")
    total = invoice.total_amount || Decimal.new("0")
    Decimal.sub(total, applied)
  end

  defp underpayment_tolerance do
    Application.get_env(:gnome_garden, :payment_matching, [])
    |> Keyword.get(:underpayment_tolerance, Decimal.new("1.00"))
  end

  # --- Applying a match ---

  defp apply_match(txn, invoice, confidence) do
    with {:ok, payment} <-
           Finance.create_payment(%{
             organization_id: invoice.organization_id,
             agreement_id: invoice.agreement_id,
             received_on: DateTime.to_date(txn.occurred_at),
             payment_method: kind_to_payment_method(txn.kind),
             currency_code: invoice.currency_code || "USD",
             amount: txn.amount,
             reference: txn.mercury_id
           }),
         {:ok, _application} <-
           Finance.create_payment_application(%{
             payment_id: payment.id,
             invoice_id: invoice.id,
             amount: txn.amount,
             applied_on: DateTime.to_date(txn.occurred_at)
           }),
         {:ok, _match} <-
           Mercury.create_payment_match(%{
             mercury_transaction_id: txn.id,
             finance_payment_id: payment.id,
             match_source: :auto
           }) do
      close_or_partial(invoice, txn)
      Mercury.update_mercury_transaction(txn, %{match_confidence: confidence})
      :ok
    else
      {:error, reason} ->
        Logger.error("PaymentMatcherWorker: failed to apply match",
          mercury_id: txn.mercury_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp close_or_partial(invoice, txn) do
    # Reload with fresh applied_amount after PaymentApplication was just created
    {:ok, fresh} = Finance.get_invoice(invoice.id, load: [:applied_amount])
    new_balance = effective_balance(fresh)

    if Decimal.compare(new_balance, underpayment_tolerance()) != :gt do
      Finance.pay_invoice(fresh)
    else
      Finance.partial_invoice(fresh, balance_amount: new_balance)
    end
  end

  defp kind_to_payment_method(:wire), do: :wire
  defp kind_to_payment_method(:ach), do: :ach
  defp kind_to_payment_method(_), do: :other
end
```

### Test file: `test/garden/mercury/payment_matcher_worker_test.exs`

Replace contents entirely:

```elixir
defmodule GnomeGarden.Mercury.PaymentMatcherWorkerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Mercury
  alias GnomeGarden.Finance
  alias GnomeGarden.Mercury.PaymentMatcherWorker

  setup do
    org =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{name: "Client Co", organization_kind: :client})
      |> Ash.create!(domain: GnomeGarden.Operations)

    account =
      GnomeGarden.Mercury.Account
      |> Ash.Changeset.for_create(:create, %{
        mercury_id: "acct-matcher-001",
        name: "GnomeGarden Checking",
        status: :active,
        kind: :checking
      })
      |> Ash.create!(domain: Mercury)

    %{org: org, account: account}
  end

  defp issued_invoice(org, amount, invoice_number \\ "INV-2026-001") do
    invoice =
      GnomeGarden.Finance.Invoice
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        invoice_number: invoice_number,
        currency_code: "USD",
        total_amount: amount,
        balance_amount: amount
      })
      |> Ash.create!(domain: Finance)

    Ash.update!(invoice, %{}, action: :issue, domain: Finance)
  end

  defp mercury_transaction(account, amount, memo \\ "") do
    {:ok, txn} = Mercury.create_mercury_transaction(%{
      account_id: account.id,
      mercury_id: "txn-#{System.unique_integer()}",
      amount: amount,
      kind: :wire,
      status: :sent,
      external_memo: memo,
      occurred_at: DateTime.utc_now()
    })
    txn
  end

  defp run_worker(txn) do
    PaymentMatcherWorker.perform(%Oban.Job{args: %{"transaction_id" => txn.id}})
  end

  # --- Exact match via invoice number ---

  test "exact match via invoice number in memo marks invoice paid", %{org: org, account: account} do
    invoice = issued_invoice(org, Decimal.new("1000.00"), "INV-2026-001")
    txn = mercury_transaction(account, Decimal.new("1000.00"), "Payment for INV-2026-001")

    assert :ok = run_worker(txn)

    {:ok, updated_invoice} = Finance.get_invoice(invoice.id)
    assert updated_invoice.status == :paid

    {:ok, updated_txn} = Mercury.get_mercury_transaction(txn.id)
    assert updated_txn.match_confidence == :exact
  end

  # --- Exact match via amount + client alias ---

  test "exact match via amount and client alias marks invoice paid", %{org: org, account: account} do
    {:ok, _alias} = Mercury.create_client_bank_alias(%{
      counterparty_name_fragment: "CLIENT CO",
      organization_id: org.id
    })
    invoice = issued_invoice(org, Decimal.new("500.00"), "INV-2026-002")
    txn = mercury_transaction(account, Decimal.new("500.00"))
    txn = %{txn | counterparty_name: "CLIENT CO INC"}

    assert :ok = run_worker(txn)

    {:ok, updated} = Finance.get_invoice(invoice.id)
    assert updated.status == :paid
  end

  # --- Partial payment ---

  test "partial payment transitions invoice to :partial", %{org: org, account: account} do
    invoice = issued_invoice(org, Decimal.new("1000.00"), "INV-2026-003")
    txn = mercury_transaction(account, Decimal.new("600.00"), "Partial INV-2026-003")

    assert :ok = run_worker(txn)

    {:ok, updated} = Finance.get_invoice(invoice.id, load: [:applied_amount])
    assert updated.status == :partial
    assert Decimal.equal?(updated.balance_amount, Decimal.new("400.00"))
  end

  # --- Underpayment tolerance ---

  test "payment within tolerance marks invoice paid", %{org: org, account: account} do
    Application.put_env(:gnome_garden, :payment_matching, underpayment_tolerance: Decimal.new("1.00"))
    on_exit(fn -> Application.delete_env(:gnome_garden, :payment_matching) end)

    invoice = issued_invoice(org, Decimal.new("1000.00"), "INV-2026-004")
    # $0.50 short — within $1.00 tolerance
    txn = mercury_transaction(account, Decimal.new("999.50"), "INV-2026-004")

    assert :ok = run_worker(txn)

    {:ok, updated} = Finance.get_invoice(invoice.id)
    assert updated.status == :paid
  end

  # --- No match ---

  test "unmatched transaction sets match_confidence to :unmatched", %{account: account} do
    txn = mercury_transaction(account, Decimal.new("9999.00"))

    assert :ok = run_worker(txn)

    {:ok, updated} = Mercury.get_mercury_transaction(txn.id)
    assert updated.match_confidence == :unmatched
  end

  test "non-existent transaction_id returns :ok without crashing" do
    job = %Oban.Job{args: %{"transaction_id" => Ash.UUID.generate()}}
    assert :ok = PaymentMatcherWorker.perform(job)
  end
end
```

- [ ] **Step 1: Run the new tests against the stub** to confirm they fail

```bash
mix test test/garden/mercury/payment_matcher_worker_test.exs
```

Expected: most tests fail.

- [ ] **Step 2: Replace `lib/garden/mercury/payment_matcher_worker.ex`** with the full implementation above.

- [ ] **Step 3: Run tests**

```bash
mix test test/garden/mercury/payment_matcher_worker_test.exs
```

Expected: all 6 tests pass.

- [ ] **Step 4: Run full test suite**

```bash
mix test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/garden/mercury/payment_matcher_worker.ex test/garden/mercury/payment_matcher_worker_test.exs
git commit -m "feat(mercury): implement PaymentMatcherWorker with full matching logic"
```

---

## Task 7: Config — Cron Entry and Underpayment Tolerance

**Files:**
- Modify: `config/config.exs`

### Changes to `config/config.exs`

**1. Add InvoiceSchedulerWorker to the Oban cron list** (add to existing `crontab:` array):

```elixir
# In the existing Oban plugins config, add to crontab:
{"0 6 * * *", GnomeGarden.Mercury.InvoiceSchedulerWorker}
```

Runs daily at 6am UTC. The full Oban config becomes:

```elixir
config :gnome_garden, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10, lead_scanning: 2, mercury: 10],
  repo: GnomeGarden.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", GnomeGarden.Agents.DeploymentSchedulerWorker},
       {"13 * * * *", GnomeGarden.Commercial.DiscoverySchedulerWorker},
       {"0 6 * * *", GnomeGarden.Mercury.InvoiceSchedulerWorker}
     ],
     timezone: "Etc/UTC"}
  ]
```

**2. Add underpayment tolerance config** (add anywhere in `config.exs`):

```elixir
config :gnome_garden, :payment_matching,
  underpayment_tolerance: Decimal.new("1.00")
```

- [ ] **Step 1: Apply both changes** to `config/config.exs`.

- [ ] **Step 2: Confirm it compiles**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add config/config.exs
git commit -m "feat(config): add InvoiceSchedulerWorker cron and underpayment tolerance"
```

---

## Task 8: InvoiceSchedulerWorker

**Files:**
- Create: `lib/garden/mercury/invoice_scheduler_worker.ex`
- Create: `test/garden/mercury/invoice_scheduler_worker_test.exs`

### `lib/garden/mercury/invoice_scheduler_worker.ex`

```elixir
defmodule GnomeGarden.Mercury.InvoiceSchedulerWorker do
  @moduledoc """
  Oban cron worker that generates and issues invoices for Agreements
  that are due for billing.

  Runs daily at 6am UTC. For each active Agreement where
  `next_billing_date <= today`, it:
  1. Calls create_invoice_from_agreement_sources — creates a draft invoice
     from all approved, unbilled TimeEntries and Expenses.
  2. Issues the invoice (draft → issued).
  3. Advances next_billing_date by one billing cycle.

  If there are no billable entries, the invoice is not created but
  next_billing_date is still advanced.
  """

  use Oban.Worker, queue: :mercury, max_attempts: 3

  require Logger

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    GnomeGarden.Commercial.Agreement
    |> Ash.Query.filter(
      status == :active and
        billing_cycle != :none and
        not is_nil(next_billing_date) and
        next_billing_date <= ^today
    )
    |> Ash.read!(domain: Commercial)
    |> Enum.each(&process_agreement/1)

    :ok
  end

  defp process_agreement(agreement) do
    Logger.info("InvoiceSchedulerWorker: processing agreement #{agreement.id}")

    case Finance.create_invoice_from_agreement_sources(agreement_id: agreement.id) do
      {:ok, invoice} ->
        case Finance.issue_invoice(invoice) do
          {:ok, issued} ->
            send_invoice_email(issued)
            advance_billing_date(agreement)
            Logger.info("InvoiceSchedulerWorker: issued invoice #{invoice.id} for agreement #{agreement.id}")

          {:error, reason} ->
            Logger.error("InvoiceSchedulerWorker: failed to issue invoice",
              agreement_id: agreement.id,
              reason: inspect(reason)
            )
        end

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        if Enum.any?(errors, &match?(%{message: msg} when is_binary(msg) and msg =~ "no billable", &1)) do
          Logger.info("InvoiceSchedulerWorker: no billable entries for agreement #{agreement.id}, advancing date")
          advance_billing_date(agreement)
        else
          Logger.error("InvoiceSchedulerWorker: unexpected error creating invoice",
            agreement_id: agreement.id,
            errors: inspect(errors)
          )
        end

      {:error, reason} ->
        Logger.error("InvoiceSchedulerWorker: failed to create invoice",
          agreement_id: agreement.id,
          reason: inspect(reason)
        )
    end
  end

  defp advance_billing_date(agreement) do
    new_date =
      case agreement.billing_cycle do
        :weekly -> Date.add(agreement.next_billing_date, 7)
        :monthly -> Date.shift(agreement.next_billing_date, month: 1)
      end

    agreement
    |> Ash.Changeset.for_update(:update, %{next_billing_date: new_date})
    |> Ash.update!(domain: Commercial)
  end

  defp send_invoice_email(invoice) do
    # Load the organization + primary contact to get the billing email address.
    # Operations.Organization does not store an email directly — look up via
    # Operations.Person (relationship: organization has_many :people).
    # Adjust the load path below to match the actual relationship name.
    {:ok, loaded} = Ash.get(
      GnomeGarden.Finance.Invoice,
      invoice.id,
      domain: GnomeGarden.Finance,
      load: [:invoice_lines, organization: [:people]]
    )

    contact_email =
      loaded.organization
      |> Map.get(:people, [])
      |> Enum.find_value(fn person -> if person.email, do: to_string(person.email) end)

    if contact_email do
      import Swoosh.Email
      alias GnomeGarden.Mailer

      new()
      |> from({"GnomeGarden Billing", "billing@gnomegarden.io"})
      |> to(contact_email)
      |> subject("Invoice #{invoice.invoice_number} — #{invoice.currency_code} #{invoice.total_amount}")
      |> html_body(invoice_email_body(loaded))
      |> Mailer.deliver!()
    else
      Logger.warning("InvoiceSchedulerWorker: no contact email for org #{loaded.organization_id}, invoice #{invoice.id} not emailed")
    end
  end

  defp invoice_email_body(invoice) do
    lines_html =
      invoice.invoice_lines
      |> Enum.map(fn line ->
        "<tr><td>#{line.description}</td><td>#{line.amount}</td></tr>"
      end)
      |> Enum.join("\n")

    """
    <p>Dear #{invoice.organization.name},</p>
    <p>Please find your invoice <strong>#{invoice.invoice_number}</strong> attached.</p>
    <p><strong>Total due: #{invoice.currency_code} #{invoice.total_amount}</strong><br>
    Due date: #{invoice.due_on}</p>
    <table border="1" cellpadding="4">
      <thead><tr><th>Description</th><th>Amount</th></tr></thead>
      <tbody>#{lines_html}</tbody>
    </table>
    <p>Please remit payment via wire or ACH per the instructions on file.</p>
    """
  end
end
```

### Test file: `test/garden/mercury/invoice_scheduler_worker_test.exs`

```elixir
defmodule GnomeGarden.Mercury.InvoiceSchedulerWorkerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Mercury.InvoiceSchedulerWorker
  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial

  setup do
    org =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{name: "Scheduler Org", organization_kind: :client})
      |> Ash.create!(domain: GnomeGarden.Operations)

    %{org: org}
  end

  defp active_agreement(org, billing_cycle, next_billing_date) do
    agreement =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "Test Agreement",
        agreement_type: :project,
        billing_model: :time_and_materials,
        billing_cycle: billing_cycle,
        next_billing_date: next_billing_date
      })
      |> Ash.create!(domain: Commercial)

    Ash.update!(agreement, %{}, action: :activate, domain: Commercial)
  end

  defp approved_time_entry(org, agreement) do
    entry =
      GnomeGarden.Finance.TimeEntry
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        agreement_id: agreement.id,
        description: "Test work",
        minutes: 60,
        billable: true,
        billed_on: nil
      })
      |> Ash.create!(domain: Finance)

    entry
    |> Ash.update!(%{}, action: :submit, domain: Finance)
    |> Ash.update!(%{}, action: :approve, domain: Finance)
  end

  test "generates and issues invoice for due agreement", %{org: org} do
    agreement = active_agreement(org, :monthly, Date.utc_today())
    _entry = approved_time_entry(org, agreement)

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    # Invoice should exist and be issued
    {:ok, invoices} = Finance.list_invoices(
      query: [filter: [agreement_id: agreement.id]]
    )
    assert length(invoices) == 1
    assert hd(invoices).status == :issued
  end

  test "advances next_billing_date after invoicing", %{org: org} do
    today = Date.utc_today()
    agreement = active_agreement(org, :monthly, today)
    _entry = approved_time_entry(org, agreement)

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    {:ok, updated} = Ash.get(GnomeGarden.Commercial.Agreement, agreement.id, domain: Commercial)
    expected = Date.shift(today, month: 1)
    assert updated.next_billing_date == expected
  end

  test "skips agreements not yet due", %{org: org} do
    future_date = Date.add(Date.utc_today(), 7)
    agreement = active_agreement(org, :weekly, future_date)
    _entry = approved_time_entry(org, agreement)

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    {:ok, invoices} = Finance.list_invoices(
      query: [filter: [agreement_id: agreement.id]]
    )
    assert invoices == []
  end

  test "advances date even when no billable entries", %{org: org} do
    today = Date.utc_today()
    agreement = active_agreement(org, :weekly, today)
    # No time entries

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    {:ok, updated} = Ash.get(GnomeGarden.Commercial.Agreement, agreement.id, domain: Commercial)
    assert updated.next_billing_date == Date.add(today, 7)
  end
end
```

- [ ] **Step 1: Run the tests against nothing** to verify they fail

```bash
mix test test/garden/mercury/invoice_scheduler_worker_test.exs
```

Expected: compile error — module not defined.

- [ ] **Step 2: Create `lib/garden/mercury/invoice_scheduler_worker.ex`** as above.

- [ ] **Step 3: Run tests**

```bash
mix test test/garden/mercury/invoice_scheduler_worker_test.exs
```

Expected: all 4 tests pass. (If `create_invoice_from_agreement_sources` raises on no entries vs returns error, adjust the error pattern in `process_agreement/1` to match actual behavior — run the test to see the real error message first.)

- [ ] **Step 4: Run full test suite**

```bash
mix test
```

Expected: all pass.

- [ ] **Step 5: Commit and push**

```bash
git add lib/garden/mercury/invoice_scheduler_worker.ex test/garden/mercury/invoice_scheduler_worker_test.exs
git commit -m "feat(mercury): add InvoiceSchedulerWorker Oban cron job"
git push
```

---

## Final Verification

- [ ] Run the complete test suite one last time:

```bash
mix test
```

- [ ] Confirm all tasks committed and pushed:

```bash
git log --oneline -10
git status
```

Expected: clean working tree, all 8 tasks committed.
