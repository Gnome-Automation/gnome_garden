defmodule GnomeGarden.Acquisition.ProviderBudget do
  @moduledoc """
  One immutable provider quota window with atomically maintained capacity.

  New windows reset capacity without erasing historical spend. Reservations
  hold capacity until they are settled to actual provider cost or released.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "acquisition_provider_budgets"
    repo GnomeGarden.Repo
    identity_index_names unique_provider_operation_window: "provider_budgets_window_index"

    custom_indexes do
      index [:provider, :operation, :resets_at]
    end
  end

  actions do
    defaults [:read]

    create :open_window do
      accept [
        :provider,
        :operation,
        :window_key,
        :window_started_at,
        :resets_at,
        :spend_limit,
        :request_limit
      ]

      upsert? true
      upsert_identity :unique_provider_operation_window
      upsert_fields []
    end

    read :by_window do
      argument :provider, :string, allow_nil?: false
      argument :operation, :string, allow_nil?: false
      argument :window_key, :string, allow_nil?: false
      get? true

      filter expr(
               provider == ^arg(:provider) and operation == ^arg(:operation) and
                 window_key == ^arg(:window_key)
             )

      prepare build(load: [:remaining_cost, :remaining_requests])
    end

    update :reserve_capacity do
      argument :estimated_cost, :decimal, allow_nil?: false
      argument :estimated_requests, :integer, allow_nil?: false

      change atomic_update(:reserved_cost, expr(reserved_cost + ^arg(:estimated_cost)))

      change atomic_update(
               :reserved_requests,
               expr(reserved_requests + ^arg(:estimated_requests))
             )

      validate GnomeGarden.Acquisition.Validations.ProviderCapacityAvailable
    end

    update :settle_capacity do
      argument :estimated_cost, :decimal, allow_nil?: false
      argument :actual_cost, :decimal, allow_nil?: false
      argument :estimated_requests, :integer, allow_nil?: false
      argument :actual_requests, :integer, allow_nil?: false

      change atomic_update(:reserved_cost, expr(reserved_cost - ^arg(:estimated_cost)))
      change atomic_update(:spent_cost, expr(spent_cost + ^arg(:actual_cost)))

      change atomic_update(
               :reserved_requests,
               expr(reserved_requests - ^arg(:estimated_requests))
             )

      change atomic_update(:used_requests, expr(used_requests + ^arg(:actual_requests)))
    end

    update :release_capacity do
      argument :estimated_cost, :decimal, allow_nil?: false
      argument :estimated_requests, :integer, allow_nil?: false

      change atomic_update(:reserved_cost, expr(reserved_cost - ^arg(:estimated_cost)))

      change atomic_update(
               :reserved_requests,
               expr(reserved_requests - ^arg(:estimated_requests))
             )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :operation, :string, allow_nil?: false, public?: true
    attribute :window_key, :string, allow_nil?: false, public?: true
    attribute :window_started_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :resets_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :spend_limit, :decimal, allow_nil?: false, public?: true
    attribute :request_limit, :integer, allow_nil?: false, public?: true
    attribute :reserved_cost, :decimal, allow_nil?: false, default: Decimal.new(0), public?: true
    attribute :spent_cost, :decimal, allow_nil?: false, default: Decimal.new(0), public?: true
    attribute :reserved_requests, :integer, allow_nil?: false, default: 0, public?: true
    attribute :used_requests, :integer, allow_nil?: false, default: 0, public?: true

    timestamps()
  end

  relationships do
    has_many :reservations, GnomeGarden.Acquisition.ProviderReservation do
      public? true
    end
  end

  calculations do
    calculate :remaining_cost,
              :decimal,
              expr(spend_limit - spent_cost - reserved_cost)

    calculate :remaining_requests,
              :integer,
              expr(request_limit - used_requests - reserved_requests)
  end

  identities do
    identity :unique_provider_operation_window, [:provider, :operation, :window_key]
  end
end
