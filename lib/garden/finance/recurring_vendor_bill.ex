defmodule GnomeGarden.Finance.RecurringVendorBill do
  @moduledoc """
  Template for automatically generating recurring vendor bills on a schedule.

  When active and next_due_on <= today, RecurringVendorBillWorker creates a
  draft VendorBill and advances next_due_on by the interval.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :vendor_id, :description, :amount, :interval, :status, :next_due_on]
  end

  postgres do
    table "finance_recurring_vendor_bills"
    repo GnomeGarden.Repo

    references do
      reference :vendor, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:vendor_id, :description, :amount, :interval, :next_due_on, :end_date, :notes]
      change set_attribute(:status, :active)
    end

    update :update do
      accept [:vendor_id, :description, :amount, :interval, :next_due_on, :end_date, :notes, :status]
    end

    update :pause do
      change set_attribute(:status, :paused)
    end

    update :resume do
      change set_attribute(:status, :active)
    end

    update :stop do
      change set_attribute(:status, :stopped)
    end

    update :advance_schedule do
      accept [:next_due_on, :status]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :interval, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:weekly, :monthly, :quarterly, :semi_annually, :annually]
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? true
      constraints one_of: [:active, :paused, :stopped]
    end

    attribute :next_due_on, :date do
      allow_nil? false
      public? true
    end

    attribute :end_date, :date do
      allow_nil? true
      public? true
    end

    attribute :notes, :string do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :vendor, GnomeGarden.Finance.Vendor do
      allow_nil? false
      public? true
    end
  end
end
