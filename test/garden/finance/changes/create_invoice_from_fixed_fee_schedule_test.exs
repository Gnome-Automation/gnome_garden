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
        organization_id: org.id,
        name: "Fixed Fee Agreement #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :fixed_fee,
        currency_code: "USD",
        contract_value: Decimal.new("10000.00"),
        payment_terms_days: 30
      })

    %{org: org, agreement: agreement}
  end

  test "generates one invoice per schedule item with correct amounts", %{agreement: agreement} do
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
        label: "Final",
        percentage: Decimal.new("50"),
        due_days: 60
      })

    assert {:ok, invoices} =
             Finance.create_invoices_from_fixed_fee_schedule(agreement.id)

    assert length(invoices) == 3

    [inv1, inv2, inv3] = invoices

    assert Decimal.equal?(inv1.total_amount, Decimal.new("2500.00"))
    assert Decimal.equal?(inv2.total_amount, Decimal.new("2500.00"))
    assert Decimal.equal?(inv3.total_amount, Decimal.new("5000.00"))

    assert inv1.notes == "Deposit"
    assert inv2.notes == "Milestone 1"
    assert inv3.notes == "Final"

    assert inv1.status == :draft
    assert inv2.status == :draft
    assert inv3.status == :draft

    assert inv1.agreement_id == agreement.id
    assert inv2.agreement_id == agreement.id
    assert inv3.agreement_id == agreement.id
  end

  test "returns error when percentages do not sum to 100", %{agreement: agreement} do
    {:ok, _} =
      Finance.create_payment_schedule_item(%{
        agreement_id: agreement.id,
        position: 1,
        label: "Deposit",
        percentage: Decimal.new("40"),
        due_days: 0
      })

    {:ok, _} =
      Finance.create_payment_schedule_item(%{
        agreement_id: agreement.id,
        position: 2,
        label: "Balance",
        percentage: Decimal.new("40"),
        due_days: 30
      })

    assert {:error, message} =
             Finance.create_invoices_from_fixed_fee_schedule(agreement.id)

    assert message =~ "80"
    assert message =~ "100%"
  end

  test "returns error when agreement has no contract_value", %{org: org} do
    {:ok, agreement_no_value} =
      Commercial.create_agreement(%{
        organization_id: org.id,
        name: "No Value Agreement #{System.unique_integer([:positive])}",
        agreement_type: :project,
        billing_model: :fixed_fee,
        currency_code: "USD"
      })

    assert {:error, message} =
             Finance.create_invoices_from_fixed_fee_schedule(agreement_no_value.id)

    assert message =~ "contract_value"
  end

  test "with no schedule items, generates a single invoice for the full contract_value",
       %{agreement: agreement} do
    assert {:ok, invoices} =
             Finance.create_invoices_from_fixed_fee_schedule(agreement.id)

    assert length(invoices) == 1

    [invoice] = invoices
    assert Decimal.equal?(invoice.total_amount, Decimal.new("10000.00"))
    assert invoice.notes == "Full payment"
    assert invoice.status == :draft
    assert invoice.agreement_id == agreement.id
  end

  describe "with selected_expense_ids" do
    setup %{agreement: agreement, org: org} do
      user =
        GnomeGarden.Repo.insert!(%GnomeGarden.Accounts.User{
          id: Ecto.UUID.generate(),
          email: "test-#{System.unique_integer([:positive])}@example.com"
        })

      {:ok, expense} =
        Finance.create_expense(%{
          agreement_id: agreement.id,
          organization_id: org.id,
          incurred_by_user_id: user.id,
          description: "Hotel",
          category: :travel,
          amount: Decimal.new("500.00"),
          incurred_on: Date.utc_today()
        })

      {:ok, expense} = Finance.submit_expense(expense)
      {:ok, expense} = Finance.approve_expense(expense)

      {:ok, expense2} =
        Finance.create_expense(%{
          agreement_id: agreement.id,
          organization_id: org.id,
          incurred_by_user_id: user.id,
          description: "Flight",
          category: :travel,
          amount: Decimal.new("300.00"),
          incurred_on: Date.utc_today()
        })

      {:ok, expense2} = Finance.submit_expense(expense2)
      {:ok, expense2} = Finance.approve_expense(expense2)

      %{expense: expense, expense2: expense2}
    end

    test "appends expense lines to the first invoice only", %{
      agreement: agreement,
      expense: expense
    } do
      {:ok, _} =
        Finance.create_payment_schedule_item(%{
          agreement_id: agreement.id,
          position: 1,
          label: "Deposit",
          percentage: Decimal.new("50"),
          due_days: 0
        })

      {:ok, _} =
        Finance.create_payment_schedule_item(%{
          agreement_id: agreement.id,
          position: 2,
          label: "Final",
          percentage: Decimal.new("50"),
          due_days: 30
        })

      assert {:ok, [inv1, inv2]} =
               Finance.create_invoices_from_fixed_fee_schedule(
                 agreement.id,
                 [to_string(expense.id)]
               )

      {:ok, inv1_lines} = Finance.list_invoice_lines_for_invoice(inv1.id)
      {:ok, inv2_lines} = Finance.list_invoice_lines_for_invoice(inv2.id)

      assert Enum.any?(inv1_lines, &(&1.expense_id == expense.id))
      assert Enum.empty?(Enum.filter(inv2_lines, & &1.expense_id))
    end

    test "updates subtotal, total_amount, balance_amount on first invoice", %{
      agreement: agreement,
      expense: expense
    } do
      assert {:ok, [first | _rest]} =
               Finance.create_invoices_from_fixed_fee_schedule(
                 agreement.id,
                 [to_string(expense.id)]
               )

      # contract_value = 10_000, no schedule → single invoice for full amount
      # + expense $500
      assert Decimal.equal?(first.subtotal, Decimal.new("10500.00"))
      assert Decimal.equal?(first.total_amount, Decimal.new("10500.00"))
      assert Decimal.equal?(first.balance_amount, Decimal.new("10500.00"))
    end

    test "marks selected expenses as billed", %{agreement: agreement, expense: expense} do
      assert {:ok, _invoices} =
               Finance.create_invoices_from_fixed_fee_schedule(
                 agreement.id,
                 [to_string(expense.id)]
               )

      {:ok, reloaded} = Finance.get_expense(expense.id)
      assert reloaded.status == :billed
    end

    test "leaves unselected expenses as approved", %{
      agreement: agreement,
      expense: expense,
      expense2: expense2
    } do
      assert {:ok, _invoices} =
               Finance.create_invoices_from_fixed_fee_schedule(
                 agreement.id,
                 [to_string(expense.id)]
               )

      {:ok, reloaded} = Finance.get_expense(expense2.id)
      assert reloaded.status == :approved
    end

    test "with empty selected_expense_ids, no expense lines added", %{agreement: agreement} do
      assert {:ok, [invoice]} =
               Finance.create_invoices_from_fixed_fee_schedule(agreement.id, [])

      {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
      assert Enum.empty?(lines)
    end

    test "with no selected_expense_ids (default), no expense lines added", %{
      agreement: agreement
    } do
      assert {:ok, [invoice]} =
               Finance.create_invoices_from_fixed_fee_schedule(agreement.id)

      {:ok, lines} = Finance.list_invoice_lines_for_invoice(invoice.id)
      assert Enum.empty?(lines)
    end
  end
end
