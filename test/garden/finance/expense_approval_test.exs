defmodule GnomeGarden.Finance.ExpenseApprovalTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.{Accounts, Commercial, Finance, Operations}

  setup do
    {:ok, user} =
      Accounts.create_user_with_password(
        %{email: "u#{System.unique_integer([:positive])}@test.com", password: "password1234", password_confirmation: "password1234"},
        authorize?: false
      )

    {:ok, tm} = Operations.create_team_member(%{user_id: user.id, display_name: "Founder"})
    {:ok, org} = Operations.create_organization(%{name: "Org #{System.unique_integer([:positive])}"})

    {:ok, agreement} =
      Commercial.create_agreement(%{organization_id: org.id, name: "Retainer", agreement_type: :project, currency_code: "USD"})

    {:ok, agreement} = Commercial.activate_agreement(agreement)

    %{org: org, tm: tm, agreement: agreement}
  end

  test "approving a billable non-materials expense on an agreement with no entitlements does not crash",
       %{org: org, tm: tm, agreement: agreement} do
    {:ok, expense} =
      Finance.create_expense(%{
        organization_id: org.id,
        agreement_id: agreement.id,
        incurred_by_team_member_id: tm.id,
        incurred_on: Date.utc_today(),
        amount: Money.new!(:USD, "50"),
        billable: true,
        category: :other,
        description: "Cloud costs"
      })

    {:ok, expense} = Finance.submit_expense(expense)
    assert {:ok, approved} = Finance.approve_expense(expense, %{approved_by_team_member_id: tm.id})
    assert approved.status == :approved
  end
end
