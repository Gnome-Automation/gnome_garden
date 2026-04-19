defmodule GnomeGarden.Commercial.TargetAccountTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Commercial

  test "promote_target_account_to_signal creates and links a signal" do
    {:ok, target_account} =
      Commercial.create_target_account(%{
        name: "Mesa Controls Brewing",
        website: "https://www.mesacontrolsbrewing.com",
        location: "Anaheim, CA",
        region: "oc",
        industry: "brewery",
        fit_score: 81,
        intent_score: 88,
        notes: "Hiring controls engineer after adding a second canning line."
      })

    {:ok, _observation} =
      Commercial.create_target_observation(%{
        target_account_id: target_account.id,
        observation_type: :hiring,
        source_channel: :job_board,
        external_ref: "target-account-test:mesa-controls-brewing:hiring",
        source_url: "https://example.com/jobs/mesa-controls-brewing",
        observed_at: DateTime.utc_now(),
        confidence_score: 88,
        summary: "Hiring controls engineer for canning line expansion"
      })

    {:ok, promoted_target_account} =
      Commercial.promote_target_account_to_signal(target_account)

    assert promoted_target_account.status == :promoted
    assert promoted_target_account.promoted_signal_id

    {:ok, signal} = Commercial.get_signal(promoted_target_account.promoted_signal_id)

    assert signal.signal_type == :outbound_target
    assert signal.source_channel == :agent_discovery
    assert metadata_value(signal.metadata, :target_account_id) == target_account.id
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
