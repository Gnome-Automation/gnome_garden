defmodule GnomeGarden.Finance.BillingSettings do
  @moduledoc """
  Singleton settings for the Finance billing subsystem.

  Always one row in the database. Use Finance.get_billing_settings/0 to read
  and Finance.upsert_billing_settings/1 to update.

  The `scope` field is always "global" — it exists only to give Ash
  a stable identity for the upsert.
  """

  use Ash.Resource,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "billing_settings"
    repo GnomeGarden.Repo
  end

  actions do
    read :read do
      primary? true
    end

    create :upsert do
      accept [:reminder_days]
      upsert? true
      upsert_identity :singleton_scope
      upsert_fields [:reminder_days]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :scope, :string do
      default "global"
      allow_nil? false
      description "Always 'global'. Exists to give the upsert a stable identity."
    end

    attribute :reminder_days, {:array, :integer} do
      default [7, 14, 30]
      allow_nil? false
      description "Days overdue at which payment reminder emails are sent."
      constraints min_length: 1,
                  items: [min: 1, max: 365]
    end

    timestamps()
  end

  identities do
    identity :singleton_scope, [:scope]
  end
end
