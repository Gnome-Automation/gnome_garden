defmodule GnomeGarden.Finance.BillingRunItem do
  @moduledoc """
  The per-agreement outcome of one `BillingRun`. Records what happened to a
  single due agreement: whether an invoice was issued, skipped (no billable
  sources), or failed — and, separately, whether its email was sent or failed.

  Keeping `outcome` (accounting) distinct from `email_outcome` (delivery) lets
  the operator see "issued but email failed" as exactly that, rather than
  conflating a delivery problem with an accounting one.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [:id, :billing_run_id, :agreement_id, :invoice_id, :outcome, :email_outcome, :detail]
  end

  postgres do
    table "finance_billing_run_items"
    repo GnomeGarden.Repo

    references do
      reference :billing_run, on_delete: :delete
      reference :agreement, on_delete: :nilify
      reference :invoice, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:billing_run_id, :agreement_id, :invoice_id, :outcome, :email_outcome, :detail]
    end

    read :for_run do
      argument :billing_run_id, :uuid, allow_nil?: false
      filter expr(billing_run_id == ^arg(:billing_run_id))
      prepare build(sort: [inserted_at: :asc], load: [:agreement, :invoice])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :outcome, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:issued, :skipped, :failed]
    end

    attribute :email_outcome, :atom do
      allow_nil? false
      default :not_attempted
      public? true
      constraints one_of: [:not_attempted, :sent, :failed]
    end

    attribute :detail, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :billing_run, GnomeGarden.Finance.BillingRun do
      allow_nil? false
      public? true
    end

    belongs_to :agreement, GnomeGarden.Commercial.Agreement do
      public? true
    end

    belongs_to :invoice, GnomeGarden.Finance.Invoice do
      public? true
    end
  end
end
