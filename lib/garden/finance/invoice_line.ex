defmodule GnomeGarden.Finance.InvoiceLine do
  @moduledoc """
  Line item on an operational invoice.

  Lines may reference labor, expense, service, or adjustment records so the
  invoice header can be traced back to operational source data.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :invoice_id,
      :line_number,
      :line_kind,
      :description,
      :quantity,
      :line_total
    ]
  end

  postgres do
    table "finance_invoice_lines"
    repo GnomeGarden.Repo

    references do
      reference :invoice, on_delete: :delete
      reference :organization, on_delete: :delete
      reference :agreement, on_delete: :nilify
      reference :project, on_delete: :nilify
      reference :work_order, on_delete: :nilify
      reference :time_entry, on_delete: :nilify
      reference :expense, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :invoice_id,
        :organization_id,
        :agreement_id,
        :project_id,
        :work_order_id,
        :time_entry_id,
        :expense_id,
        :line_number,
        :line_kind,
        :description,
        :quantity,
        :unit_price,
        :line_total,
        :notes
      ]
    end

    update :update do
      accept [
        :invoice_id,
        :organization_id,
        :agreement_id,
        :project_id,
        :work_order_id,
        :time_entry_id,
        :expense_id,
        :line_number,
        :line_kind,
        :description,
        :quantity,
        :unit_price,
        :line_total,
        :notes
      ]
    end

    read :for_invoice do
      argument :invoice_id, :uuid, allow_nil?: false
      filter expr(invoice_id == ^arg(:invoice_id))
      prepare build(sort: [line_number: :asc, inserted_at: :asc], load: [:time_entry, :expense])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :line_number, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :line_kind, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :labor,
                    :expense,
                    :material,
                    :service,
                    :adjustment,
                    :tax,
                    :other
                  ]
    end

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :quantity, :decimal do
      allow_nil? false
      public? true
    end

    attribute :unit_price, :decimal do
      allow_nil? false
      public? true
    end

    attribute :line_total, :decimal do
      allow_nil? false
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :invoice, GnomeGarden.Finance.Invoice do
      allow_nil? false
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      public? true
    end

    belongs_to :project, GnomeGarden.Execution.Project do
      public? true
    end

    belongs_to :work_order, GnomeGarden.Execution.WorkOrder do
      public? true
    end

    belongs_to :time_entry, GnomeGarden.Finance.TimeEntry do
      public? true
    end

    belongs_to :expense, GnomeGarden.Finance.Expense do
      public? true
    end
  end

  identities do
    identity :unique_line_number_per_invoice, [:invoice_id, :line_number]
  end
end
