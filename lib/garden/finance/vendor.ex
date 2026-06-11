defmodule GnomeGarden.Finance.Vendor do
  @moduledoc """
  A vendor (supplier) that issues bills to the company.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "finance_vendors"
    repo GnomeGarden.Repo
  end

  policies do
    bypass always() do
      authorize_if always()
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :email, :phone, :address, :payment_terms_days, :notes]
    end

    update :update do
      primary? true
      accept [:name, :email, :phone, :address, :payment_terms_days, :notes, :active]
    end

    update :deactivate do
      require_atomic? false
      change set_attribute(:active, false)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :email, :string do
      public? true
    end

    attribute :phone, :string do
      public? true
    end

    attribute :address, :string do
      public? true
    end

    attribute :payment_terms_days, :integer do
      default 30
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :bills, GnomeGarden.Finance.VendorBill
  end
end
