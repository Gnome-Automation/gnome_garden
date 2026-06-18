defmodule GnomeGarden.Banking.BankRule do
  @moduledoc """
  A categorization rule applied to bank transactions during reconciliation. When
  a transaction's `match_field` satisfies `match_type`/`match_value`, the rule
  assigns `set_category`. Rules are evaluated in `priority` order (lowest first);
  the first matching enabled rule wins.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Banking,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :name, :priority, :match_field, :match_type, :match_value, :set_category, :enabled?]
  end

  postgres do
    table "banking_rules"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:name, :priority, :match_field, :match_type, :match_value, :set_category, :enabled?]
    end

    update :update do
      accept [:name, :priority, :match_field, :match_type, :match_value, :set_category, :enabled?]
    end

    update :enable do
      accept []
      change set_attribute(:enabled?, true)
    end

    update :disable do
      accept []
      change set_attribute(:enabled?, false)
    end

    destroy :destroy do
    end

    read :sorted do
      filter expr(enabled? == true)
      prepare build(sort: [priority: :asc, inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :priority, :integer do
      allow_nil? false
      default 100
      public? true
    end

    attribute :match_field, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:counterparty_name, :description]
    end

    attribute :match_type, :atom do
      allow_nil? false
      default :contains
      public? true
      constraints one_of: [:contains, :equals, :starts_with]
    end

    attribute :match_value, :string do
      allow_nil? false
      public? true
    end

    attribute :set_category, :string do
      allow_nil? false
      public? true
    end

    attribute :enabled?, :boolean do
      allow_nil? false
      default true
      public? true
    end

    timestamps()
  end
end
