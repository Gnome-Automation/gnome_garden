defmodule GnomeGarden.Finance.FinanceSequence do
  @moduledoc """
  Atomic sequence counter table. One row per named sequence.

  Do NOT use Ash actions to increment — use Finance.next_sequence_value/1
  which executes a raw atomic SQL UPDATE ... RETURNING.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_sequences"
    repo GnomeGarden.Repo
  end

  actions do
    defaults [:read]
  end

  attributes do
    attribute :name, :string do
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :last_value, :integer do
      default 0
      allow_nil? false
      public? true
    end

    # No timestamps() — FinanceSequence is a counter table; audit trail not needed
    # This also keeps the seed SQL simple (no inserted_at/updated_at columns)
  end
end
