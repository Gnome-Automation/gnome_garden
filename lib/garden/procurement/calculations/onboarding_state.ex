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
      :source_type,
      :config_status,
      :requires_login,
      :last_scanned_at,
      credentials: [:status, :test_status],
      browser_sessions: [:status, :expires_at]
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

      source.requires_login and not authentication_ready?(source) ->
        :needs_credentials

      is_nil(source.last_scanned_at) ->
        :awaiting_first_scan

      true ->
        :active
    end
  end

  defp authentication_ready?(source) do
    credential_ready?(source) and
      (source.source_type != :bidnet or has_valid_browser_session?(source))
  end

  defp credential_ready?(source) do
    Enum.any?(source.credentials, fn credential ->
      credential.status == :active and credential.test_status == :verified
    end) or
      GnomeGarden.Procurement.SourceCredentials.credential_status(source) in [
        :verified,
        :env_configured
      ]
  end

  defp has_valid_browser_session?(source) do
    now = DateTime.utc_now()

    Enum.any?(source.browser_sessions, fn session ->
      session.status == :valid and
        match?(%DateTime{}, session.expires_at) and
        DateTime.after?(session.expires_at, now)
    end)
  end
end
