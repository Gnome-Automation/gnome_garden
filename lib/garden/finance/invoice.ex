defmodule GnomeGarden.Finance.Invoice do
  @moduledoc """
  Operational invoice header for billed work.

  This is intentionally lightweight and designed to sync outward to a
  dedicated accounting system if needed.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAdmin.Resource, AshStateMachine]

  admin do
    table_columns [
      :id,
      :invoice_number,
      :organization_id,
      :status,
      :issued_on,
      :due_on,
      :total_amount,
      :balance_amount,
      :line_total_amount,
      :applied_amount
    ]
  end

  postgres do
    table "finance_invoices"
    repo GnomeGarden.Repo

    references do
      reference :organization, on_delete: :delete
      reference :agreement, on_delete: :nilify
      reference :project, on_delete: :nilify
      reference :work_order, on_delete: :nilify
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :issue, from: :draft, to: :issued
      transition :partial, from: [:issued, :partial], to: :partial
      transition :mark_paid, from: [:issued, :partial], to: :paid
      transition :void, from: [:draft, :issued], to: :void
      transition :reopen, from: [:void, :paid], to: :draft
      transition :write_off, from: [:issued, :partial], to: :write_off
    end
  end

  policies do
    policy action([:portal_index, :portal_show]) do
      authorize_if always()
    end

    bypass always() do
      authorize_if always()
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
        :invoice_number,
        :currency_code,
        :subtotal,
        :tax_total,
        :total_amount,
        :balance_amount,
        :due_on,
        :notes
      ]
    end

    create :create_from_agreement_sources do
      argument :agreement_id, :uuid, allow_nil?: false
      argument :expense_ids, {:array, :string}, default: []

      accept [
        :invoice_number,
        :due_on,
        :notes
      ]

      change GnomeGarden.Finance.Changes.CreateInvoiceFromAgreementSources
    end

    update :update do
      accept [
        :organization_id,
        :agreement_id,
        :project_id,
        :work_order_id,
        :invoice_number,
        :currency_code,
        :subtotal,
        :tax_total,
        :total_amount,
        :balance_amount,
        :due_on,
        :notes
      ]
    end

    update :issue do
      require_atomic? false
      accept []
      change transition_state(:issued)
      change set_attribute(:issued_on, &Date.utc_today/0)

      change fn changeset, _context ->
        total_amount = Ash.Changeset.get_attribute(changeset, :total_amount)
        Ash.Changeset.change_attribute(changeset, :balance_amount, total_amount)
      end
    end

    update :mark_paid do
      accept []
      change transition_state(:paid)
      change set_attribute(:paid_on, &Date.utc_today/0)
      change set_attribute(:balance_amount, Decimal.new("0"))
    end

    update :partial do
      accept [:balance_amount]
      change transition_state(:partial)
    end

    update :write_off do
      accept []
      change transition_state(:write_off)
      change set_attribute(:balance_amount, Decimal.new("0"))
    end

    update :void do
      accept []
      change transition_state(:void)
    end

    update :reopen do
      accept []
      change transition_state(:draft)
      change set_attribute(:issued_on, nil)
      change set_attribute(:paid_on, nil)
    end

    read :open do
      filter expr(status in [:issued, :partial])

      prepare build(
                sort: [due_on: :asc, inserted_at: :desc],
                load: [
                  :organization,
                  :agreement,
                  :project,
                  :work_order,
                  :invoice_lines,
                  :payment_applications
                ]
              )
    end

    read :overdue do
      filter expr(
               status in [:issued, :partial] and not is_nil(due_on) and due_on < ^Date.utc_today()
             )

      prepare build(
                sort: [due_on: :asc],
                load: [
                  :organization,
                  :agreement,
                  :project,
                  :work_order,
                  :invoice_lines,
                  :payment_applications
                ]
              )
    end

    read :portal_index do
      description "Portal-scoped invoice list — returns only invoices for actor's organization."
      filter expr(organization_id == ^actor(:organization_id))
      prepare build(load: [:invoice_lines, :agreement, :organization])
    end

    read :portal_show do
      description "Portal-scoped invoice detail — returns a single invoice for actor's organization."
      filter expr(organization_id == ^actor(:organization_id))
      get? true
      prepare build(load: [:invoice_lines, :agreement, :organization])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :invoice_number, :string do
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true

      constraints one_of: [
                    :draft,
                    :issued,
                    :partial,
                    :paid,
                    :void,
                    :write_off
                  ]
    end

    attribute :currency_code, :string do
      allow_nil? false
      default "USD"
      public? true
    end

    attribute :subtotal, :decimal do
      public? true
    end

    attribute :tax_total, :decimal do
      public? true
    end

    attribute :total_amount, :decimal do
      public? true
    end

    attribute :balance_amount, :decimal do
      public? true
    end

    attribute :issued_on, :date do
      public? true
    end

    attribute :due_on, :date do
      public? true
    end

    attribute :paid_on, :date do
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    attribute :stripe_payment_url, :string do
      allow_nil? true
      description "Stripe Payment Link URL. Generated on invoice issue. Nil if Stripe is unavailable."
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

    has_many :invoice_lines, GnomeGarden.Finance.InvoiceLine do
      public? true
    end

    has_many :payment_applications, GnomeGarden.Finance.PaymentApplication do
      public? true
    end

    has_one :credit_note, GnomeGarden.Finance.CreditNote
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 draft: :default,
                 issued: :warning,
                 partial: :warning,
                 paid: :success,
                 void: :error,
                 write_off: :error
               ],
               default: :default}
  end

  aggregates do
    count :line_count, :invoice_lines do
      public? true
    end

    count :payment_application_count, :payment_applications do
      public? true
    end

    sum :line_total_amount, :invoice_lines, :line_total do
      public? true
    end

    sum :applied_amount, :payment_applications, :amount do
      public? true
    end
  end
end
