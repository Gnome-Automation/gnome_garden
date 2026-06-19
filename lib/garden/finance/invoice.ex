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

      validate {GnomeGarden.Validations.SingleCurrency,
                attributes: [:subtotal, :tax_total, :total_amount, :balance_amount]}
    end

    create :create_from_agreement_sources do
      argument :agreement_id, :uuid, allow_nil?: false

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

      change GnomeGarden.Finance.Changes.PostInvoiceIssuedToLedger
    end

    update :mark_paid do
      require_atomic? false
      accept []
      change transition_state(:paid)
      change set_attribute(:paid_on, &Date.utc_today/0)
      change GnomeGarden.Finance.Changes.ZeroInvoiceBalance
    end

    update :partial do
      accept [:balance_amount]
      change transition_state(:partial)
    end

    update :write_off do
      require_atomic? false
      accept []
      change transition_state(:write_off)
      change GnomeGarden.Finance.Changes.ZeroInvoiceBalance
    end

    update :void do
      require_atomic? false
      accept []
      change transition_state(:void)
      change GnomeGarden.Finance.Changes.PostInvoiceVoidedReversal
    end

    update :reopen do
      accept []
      change transition_state(:draft)
      change set_attribute(:issued_on, nil)
      change set_attribute(:paid_on, nil)
    end

    # Email delivery is recorded independently of the invoice's accounting
    # status (these never transition status or touch the ledger).
    update :mark_email_sent do
      accept []
      change set_attribute(:email_status, :sent)
      change set_attribute(:email_sent_at, &DateTime.utc_now/0)
      change set_attribute(:last_email_attempted_at, &DateTime.utc_now/0)
      change set_attribute(:email_failure_reason, nil)
    end

    update :mark_email_failed do
      accept [:email_failure_reason]
      change set_attribute(:email_status, :failed)
      change set_attribute(:email_failed_at, &DateTime.utc_now/0)
      change set_attribute(:last_email_attempted_at, &DateTime.utc_now/0)
    end

    read :email_failed do
      filter expr(email_status == :failed)
      prepare build(sort: [email_failed_at: :desc], load: [:organization])
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

    read :drafts do
      filter expr(status == :draft)
      prepare build(sort: [inserted_at: :desc], load: [:organization])
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

    action :ar_aging, :map do
      argument :as_of, :date, default: &Date.utc_today/0
      run GnomeGarden.Finance.Actions.BuildArAging
    end

    action :finance_overview_workspace, :map do
      run GnomeGarden.Finance.Actions.BuildFinanceOverviewWorkspace
    end

    action :receivables_workspace, :map do
      run GnomeGarden.Finance.Actions.BuildReceivablesWorkspace
    end

    action :work_to_bill_workspace, :map do
      run GnomeGarden.Finance.Actions.BuildWorkToBillWorkspace
    end

    action :money_morning_workspace, :map do
      run GnomeGarden.Finance.Actions.BuildMoneyMorningWorkspace
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

    attribute :subtotal, :money do
      public? true
    end

    attribute :tax_total, :money do
      public? true
    end

    attribute :total_amount, :money do
      public? true
    end

    attribute :balance_amount, :money do
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

    # Email delivery state, tracked separately from accounting status: an
    # invoice can be :issued (posted to the ledger) while its email delivery is
    # still :pending or :failed. Delivery never gates issuance.
    attribute :email_status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :sent, :failed]
    end

    attribute :last_email_attempted_at, :utc_datetime, public?: true
    attribute :email_sent_at, :utc_datetime, public?: true
    attribute :email_failed_at, :utc_datetime, public?: true
    attribute :email_failure_reason, :string, public?: true

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
      filter expr(line_total[:currency] == "USD")
    end

    sum :applied_amount, :payment_applications, :amount do
      public? true
      filter expr(amount[:currency] == "USD")
    end
  end
end
