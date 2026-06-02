defmodule GnomeGarden.Finance.RecurringInvoiceLine do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_recurring_invoice_lines"
    repo GnomeGarden.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :line_number, :integer do
      default 1
      allow_nil? false
    end

    attribute :line_kind, :atom do
      constraints one_of: [:labor, :expense, :material, :service, :adjustment, :tax, :other]
      default :service
      allow_nil? false
    end

    attribute :description, :string, allow_nil?: false
    attribute :quantity, :decimal, allow_nil?: false
    attribute :unit_price, :decimal, allow_nil?: false
    attribute :line_total, :decimal, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :recurring_invoice, GnomeGarden.Finance.RecurringInvoice do
      allow_nil? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:line_number, :line_kind, :description, :quantity, :unit_price, :line_total, :recurring_invoice_id]
    end

    update :update do
      accept [:line_number, :line_kind, :description, :quantity, :unit_price, :line_total]
    end
  end
end
