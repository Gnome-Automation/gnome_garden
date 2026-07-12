defmodule GnomeGarden.Acquisition.FindingAdmissionCapacity do
  @moduledoc """
  Atomically maintained Finding-admission capacity for one run or UTC day.

  Capacity rows are immutable windows. Admission consumes both a run window and
  a daily window in the same transaction that creates the Finding.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "acquisition_finding_admission_capacities"
    repo GnomeGarden.Repo
    identity_index_names unique_scope_key: "finding_admission_capacities_scope_key_index"

    custom_indexes do
      index [:scope, :resets_at]
    end
  end

  actions do
    defaults [:read]

    create :open do
      accept [:scope, :scope_key, :window_started_at, :resets_at, :admission_limit]
      upsert? true
      upsert_identity :unique_scope_key
      upsert_fields []
    end

    read :by_scope_key do
      argument :scope, :atom, allow_nil?: false
      argument :scope_key, :string, allow_nil?: false
      get? true
      filter expr(scope == ^arg(:scope) and scope_key == ^arg(:scope_key))
    end

    update :consume do
      change atomic_update(:admitted_count, expr(admitted_count + 1))
      validate GnomeGarden.Acquisition.Validations.FindingAdmissionCapacityAvailable
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :scope, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:run, :day]
    end

    attribute :scope_key, :string, allow_nil?: false, public?: true
    attribute :window_started_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :resets_at, :utc_datetime, public?: true
    attribute :admission_limit, :integer, allow_nil?: false, public?: true
    attribute :admitted_count, :integer, allow_nil?: false, default: 0, public?: true

    timestamps()
  end

  identities do
    identity :unique_scope_key, [:scope, :scope_key]
  end
end
