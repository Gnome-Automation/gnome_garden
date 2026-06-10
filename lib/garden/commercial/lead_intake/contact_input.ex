defmodule GnomeGarden.Commercial.LeadIntake.ContactInput do
  @moduledoc false

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  actions do
    defaults [:read, create: :*, update: :*]
  end

  attributes do
    attribute :first_name, :string do
      allow_nil? false
      public? true
    end

    attribute :last_name, :string do
      allow_nil? false
      public? true
    end

    attribute :email, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :mobile, :string, public?: true
    attribute :title, :string, public?: true
    attribute :department, :string, public?: true
    attribute :notes, :string, public?: true

    attribute :contact_roles, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :is_primary, :boolean do
      allow_nil? false
      default false
      public? true
    end
  end
end
