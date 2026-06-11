defmodule GnomeGarden.Finance.VendorBill do
  @moduledoc """
  A bill received from a vendor.

  Bills start as :draft, are approved, then marked paid.
  Posted entries to the GL happen automatically on approval.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  postgres do
    table "finance_vendor_bills"
    repo GnomeGarden.Repo

    references do
      reference :vendor, on_delete: :restrict
    end
  end

  policies do
    bypass always() do
      authorize_if always()
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :approve, from: :draft, to: :approved
      transition :mark_paid, from: :approved, to: :paid
      transition :void, from: [:draft, :approved], to: :voided
      transition :reopen, from: :voided, to: :draft
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:vendor_id, :issued_on, :due_on, :description, :total_amount, :notes]
      change GnomeGarden.Finance.Changes.GenerateBillNumber
    end

    update :update do
      primary? true
      accept [:vendor_id, :issued_on, :due_on, :description, :total_amount, :notes]
    end

    update :approve do
      require_atomic? false
      change transition_state(:approved)
    end

    update :mark_paid do
      require_atomic? false
      change transition_state(:paid)
    end

    update :void do
      require_atomic? false
      change transition_state(:voided)
    end

    update :reopen do
      require_atomic? false
      change transition_state(:draft)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :bill_number, :string do
      allow_nil? false
      public? true
    end

    attribute :issued_on, :date do
      allow_nil? false
      public? true
    end

    attribute :due_on, :date do
      public? true
    end

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :total_amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :approved, :paid, :voided]
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :vendor, GnomeGarden.Finance.Vendor do
      allow_nil? false
    end
  end
end
