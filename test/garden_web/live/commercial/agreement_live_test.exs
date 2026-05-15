defmodule GnomeGardenWeb.Commercial.AgreementLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Repo

  setup :register_and_log_in_user

  setup do
    user =
      Repo.insert!(%GnomeGarden.Accounts.User{
        id: Ecto.UUID.generate(),
        email: "test-#{System.unique_integer([:positive])}@example.com",
        hashed_password: "$2b$12$placeholder_hash_for_test_only_do_not_use_in_prod"
      })

    {:ok, team_member} =
      Operations.create_team_member(%{
        user_id: user.id,
        display_name: "Test Member",
        role: :operator,
        status: :active
      })

    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    {:ok, tm_agreement} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "T&M Agreement #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :time_and_materials,
        currency_code: "USD",
        payment_terms_days: 30
      })

    tm_agreement =
      tm_agreement
      |> Ash.Changeset.for_update(:activate, %{})
      |> Ash.update!(domain: Commercial, authorize?: false)

    {:ok, ff_agreement} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "Fixed Fee Agreement #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :fixed_fee,
        currency_code: "USD",
        contract_value: Decimal.new("5000.00"),
        payment_terms_days: 30
      })

    {:ok, expense} =
      Finance.create_expense(%{
        agreement_id: tm_agreement.id,
        organization_id: org.id,
        incurred_by_team_member_id: team_member.id,
        description: "Hotel",
        category: :travel,
        amount: Decimal.new("200.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense} = Finance.submit_expense(expense)
    {:ok, expense} = Finance.approve_expense(expense)

    %{
      org: org,
      tm_agreement: tm_agreement,
      ff_agreement: ff_agreement,
      expense: expense,
      user: user,
      team_member: team_member
    }
  end

  test "renders unbilled expenses table on T&M agreement", %{
    conn: conn,
    tm_agreement: agreement,
    expense: expense
  } do
    {:ok, _view, html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    assert html =~ "Unbilled Expenses"
    assert html =~ expense.description
  end

  test "renders unbilled expenses table on fixed-fee agreement", %{
    conn: conn,
    ff_agreement: agreement,
    org: org,
    user: _user,
    team_member: team_member
  } do
    {:ok, exp} =
      Finance.create_expense(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        incurred_by_team_member_id: team_member.id,
        description: "Equipment rental",
        category: :equipment,
        amount: Decimal.new("150.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, exp} = Finance.submit_expense(exp)
    {:ok, exp} = Finance.approve_expense(exp)

    {:ok, _view, html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    assert html =~ "Unbilled Expenses"
    assert html =~ exp.description
  end

  test "does not render unbilled expenses section when there are none", %{
    conn: conn,
    ff_agreement: agreement
  } do
    {:ok, _view, html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    refute html =~ "Unbilled Expenses"
  end

  test "toggle_expense adds expense to selection (checkbox checked)", %{
    conn: conn,
    tm_agreement: agreement,
    expense: expense
  } do
    {:ok, view, _html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    html =
      view
      |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
      |> render_click()

    assert html =~ ~s(checked)
  end

  test "toggle_expense removes expense from selection on second click", %{
    conn: conn,
    tm_agreement: agreement,
    expense: expense
  } do
    {:ok, view, _html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    view
    |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
    |> render_click()

    html =
      view
      |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
      |> render_click()

    refute html =~ ~s(checked)
  end

  test "generating T&M invoice with selected expense marks expense as billed and removes it from table",
       %{
         conn: conn,
         tm_agreement: agreement,
         expense: expense,
         org: org,
         user: _user,
         team_member: team_member
       } do
    {:ok, te} =
      Finance.create_time_entry(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        member_team_member_id: team_member.id,
        description: "Dev work",
        minutes: 60,
        bill_rate: Decimal.new("100.00"),
        work_date: Date.utc_today()
      })

    {:ok, te} = Finance.submit_time_entry(te)
    {:ok, _te} = Finance.approve_time_entry(te)

    {:ok, view, _html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    view
    |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
    |> render_click()

    html =
      view
      |> element("[phx-click='generate_invoice']")
      |> render_click()

    refute html =~ expense.description

    {:ok, reloaded} = Finance.get_expense(expense.id)
    assert reloaded.status == :billed
  end

  test "unselected expenses remain in table after invoice generation", %{
    conn: conn,
    tm_agreement: agreement,
    expense: expense,
    org: org,
    user: _user,
    team_member: team_member
  } do
    {:ok, expense2} =
      Finance.create_expense(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        incurred_by_team_member_id: team_member.id,
        description: "Flight",
        category: :travel,
        amount: Decimal.new("350.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense2} = Finance.submit_expense(expense2)
    {:ok, expense2} = Finance.approve_expense(expense2)

    {:ok, te} =
      Finance.create_time_entry(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        member_team_member_id: team_member.id,
        description: "Work",
        minutes: 60,
        bill_rate: Decimal.new("100.00"),
        work_date: Date.utc_today()
      })

    {:ok, te} = Finance.submit_time_entry(te)
    {:ok, _te} = Finance.approve_time_entry(te)

    {:ok, view, _html} = live(conn, ~p"/commercial/agreements/#{agreement}")

    view
    |> element("[phx-click='toggle_expense'][phx-value-id='#{expense.id}']")
    |> render_click()

    html =
      view
      |> element("[phx-click='generate_invoice']")
      |> render_click()

    assert html =~ expense2.description
  end
end
