defmodule GnomeGarden.Commercial.Signal do
  @moduledoc """
  Raw business signal that may justify commercial follow-up.

  Signals capture bids, inbound requests, promoted discovery findings,
  referrals, renewal cues, or service-driven expansion opportunities before
  Gnome commits to a formal pursuit.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :title,
      :signal_type,
      :source_channel,
      :status,
      :organization_id,
      :observed_at,
      :inserted_at
    ]
  end

  postgres do
    table "commercial_signals"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :nilify
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :owner_team_member, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:new]
    default_initial_state :new

    transitions do
      transition :start_review, from: :new, to: :reviewing
      transition :accept, from: [:new, :reviewing], to: :accepted
      transition :reject, from: [:new, :reviewing], to: :rejected
      transition :convert, from: :accepted, to: :converted
      transition :archive, from: :*, to: :archived
      transition :reopen, from: [:rejected, :archived], to: :new
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :title,
        :description,
        :signal_type,
        :source_channel,
        :external_ref,
        :source_url,
        :observed_at,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_team_member_id,
        :notes,
        :metadata
      ]
    end

    create :create_from_bid do
      argument :source_bid_id, :uuid, allow_nil?: false

      accept [
        :title,
        :description,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_team_member_id,
        :notes,
        :metadata
      ]

      change {GnomeGarden.Commercial.Changes.CreateSignalFromBid, []}
    end

    update :update do
      accept [
        :title,
        :description,
        :signal_type,
        :source_channel,
        :external_ref,
        :source_url,
        :observed_at,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_team_member_id,
        :notes,
        :metadata
      ]
    end

    update :start_review do
      accept []
      change transition_state(:reviewing)
    end

    update :accept do
      accept []
      change transition_state(:accepted)
    end

    update :reject do
      accept [:notes]
      change transition_state(:rejected)
    end

    update :convert do
      accept []
      change transition_state(:converted)
    end

    update :archive do
      accept []
      change transition_state(:archived)
    end

    update :reopen do
      accept []
      change transition_state(:new)
    end

    read :review_queue do
      filter expr(status in [:new, :reviewing, :accepted])

      prepare build(sort: [observed_at: :desc, inserted_at: :desc], load: [:organization, :site])
    end

    read :by_external_ref do
      argument :external_ref, :string, allow_nil?: false
      get_by [:external_ref]
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [observed_at: :desc, inserted_at: :desc], load: [:organization, :site])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :signal_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :bid_notice,
                    :inbound_request,
                    :outbound_target,
                    :referral,
                    :renewal,
                    :service_need,
                    :market_signal,
                    :other
                  ]
    end

    attribute :source_channel, :atom do
      allow_nil? false
      default :manual
      public? true

      constraints one_of: [
                    :procurement_portal,
                    :website,
                    :email,
                    :phone,
                    :referral,
                    :agent_discovery,
                    :service_event,
                    :manual,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :new
      public? true

      constraints one_of: [
                    :new,
                    :reviewing,
                    :accepted,
                    :rejected,
                    :converted,
                    :archived
                  ]
    end

    attribute :external_ref, :string do
      public? true
    end

    attribute :source_url, :string do
      public? true
    end

    attribute :observed_at, :utc_datetime do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, GnomeGarden.Operations.Organization do
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

    has_many :pursuits, GnomeGarden.Commercial.Pursuit do
      public? true
    end

    has_one :procurement_bid, GnomeGarden.Procurement.Bid do
      destination_attribute :signal_id
      public? true
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 new: :default,
                 reviewing: :info,
                 accepted: :success,
                 rejected: :error,
                 converted: :success,
                 archived: :warning
               ],
               default: :default}
  end
end
