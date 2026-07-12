defmodule GnomeGarden.Acquisition.TelemetryTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Acquisition.Telemetry

  test "emits bounded provider and trace events" do
    handler = "acquisition-telemetry-#{System.unique_integer([:positive])}"

    events = [
      [:gnome_garden, :acquisition, :provider, :stop],
      [:gnome_garden, :acquisition, :candidate, :routed]
    ]

    :ok = :telemetry.attach_many(handler, events, &send_event/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    Telemetry.provider(:exa, :search, :ok, %{duration: 10, cost: 0.01, result_count: 2})
    Telemetry.candidate_routing(%{candidate_count: 2}, %{lead_preview_run_id: "trace-id"})

    assert_receive {[:gnome_garden, :acquisition, :provider, :stop], measurements, metadata}
    assert measurements.result_count == 2
    assert metadata == %{provider: :exa, operation: :search, outcome: :ok}

    assert_receive {[:gnome_garden, :acquisition, :candidate, :routed], _, trace}
    assert trace.lead_preview_run_id == "trace-id"
  end

  test "evaluates SLOs and emits alerts without high-cardinality tags" do
    handler = "acquisition-slo-#{System.unique_integer([:positive])}"
    event = [:gnome_garden, :acquisition, :slo, :alert]
    :ok = :telemetry.attach(handler, event, &send_event/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    alerts = Telemetry.evaluate_slos(%{queue_backlog: 30, budget_remaining_ratio: 0.05})
    assert Enum.map(alerts, & &1.kind) == [:queue_backlog, :provider_budget_exhaustion]

    assert_receive {^event, %{value: 30, threshold: 25, count: 1}, metadata}
    assert metadata == %{kind: :queue_backlog, severity: :warning}
    refute Map.has_key?(metadata, :run_id)
  end

  defp send_event(event, measurements, metadata, pid),
    do: send(pid, {event, measurements, metadata})
end
