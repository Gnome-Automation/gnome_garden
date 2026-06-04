defmodule GnomeGarden.Repo.Migrations.AddLateFees do
  use Ecto.Migration

  def change do
    alter table(:billing_settings) do
      add :late_fee_enabled, :boolean, null: false, default: false
      add :late_fee_days, :integer, null: false, default: 30
      add :late_fee_type, :string, null: false, default: "percent"
      add :late_fee_value, :decimal, null: false, default: "1.5"
    end

    alter table(:finance_invoices) do
      add :late_fee_applied_on, :date, null: true
    end
  end
end
