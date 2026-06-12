defmodule GnomeGarden.Finance.Retainer do
  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [GnomeGarden.Finance.Notifiers.RetainerGLNotifier]

  admin do
    table_columns [:id, :retainer_number, :organization_id, :amount, :status, :auto_apply, :received_on]
  end

  postgres do
    table "finance_retainers"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :issue, from: :draft, to: :issued
      transition :mark_paid, from: :issued, to: :paid
      transition :exhaust, from: :paid, to: :exhausted
      transition :reopen, from: :exhausted, to: :paid
      transition :void, from: [:draft, :issued, :paid], to: :void
    end
  end

  policies do
    bypass action_type(:read) do
      authorize_if always()
    end

    bypass action_type(:create) do
      authorize_if always()
    end

    bypass action_type(:update) do
      authorize_if always()
    end

    bypass action_type(:destroy) do
      authorize_if always()
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:organization_id, :amount, :auto_apply, :received_on, :notes]
      change GnomeGarden.Finance.Changes.GenerateRetainerNumber
    end

    update :update do
      accept [:organization_id, :amount, :auto_apply, :received_on, :notes]
    end

    update :issue do
      accept []
      change transition_state(:issued)
    end

    update :mark_paid do
      accept []
      change transition_state(:paid)
    end

    update :exhaust do
      accept []
      change transition_state(:exhausted)
    end

    update :reopen do
      accept []
      change transition_state(:paid)
    end

    update :void do
      accept []
      change transition_state(:void)
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [inserted_at: :desc], load: [:organization, :applications])
    end

    read :available_for_organization do
      description "Paid retainers with remaining balance > 0"
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id) and status == :paid)
      prepare build(load: [:balance_amount])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :retainer_number, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :issued, :paid, :exhausted, :void]
    end

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :auto_apply, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :received_on, :date do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end

    has_many :applications, GnomeGarden.Finance.RetainerApplication do
      public? true
    end
  end

  aggregates do
    sum :applied_amount, :applications, :amount do
      public? true
      default Decimal.new("0")
    end
  end

  calculations do
    calculate :balance_amount, :decimal, expr(amount - applied_amount) do
      public? true
    end

    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 draft: :default,
                 issued: :info,
                 paid: :success,
                 exhausted: :default,
                 void: :error
               ],
               default: :default}
  end
end
