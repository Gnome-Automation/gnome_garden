defmodule GnomeGarden.Commercial.Pursuit do
  @moduledoc """
  Internal revenue pursuit for a concrete business opportunity.

  Pursuits turn qualified signals into forecastable pipeline and eventually
  won or lost commercial outcomes.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :name,
      :pursuit_type,
      :stage,
      :priority,
      :probability,
      :target_value,
      :expected_close_on,
      :inserted_at
    ]
  end

  postgres do
    table "commercial_pursuits"
    repo GnomeGarden.Repo

    references do
      reference :signal, on_delete: :nilify
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :owner_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :stage
    initial_states [:new]
    default_initial_state :new

    transitions do
      transition :qualify, from: [:new, :reopened], to: :qualified
      transition :estimate, from: :qualified, to: :estimating
      transition :propose, from: [:qualified, :estimating], to: :proposed
      transition :negotiate, from: :proposed, to: :negotiating
      transition :mark_won, from: [:proposed, :negotiating], to: :won
      transition :mark_lost, from: [:qualified, :estimating, :proposed, :negotiating], to: :lost
      transition :archive, from: :*, to: :archived
      transition :reopen, from: [:lost, :archived], to: :reopened
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :signal_id,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_user_id,
        :name,
        :description,
        :pursuit_type,
        :priority,
        :probability,
        :target_value,
        :expected_close_on,
        :delivery_model,
        :billing_model,
        :notes
      ]
    end

    update :update do
      accept [
        :signal_id,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_user_id,
        :name,
        :description,
        :pursuit_type,
        :priority,
        :probability,
        :target_value,
        :expected_close_on,
        :delivery_model,
        :billing_model,
        :notes
      ]
    end

    update :qualify do
      accept []
      change transition_state(:qualified)
    end

    update :estimate do
      accept []
      change transition_state(:estimating)
    end

    update :propose do
      accept []
      change transition_state(:proposed)
    end

    update :negotiate do
      accept []
      change transition_state(:negotiating)
    end

    update :mark_won do
      accept []
      change transition_state(:won)
      change set_attribute(:probability, 100)
    end

    update :mark_lost do
      accept []
      change transition_state(:lost)
      change set_attribute(:probability, 0)
    end

    update :archive do
      accept []
      change transition_state(:archived)
    end

    update :reopen do
      accept []
      change transition_state(:reopened)
    end

    read :active do
      filter expr(stage in [:new, :qualified, :estimating, :proposed, :negotiating, :reopened])

      prepare build(
                sort: [expected_close_on: :asc, inserted_at: :desc],
                load: [:organization, :site, :proposals]
              )
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))

      prepare build(
                sort: [expected_close_on: :asc, inserted_at: :desc],
                load: [:organization, :site, :proposals]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :pursuit_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :new_logo,
                    :existing_account,
                    :bid_response,
                    :change_order,
                    :renewal,
                    :service_expansion,
                    :other
                  ]
    end

    attribute :stage, :atom do
      allow_nil? false
      default :new
      public? true

      constraints one_of: [
                    :new,
                    :qualified,
                    :estimating,
                    :proposed,
                    :negotiating,
                    :won,
                    :lost,
                    :archived,
                    :reopened
                  ]
    end

    attribute :priority, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [:low, :normal, :high, :strategic]
    end

    attribute :probability, :integer do
      allow_nil? false
      default 10
      public? true
      constraints min: 0, max: 100
    end

    attribute :target_value, :decimal do
      public? true
    end

    attribute :expected_close_on, :date do
      public? true
    end

    attribute :delivery_model, :atom do
      allow_nil? false
      default :project
      public? true

      constraints one_of: [
                    :project,
                    :service,
                    :maintenance,
                    :retainer,
                    :mixed
                  ]
    end

    attribute :billing_model, :atom do
      allow_nil? false
      default :fixed_fee
      public? true

      constraints one_of: [
                    :fixed_fee,
                    :time_and_materials,
                    :retainer,
                    :milestone,
                    :unit,
                    :mixed
                  ]
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :signal, GnomeGarden.Commercial.Signal do
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end

    belongs_to :site, GnomeGarden.Operations.Site do
      public? true
    end

    belongs_to :managed_system, GnomeGarden.Operations.ManagedSystem do
      public? true
    end

    belongs_to :owner_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :agreements, GnomeGarden.Commercial.Agreement do
      public? true
    end

    has_many :proposals, GnomeGarden.Commercial.Proposal do
      public? true
    end
  end

  calculations do
    calculate :weighted_value, :decimal, expr(target_value * probability / 100)
  end

  aggregates do
    count :proposal_count, :proposals do
      public? true
    end
  end
end
