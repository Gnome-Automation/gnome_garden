defmodule GnomeGarden.Procurement.OnboardingStateTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Procurement.Calculations.OnboardingState

  test "activation requires a successful scan" do
    source = source_fixture()

    assert OnboardingState.calculate([source], [], %{}) == [:awaiting_first_scan]

    scanned = %{source | last_scanned_at: DateTime.utc_now()}
    assert OnboardingState.calculate([scanned], [], %{}) == [:active]
  end

  test "BidNet activation requires a current browser session" do
    source = %{
      source_fixture()
      | source_type: :bidnet,
        requires_login: true,
        last_scanned_at: DateTime.utc_now(),
        credentials: [%{status: :active, test_status: :verified}]
    }

    assert OnboardingState.calculate([source], [], %{}) == [:needs_credentials]

    ready = %{
      source
      | browser_sessions: [
          %{status: :valid, expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second)}
        ]
    }

    assert OnboardingState.calculate([ready], [], %{}) == [:active]
  end

  defp source_fixture do
    %{
      enabled: true,
      status: :approved,
      source_type: :planetbids,
      config_status: :configured,
      requires_login: false,
      last_scanned_at: nil,
      credentials: [],
      browser_sessions: []
    }
  end
end
