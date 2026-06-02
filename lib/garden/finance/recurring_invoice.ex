defmodule GnomeGarden.Finance.RecurringInvoice do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_recurring_invoices"
    repo GnomeGarden.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:active, :paused, :stopped]
      default :active
      allow_nil? false
    end

    attribute :interval, :atom do
      constraints one_of: [:daily, :weekly, :monthly, :quarterly, :semi_annually, :annually]
      allow_nil? false
    end

    attribute :net_terms_days, :integer do
      default 30
      allow_nil? false
    end

    attribute :start_date, :date, allow_nil?: false
    attribute :end_date, :date, allow_nil?: true
    attribute :next_generation_date, :date, allow_nil?: false

    attribute :delivery_mode, :atom do
      constraints one_of: [:auto_issue, :draft]
      default :auto_issue
      allow_nil? false
    end

    attribute :tax_rate, :decimal do
      default Decimal.new(0)
      allow_nil? false
    end

    attribute :notes, :string, allow_nil?: true

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
    end

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      allow_nil? true
    end

    has_many :recurring_invoice_lines, GnomeGarden.Finance.RecurringInvoiceLine
    has_many :invoices, GnomeGarden.Finance.Invoice
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :status, :interval, :net_terms_days, :start_date, :end_date,
        :next_generation_date, :delivery_mode, :tax_rate, :notes,
        :organization_id, :agreement_id
      ]
    end

    update :update do
      accept [
        :status, :interval, :net_terms_days, :start_date, :end_date,
        :next_generation_date, :delivery_mode, :tax_rate, :notes,
        :organization_id, :agreement_id
      ]
    end

    update :pause do
      accept []
      change set_attribute(:status, :paused)
    end

    update :resume do
      accept []
      change set_attribute(:status, :active)
    end

    update :stop do
      accept []
      change set_attribute(:status, :stopped)
    end

    update :advance_schedule do
      accept [:next_generation_date, :status]
    end
  end
end
