defmodule GnomeGarden.Commercial.ServiceLevelPolicy do
  @moduledoc """
  Service response and resolution commitments attached to an agreement.

  Policies can be applied to tickets manually or by future automation based on
  severity, service type, or customer coverage terms.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :agreement_id,
      :organization_id,
      :name,
      :status,
      :severity,
      :coverage_mode,
      :response_target_minutes,
      :resolution_target_minutes
    ]
  end

  postgres do
    table "commercial_service_level_policies"
    repo GnomeGarden.Repo
    identity_index_names unique_severity_per_agreement: "cslp_agreement_severity_idx"

    references do
      reference :agreement, on_delete: :delete
      reference :organization, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :activate, from: :draft, to: :active
      transition :retire, from: [:draft, :active], to: :retired
      transition :reopen, from: :retired, to: :draft
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :agreement_id,
        :organization_id,
        :name,
        :description,
        :severity,
        :coverage_mode,
        :response_target_minutes,
        :resolution_target_minutes,
        :business_hours_timezone,
        :notes
      ]
    end

    update :update do
      accept [
        :agreement_id,
        :organization_id,
        :name,
        :description,
        :severity,
        :coverage_mode,
        :response_target_minutes,
        :resolution_target_minutes,
        :business_hours_timezone,
        :notes
      ]
    end

    update :activate do
      accept []
      change transition_state(:active)
    end

    update :retire do
      accept []
      change transition_state(:retired)
    end

    update :reopen do
      accept []
      change transition_state(:draft)
    end

    read :active do
      filter expr(status == :active)
      prepare build(
                sort: [severity: :desc, inserted_at: :asc],
                load: [:organization, :agreement, :tickets]
              )
    end

    read :for_agreement do
      argument :agreement_id, :uuid, allow_nil?: false
      filter expr(agreement_id == ^arg(:agreement_id))

      prepare build(
                sort: [severity: :desc, inserted_at: :asc],
                load: [:organization, :agreement, :tickets]
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

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true

      constraints one_of: [:draft, :active, :retired]
    end

    attribute :severity, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [:low, :normal, :high, :critical]
    end

    attribute :coverage_mode, :atom do
      allow_nil? false
      default :business_hours
      public? true

      constraints one_of: [:business_hours, :twenty_four_seven, :best_effort]
    end

    attribute :response_target_minutes, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :resolution_target_minutes, :integer do
      public? true
      constraints min: 1
    end

    attribute :business_hours_timezone, :string do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      allow_nil? false
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
      public? true
    end

    has_many :tickets, GnomeGarden.Execution.ServiceTicket do
      public? true
    end
  end

  identities do
    identity :unique_severity_per_agreement, [:agreement_id, :severity]
  end
end
