defmodule GnomeGarden.Commercial.ProposalLine do
  @moduledoc """
  Line item on a commercial proposal.

  Proposal lines capture the priced scope that ultimately rolls up into a
  customer-facing quote or estimate.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Commercial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :id,
      :proposal_id,
      :line_number,
      :line_kind,
      :description,
      :quantity,
      :line_total
    ]
  end

  postgres do
    table "commercial_proposal_lines"
    repo GnomeGarden.Repo
    identity_index_names unique_line_number_per_proposal: "cpl_proposal_line_no_idx"

    references do
      reference :proposal, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :proposal_id,
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
        :proposal_id,
        :line_number,
        :line_kind,
        :description,
        :quantity,
        :unit_price,
        :line_total,
        :notes
      ]
    end

    read :for_proposal do
      argument :proposal_id, :uuid, allow_nil?: false
      filter expr(proposal_id == ^arg(:proposal_id))
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
                    :allowance,
                    :adjustment,
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
    belongs_to :proposal, GnomeGarden.Commercial.Proposal do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_line_number_per_proposal, [:proposal_id, :line_number]
  end
end
