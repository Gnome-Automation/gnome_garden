defmodule GnomeGarden.Automation.Rule do
  @moduledoc """
  A criteria-triggered automation rule: trigger + criteria + actions.

  Lifecycle: draft → published → disabled. Published rules are immutable in
  place — clone to edit — and every run snapshots the definition it executed,
  so history never rewrites. Criteria and actions are validated at write
  time; the action vocabulary is typed, never arbitrary code.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Automation,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource],
    notifiers: [Ash.Notifier.PubSub]

  admin do
    table_columns [:id, :name, :trigger_resource, :trigger_action, :status, :inserted_at]
  end

  postgres do
    table "automation_rules"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :name,
        :description,
        :trigger_resource,
        :trigger_action,
        :criteria,
        :actions,
        :cloned_from_rule_id
      ]
    end

    update :update do
      require_atomic? false
      accept [:name, :description, :trigger_resource, :trigger_action, :criteria, :actions]

      validate attribute_equals(:status, :draft),
        message: "published rules are immutable; clone to edit"
    end

    update :publish do
      require_atomic? false
      accept []
      validate attribute_equals(:status, :draft), message: "only drafts can be published"
      change set_attribute(:status, :published)
      change set_attribute(:published_at, &DateTime.utc_now/0)
    end

    update :disable do
      require_atomic? false
      accept []

      validate attribute_equals(:status, :published),
        message: "only published rules can be disabled"

      change set_attribute(:status, :disabled)
    end

    update :enable do
      require_atomic? false
      accept []

      validate attribute_equals(:status, :disabled),
        message: "only disabled rules can be re-enabled"

      change set_attribute(:status, :published)
    end

    destroy :destroy_draft do
      require_atomic? false

      validate attribute_equals(:status, :draft),
        message: "published rules archive their history; disable instead"
    end

    action :clone, :struct do
      constraints instance_of: __MODULE__
      argument :rule_id, :uuid, allow_nil?: false
      argument :new_name, :string
      run GnomeGarden.Automation.Actions.CloneRule
    end

    action :dry_run, :map do
      argument :rule_id, :uuid, allow_nil?: false
      run GnomeGarden.Automation.Actions.DryRunRule
    end

    action :ensure_starters, :map do
      run GnomeGarden.Automation.Actions.EnsureStarterRules
    end

    read :published do
      filter expr(status == :published)
      prepare build(sort: [name: :asc])
    end

    read :matching do
      argument :trigger_resource, :string, allow_nil?: false
      argument :trigger_action, :string, allow_nil?: false

      filter expr(
               status == :published and
                 trigger_resource == ^arg(:trigger_resource) and
                 trigger_action == ^arg(:trigger_action)
             )

      prepare build(sort: [name: :asc])
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      get_by [:name]
    end
  end

  pub_sub do
    module GnomeGardenWeb.Endpoint
    prefix "automation_rule"

    publish_all :create, "created"
    publish_all :update, "updated"
    publish_all :update, ["updated", :_pkey]
    publish_all :destroy, "destroyed"
  end

  validations do
    validate {GnomeGarden.Automation.Validations.ValidDefinition, []}
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
      constraints one_of: [:draft, :published, :disabled]
    end

    attribute :trigger_resource, :string do
      allow_nil? false
      public? true
    end

    attribute :trigger_action, :string do
      allow_nil? false
      public? true
    end

    attribute :criteria, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :actions, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :published_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :runs, GnomeGarden.Automation.Run do
      destination_attribute :rule_id
      public? true
    end

    # Clone lineage is the rule's change history: published definitions are
    # immutable, so edits arrive as new drafts pointing at their ancestor.
    belongs_to :cloned_from_rule, __MODULE__ do
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end

  def snapshot(rule) do
    %{
      "rule_id" => rule.id,
      "name" => rule.name,
      "trigger_resource" => rule.trigger_resource,
      "trigger_action" => rule.trigger_action,
      "criteria" => rule.criteria,
      "actions" => rule.actions,
      "published_at" => rule.published_at && DateTime.to_iso8601(rule.published_at)
    }
  end
end
