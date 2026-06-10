defmodule GnomeGarden.Commercial.LeadIntake.SignalInput do
  @moduledoc false

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  actions do
    defaults [:read, create: :*, update: :*]
  end

  attributes do
    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string, public?: true
    attribute :source_url, :string, public?: true
    attribute :external_ref, :string, public?: true
    attribute :referral_source, :string, public?: true
    attribute :notes, :string, public?: true
    attribute :suspected_needs, {:array, :string}, public?: true, default: []
  end
end
