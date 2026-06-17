defmodule GnomeGarden.Finance.Actions.BuildBankSyncHistoryWorkspace do
  @moduledoc """
  Builds the provider sync history workspace context.

  This keeps sync health as a Finance workflow instead of requiring the
  LiveView to coordinate multiple sync/event reads itself.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance

  @impl true
  def run(_input, _opts, context) do
    actor = context.actor

    with {:ok, sync_runs} <- Finance.list_bank_sync_run_history(actor: actor),
         {:ok, integration_events} <- Finance.list_bank_integration_event_history(actor: actor) do
      {:ok,
       %{
         sync_runs: sync_runs,
         integration_events: integration_events,
         latest_sync_run: List.first(sync_runs),
         latest_integration_event: List.first(integration_events),
         sync_run_count: length(sync_runs),
         succeeded_sync_count: Enum.count(sync_runs, &(&1.status == :succeeded)),
         failed_sync_count: Enum.count(sync_runs, &(&1.status == :failed)),
         running_sync_count: Enum.count(sync_runs, &(&1.status == :running)),
         partial_sync_count: Enum.count(sync_runs, &(&1.status == :partial)),
         event_count: length(integration_events),
         failed_event_count: Enum.count(integration_events, &(&1.status == :failed)),
         pending_event_count:
           Enum.count(integration_events, &(&1.status in [:received, :processing])),
         webhook_event_count: Enum.count(integration_events, &(&1.source == :webhook)),
         manual_event_count: Enum.count(integration_events, &(&1.source == :manual_sync))
       }}
    end
  end
end
