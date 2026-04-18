defmodule GnomeGarden.Execution.Project do
  @moduledoc """
  Time-bound scoped delivery effort.

  Projects represent finite implementation or upgrade work, distinct from
  recurring service or maintenance work orders.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Execution,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :code,
      :name,
      :project_type,
      :delivery_mode,
      :status,
      :priority,
      :target_end_on,
      :inserted_at
    ]
  end

  postgres do
    table "execution_projects"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :agreement, on_delete: :nilify
      reference :manager_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:planned]
    default_initial_state :planned

    transitions do
      transition :approve, from: :planned, to: :ready
      transition :start, from: [:planned, :ready, :on_hold], to: :active
      transition :hold, from: [:ready, :active], to: :on_hold
      transition :complete, from: [:active, :on_hold], to: :completed
      transition :cancel, from: [:planned, :ready, :on_hold], to: :cancelled
      transition :reopen, from: [:completed, :cancelled], to: :ready
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :organization_id,
        :site_id,
        :managed_system_id,
        :agreement_id,
        :manager_user_id,
        :code,
        :name,
        :description,
        :project_type,
        :delivery_mode,
        :priority,
        :start_on,
        :target_end_on,
        :budget_hours,
        :budget_amount,
        :notes
      ]
    end

    create :create_from_agreement do
      argument :agreement_id, :uuid, allow_nil?: false

      accept [
        :code,
        :name,
        :description,
        :project_type,
        :delivery_mode,
        :priority,
        :start_on,
        :target_end_on,
        :budget_hours,
        :budget_amount,
        :notes,
        :manager_user_id
      ]

      change GnomeGarden.Execution.Changes.CreateProjectFromAgreement
    end

    update :update do
      accept [
        :organization_id,
        :site_id,
        :managed_system_id,
        :agreement_id,
        :manager_user_id,
        :code,
        :name,
        :description,
        :project_type,
        :delivery_mode,
        :priority,
        :start_on,
        :target_end_on,
        :actual_end_on,
        :budget_hours,
        :budget_amount,
        :notes
      ]
    end

    update :approve do
      accept []
      change transition_state(:ready)
    end

    update :start do
      accept []
      change transition_state(:active)
    end

    update :hold do
      accept []
      change transition_state(:on_hold)
    end

    update :complete do
      accept []
      change transition_state(:completed)
      change set_attribute(:actual_end_on, &Date.utc_today/0)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
      accept []
      change transition_state(:ready)
    end

    read :active do
      filter expr(status in [:ready, :active, :on_hold])
      prepare build(sort: [target_end_on: :asc, inserted_at: :desc], load: [:organization, :site, :agreement])
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [target_end_on: :asc, inserted_at: :desc], load: [:organization, :site, :agreement])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :code, :string do
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :project_type, :atom do
      allow_nil? false
      default :implementation
      public? true

      constraints one_of: [
                    :implementation,
                    :upgrade,
                    :integration,
                    :commissioning,
                    :software_delivery,
                    :internal,
                    :other
                  ]
    end

    attribute :delivery_mode, :atom do
      allow_nil? false
      default :hybrid
      public? true

      constraints one_of: [
                    :physical,
                    :digital,
                    :hybrid
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :planned
      public? true

      constraints one_of: [
                    :planned,
                    :ready,
                    :active,
                    :on_hold,
                    :completed,
                    :cancelled
                  ]
    end

    attribute :priority, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [:low, :normal, :high, :critical]
    end

    attribute :start_on, :date do
      public? true
    end

    attribute :target_end_on, :date do
      public? true
    end

    attribute :actual_end_on, :date do
      public? true
    end

    attribute :budget_hours, :decimal do
      public? true
    end

    attribute :budget_amount, :decimal do
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

    belongs_to :site, GnomeGarden.Operations.Site do
      public? true
    end

    belongs_to :managed_system, GnomeGarden.Operations.ManagedSystem do
      public? true
    end

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      public? true
    end

    belongs_to :manager_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :work_items, GnomeGarden.Execution.WorkItem do
      public? true
    end

    has_many :work_orders, GnomeGarden.Execution.WorkOrder do
      public? true
    end
  end
end
