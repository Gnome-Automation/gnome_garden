defmodule GnomeGarden.Finance.Changes.CreateInvoiceFromAgreementSourcesTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance
  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Repo

  setup do
    {:ok, org} =
      Operations.create_organization(%{
        name: "Test Org #{System.unique_integer([:positive])}",
        organization_kind: :business
      })

    user =
      Repo.insert!(%GnomeGarden.Accounts.User{
        id: Ecto.UUID.generate(),
        email: "te-#{System.unique_integer([:positive])}@example.com"
      })

    {:ok, team_member} =
      Operations.create_team_member(%{
        user_id: user.id,
        display_name: "Test Member",
        role: :operator,
        status: :active
      })

    {:ok, agreement} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "T&M Agreement #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :time_and_materials,
        currency_code: "USD",
        payment_terms_days: 30
      })

    # Activate the agreement so T&M invoice generation passes the status check
    agreement =
      agreement
      |> Ash.Changeset.for_update(:activate, %{})
      |> Ash.update!(domain: Commercial, authorize?: false)

    {:ok, time_entry} =
      Finance.create_time_entry(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        member_team_member_id: team_member.id,
        description: "Backend dev",
        minutes: 120,
        bill_rate: Decimal.new("150.00"),
        work_date: Date.utc_today()
      })

    {:ok, time_entry} = Finance.submit_time_entry(time_entry)
    {:ok, time_entry} = Finance.approve_time_entry(time_entry)

    {:ok, expense} =
      Finance.create_expense(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        incurred_by_team_member_id: team_member.id,
        description: "Hotel stay",
        category: :travel,
        amount: Decimal.new("250.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense} = Finance.submit_expense(expense)
    {:ok, expense} = Finance.approve_expense(expense)

    {:ok, expense2} =
      Finance.create_expense(%{
        agreement_id: agreement.id,
        organization_id: org.id,
        incurred_by_team_member_id: team_member.id,
        description: "Flight",
        category: :travel,
        amount: Decimal.new("400.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, expense2} = Finance.submit_expense(expense2)
    {:ok, expense2} = Finance.approve_expense(expense2)

    %{org: org, agreement: agreement, user: user, team_member: team_member, time_entry: time_entry, expense: expense, expense2: expense2}
  end

  test "includes only selected expenses as invoice lines", %{
    agreement: agreement,
    expense: expense
  } do
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [to_string(expense.id)],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    expense_lines = Enum.filter(lines, &(&1.expense_id == expense.id))
    assert length(expense_lines) == 1
  end

  test "excludes unselected expenses", %{
    agreement: agreement,
    expense: expense,
    expense2: expense2
  } do
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [to_string(expense.id)],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    expense2_lines = Enum.filter(lines, &(&1.expense_id == expense2.id))
    assert Enum.empty?(expense2_lines)
  end

  test "marks only selected expenses as billed", %{
    agreement: agreement,
    expense: expense,
    expense2: expense2
  } do
    assert {:ok, _invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [to_string(expense.id)],
               authorize?: false
             )

    {:ok, billed} = Finance.get_expense(expense.id)
    {:ok, unbilled} = Finance.get_expense(expense2.id)

    assert billed.status == :billed
    assert unbilled.status == :approved
  end

  test "with empty expense_ids, no expense lines are created", %{
    agreement: agreement,
    expense: _expense
  } do
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    expense_lines = Enum.filter(lines, & &1.expense_id)
    assert Enum.empty?(expense_lines)
  end

  test "with empty expense_ids, time entries are still invoiced", %{
    agreement: agreement,
    time_entry: time_entry
  } do
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    time_lines = Enum.filter(lines, &(&1.time_entry_id == time_entry.id))
    assert length(time_lines) == 1
  end

  test "invoice subtotal reflects only selected expenses", %{
    agreement: agreement,
    expense: expense
  } do
    # time_entry: 120 min * $150/hr = $300, expense: $250 → total $550
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement.id,
               expense_ids: [to_string(expense.id)],
               authorize?: false
             )

    assert Decimal.equal?(invoice.total_amount, Decimal.new("550.00"))
  end

  test "expense-only invoice generates when expense selected and no time entries exist", %{
    org: org,
    user: _user,
    team_member: team_member
  } do
    # Edge case from spec: validate_sources_present must treat selected expenses as valid
    {:ok, agreement_no_te} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "Expense Only #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :time_and_materials,
        currency_code: "USD",
        payment_terms_days: 30
      })

    agreement_no_te =
      agreement_no_te
      |> Ash.Changeset.for_update(:activate, %{})
      |> Ash.update!(domain: Commercial, authorize?: false)

    {:ok, exp} =
      Finance.create_expense(%{
        agreement_id: agreement_no_te.id,
        organization_id: org.id,
        incurred_by_team_member_id: team_member.id,
        description: "Conference fee",
        category: :other,
        amount: Decimal.new("100.00"),
        incurred_on: Date.utc_today()
      })

    {:ok, exp} = Finance.submit_expense(exp)
    {:ok, exp} = Finance.approve_expense(exp)

    # No time entries — should succeed because selected expense satisfies source check
    assert {:ok, invoice} =
             Finance.create_invoice_from_agreement_sources(agreement_no_te.id,
               expense_ids: [to_string(exp.id)],
               authorize?: false
             )

    {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
    assert length(lines) == 1
    assert hd(lines).expense_id == exp.id

    {:ok, reloaded_exp} = Finance.get_expense(exp.id)
    assert reloaded_exp.status == :billed
  end
end
