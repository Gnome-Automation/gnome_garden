defmodule GnomeGardenWeb.FinanceWorkToBillLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  alias GnomeGarden.Commercial
  alias GnomeGarden.Finance
  alias GnomeGarden.Operations

  test "renders the work to bill workspace", %{conn: conn, current_team_member: team_member} do
    {organization, agreement} = customer_agreement!()
    _time_entry = approved_time_entry!(organization, agreement, team_member)
    _expense = approved_expense!(organization, agreement, team_member)

    {:ok, _view, html} = live(conn, ~p"/finance/work-to-bill")

    assert html =~ "Work to Bill"
    assert html =~ "Invoice Candidates"
    assert html =~ "Approved Time"
    assert html =~ "Approved Expenses"
    assert html =~ organization.name
    assert html =~ "Commissioning support"
    assert html =~ "Panel materials"
  end

  defp customer_agreement! do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Work To Bill Customer #{System.unique_integer([:positive])}",
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

  defp approved_time_entry!(organization, agreement, team_member) do
    {:ok, time_entry} =
      Finance.create_time_entry(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        member_team_member_id: team_member.id,
        work_date: Date.utc_today(),
        minutes: 90,
        description: "Commissioning support",
        billable: true,
        bill_rate: Decimal.new("125.00")
      })

    {:ok, time_entry} = Finance.submit_time_entry(time_entry)
    {:ok, time_entry} = Finance.approve_time_entry(time_entry)
    time_entry
  end

  defp approved_expense!(organization, agreement, team_member) do
    {:ok, expense} =
      Finance.create_expense(%{
        organization_id: organization.id,
        agreement_id: agreement.id,
        incurred_by_team_member_id: team_member.id,
        incurred_on: Date.utc_today(),
        category: :materials,
        description: "Panel materials",
        amount: Decimal.new("60.00"),
        billable: true,
        vendor: "Supply House"
      })

    {:ok, expense} = Finance.submit_expense(expense)
    {:ok, expense} = Finance.approve_expense(expense)
    expense
  end
end
