defmodule GnomeGarden.Commercial.ChangeOrder do
  @moduledoc """
  Post-award commercial amendment attached to an agreement.

  Change orders capture scope, schedule, or pricing deltas after award without
  overwriting the original proposal or agreement intent.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :change_order_number,
      :agreement_id,
      :project_id,
      :title,
      :status,
      :change_type,
      :requested_on,
      :approved_on,
      :total_amount
    ]
  end

  postgres do
    table "commercial_change_orders"
    repo GnomeGarden.Repo

    references do
      reference :agreement, on_delete: :delete
      reference :project, on_delete: :nilify
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :owner_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :submit, from: [:draft, :rejected], to: :submitted
      transition :approve, from: :submitted, to: :approved
      transition :reject, from: :submitted, to: :rejected
      transition :implement, from: :approved, to: :implemented
      transition :cancel, from: [:draft, :submitted, :approved], to: :cancelled
      transition :reopen, from: [:rejected, :cancelled], to: :draft
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :agreement_id,
        :project_id,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_user_id,
        :change_order_number,
        :title,
        :description,
        :change_type,
        :pricing_model,
        :requested_on,
        :effective_on,
        :schedule_impact_days,
        :notes
      ]
    end

    update :update do
      accept [
        :agreement_id,
        :project_id,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_user_id,
        :change_order_number,
        :title,
        :description,
        :change_type,
        :pricing_model,
        :requested_on,
        :effective_on,
        :schedule_impact_days,
        :notes
      ]
    end

    update :submit do
      accept []
      change transition_state(:submitted)
    end

    update :approve do
      accept []
      change transition_state(:approved)
      change set_attribute(:approved_on, &Date.utc_today/0)
    end

    update :reject do
      accept [:notes]
      change transition_state(:rejected)
      change set_attribute(:approved_on, nil)
    end

    update :implement do
      accept []
      change transition_state(:implemented)
      change set_attribute(:implemented_on, &Date.utc_today/0)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
      accept []
      change transition_state(:draft)
      change set_attribute(:approved_on, nil)
      change set_attribute(:implemented_on, nil)
    end

    read :active do
      filter expr(status in [:draft, :submitted, :approved])

      prepare build(
                sort: [requested_on: :desc, inserted_at: :desc],
                load: [:agreement, :project, :organization, :change_order_lines]
              )
    end

    read :for_agreement do
      argument :agreement_id, :uuid, allow_nil?: false
      filter expr(agreement_id == ^arg(:agreement_id))

      prepare build(
                sort: [requested_on: :desc, inserted_at: :desc],
                load: [:agreement, :project, :organization, :change_order_lines]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :change_order_number, :string do
      allow_nil? false
      public? true
    end

    attribute :title, :string do
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

      constraints one_of: [:draft, :submitted, :approved, :rejected, :implemented, :cancelled]
    end

    attribute :change_type, :atom do
      allow_nil? false
      default :scope_addition
      public? true

      constraints one_of: [
                    :scope_addition,
                    :scope_reduction,
                    :substitution,
                    :schedule_change,
                    :rate_change,
                    :allowance_draw,
                    :other
                  ]
    end

    attribute :pricing_model, :atom do
      allow_nil? false
      default :fixed_fee
      public? true

      constraints one_of: [:fixed_fee, :time_and_materials, :retainer, :milestone, :unit, :mixed]
    end

    attribute :requested_on, :date do
      public? true
    end

    attribute :approved_on, :date do
      public? true
    end

    attribute :implemented_on, :date do
      public? true
    end

    attribute :effective_on, :date do
      public? true
    end

    attribute :schedule_impact_days, :integer do
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

    belongs_to :project, GnomeGarden.Execution.Project do
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

    has_many :change_order_lines, GnomeGarden.Commercial.ChangeOrderLine do
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
                 submitted: :warning,
                 approved: :success,
                 rejected: :error,
                 implemented: :info,
                 cancelled: :default
               ],
               default: :default}
  end

  aggregates do
    count :line_count, :change_order_lines do
      public? true
    end

    sum :total_amount, :change_order_lines, :line_total do
      public? true
    end
  end

  identities do
    identity :unique_change_order_number, [:change_order_number]
  end
end
