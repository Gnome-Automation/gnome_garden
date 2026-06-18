defmodule GnomeGarden.Repo.Migrations.FinanceLedgerAndMoney do
  @moduledoc """
  Creates the Ledger domain (accounts, journal entries, journal lines) and
  converts existing Finance monetary columns from :decimal to :money
  (money_with_currency).

  The decimal -> money conversions use explicit `USING` casts because Postgres
  cannot implicitly cast numeric to the money_with_currency composite type.
  Existing values are assumed to be USD.
  """

  use Ecto.Migration

  def up do
    money_up("finance_invoice_lines", "line_total")
    money_up("finance_invoice_lines", "unit_price")
    money_up("finance_time_entries", "cost_rate")
    money_up("finance_time_entries", "bill_rate")
    money_up("finance_expenses", "amount")

    create table(:ledger_journal_lines, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :debit, :money_with_currency
      add :credit, :money_with_currency
      add :description, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :journal_entry_id, :uuid, null: false
      add :account_id, :uuid, null: false
    end

    create table(:ledger_accounts, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :number, :text, null: false
      add :name, :text, null: false
      add :type, :text, null: false
      add :normal_balance, :text, null: false
      add :description, :text
      add :system?, :boolean, null: false, default: false
      add :active?, :boolean, null: false, default: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:ledger_accounts, [:number], name: "ledger_accounts_unique_number_index")

    money_up("finance_payment_applications", "amount")
    money_up("finance_invoices", "balance_amount")
    money_up("finance_invoices", "total_amount")
    money_up("finance_invoices", "tax_total")
    money_up("finance_invoices", "subtotal")
    money_up("finance_payments", "amount")

    create table(:ledger_journal_entries, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:ledger_journal_lines) do
      modify :journal_entry_id,
             references(:ledger_journal_entries,
               column: :id,
               name: "ledger_journal_lines_journal_entry_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :delete_all
             )

      modify :account_id,
             references(:ledger_accounts,
               column: :id,
               name: "ledger_journal_lines_account_id_fkey",
               type: :uuid,
               prefix: "public",
               on_delete: :restrict
             )
    end

    alter table(:ledger_journal_entries) do
      add :entry_number, :text, null: false
      add :date, :date, null: false
      add :description, :text
      add :entry_type, :text, null: false
      add :status, :text, null: false, default: "draft"
      add :reference_id, :uuid
      add :reference_type, :text
      add :posted_at, :utc_datetime

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:ledger_journal_entries, [:reference_type, :reference_id, :entry_type],
             name: "ledger_journal_entries_unique_business_event",
             unique: true,
             where: "reference_id IS NOT NULL"
           )

    create unique_index(:ledger_journal_entries, [:entry_number],
             name: "ledger_journal_entries_unique_entry_number_index"
           )
  end

  def down do
    drop_if_exists unique_index(:ledger_journal_entries, [:entry_number],
                     name: "ledger_journal_entries_unique_entry_number_index"
                   )

    drop_if_exists index(:ledger_journal_entries, [:reference_type, :reference_id, :entry_type],
                     name: "ledger_journal_entries_unique_business_event"
                   )

    drop constraint(:ledger_journal_lines, "ledger_journal_lines_journal_entry_id_fkey")
    drop constraint(:ledger_journal_lines, "ledger_journal_lines_account_id_fkey")

    drop table(:ledger_journal_entries)

    money_down("finance_payments", "amount")
    money_down("finance_invoices", "subtotal")
    money_down("finance_invoices", "tax_total")
    money_down("finance_invoices", "total_amount")
    money_down("finance_invoices", "balance_amount")
    money_down("finance_payment_applications", "amount")

    drop_if_exists unique_index(:ledger_accounts, [:number],
                     name: "ledger_accounts_unique_number_index"
                   )

    drop table(:ledger_accounts)
    drop table(:ledger_journal_lines)

    money_down("finance_expenses", "amount")
    money_down("finance_time_entries", "bill_rate")
    money_down("finance_time_entries", "cost_rate")
    money_down("finance_invoice_lines", "unit_price")
    money_down("finance_invoice_lines", "line_total")
  end

  defp money_up(table, column) do
    execute """
    ALTER TABLE #{table}
    ALTER COLUMN #{column} TYPE money_with_currency
    USING CASE
      WHEN #{column} IS NOT NULL THEN ROW('USD', #{column})::money_with_currency
      ELSE NULL
    END
    """
  end

  defp money_down(table, column) do
    execute """
    ALTER TABLE #{table}
    ALTER COLUMN #{column} TYPE numeric
    USING (#{column}).amount
    """
  end
end
