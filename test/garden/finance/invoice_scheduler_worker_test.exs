defmodule GnomeGarden.Finance.InvoiceSchedulerWorkerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  require Ash.Query

  alias GnomeGarden.Finance.InvoiceSchedulerWorker
  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial

  setup do
    org =
      GnomeGarden.Operations.Organization
      |> Ash.Changeset.for_create(:create, %{
        name: "Scheduler Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })
      |> Ash.create!(domain: GnomeGarden.Operations)

    email = "worker-#{System.unique_integer([:positive])}@example.com"
    password = "valid-password-#{System.unique_integer([:positive])}"

    {:ok, user} =
      GnomeGarden.Accounts.create_user_with_password(%{
        email: email,
        password: password,
        password_confirmation: password
      })

    team_member =
      Ash.Seed.seed!(GnomeGarden.Operations.TeamMember, %{
        user_id: user.id,
        display_name: "Scheduler Worker #{System.unique_integer([:positive])}",
        role: :admin,
        status: :active
      })

    %{org: org, team_member: team_member}
  end

  defp active_agreement(org, billing_cycle, next_billing_date) do
    agreement =
      GnomeGarden.Commercial.Agreement
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        name: "Test Agreement #{System.unique_integer([:positive])}",
        billing_cycle: billing_cycle,
        next_billing_date: next_billing_date
      })
      |> Ash.create!(domain: Commercial)

    agreement
    |> Ash.Changeset.for_update(:activate, %{})
    |> Ash.update!(domain: Commercial)
  end

  defp approved_time_entry(org, agreement, team_member) do
    # bill_rate is required — validate_time_entry_rates will error if nil
    entry =
      GnomeGarden.Finance.TimeEntry
      |> Ash.Changeset.for_create(:create, %{
        organization_id: org.id,
        agreement_id: agreement.id,
        member_team_member_id: team_member.id,
        work_date: Date.utc_today(),
        description: "Test work",
        minutes: 60,
        billable: true,
        bill_rate: Money.new!(:USD, "100.00")
      })
      |> Ash.create!(domain: Finance)

    entry =
      entry
      |> Ash.Changeset.for_update(:submit, %{})
      |> Ash.update!(domain: Finance)

    entry
    |> Ash.Changeset.for_update(:approve, %{})
    |> Ash.update!(domain: Finance)
  end

  test "generates and issues invoice for due agreement", %{org: org, team_member: team_member} do
    agreement = active_agreement(org, :monthly, Date.utc_today())
    _entry = approved_time_entry(org, agreement, team_member)

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    invoices =
      GnomeGarden.Finance.Invoice
      |> Ash.Query.filter(agreement_id == ^agreement.id)
      |> Ash.read!(domain: Finance)

    assert length(invoices) == 1
    assert hd(invoices).status == :issued
  end

  test "advances next_billing_date after invoicing", %{org: org, team_member: team_member} do
    today = Date.utc_today()
    agreement = active_agreement(org, :monthly, today)
    _entry = approved_time_entry(org, agreement, team_member)

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    {:ok, updated} = Ash.get(GnomeGarden.Commercial.Agreement, agreement.id, domain: Commercial)
    assert updated.next_billing_date == Date.shift(today, month: 1)
  end

  test "skips agreements not yet due", %{org: org, team_member: team_member} do
    future_date = Date.add(Date.utc_today(), 7)
    agreement = active_agreement(org, :weekly, future_date)
    _entry = approved_time_entry(org, agreement, team_member)

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    invoices =
      GnomeGarden.Finance.Invoice
      |> Ash.Query.filter(agreement_id == ^agreement.id)
      |> Ash.read!(domain: Finance)

    assert invoices == []
  end

  test "advances date even when no billable entries", %{org: org} do
    today = Date.utc_today()
    agreement = active_agreement(org, :weekly, today)
    # No time entries created

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    {:ok, updated} = Ash.get(GnomeGarden.Commercial.Agreement, agreement.id, domain: Commercial)
    assert updated.next_billing_date == Date.add(today, 7)
  end

  # The key behavioral rule: a failed email leaves the invoice issued and the
  # ledger entry intact; issuance is never undone or retried by the email step.
  test "issues + posts even when the email fails, recording a partial-failure run", %{org: org, team_member: team_member} do
    today = Date.utc_today()
    agreement = active_agreement(org, :monthly, today)
    _entry = approved_time_entry(org, agreement, team_member)

    # No Person with a contact email exists for this org, so email delivery fails.
    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    [invoice] =
      GnomeGarden.Finance.Invoice
      |> Ash.Query.filter(agreement_id == ^agreement.id)
      |> Ash.read!(domain: Finance)

    # Invoice remains issued; email delivery is recorded as failed, separately.
    assert invoice.status == :issued
    assert invoice.email_status == :failed
    assert invoice.email_failure_reason =~ "no contact email"

    # The ledger posting survived the email failure.
    {:ok, entries} = GnomeGarden.Ledger.list_journal_entries_for_reference("invoice", invoice.id)
    assert Enum.any?(entries, &(&1.entry_type == :invoice_issued))

    # Billing date advanced (issue succeeded).
    {:ok, updated} = Ash.get(GnomeGarden.Commercial.Agreement, agreement.id, domain: Commercial)
    assert updated.next_billing_date == Date.shift(today, month: 1)

    # The run records the failure as partial, with a matching per-agreement item.
    {:ok, [run]} = Finance.list_recent_billing_runs()
    assert run.status == :partial_failure
    assert run.scanned_count == 1
    assert run.issued_count == 1
    assert run.emailed_count == 0
    assert run.failed_count == 1

    {:ok, [item]} = Finance.list_billing_run_items_for_run(run.id)
    assert item.outcome == :issued
    assert item.email_outcome == :failed
    assert item.invoice_id == invoice.id
  end

  test "records a succeeded run that skips agreements with nothing to bill", %{org: org} do
    agreement = active_agreement(org, :weekly, Date.utc_today())

    assert :ok = InvoiceSchedulerWorker.perform(%Oban.Job{args: %{}})

    {:ok, [run]} = Finance.list_recent_billing_runs()
    assert run.status == :succeeded
    assert run.scanned_count == 1
    assert run.skipped_count == 1
    assert run.issued_count == 0

    {:ok, [item]} = Finance.list_billing_run_items_for_run(run.id)
    assert item.outcome == :skipped
    assert item.agreement_id == agreement.id
  end
end
