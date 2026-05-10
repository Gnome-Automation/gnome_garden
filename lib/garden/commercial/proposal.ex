defmodule GnomeGarden.Commercial.Proposal do
  @moduledoc """
  Commercial proposal or estimate prepared for a pursuit.

  Proposals sit between internal pursuit qualification and signed agreements,
  allowing Gnome to track issued quotes, revisions, acceptance, and expiry.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :proposal_number,
      :pursuit_id,
      :name,
      :status,
      :revision_number,
      :valid_until_on,
      :total_amount
    ]
  end

  postgres do
    table "commercial_proposals"
    repo GnomeGarden.Repo

    references do
      reference :pursuit, on_delete: :delete
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :owner_team_member, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :issue, from: [:draft, :expired, :rejected], to: :issued
      transition :accept, from: :issued, to: :accepted
      transition :reject, from: :issued, to: :rejected
      transition :expire, from: :issued, to: :expired
      transition :supersede, from: [:draft, :issued, :rejected, :expired], to: :superseded
      transition :reopen, from: [:rejected, :expired, :superseded], to: :draft
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :pursuit_id,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_team_member_id,
        :proposal_number,
        :name,
        :description,
        :revision_number,
        :pricing_model,
        :currency_code,
        :valid_until_on,
        :delivery_model,
        :notes
      ]
    end

    update :update do
      accept [
        :pursuit_id,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_team_member_id,
        :proposal_number,
        :name,
        :description,
        :revision_number,
        :pricing_model,
        :currency_code,
        :valid_until_on,
        :delivery_model,
        :notes
      ]
    end

    update :issue do
      accept []
      change transition_state(:issued)
      change set_attribute(:issued_on, &Date.utc_today/0)
    end

    update :accept do
      accept []
      change transition_state(:accepted)
      change set_attribute(:accepted_on, &Date.utc_today/0)
    end

    update :reject do
      accept [:notes]
      change transition_state(:rejected)
    end

    update :expire do
      accept []
      change transition_state(:expired)
    end

    update :supersede do
      accept []
      change transition_state(:superseded)
    end

    update :reopen do
      accept []
      change transition_state(:draft)
      change set_attribute(:accepted_on, nil)
    end

    read :active do
      filter expr(status in [:draft, :issued, :accepted])

      prepare build(
                sort: [valid_until_on: :asc, inserted_at: :desc],
                load: [:pursuit, :organization, :proposal_lines, :agreements]
              )
    end

    read :for_pursuit do
      argument :pursuit_id, :uuid, allow_nil?: false
      filter expr(pursuit_id == ^arg(:pursuit_id))

      prepare build(
                sort: [revision_number: :desc, inserted_at: :desc],
                load: [:pursuit, :organization, :proposal_lines, :agreements]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :proposal_number, :string do
      allow_nil? false
      public? true
    end

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

      constraints one_of: [:draft, :issued, :accepted, :rejected, :expired, :superseded]
    end

    attribute :revision_number, :integer do
      allow_nil? false
      default 1
      public? true
      constraints min: 1
    end

    attribute :pricing_model, :atom do
      allow_nil? false
      default :fixed_fee
      public? true

      constraints one_of: [:fixed_fee, :time_and_materials, :retainer, :milestone, :unit, :mixed]
    end

    attribute :currency_code, :string do
      allow_nil? false
      default "USD"
      public? true
    end

    attribute :valid_until_on, :date do
      public? true
    end

    attribute :issued_on, :date do
      public? true
    end

    attribute :accepted_on, :date do
      public? true
    end

    attribute :delivery_model, :atom do
      allow_nil? false
      default :project
      public? true

      constraints one_of: [:project, :service, :maintenance, :retainer, :mixed]
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :pursuit, GnomeGarden.Commercial.Pursuit do
      allow_nil? false
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

    belongs_to :owner_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    has_many :proposal_lines, GnomeGarden.Commercial.ProposalLine do
      public? true
    end

    has_many :agreements, GnomeGarden.Commercial.Agreement do
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 draft: :default,
                 issued: :warning,
                 accepted: :success,
                 rejected: :error,
                 expired: :warning,
                 superseded: :default
               ],
               default: :default}
  end

  aggregates do
    count :line_count, :proposal_lines do
      public? true
    end

    count :agreement_count, :agreements do
      public? true
    end

    sum :total_amount, :proposal_lines, :line_total do
      public? true
    end
  end

  identities do
    identity :unique_proposal_number, [:proposal_number]
  end
end
