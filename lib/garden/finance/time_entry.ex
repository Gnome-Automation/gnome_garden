defmodule GnomeGarden.Finance.TimeEntry do
  @moduledoc """
  Time worked against an agreement, project, work item, or work order.

  Time entries are the core operational-finance truth for labor cost and
  billable utilization.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :work_date,
      :member_user_id,
      :organization_id,
      :project_id,
      :work_order_id,
      :minutes,
      :status
    ]
  end

  postgres do
    table "finance_time_entries"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :agreement, on_delete: :nilify
      reference :project, on_delete: :nilify
      reference :work_item, on_delete: :nilify
      reference :work_order, on_delete: :nilify
      reference :member_user, on_delete: :nilify
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
        :work_item_id,
        :work_order_id,
        :member_user_id,
        :work_date,
        :minutes,
        :description,
        :billable,
        :bill_rate,
        :cost_rate,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :agreement_id,
        :project_id,
        :work_item_id,
        :work_order_id,
        :member_user_id,
        :work_date,
        :minutes,
        :description,
        :billable,
        :bill_rate,
        :cost_rate,
        :notes
      ]
    end

    update :submit do
      accept []
      change transition_state(:submitted)
    end

    update :approve do
      accept [:approved_by_user_id]
      change transition_state(:approved)
      change set_attribute(:approved_at, &DateTime.utc_now/0)
    end

    update :reject do
      accept [:notes]
      change transition_state(:rejected)
    end

    update :mark_billed do
      accept []
      change transition_state(:billed)
      change set_attribute(:billed_at, &DateTime.utc_now/0)
    end

    update :reopen do
      accept []
      change transition_state(:draft)
      change set_attribute(:approved_at, nil)
      change set_attribute(:approved_by_user_id, nil)
      change set_attribute(:billed_at, nil)
    end

    read :open do
      filter expr(status in [:draft, :submitted, :approved])

      prepare build(
                sort: [work_date: :desc, inserted_at: :desc],
                load: [:project, :work_order, :member_user]
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
                sort: [work_date: :asc, inserted_at: :asc],
                load: [:project, :work_order, :member_user]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :work_date, :date do
      allow_nil? false
      public? true
    end

    attribute :minutes, :integer do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? false
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

    attribute :bill_rate, :decimal do
      public? true
    end

    attribute :cost_rate, :decimal do
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

    belongs_to :work_item, GnomeGarden.Execution.WorkItem do
      public? true
    end

    belongs_to :work_order, GnomeGarden.Execution.WorkOrder do
      public? true
    end

    belongs_to :member_user, GnomeGarden.Accounts.User do
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
end
