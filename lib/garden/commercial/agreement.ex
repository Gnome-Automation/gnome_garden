defmodule GnomeGarden.Commercial.Agreement do
  @moduledoc """
  Signed or signable commercial agreement with a customer.

  Agreements capture the commercial commitment that later drives projects,
  work orders, invoicing, and contract consumption.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :reference_number,
      :name,
      :agreement_type,
      :status,
      :billing_model,
      :contract_value,
      :start_on,
      :end_on,
      :invoiced_amount,
      :received_amount
    ]
  end

  postgres do
    table "commercial_agreements"
    repo GnomeGarden.Repo

    references do
      reference :pursuit, on_delete: :nilify
      reference :proposal, on_delete: :nilify
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
      transition :submit_for_signature, from: :draft, to: :pending_signature
      transition :activate, from: [:draft, :pending_signature], to: :active
      transition :suspend, from: :active, to: :suspended
      transition :complete, from: [:active, :suspended], to: :completed

      transition :terminate,
        from: [:draft, :pending_signature, :active, :suspended],
        to: :terminated

      transition :reopen, from: [:suspended, :terminated], to: :active
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :pursuit_id,
        :proposal_id,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_user_id,
        :reference_number,
        :name,
        :agreement_type,
        :billing_model,
        :currency_code,
        :contract_value,
        :start_on,
        :end_on,
        :auto_renew,
        :renewal_notice_days,
        :notes
      ]
    end

    create :create_from_proposal do
      argument :proposal_id, :uuid, allow_nil?: false

      accept [
        :reference_number,
        :name,
        :agreement_type,
        :billing_model,
        :currency_code,
        :contract_value,
        :start_on,
        :end_on,
        :auto_renew,
        :renewal_notice_days,
        :notes,
        :owner_user_id
      ]

      change GnomeGarden.Commercial.Changes.CreateAgreementFromProposal
    end

    update :update do
      accept [
        :pursuit_id,
        :proposal_id,
        :organization_id,
        :site_id,
        :managed_system_id,
        :owner_user_id,
        :reference_number,
        :name,
        :agreement_type,
        :billing_model,
        :currency_code,
        :contract_value,
        :start_on,
        :end_on,
        :auto_renew,
        :renewal_notice_days,
        :notes
      ]
    end

    update :submit_for_signature do
      accept []
      change transition_state(:pending_signature)
    end

    update :activate do
      accept []
      change transition_state(:active)
    end

    update :suspend do
      accept []
      change transition_state(:suspended)
    end

    update :complete do
      accept []
      change transition_state(:completed)
    end

    update :terminate do
      accept []
      change transition_state(:terminated)
    end

    update :reopen do
      accept []
      change transition_state(:active)
    end

    read :active do
      filter expr(status == :active)

      prepare build(
                sort: [end_on: :asc, inserted_at: :desc],
                load: [
                  :organization,
                  :site,
                  :pursuit,
                  :proposal,
                  :projects,
                  :change_orders,
                  :service_tickets,
                  :service_level_policies,
                  :service_entitlements,
                  :invoices,
                  :payments
                ]
              )
    end

    read :expiring_soon do
      argument :days, :integer, default: 45

      filter expr(
               status == :active and
                 not is_nil(end_on) and
                 end_on < from_now(^arg(:days), :day)
             )

      prepare build(
                sort: [end_on: :asc],
                load: [
                  :organization,
                  :site,
                  :pursuit,
                  :proposal,
                  :projects,
                  :change_orders,
                  :service_tickets,
                  :service_level_policies,
                  :service_entitlements,
                  :invoices,
                  :payments
                ]
              )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :reference_number, :string do
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :agreement_type, :atom do
      allow_nil? false
      default :project
      public? true

      constraints one_of: [
                    :msa,
                    :sow,
                    :project,
                    :service,
                    :maintenance,
                    :retainer,
                    :support,
                    :warranty,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true

      constraints one_of: [
                    :draft,
                    :pending_signature,
                    :active,
                    :suspended,
                    :completed,
                    :terminated
                  ]
    end

    attribute :billing_model, :atom do
      allow_nil? false
      default :fixed_fee
      public? true

      constraints one_of: [
                    :fixed_fee,
                    :time_and_materials,
                    :retainer,
                    :milestone,
                    :unit,
                    :mixed
                  ]
    end

    attribute :currency_code, :string do
      allow_nil? false
      default "USD"
      public? true
    end

    attribute :contract_value, :decimal do
      public? true
    end

    attribute :start_on, :date do
      public? true
    end

    attribute :end_on, :date do
      public? true
    end

    attribute :auto_renew, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :renewal_notice_days, :integer do
      allow_nil? false
      default 30
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :pursuit, GnomeGarden.Commercial.Pursuit do
      public? true
    end

    belongs_to :proposal, GnomeGarden.Commercial.Proposal do
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

    has_many :projects, GnomeGarden.Execution.Project do
      public? true
    end

    has_many :change_orders, GnomeGarden.Commercial.ChangeOrder do
      public? true
    end

    has_many :service_tickets, GnomeGarden.Execution.ServiceTicket do
      public? true
    end

    has_many :service_level_policies, GnomeGarden.Commercial.ServiceLevelPolicy do
      public? true
    end

    has_many :service_entitlements, GnomeGarden.Commercial.ServiceEntitlement do
      public? true
    end

    has_many :service_entitlement_usages, GnomeGarden.Commercial.ServiceEntitlementUsage do
      public? true
    end

    has_many :work_orders, GnomeGarden.Execution.WorkOrder do
      public? true
    end

    has_many :maintenance_plans, GnomeGarden.Execution.MaintenancePlan do
      public? true
    end

    has_many :time_entries, GnomeGarden.Finance.TimeEntry do
      public? true
    end

    has_many :expenses, GnomeGarden.Finance.Expense do
      public? true
    end

    has_many :invoices, GnomeGarden.Finance.Invoice do
      public? true
    end

    has_many :payments, GnomeGarden.Finance.Payment do
      public? true
    end
  end

  aggregates do
    count :project_count, :projects do
      public? true
    end

    count :service_ticket_count, :service_tickets do
      public? true
    end

    count :open_service_ticket_count, :service_tickets do
      public? true
      filter expr(status in [:new, :triaged, :in_progress, :waiting_on_customer, :resolved])
    end

    count :open_work_order_count, :work_orders do
      public? true
      filter expr(status in [:new, :scheduled, :dispatched, :in_progress])
    end

    count :invoice_count, :invoices do
      public? true
    end

    count :payment_count, :payments do
      public? true
    end

    count :maintenance_plan_count, :maintenance_plans do
      public? true
    end

    count :service_entitlement_count, :service_entitlements do
      public? true
    end

    count :change_order_count, :change_orders do
      public? true
    end

    sum :invoiced_amount, :invoices, :total_amount do
      public? true
    end

    sum :received_amount, :payments, :amount do
      public? true
      filter expr(status in [:received, :deposited])
    end

    sum :billable_minutes, :time_entries, :minutes do
      public? true
      filter expr(billable == true)
    end

    sum :expense_amount, :expenses, :amount do
      public? true
    end

    sum :approved_change_order_amount, :change_orders, :total_amount do
      public? true
      filter expr(status in [:approved, :implemented])
    end
  end
end
