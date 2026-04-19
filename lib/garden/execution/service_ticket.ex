defmodule GnomeGarden.Execution.ServiceTicket do
  @moduledoc """
  Customer-facing service intake record.

  Service tickets capture support, incident, warranty, and maintenance requests
  before and alongside the work orders used to execute the actual work.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Execution,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :ticket_number,
      :title,
      :organization_id,
      :requester_person_id,
      :service_level_policy_id,
      :ticket_type,
      :status,
      :severity,
      :reported_at
    ]
  end

  postgres do
    table "execution_service_tickets"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :site, on_delete: :nilify
      reference :managed_system, on_delete: :nilify
      reference :asset, on_delete: :nilify
      reference :agreement, on_delete: :nilify
      reference :requester_person, on_delete: :nilify
      reference :service_level_policy, on_delete: :nilify
      reference :requester_user, on_delete: :nilify
      reference :owner_user, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:new]
    default_initial_state :new

    transitions do
      transition :triage, from: :new, to: :triaged
      transition :start, from: [:new, :triaged, :waiting_on_customer], to: :in_progress
      transition :pause, from: [:triaged, :in_progress], to: :waiting_on_customer
      transition :resolve, from: [:triaged, :in_progress, :waiting_on_customer], to: :resolved
      transition :close, from: :resolved, to: :closed
      transition :cancel, from: [:new, :triaged, :waiting_on_customer], to: :cancelled
      transition :reopen, from: [:resolved, :closed, :cancelled], to: :triaged
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
        :asset_id,
        :agreement_id,
        :requester_person_id,
        :service_level_policy_id,
        :requester_user_id,
        :owner_user_id,
        :ticket_number,
        :title,
        :description,
        :ticket_type,
        :source_channel,
        :severity,
        :impact,
        :reported_at,
        :due_on,
        :resolution_summary,
        :notes
      ]
    end

    update :update do
      accept [
        :organization_id,
        :site_id,
        :managed_system_id,
        :asset_id,
        :agreement_id,
        :requester_person_id,
        :service_level_policy_id,
        :requester_user_id,
        :owner_user_id,
        :ticket_number,
        :title,
        :description,
        :ticket_type,
        :source_channel,
        :severity,
        :impact,
        :reported_at,
        :due_on,
        :resolution_summary,
        :notes
      ]
    end

    update :triage do
      accept []
      change transition_state(:triaged)
    end

    update :start do
      accept []
      change transition_state(:in_progress)
    end

    update :pause do
      accept []
      change transition_state(:waiting_on_customer)
    end

    update :resolve do
      accept [:resolution_summary]
      change transition_state(:resolved)
      change set_attribute(:resolved_at, &DateTime.utc_now/0)
    end

    update :close do
      accept []
      change transition_state(:closed)
      change set_attribute(:closed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change transition_state(:cancelled)
    end

    update :reopen do
      accept []
      change transition_state(:triaged)
      change set_attribute(:resolved_at, nil)
      change set_attribute(:closed_at, nil)
    end

    read :open do
      filter expr(status in [:new, :triaged, :in_progress, :waiting_on_customer, :resolved])

      prepare build(
                sort: [severity: :desc, reported_at: :desc, inserted_at: :desc],
                load: [
                  :organization,
                  :site,
                  :managed_system,
                  :asset,
                  :agreement,
                  :requester_person,
                  :service_level_policy,
                  :work_orders
                ]
              )
    end

    read :for_organization do
      argument :organization_id, :uuid, allow_nil?: false
      filter expr(organization_id == ^arg(:organization_id))

      prepare build(
                sort: [reported_at: :desc, inserted_at: :desc],
                load: [
                  :organization,
                  :site,
                  :managed_system,
                  :asset,
                  :agreement,
                  :requester_person,
                  :service_level_policy,
                  :work_orders
                ]
              )
    end

    read :for_requester_person do
      argument :requester_person_id, :uuid, allow_nil?: false
      filter expr(requester_person_id == ^arg(:requester_person_id))

      prepare build(
                sort: [reported_at: :desc, inserted_at: :desc],
                load: [
                  :organization,
                  :site,
                  :managed_system,
                  :asset,
                  :agreement,
                  :requester_person,
                  :service_level_policy,
                  :work_orders
                ]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :ticket_number, :string do
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :ticket_type, :atom do
      allow_nil? false
      default :incident
      public? true

      constraints one_of: [
                    :incident,
                    :service_request,
                    :warranty,
                    :maintenance,
                    :monitoring_alert,
                    :other
                  ]
    end

    attribute :source_channel, :atom do
      allow_nil? false
      default :manual
      public? true

      constraints one_of: [:email, :phone, :portal, :monitoring, :manual, :other]
    end

    attribute :status, :atom do
      allow_nil? false
      default :new
      public? true

      constraints one_of: [
                    :new,
                    :triaged,
                    :in_progress,
                    :waiting_on_customer,
                    :resolved,
                    :closed,
                    :cancelled
                  ]
    end

    attribute :severity, :atom do
      allow_nil? false
      default :normal
      public? true

      constraints one_of: [:low, :normal, :high, :critical]
    end

    attribute :impact, :atom do
      allow_nil? false
      default :single_area
      public? true

      constraints one_of: [:single_area, :multi_area, :site_wide, :enterprise]
    end

    attribute :reported_at, :utc_datetime do
      public? true
    end

    attribute :due_on, :date do
      public? true
    end

    attribute :resolved_at, :utc_datetime do
      public? true
    end

    attribute :closed_at, :utc_datetime do
      public? true
    end

    attribute :resolution_summary, :string do
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

    belongs_to :asset, GnomeGarden.Operations.Asset do
      public? true
    end

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      public? true
    end

    belongs_to :requester_person, GnomeGarden.Operations.Person do
      public? true
    end

    belongs_to :service_level_policy, GnomeGarden.Commercial.ServiceLevelPolicy do
      public? true
    end

    belongs_to :requester_user, GnomeGarden.Accounts.User do
      public? true
    end

    belongs_to :owner_user, GnomeGarden.Accounts.User do
      public? true
    end

    has_many :work_orders, GnomeGarden.Execution.WorkOrder do
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
                 triaged: :info,
                 in_progress: :warning,
                 waiting_on_customer: :warning,
                 resolved: :success,
                 closed: :default,
                 cancelled: :error
               ],
               default: :default}

    calculate :severity_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :severity,
               mapping: [
                 low: :default,
                 normal: :info,
                 high: :warning,
                 critical: :error
               ],
               default: :default}
  end

  aggregates do
    count :work_order_count, :work_orders do
      public? true
    end
  end

  identities do
    identity :unique_ticket_number, [:ticket_number]
  end
end
