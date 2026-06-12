alias GnomeGarden.Finance

accounts = [
  # Assets (debit normal balance)
  %{number: 1000, name: "Cash", type: :asset, is_system: true},
  %{number: 1100, name: "Accounts Receivable", type: :asset, is_system: true},
  %{number: 1200, name: "Prepaid Expenses", type: :asset, is_system: false},
  %{number: 1300, name: "Unbilled Work in Progress", type: :asset, is_system: false},

  # Liabilities (credit normal balance)
  %{number: 2000, name: "Accounts Payable", type: :liability, is_system: true},
  %{number: 2100, name: "Accrued Expenses", type: :liability, is_system: false},
  %{number: 2200, name: "Sales Tax Payable", type: :liability, is_system: true},
  %{number: 2300, name: "Unearned Revenue / Deposits", type: :liability, is_system: true},

  # Equity (credit normal balance)
  %{number: 3000, name: "Owner's Equity", type: :equity, is_system: false},
  %{number: 3100, name: "Retained Earnings", type: :equity, is_system: false},

  # Revenue (credit normal balance)
  %{number: 4000, name: "Service Revenue", type: :revenue, is_system: true},
  %{number: 4100, name: "Other Revenue", type: :revenue, is_system: false},

  # Expenses (debit normal balance)
  %{number: 5000, name: "Cost of Services", type: :expense, is_system: false},
  %{number: 5100, name: "Payroll & Labor", type: :expense, is_system: false},
  %{number: 5200, name: "Software & Subscriptions", type: :expense, is_system: false},
  %{number: 5300, name: "Bank Fees", type: :expense, is_system: true},
  %{number: 5400, name: "Depreciation", type: :expense, is_system: false},
  %{number: 5500, name: "Other Expenses", type: :expense, is_system: false},
  %{number: 5600, name: "Materials & Supplies", type: :expense, is_system: false},
  %{number: 5700, name: "Equipment & Tools", type: :expense, is_system: false},
  %{number: 5800, name: "Subcontractors", type: :expense, is_system: false},
  %{number: 5900, name: "Vehicle & Travel", type: :expense, is_system: false},
  %{number: 5910, name: "Meals & Lodging", type: :expense, is_system: false},
  %{number: 5950, name: "Bad Debt Expense", type: :expense, is_system: false}
]

Enum.each(accounts, fn attrs ->
  case Finance.get_account_by_number(attrs.number, authorize?: false) do
    {:ok, _existing} ->
      :ok

    {:error, _} ->
      case Finance.create_account(attrs, authorize?: false) do
        {:ok, account} ->
          IO.puts("Created account #{account.number} - #{account.name}")

        {:error, error} ->
          IO.puts("Failed to create #{attrs.number} - #{attrs.name}: #{inspect(error)}")
      end
  end
end)

IO.puts("Chart of accounts seed complete.")
