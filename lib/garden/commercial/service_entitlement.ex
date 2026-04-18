defmodule GnomeGarden.Commercial.ServiceEntitlement do
  @moduledoc """
  Included service capacity or allowance defined by an agreement.

  Entitlements model what a contract includes, such as support labor, onsite
  visits, inspections, or materials allowances, independent from how usage is
  later recorded and billed.
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
      :name,
      :status,
      :entitlement_type,
      :included_quantity,
      :quantity_unit,
      :renewal_cadence,
      :consumed_quantity
    ]
  end

  postgres do
    table "commercial_service_entitlements"
    repo GnomeGarden.Repo
    identity_index_names unique_name_per_agreement: "cse_agreement_name_idx"

    references do
      reference :agreement, on_delete: :delete
      reference :service_level_policy, on_delete: :nilify
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
        :service_level_policy_id,
        :name,
        :description,
        :entitlement_type,
        :quantity_unit,
        :included_quantity,
        :renewal_cadence,
        :carryover_mode,
        :overage_billing_model,
        :start_on,
        :end_on,
        :notes
      ]
    end

    update :update do
      accept [
        :agreement_id,
        :service_level_policy_id,
        :name,
        :description,
        :entitlement_type,
        :quantity_unit,
        :included_quantity,
        :renewal_cadence,
        :carryover_mode,
        :overage_billing_model,
        :start_on,
        :end_on,
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
                sort: [inserted_at: :asc],
                load: [:agreement, :service_level_policy, :usage_events]
              )
    end

    read :for_agreement do
      argument :agreement_id, :uuid, allow_nil?: false
      filter expr(agreement_id == ^arg(:agreement_id))

      prepare build(
                sort: [inserted_at: :asc],
                load: [:agreement, :service_level_policy, :usage_events]
              )
    end

    read :available_for_usage do
      argument :agreement_id, :uuid, allow_nil?: false
      argument :entitlement_type, :atom, allow_nil?: false
      argument :usage_on, :date, allow_nil?: false

      filter expr(
               agreement_id == ^arg(:agreement_id) and
                 status == :active and
                 entitlement_type == ^arg(:entitlement_type) and
                 (is_nil(start_on) or start_on <= ^arg(:usage_on)) and
                 (is_nil(end_on) or end_on >= ^arg(:usage_on))
             )

      prepare build(
                sort: [inserted_at: :asc],
                load: [:agreement, :service_level_policy]
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

    attribute :entitlement_type, :atom do
      allow_nil? false
      default :labor
      public? true

      constraints one_of: [
                    :labor,
                    :onsite_visit,
                    :inspection,
                    :monitoring,
                    :materials,
                    :ticket,
                    :other
                  ]
    end

    attribute :quantity_unit, :atom do
      allow_nil? false
      default :hour
      public? true

      constraints one_of: [:minute, :hour, :day, :visit, :ticket, :inspection, :usd, :other]
    end

    attribute :included_quantity, :decimal do
      allow_nil? false
      public? true
    end

    attribute :renewal_cadence, :atom do
      allow_nil? false
      default :contract_term
      public? true

      constraints one_of: [:none, :month, :quarter, :year, :contract_term]
    end

    attribute :carryover_mode, :atom do
      allow_nil? false
      default :none
      public? true

      constraints one_of: [:none, :period_only, :contract_term]
    end

    attribute :overage_billing_model, :atom do
      allow_nil? false
      default :bill_at_agreement_rate
      public? true

      constraints one_of: [
                    :included_only,
                    :bill_at_agreement_rate,
                    :bill_at_standard_rate,
                    :quote_required
                  ]
    end

    attribute :start_on, :date do
      public? true
    end

    attribute :end_on, :date do
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

    belongs_to :service_level_policy, GnomeGarden.Commercial.ServiceLevelPolicy do
      public? true
    end

    has_many :usage_events, GnomeGarden.Commercial.ServiceEntitlementUsage do
      public? true
    end
  end

  aggregates do
    count :usage_event_count, :usage_events do
      public? true
    end

    sum :consumed_quantity, :usage_events, :quantity do
      public? true
    end
  end

  identities do
    identity :unique_name_per_agreement, [:agreement_id, :name]
  end
end
