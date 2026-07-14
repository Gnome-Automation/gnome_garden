defmodule GnomeGarden.Procurement.Calculations.OnboardingState do
  @moduledoc """
  Derived source-onboarding state — never persisted, so it cannot drift from
  the fields that own it (status, config, credentials, scan history).

  `:active` requires a first successful scan: account creation alone is not
  an activated source.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [
      :enabled,
      :status,
      :config_status,
      :requires_login,
      :last_scanned_at,
      credentials: [:status]
    ]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &state/1)
  end

  defp state(source) do
    cond do
      source.status != :approved or not source.enabled ->
        :pending_approval

      source.config_status not in [:configured, :scan_failed] ->
        :needs_configuration

      source.requires_login and not has_active_credential?(source) ->
        :needs_credentials

      is_nil(source.last_scanned_at) ->
        :awaiting_first_scan

      true ->
        :active
    end
  end

  defp has_active_credential?(source),
    do: Enum.any?(source.credentials, &(&1.status == :active))
end
