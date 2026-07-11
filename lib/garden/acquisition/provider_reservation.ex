defmodule GnomeGarden.Acquisition.ProviderReservation do
  @moduledoc """
  Idempotent capacity reservation for one provider operation.

  A released zero-cost reservation can be reopened by a retry while retaining
  its original identity. Settled reservations are immutable audit records.
  """

  use Ash.Resource,
    otp_app: :gnome_garden,
    domain: GnomeGarden.Acquisition,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "acquisition_provider_reservations"
    repo GnomeGarden.Repo

    references do
      reference :provider_budget, on_delete: :restrict
    end

    custom_indexes do
      index [:provider_budget_id, :status], name: "provider_reservations_budget_status_index"
    end
  end

  actions do
    defaults [:read]

    action :reserve, :map do
      argument :request, :map, allow_nil?: false
      run GnomeGarden.Acquisition.Actions.ReserveProviderCapacity
    end

    action :settle, :map do
      argument :settlement, :map, allow_nil?: false
      run GnomeGarden.Acquisition.Actions.SettleProviderCapacity
    end

    action :release, :map do
      argument :release, :map, allow_nil?: false
      run GnomeGarden.Acquisition.Actions.ReleaseProviderCapacity
    end

    create :create do
      accept [
        :provider_budget_id,
        :idempotency_key,
        :estimated_cost,
        :estimated_requests,
        :metadata
      ]
    end

    read :by_idempotency_key do
      argument :idempotency_key, :string, allow_nil?: false
      get? true
      filter expr(idempotency_key == ^arg(:idempotency_key))
      prepare build(load: [:provider_budget])
    end

    update :mark_settled do
      accept [:status, :actual_cost, :actual_requests, :failure_reason]
      validate GnomeGarden.Acquisition.Validations.ProviderReservationOpen
    end

    update :mark_released do
      accept [:failure_reason]
      change set_attribute(:status, :released)
      validate GnomeGarden.Acquisition.Validations.ProviderReservationOpen
    end

    update :reopen do
      change set_attribute(:status, :reserved)
      change set_attribute(:failure_reason, nil)
      validate GnomeGarden.Acquisition.Validations.ProviderReservationReopenable
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :idempotency_key, :string, allow_nil?: false, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :reserved
      public? true
      constraints one_of: [:reserved, :settled, :partial_failure, :failed, :released]
    end

    attribute :estimated_cost, :decimal, allow_nil?: false, public?: true
    attribute :actual_cost, :decimal, allow_nil?: false, default: Decimal.new(0), public?: true
    attribute :estimated_requests, :integer, allow_nil?: false, public?: true
    attribute :actual_requests, :integer, allow_nil?: false, default: 0, public?: true
    attribute :failure_reason, :string, public?: true
    attribute :metadata, :map, allow_nil?: false, default: %{}, public?: true

    timestamps()
  end

  relationships do
    belongs_to :provider_budget, GnomeGarden.Acquisition.ProviderBudget do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_idempotency_key, [:idempotency_key]
  end
end
