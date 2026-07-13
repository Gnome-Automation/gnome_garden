defmodule GnomeGarden.Operations.PlaybookStep do
  @moduledoc """
  One ordered step in a playbook, carrying inline task-template fields.

  A separate reusable TaskTemplate resource is deliberately deferred until
  real cross-playbook duplication appears. Applying a playbook snapshots each
  step onto the generated task, so later edits never rewrite history.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Operations,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "playbook_steps"
    repo GnomeGarden.Repo

    references do
      reference :playbook, on_delete: :delete
      reference :assignee_team_member, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :playbook_id,
        :position,
        :title,
        :description,
        :task_type,
        :priority,
        :due_offset_days,
        :assignee_strategy,
        :assignee_team_member_id
      ]
    end

    update :update do
      accept [
        :position,
        :title,
        :description,
        :task_type,
        :priority,
        :due_offset_days,
        :assignee_strategy,
        :assignee_team_member_id
      ]
    end

    read :for_playbook do
      argument :playbook_id, :uuid, allow_nil?: false
      filter expr(playbook_id == ^arg(:playbook_id))
      prepare build(sort: [position: :asc])
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "playbook_step"

    publish_all :create, ["playbook", :playbook_id]
    publish_all :update, ["playbook", :playbook_id]
    publish_all :destroy, ["playbook", :playbook_id]
  end

  validations do
    validate present(:assignee_team_member_id) do
      where attribute_equals(:assignee_strategy, :specific)
      message "is required when the assignee strategy is a specific member"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :task_type, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :review,
                    :research,
                    :call,
                    :email,
                    :evidence,
                    :proposal,
                    :finance,
                    :source_cleanup,
                    :agent_followup,
                    :other
                  ]
    end

    attribute :priority, :atom do
      allow_nil? false
      default :normal
      public? true
      constraints one_of: [:low, :normal, :high, :urgent]
    end

    attribute :due_offset_days, :integer do
      public? true
      constraints min: 0
    end

    attribute :assignee_strategy, :atom do
      allow_nil? false
      default :unassigned
      public? true
      constraints one_of: [:unassigned, :applier, :specific]
    end

    timestamps()
  end

  relationships do
    belongs_to :playbook, GnomeGarden.Operations.Playbook do
      allow_nil? false
      public? true
    end

    belongs_to :assignee_team_member, GnomeGarden.Operations.TeamMember do
      public? true
    end
  end
end
