defmodule GnomeGarden.Ledger.DefaultChartOfAccounts do
  @moduledoc """
  Idempotently seeds the standard chart of accounts for a professional-services
  firm. These system accounts are the posting targets used by the
  `GnomeGarden.Finance` GL-posting changes (AR, cash, revenue, tax payable,
  customer retainers/deferred revenue, AP).

  Run via `priv/repo/seeds.exs` or call `ensure_defaults/0` directly.
  """

  alias GnomeGarden.Ledger

  @accounts [
    %{number: "1000", name: "Operating Bank", type: :asset, normal_balance: :debit, system?: true},
    %{number: "1100", name: "Accounts Receivable", type: :asset, normal_balance: :debit, system?: true},
    %{number: "1200", name: "Undeposited Funds", type: :asset, normal_balance: :debit, system?: true},
    %{number: "2000", name: "Accounts Payable", type: :liability, normal_balance: :credit, system?: true},
    %{number: "2200", name: "Sales Tax Payable", type: :liability, normal_balance: :credit, system?: true},
    %{number: "2300", name: "Customer Retainers (Deferred Revenue)", type: :liability, normal_balance: :credit, system?: true},
    %{number: "3000", name: "Owner's Equity", type: :equity, normal_balance: :credit, system?: false},
    %{number: "4000", name: "Service Revenue", type: :revenue, normal_balance: :credit, system?: true},
    %{number: "4100", name: "Reimbursed Expense Revenue", type: :revenue, normal_balance: :credit, system?: false},
    %{number: "5000", name: "Operating Expenses", type: :expense, normal_balance: :debit, system?: true},
    %{number: "6000", name: "Reimbursable Project Expenses", type: :expense, normal_balance: :debit, system?: false}
  ]

  @doc """
  Creates any standard accounts that don't already exist. Returns the list of
  newly-created accounts.
  """
  def ensure_defaults do
    existing_numbers =
      Ledger.list_accounts!()
      |> MapSet.new(& &1.number)

    @accounts
    |> Enum.reject(&MapSet.member?(existing_numbers, &1.number))
    |> Enum.map(&Ledger.create_account!/1)
  end

  @doc "The canonical default account definitions."
  def definitions, do: @accounts
end
