defmodule GnomeGarden.Finance.Actions.IngestMercuryWebhookEvent do
  @moduledoc """
  Records a Mercury webhook event and triggers the provider pull-sync boundary.
  """

  use Ash.Resource.Actions.Implementation

  alias GnomeGarden.Finance
  alias GnomeGarden.Finance.BankSyncWorker

  @sync_event_types ~w(transaction.created transaction.updated balance.updated)

  @impl true
  def run(input, _opts, context) do
    event_type = Ash.ActionInput.get_argument(input, :event_type)
    payload = Ash.ActionInput.get_argument(input, :payload)

    attrs =
      %{
        provider: :mercury,
        provider_event_id: payload["eventId"] || payload["id"],
        event_type: event_type,
        source: :webhook,
        status: event_status(event_type),
        error_message: event_error(event_type),
        bank_account_id: local_bank_account_id(payload, context.actor),
        payload: payload
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    with {:ok, event} <-
           Finance.record_bank_integration_event(attrs,
             actor: context.actor,
             authorize?: false
           ),
         {:ok, job} <- maybe_enqueue_sync(event_type) do
      {:ok, %{event: event, sync_job: job, sync_enqueued?: not is_nil(job)}}
    end
  end

  defp maybe_enqueue_sync(event_type) when event_type in @sync_event_types do
    BankSyncWorker.new(%{
      "provider" => "mercury",
      "environment" => "production",
      "source" => "webhook"
    })
    |> Oban.insert()
  end

  defp maybe_enqueue_sync(_event_type), do: {:ok, nil}

  defp local_bank_account_id(%{"accountId" => provider_account_id}, actor)
       when is_binary(provider_account_id) do
    case Finance.get_bank_account_by_provider_id(:mercury, provider_account_id,
           actor: actor,
           authorize?: false
         ) do
      {:ok, account} -> account.id
      {:error, _error} -> nil
    end
  end

  defp local_bank_account_id(_payload, _actor), do: nil

  defp event_status(event_type) when event_type in @sync_event_types, do: :received
  defp event_status(_event_type), do: :ignored

  defp event_error(event_type) when event_type in @sync_event_types, do: nil
  defp event_error(event_type), do: "Unknown Mercury webhook event: #{event_type}"
end
