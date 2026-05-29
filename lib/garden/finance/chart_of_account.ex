defmodule GnomeGarden.Finance.ChartOfAccount do
  @moduledoc """
  Chart of Accounts — the master list of GL accounts used for double-entry bookkeeping.

  System accounts (`is_system: true`) cannot be deleted or have their type changed.
  Inactive accounts are hidden from dropdowns but preserved for historical entries.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Finance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "finance_chart_of_accounts"
    repo GnomeGarden.Repo
  end

  identities do
    identity :unique_number, [:number]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [:number, :name, :type, :is_system, :description]

      change fn changeset, _context ->
        type = Ash.Changeset.get_attribute(changeset, :type)

        normal_balance =
          case type do
            t when t in [:asset, :expense] -> :debit
            t when t in [:liability, :equity, :revenue] -> :credit
            _ -> nil
          end

        Ash.Changeset.change_attribute(changeset, :normal_balance, normal_balance)
      end
    end

    update :update do
      accept [:name, :description]
      require_atomic? false

      validate fn changeset, _context ->
        is_system = Ash.Changeset.get_data(changeset, :is_system)

        if is_system && Ash.Changeset.changing_attribute?(changeset, :type) do
          {:error, field: :type, message: "cannot change type of a system account"}
        else
          :ok
        end
      end
    end

    update :deactivate do
      accept []
      require_atomic? false

      validate fn changeset, _context ->
        is_system = Ash.Changeset.get_data(changeset, :is_system)

        if is_system do
          {:error, field: :active, message: "cannot deactivate a system account"}
        else
          :ok
        end
      end

      change set_attribute(:active, false)
    end

    destroy :delete do
      primary? true
      require_atomic? false

      validate fn changeset, _context ->
        is_system = Ash.Changeset.get_data(changeset, :is_system)

        if is_system do
          {:error, field: :is_system, message: "cannot delete a system account"}
        else
          :ok
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :integer do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:asset, :liability, :equity, :revenue, :expense]
    end

    attribute :normal_balance, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:debit, :credit]
    end

    attribute :is_system, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :journal_entry_lines, GnomeGarden.Finance.JournalEntryLine do
      destination_attribute :account_id
    end
  end
end
