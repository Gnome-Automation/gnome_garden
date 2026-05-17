defmodule GnomeGarden.Finance.CreditNoteLine do
  @moduledoc """
  One line on a credit note, mirroring an InvoiceLine with negated amounts.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "credit_note_lines"
    repo GnomeGarden.Repo

    references do
      reference :credit_note, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:credit_note_id, :position, :description, :quantity, :unit_price, :line_total]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :quantity, :decimal do
      public? true
    end

    attribute :unit_price, :decimal do
      public? true
    end

    attribute :line_total, :decimal do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :credit_note, GnomeGarden.Finance.CreditNote do
      allow_nil? false
    end
  end
end
