defmodule GnomeGarden.Finance.CreditNote do
  @moduledoc """
  Credit note document created when a voided invoice needs a reconcilable trail.

  One credit note per invoice (enforced by UNIQUE index on invoice_id).
  Staff creates this explicitly after voiding — it is never auto-created.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "credit_notes"
    repo GnomeGarden.Repo

    references do
      reference :invoice, on_delete: :restrict
      reference :organization, on_delete: :restrict
    end
  end

  identities do
    identity :unique_credit_note_number, [:credit_note_number]
    identity :one_credit_note_per_invoice, [:invoice_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [
        :credit_note_number,
        :invoice_id,
        :organization_id,
        :total_amount,
        :currency_code,
        :reason
      ]
    end

    update :issue do
      accept []
      require_atomic? false

      # Guard: CreditNote does not use AshStateMachine — enforce draft-only manually
      validate fn changeset, _context ->
        if Ash.Changeset.get_data(changeset, :status) == :draft do
          :ok
        else
          {:error, field: :status, message: "can only issue a draft credit note"}
        end
      end

      change set_attribute(:status, :issued)
      change set_attribute(:issued_on, &Date.utc_today/0)
    end

    update :update do
      accept [:reason]
      require_atomic? false

      validate fn changeset, _context ->
        if Ash.Changeset.get_data(changeset, :status) == :draft do
          :ok
        else
          {:error, field: :status, message: "can only edit a draft credit note"}
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :credit_note_number, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      default :draft
      allow_nil? false
      public? true
      constraints one_of: [:draft, :issued]
    end

    attribute :total_amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :currency_code, :string do
      default "USD"
      allow_nil? false
      public? true
    end

    attribute :issued_on, :date do
      public? true
    end

    attribute :reason, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :invoice, GnomeGarden.Finance.Invoice do
      allow_nil? false
    end

    belongs_to :organization, GnomeGarden.Operations.Organization do
      allow_nil? false
    end

    has_many :credit_note_lines, GnomeGarden.Finance.CreditNoteLine do
      sort position: :asc
    end
  end

  calculations do
    calculate :status_variant,
              :atom,
              {GnomeGarden.Calculations.EnumVariant,
               field: :status,
               mapping: [
                 draft: :default,
                 issued: :success
               ],
               default: :default}
  end
end
