defmodule GnomeGarden.Operations.PlaybookRun do
  @moduledoc """
  One application of a playbook against a Garden record.

  The run copies the playbook name and each generated task snapshots its
  originating step, so run history survives playbook edits and archiving.
  Progress is derived from task aggregates rather than stored state.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "playbook_runs"
    repo GnomeGarden.Repo

    references do
      reference :playbook, on_delete: :restrict
      reference :applied_by_team_member, on_delete: :nilify
      reference :pursuit, on_delete: :nilify
      reference :project, on_delete: :nilify
      reference :bid, on_delete: :nilify
      reference :procurement_source, on_delete: :nilify
      reference :organization, on_delete: :nilify
      reference :signal, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :apply do
      primary? true

      accept [
        :playbook_id,
        :pursuit_id,
        :project_id,
        :bid_id,
        :procurement_source_id,
        :organization_id,
        :signal_id
      ]

      change GnomeGarden.Operations.Changes.ApplyPlaybookSteps
    end

    read :for_pursuit do
      argument :pursuit_id, :uuid, allow_nil?: false
      filter expr(pursuit_id == ^arg(:pursuit_id))
      prepare build(sort: [inserted_at: :desc], load: [:task_count, :completed_task_count])
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [inserted_at: :desc], load: [:task_count, :completed_task_count])
    end

    read :for_bid do
      argument :bid_id, :uuid, allow_nil?: false
      filter expr(bid_id == ^arg(:bid_id))
      prepare build(sort: [inserted_at: :desc], load: [:task_count, :completed_task_count])
    end

    read :for_procurement_source do
      argument :procurement_source_id, :uuid, allow_nil?: false
      filter expr(procurement_source_id == ^arg(:procurement_source_id))
      prepare build(sort: [inserted_at: :desc], load: [:task_count, :completed_task_count])
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))
      prepare build(sort: [inserted_at: :desc], load: [:task_count, :completed_task_count])
    end

    read :for_signal do
      argument :signal_id, :uuid, allow_nil?: false
      filter expr(signal_id == ^arg(:signal_id))
      prepare build(sort: [inserted_at: :desc], load: [:task_count, :completed_task_count])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "playbook_run"

    publish_all :create, "created"
    publish_all :create, ["pursuit", :pursuit_id]
    publish_all :create, ["project", :project_id]
    publish_all :create, ["bid", :bid_id]
    publish_all :create, ["procurement_source", :procurement_source_id]
    publish_all :create, ["organization", :organization_id]
    publish_all :create, ["signal", :signal_id]
  end

  attributes do
    uuid_primary_key :id

    attribute :playbook_name, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :playbook, GnomeGarden.Operations.Playbook do
      allow_nil? false
      public? true
    end

    belongs_to :applied_by_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end

    belongs_to :pursuit, GnomeGarden.Commercial.Pursuit do
      public? true
    end

    belongs_to :project, GnomeGarden.Execution.Project do
      public? true
    end

    belongs_to :bid, GnomeGarden.Procurement.Bid do
      public? true
    end

    belongs_to :procurement_source, GnomeGarden.Procurement.ProcurementSource do
      public? true
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      public? true
    end

    belongs_to :signal, GnomeGarden.Commercial.Signal do
      public? true
    end

    has_many :tasks, GnomeGarden.Operations.Task do
      destination_attribute :playbook_run_id
      public? true
    end
  end

  aggregates do
    count :task_count, :tasks

    count :completed_task_count, :tasks do
      filter expr(status == :completed)
    end
  end
end
