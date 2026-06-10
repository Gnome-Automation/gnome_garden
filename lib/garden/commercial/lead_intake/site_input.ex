defmodule GnomeGarden.Commercial.LeadIntake.SiteInput do
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

    attribute :address1, :string, public?: true
    attribute :address2, :string, public?: true
    attribute :city, :string, public?: true
    attribute :state, :string, public?: true
    attribute :postal_code, :string, public?: true
    attribute :country_code, :string, public?: true
    attribute :timezone, :string, public?: true
    attribute :notes, :string, public?: true
  end
end
