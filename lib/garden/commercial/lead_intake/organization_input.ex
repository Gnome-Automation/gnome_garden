defmodule GnomeGarden.Commercial.LeadIntake.OrganizationInput do
  @moduledoc false

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  actions do
    defaults [:read, create: :*, update: :*]
  end

  attributes do
    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :legal_name, :string, public?: true
    attribute :website, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :primary_region, :string, public?: true
    attribute :notes, :string, public?: true
  end
end
