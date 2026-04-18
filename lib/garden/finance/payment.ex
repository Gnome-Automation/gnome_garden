defmodule GnomeGarden.Finance.Payment do
  @moduledoc """
  Operational record of received customer money.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :payment_number,
      :organization_id,
      :status,
      :received_on,
      :payment_method,
      :amount
    ]
  end

  postgres do
    table "finance_payments"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :agreement, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:received]
    default_initial_state :received

    transitions do
      transition :deposit, from: :received, to: :deposited
      transition :reverse, from: [:received, :deposited], to: :reversed
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :organization_id,
        :agreement_id,
        :payment_number,
        :payment_method,
        :received_on,
        :currency_code,
        :amount,
        :reference,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :agreement_id,
        :payment_number,
        :payment_method,
        :received_on,
        :currency_code,
        :amount,
        :reference,
        :notes
      ]
    end

    update :deposit do
      accept []
      change transition_state(:deposited)
      change set_attribute(:deposited_on, &Date.utc_today/0)
    end

    update :reverse do
      accept []
      change transition_state(:reversed)
      change set_attribute(:reversed_on, &Date.utc_today/0)
    end

    read :open do
      filter expr(status in [:received, :deposited])
      prepare build(sort: [received_on: :desc, inserted_at: :desc], load: [:organization, :applications])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :payment_number, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :received
      public? true

      constraints one_of: [:received, :deposited, :reversed]
    end

    attribute :payment_method, :atom do
      allow_nil? false
      default :ach
      public? true

      constraints one_of: [:ach, :wire, :check, :card, :cash, :other]
    end

    attribute :received_on, :date do
      allow_nil? false
      public? true
    end

    attribute :deposited_on, :date do
      public? true
    end

    attribute :reversed_on, :date do
      public? true
    end

    attribute :currency_code, :string do
      allow_nil? false
      default "USD"
      public? true
    end

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :reference, :string do
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

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      public? true
    end

    has_many :applications, GnomeGarden.Finance.PaymentApplication do
      public? true
    end
  end
end
