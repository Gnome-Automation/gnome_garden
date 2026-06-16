defmodule GnomeGarden.Finance.WorkToBillWorkspaceTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Accounts
  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  test "builds invoice candidates from approved billable time and expenses" do
    team_member = team_member!()
    {organization, agreement} = customer_agreement!()

    _time_entry = approved_time_entry!(organization, agreement, team_member, billable?: true)
    _expense = approved_expense!(organization, agreement, team_member, billable?: true)

    _unbillable_time =
      approved_time_entry!(organization, agreement, team_member, billable?: false)

    workspace = Finance.get_work_to_bill_workspace!()

    assert workspace.time_entry_count == 1
    assert workspace.expense_count == 1
    assert workspace.source_group_count == 1
    assert workspace.billable_minutes == 120
    assert Decimal.equal?(workspace.labor_total, Decimal.new("300.0"))
    assert Decimal.equal?(workspace.expense_total, Decimal.new("80.00"))
    assert Decimal.equal?(workspace.ready_total, Decimal.new("380.00"))

    [group] = workspace.source_groups
    assert group.organization_id == organization.id
    assert group.agreement_id == agreement.id
    assert group.time_entry_count == 1
    assert group.expense_count == 1
  end

  defp team_member! do
    password = "valid-password-#{System.unique_integer([:positive])}"

    {:ok, user} =
      Accounts.create_user_with_password(%{
        email: "billing-#{System.unique_integer([:positive])}@example.com",
        password: password,
        password_confirmation: password
      })

    {:ok, team_member} =
      Operations.create_team_member(%{
        user_id: user.id,
        display_name: "Billing Operator",
        role: :admin,
        status: :active
      })

    team_member
  end

  defp customer_agreement! do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Billing Customer #{System.unique_integer([:positive])}",
        status: :active,
        relationship_roles: ["customer"]
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: organization.id,
        name: "Support Agreement",
        agreement_type: :service
      })

    {organization, agreement}
  end

  defp approved_time_entry!(organization, agreement, team_member, opts) do
    {:ok, time_entry} =
      Finance.create_time_entry(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        member_team_member_id: team_member.id,
        work_date: Date.utc_today(),
        minutes: 120,
        description: "Commissioning support",
        billable: Keyword.fetch!(opts, :billable?),
        bill_rate: Decimal.new("150.00")
      })

    {:ok, time_entry} = Finance.submit_time_entry(time_entry)
    {:ok, time_entry} = Finance.approve_time_entry(time_entry)
    time_entry
  end

  defp approved_expense!(organization, agreement, team_member, opts) do
    {:ok, expense} =
      Finance.create_expense(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        incurred_by_team_member_id: team_member.id,
        incurred_on: Date.utc_today(),
        category: :materials,
        description: "Panel materials",
        amount: Decimal.new("80.00"),
        billable: Keyword.fetch!(opts, :billable?),
        vendor: "Supply House"
      })

    {:ok, expense} = Finance.submit_expense(expense)
    {:ok, expense} = Finance.approve_expense(expense)
    expense
  end
end
