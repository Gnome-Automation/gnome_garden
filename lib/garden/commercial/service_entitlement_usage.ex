defmodule GnomeGarden.Commercial.ServiceEntitlementUsage do
  @moduledoc """
  Usage event recorded against a service entitlement.

  This forms a contract-consumption ledger that can be driven manually today
  and later automated from time entries, expenses, or work orders.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :service_entitlement_id,
      :agreement_id,
      :source_type,
      :quantity,
      :usage_on,
      :inserted_at
    ]
  end

  postgres do
    table "commercial_service_entitlement_usages"
    repo GnomeGarden.Repo

    references do
      reference :agreement, on_delete: :delete
      reference :service_entitlement, on_delete: :delete
      reference :time_entry, on_delete: :nilify
      reference :expense, on_delete: :nilify
      reference :work_order, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :agreement_id,
        :service_entitlement_id,
        :time_entry_id,
        :expense_id,
        :work_order_id,
        :source_type,
        :usage_on,
        :quantity,
        :notes
      ]
    end

    update :update do
      accept [
        :agreement_id,
        :service_entitlement_id,
        :time_entry_id,
        :expense_id,
        :work_order_id,
        :source_type,
        :usage_on,
        :quantity,
        :notes
      ]
    end

    read :for_entitlement do
      argument :service_entitlement_id, :uuid, allow_nil?: false
      filter expr(service_entitlement_id == ^arg(:service_entitlement_id))

      prepare build(
                sort: [usage_on: :desc, inserted_at: :desc],
                load: [:time_entry, :expense, :work_order]
              )
    end

    read :for_agreement do
      argument :agreement_id, :uuid, allow_nil?: false
      filter expr(agreement_id == ^arg(:agreement_id))

      prepare build(
                sort: [usage_on: :desc, inserted_at: :desc],
                load: [:service_entitlement, :time_entry, :expense, :work_order]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source_type, :atom do
      allow_nil? false
      default :manual_adjustment
      public? true

      constraints one_of: [:manual_adjustment, :time_entry, :expense, :work_order]
    end

    attribute :usage_on, :date do
      allow_nil? false
      public? true
    end

    attribute :quantity, :decimal do
      allow_nil? false
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      allow_nil? false
      public? true
    end

    belongs_to :service_entitlement, GnomeGarden.Commercial.ServiceEntitlement do
      allow_nil? false
      public? true
    end

    belongs_to :time_entry, GnomeGarden.Finance.TimeEntry do
      public? true
    end

    belongs_to :expense, GnomeGarden.Finance.Expense do
      public? true
    end

    belongs_to :work_order, GnomeGarden.Execution.WorkOrder do
      public? true
    end
  end
end
