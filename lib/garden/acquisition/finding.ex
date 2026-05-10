defmodule GnomeGarden.Acquisition.Finding do
  @moduledoc """
  Unified raw intake record for agent-discovered work.

  Findings are reviewed before they become active commercial opportunities.
  This is the durable operator queue that procurement bids and discovery
  targets now converge on.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [
      :title,
      :finding_family,
      :finding_type,
      :status,
      :due_at,
      :location,
      :work_summary,
      :fit_score,
      :score_tier,
      :intent_score,
      :confidence
    ]
  end

  postgres do
    table "acquisition_findings"
    repo GnomeGarden.Repo

    custom_indexes do
      index [:finding_family, :status]
      index [:status, :observed_at]
      index [:signal_id]
    end

    references do
      reference :source, on_delete: :nilify
      reference :program, on_delete: :nilify
      reference :agent_run, on_delete: :nilify
      reference :organization, on_delete: :nilify
      reference :person, on_delete: :nilify
      reference :signal, on_delete: :nilify
      reference :source_bid, on_delete: :nilify
      reference :source_discovery_record, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:new]
    default_initial_state :new

    transitions do
      transition :start_review, from: [:new], to: :reviewing
      transition :accept, from: [:reviewing], to: :accepted
      transition :reject, from: [:reviewing, :accepted, :parked], to: :rejected

      transition :suppress,
        from: [:reviewing, :accepted, :parked, :rejected],
        to: :suppressed

      transition :park, from: [:reviewing, :accepted, :rejected], to: :parked
      transition :reopen, from: [:rejected, :suppressed, :parked], to: :new
      transition :promote, from: [:accepted], to: :promoted
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :title,
        :summary,
        :external_ref,
        :source_url,
        :finding_family,
        :finding_type,
        :status,
        :due_at,
        :due_note,
        :location,
        :location_note,
        :work_summary,
        :work_type,
        :work_note,
        :fit_score,
        :score_tier,
        :score_note,
        :intent_score,
        :confidence,
        :recommendation,
        :watchouts,
        :observed_at,
        :reviewed_at,
        :promoted_at,
        :metadata,
        :source_id,
        :program_id,
        :agent_run_id,
        :organization_id,
        :person_id,
        :signal_id,
        :source_bid_id,
        :source_discovery_record_id
      ]
    end

    update :update do
      accept [
        :title,
        :summary,
        :source_url,
        :finding_family,
        :finding_type,
        :status,
        :due_at,
        :due_note,
        :location,
        :location_note,
        :work_summary,
        :work_type,
        :work_note,
        :fit_score,
        :score_tier,
        :score_note,
        :intent_score,
        :confidence,
        :recommendation,
        :watchouts,
        :observed_at,
        :reviewed_at,
        :promoted_at,
        :metadata,
        :source_id,
        :program_id,
        :agent_run_id,
        :organization_id,
        :person_id,
        :signal_id,
        :source_bid_id,
        :source_discovery_record_id
      ]
    end

    update :start_review do
      public? false
      accept []
      change transition_state(:reviewing)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :accept do
      public? false
      require_atomic? false
      accept []
      change {GnomeGarden.Acquisition.Changes.RequireAcceptanceReady, []}
      change transition_state(:accepted)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :reject do
      public? false
      accept []
      change transition_state(:rejected)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :suppress do
      public? false
      accept []
      change transition_state(:suppressed)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :park do
      public? false
      accept []
      change transition_state(:parked)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    update :reopen do
      public? false
      accept []
      change transition_state(:new)
    end

    update :promote do
      public? false
      require_atomic? false
      accept [:signal_id]
      change {GnomeGarden.Acquisition.Changes.RequirePromotionReady, []}
      change transition_state(:promoted)
      change set_attribute(:promoted_at, &DateTime.utc_now/0)
      change set_attribute(:reviewed_at, &DateTime.utc_now/0)
    end

    read :review_queue do
      filter expr(status in [:new, :reviewing, :accepted])

      prepare build(
                sort: [
                  intent_score: :desc,
                  fit_score: :desc,
                  observed_at: :desc,
                  inserted_at: :desc
                ],
                load: [
                  :status_variant,
                  :score_tier_variant,
                  :due_status_label,
                  :acceptance_ready,
                  :acceptance_blockers,
                  :latest_review_decision,
                  :latest_review_reason,
                  :latest_review_decision_at,
                  :promotion_ready,
                  :promotion_blockers,
                  :source,
                  :program,
                  :organization,
                  :signal
                ]
              )
    end

    read :for_program do
      argument :program_id, :uuid, allow_nil?: false
      filter expr(program_id == ^arg(:program_id))

      prepare build(
                sort: [observed_at: :desc, inserted_at: :desc],
                load: [
                  :status_variant,
                  :score_tier_variant,
                  :due_status_label,
                  :acceptance_ready,
                  :acceptance_blockers,
                  :latest_review_decision,
                  :latest_review_reason,
                  :latest_review_decision_at,
                  :promotion_ready,
                  :promotion_blockers,
                  :organization,
                  :signal,
                  :source
                ]
              )
    end

    read :promoted do
      filter expr(status == :promoted)

      prepare build(
                sort: [promoted_at: :desc, reviewed_at: :desc, updated_at: :desc],
                load: [
                  :status_variant,
                  :score_tier_variant,
                  :due_status_label,
                  :latest_review_decision,
                  :latest_review_reason,
                  :latest_review_decision_at,
                  :promotion_ready,
                  :promotion_blockers,
                  :signal,
                  :organization
                ]
              )
    end

    read :rejected do
      filter expr(status == :rejected)

      prepare build(
                sort: [updated_at: :desc],
                load: [
                  :status_variant,
                  :score_tier_variant,
                  :due_status_label,
                  :latest_review_decision,
                  :latest_review_reason,
                  :latest_review_decision_at,
                  :organization
                ]
              )
    end

    read :suppressed do
      filter expr(status == :suppressed)

      prepare build(
                sort: [updated_at: :desc],
                load: [
                  :status_variant,
                  :score_tier_variant,
                  :due_status_label,
                  :latest_review_decision,
                  :latest_review_reason,
                  :latest_review_decision_at,
                  :organization
                ]
              )
    end

    read :parked do
      filter expr(status == :parked)

      prepare build(
                sort: [updated_at: :desc],
                load: [
                  :status_variant,
                  :score_tier_variant,
                  :due_status_label,
                  :latest_review_decision,
                  :latest_review_reason,
                  :latest_review_decision_at,
                  :organization
                ]
              )
    end

    read :by_external_ref do
      argument :external_ref, :string, allow_nil?: false
      get_by [:external_ref]
    end

    read :by_source_bid do
      argument :source_bid_id, :uuid, allow_nil?: false
      get? true
      filter expr(source_bid_id == ^arg(:source_bid_id))
      prepare build(sort: [updated_at: :desc, inserted_at: :desc], limit: 1)
    end

    read :by_source_discovery_record do
      argument :source_discovery_record_id, :uuid, allow_nil?: false
      get? true
      filter expr(source_discovery_record_id == ^arg(:source_discovery_record_id))
      prepare build(sort: [updated_at: :desc, inserted_at: :desc], limit: 1)
    end

    read :by_signal do
      argument :signal_id, :uuid, allow_nil?: false
      get? true
      filter expr(signal_id == ^arg(:signal_id))
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "finding"

    publish :create, "created"
    publish :update, "updated"
    publish :start_review, "updated"
    publish :accept, "updated"
    publish :reject, "updated"
    publish :suppress, "updated"
    publish :park, "updated"
    publish :reopen, "updated"
    publish :promote, "updated"
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :summary, :string do
      public? true
    end

    attribute :external_ref, :string do
      allow_nil? false
      public? true
    end

    attribute :source_url, :string do
      public? true
    end

    attribute :finding_family, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:procurement, :discovery, :research, :operations, :other]
    end

    attribute :finding_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :bid_notice,
                    :company_signal,
                    :hiring_signal,
                    :expansion_signal,
                    :contact_signal,
                    :integrator_request,
                    :research_note,
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
                    :suppressed,
                    :parked,
                    :promoted
                  ]
    end

    attribute :due_at, :utc_datetime do
      public? true
    end

    attribute :due_note, :string do
      public? true
    end

    attribute :location, :string do
      public? true
    end

    attribute :location_note, :string do
      public? true
    end

    attribute :work_summary, :string do
      public? true
    end

    attribute :work_type, :string do
      public? true
    end

    attribute :work_note, :string do
      public? true
    end

    attribute :fit_score, :integer do
      public? true
      constraints min: 0, max: 100
    end

    attribute :score_tier, :atom do
      public? true
      constraints one_of: [:hot, :warm, :prospect]
    end

    attribute :score_note, :string do
      public? true
    end

    attribute :intent_score, :integer do
      public? true
      constraints min: 0, max: 100
    end

    attribute :confidence, :atom do
      public? true
      constraints one_of: [:low, :medium, :high]
    end

    attribute :recommendation, :string do
      public? true
    end

    attribute :watchouts, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :observed_at, :utc_datetime do
      public? true
    end

    attribute :reviewed_at, :utc_datetime do
      public? true
    end

    attribute :promoted_at, :utc_datetime do
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source_discovery_record_id, :uuid do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :source, GnomeGarden.Acquisition.Source do
      public? true
    end

    belongs_to :program, GnomeGarden.Acquisition.Program do
      public? true
    end

    belongs_to :agent_run, GnomeGarden.Agents.AgentRun do
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
    end

    belongs_to :person, GnomeGarden.Operations.Person do
      public? true
    end

    belongs_to :signal, GnomeGarden.Commercial.Signal do
      public? true
    end

    belongs_to :source_bid, GnomeGarden.Procurement.Bid do
      public? true
    end

    belongs_to :source_discovery_record, GnomeGarden.Commercial.DiscoveryRecord do
      source_attribute :source_discovery_record_id
      public? true
    end

    has_many :review_decisions, GnomeGarden.Acquisition.FindingReviewDecision do
      destination_attribute :finding_id
      public? true
    end

    has_many :finding_documents, GnomeGarden.Acquisition.FindingDocument do
      destination_attribute :finding_id
      public? true
    end

    many_to_many :documents, GnomeGarden.Acquisition.Document do
      through GnomeGarden.Acquisition.FindingDocument
      source_attribute_on_join_resource :finding_id
      destination_attribute_on_join_resource :document_id
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
                 suppressed: :warning,
                 parked: :warning,
                 promoted: :success
               ],
               default: :default}

    calculate :score_tier_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :score_tier,
               mapping: [
                 hot: :error,
                 warm: :warning,
                 prospect: :info
               ],
               default: :default}

    calculate :due_status_label,
              :string,
              expr(
                cond do
                  is_nil(due_at) -> nil
                  due_at < ^DateTime.utc_now() -> "Past due"
                  not is_nil(due_note) -> due_note
                  true -> "Upcoming"
                end
              )

    calculate :acceptance_ready,
              :boolean,
              {GnomeGarden.Calculations.AcquisitionAcceptanceReadiness, return: :ready}

    calculate :acceptance_blockers,
              {:array, :string},
              {GnomeGarden.Calculations.AcquisitionAcceptanceReadiness, return: :blockers}

    calculate :promotion_ready,
              :boolean,
              {GnomeGarden.Calculations.AcquisitionPromotionReadiness, return: :ready}

    calculate :promotion_blockers,
              {:array, :string},
              {GnomeGarden.Calculations.AcquisitionPromotionReadiness, return: :blockers}
  end

  aggregates do
    count :review_decision_count, :review_decisions do
      public? true
    end

    count :document_count, :finding_documents do
      public? true
    end

    count :promotion_document_count, :documents do
      filter expr(document_type in [:solicitation, :scope, :pricing, :addendum])

      public? true
    end

    first :latest_review_decision, :review_decisions, :decision do
      sort recorded_at: :desc
      public? true
    end

    first :latest_review_reason, :review_decisions, :reason do
      sort recorded_at: :desc
      public? true
    end

    first :latest_review_decision_at, :review_decisions, :recorded_at do
      sort recorded_at: :desc
      public? true
    end
  end

  identities do
    identity :unique_external_ref, [:external_ref]
    identity :unique_source_bid, [:source_bid_id]
    identity :unique_source_discovery_record, [:source_discovery_record_id]
  end
end
