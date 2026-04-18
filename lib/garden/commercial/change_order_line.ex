defmodule GnomeGarden.Commercial.ChangeOrderLine do
  @moduledoc """
  Line item on a change order.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :change_order_id,
      :line_number,
      :line_kind,
      :description,
      :quantity,
      :line_total
    ]
  end

  postgres do
    table "commercial_change_order_lines"
    repo GnomeGarden.Repo
    identity_index_names unique_line_number_per_change_order: "ccol_change_order_line_no_idx"

    references do
      reference :change_order, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :change_order_id,
        :line_number,
        :line_kind,
        :description,
        :quantity,
        :unit_price,
        :line_total,
        :notes
      ]
    end

    update :update do
      accept [
        :change_order_id,
        :line_number,
        :line_kind,
        :description,
        :quantity,
        :unit_price,
        :line_total,
        :notes
      ]
    end

    read :for_change_order do
      argument :change_order_id, :uuid, allow_nil?: false
      filter expr(change_order_id == ^arg(:change_order_id))
      prepare build(sort: [line_number: :asc, inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :line_number, :integer do
      allow_nil? false
      default 1
      public? true
      constraints min: 1
    end

    attribute :line_kind, :atom do
      allow_nil? false
      default :other
      public? true

      constraints one_of: [
                    :engineering,
                    :software,
                    :hardware,
                    :materials,
                    :commissioning,
                    :service,
                    :credit,
                    :allowance,
                    :other
                  ]
    end

    attribute :description, :string do
      allow_nil? false
      public? true
    end

    attribute :quantity, :decimal do
      allow_nil? false
      public? true
    end

    attribute :unit_price, :decimal do
      allow_nil? false
      public? true
    end

    attribute :line_total, :decimal do
      allow_nil? false
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :change_order, GnomeGarden.Commercial.ChangeOrder do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_line_number_per_change_order, [:change_order_id, :line_number]
  end
end
