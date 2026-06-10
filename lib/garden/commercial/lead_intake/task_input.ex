defmodule GnomeGarden.Commercial.LeadIntake.TaskInput do
  @moduledoc false

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  actions do
    defaults [:read, create: :*, update: :*]
  end

  attributes do
    attribute :title, :string, public?: true
    attribute :description, :string, public?: true

    attribute :task_type, :atom do
      allow_nil? false
      default :call
      public? true
      constraints one_of: [:review, :research, :call, :email, :evidence, :proposal, :other]
    end

    attribute :priority, :atom do
      allow_nil? false
      default :high
      public? true
      constraints one_of: [:low, :normal, :high, :urgent]
    end
  end
end
