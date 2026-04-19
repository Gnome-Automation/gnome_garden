defmodule GnomeGarden.Finance.Expense do
  @moduledoc """
  Non-labor cost incurred against customer or internal work.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :incurred_on,
      :organization_id,
      :project_id,
      :work_order_id,
      :category,
      :amount,
      :status
    ]
  end

  postgres do
    table "finance_expenses"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :agreement, on_delete: :nilify
      reference :project, on_delete: :nilify
      reference :work_order, on_delete: :nilify
      reference :incurred_by_user, on_delete: :nilify
      reference :approved_by_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :submit, from: :draft, to: :submitted
      transition :approve, from: :submitted, to: :approved
      transition :reject, from: :submitted, to: :rejected
      transition :mark_billed, from: :approved, to: :billed
      transition :reopen, from: [:rejected, :approved], to: :draft
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :organization_id,
        :agreement_id,
        :project_id,
        :work_order_id,
        :incurred_by_user_id,
        :incurred_on,
        :category,
        :description,
        :amount,
        :vendor,
        :receipt_url,
        :billable,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :agreement_id,
        :project_id,
        :work_order_id,
        :incurred_by_user_id,
        :incurred_on,
        :category,
        :description,
        :amount,
        :vendor,
        :receipt_url,
        :billable,
        :notes
      ]
    end

    update :submit do
      accept []
      change transition_state(:submitted)
    end

    update :approve do
      require_atomic? false
      accept [:approved_by_user_id]
      change transition_state(:approved)
      change set_attribute(:approved_at, &DateTime.utc_now/0)
      change {GnomeGarden.Commercial.Changes.SyncExpenseEntitlementUsage, mode: :sync}
    end

    update :reject do
      require_atomic? false
      accept [:notes]
      change transition_state(:rejected)
      change {GnomeGarden.Commercial.Changes.SyncExpenseEntitlementUsage, mode: :clear}
    end

    update :mark_billed do
      accept []
      change transition_state(:billed)
      change set_attribute(:billed_at, &DateTime.utc_now/0)
    end

    update :reopen do
      require_atomic? false
      accept []
      change transition_state(:draft)
      change set_attribute(:approved_at, nil)
      change set_attribute(:approved_by_user_id, nil)
      change set_attribute(:billed_at, nil)
      change {GnomeGarden.Commercial.Changes.SyncExpenseEntitlementUsage, mode: :clear}
    end

    read :open do
      filter expr(status in [:draft, :submitted, :approved])

      prepare build(
                sort: [incurred_on: :desc, inserted_at: :desc],
                load: [:project, :work_order]
              )
    end

    read :billable_for_agreement do
      argument :agreement_id, :uuid, allow_nil?: false

      filter expr(
               agreement_id == ^arg(:agreement_id) and
                 status == :approved and
                 billable == true
             )

      prepare build(
                sort: [incurred_on: :asc, inserted_at: :asc],
                load: [:project, :work_order]
              )
    end

    read :approved_unbilled do
      filter expr(status == :approved)

      prepare build(
                sort: [incurred_on: :desc, inserted_at: :desc],
                load: [:organization, :project, :work_order]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :incurred_on, :date do
      allow_nil? false
      public? true
    end

    attribute :category, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :travel,
                    :lodging,
                    :meals,
                    :materials,
                    :equipment,
                    :software,
                    :other
                  ]
    end

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :vendor, :string do
      public? true
    end

    attribute :receipt_url, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true

      constraints one_of: [
                    :draft,
                    :submitted,
                    :approved,
                    :rejected,
                    :billed
                  ]
    end

    attribute :billable, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :approved_at, :utc_datetime do
      public? true
    end

    attribute :billed_at, :utc_datetime do
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

    belongs_to :project, GnomeGarden.Execution.Project do
      public? true
    end

    belongs_to :work_order, GnomeGarden.Execution.WorkOrder do
      public? true
    end

    belongs_to :incurred_by_user, GnomeGarden.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :approved_by_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :service_entitlement_usages, GnomeGarden.Commercial.ServiceEntitlementUsage do
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
                 billed: :info
               ],
               default: :default}
  end

  aggregates do
    count :entitlement_usage_count, :service_entitlement_usages do
      public? true
    end
  end
end
