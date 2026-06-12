defmodule GnomeGarden.Finance.RetainerApplication do
  @moduledoc """
  Stub module — full implementation in Task 4.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_retainer_applications"
    repo GnomeGarden.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :retainer, GnomeGarden.Finance.Retainer do
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
