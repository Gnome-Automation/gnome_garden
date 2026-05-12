defmodule GnomeGarden.Mercury.InvoiceSchedulerWorkerTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  require Ash.Query

  alias GnomeGarden.Mercury.InvoiceSchedulerWorker
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
        bill_rate: Decimal.new("100.00")
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
end
