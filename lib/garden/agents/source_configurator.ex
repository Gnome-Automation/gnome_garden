defmodule GnomeGarden.Agents.SourceConfigurator do
  @moduledoc """
  Launches browser-based site discovery for procurement sources.

  This is the "figure out the site once" path: SmartScanner uses Jido browser
  primitives to discover a source's scrape configuration and saves it for later
  deterministic scans.
  """

  require Logger

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Agents.Workers.Sales.SmartScanner

  @default_timeout 600_000

  @type start_result ::
          {:ok, %{source: ProcurementSource.t(), mode: :started | :already_pending}}
          | {:error, term()}

  @spec discover_source(ProcurementSource.t() | Ecto.UUID.t(), keyword()) :: start_result
  def discover_source(source_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, source} <- fetch_source(source_or_id, actor),
         :ok <- ensure_discoverable(source),
         {:ok, prepared_source, mode} <- prepare_source(source, actor),
         {:ok, _pid} <-
           Task.Supervisor.start_child(GnomeGarden.AsyncSupervisor, fn ->
             run_discovery(prepared_source.id, actor)
           end) do
      {:ok, %{source: prepared_source, mode: mode}}
    end
  end

  defp fetch_source(%ProcurementSource{} = source, _actor), do: {:ok, source}

  defp fetch_source(id, actor) when is_binary(id) do
    Procurement.get_procurement_source(id, actor_opts(actor))
  end

  defp ensure_discoverable(%{status: :approved, config_status: status})
       when status in [:found, :pending, :config_failed],
       do: :ok

  defp ensure_discoverable(%{status: status}) when status != :approved do
    {:error, "Only approved sources can be configured."}
  end

  defp ensure_discoverable(%{config_status: :configured}),
    do: {:error, "This source is already configured."}

  defp ensure_discoverable(%{config_status: :scan_failed}),
    do: {:error, "This source is already configured. Use scan retry instead."}

  defp ensure_discoverable(%{config_status: status}),
    do: {:error, "This source cannot be discovered from state #{status}."}

  defp prepare_source(%{config_status: :found} = source, actor) do
    case Procurement.queue_procurement_source(source, %{}, actor_opts(actor)) do
      {:ok, queued_source} -> {:ok, queued_source, :started}
      {:error, error} -> {:error, error}
    end
  end

  defp prepare_source(%{config_status: :config_failed} = source, actor) do
    case Procurement.retry_procurement_source_config(source, %{}, actor_opts(actor)) do
      {:ok, retried_source} -> {:ok, retried_source, :started}
      {:error, error} -> {:error, error}
    end
  end

  defp prepare_source(%{config_status: :pending} = source, _actor),
    do: {:ok, source, :already_pending}

  defp run_discovery(source_id, actor) do
    runtime_instance_id =
      "smart_scanner_discovery:#{source_id}:#{System.unique_integer([:positive])}"

    case GnomeGarden.Jido.start_agent(SmartScanner, id: runtime_instance_id) do
      {:ok, pid} ->
        try do
          case SmartScanner.discover_site(pid, source_id, timeout: @default_timeout) do
            {:ok, result} ->
              Logger.info(
                "[SourceConfigurator] Discovery finished for #{source_id}: #{inspect(result, limit: 10)}"
              )

              :ok

            {:error, reason} ->
              mark_discovery_failed(source_id, actor, reason)
          end
        rescue
          exception ->
            mark_discovery_failed(source_id, actor, exception)
        catch
          kind, reason ->
            mark_discovery_failed(source_id, actor, {kind, reason})
        after
          _ = GnomeGarden.Jido.stop_agent(runtime_instance_id)
        end

      {:error, reason} ->
        mark_discovery_failed(source_id, actor, reason)
    end
  end

  defp mark_discovery_failed(source_id, actor, reason) do
    Logger.error(
      "[SourceConfigurator] Discovery failed for #{source_id}: #{format_reason(reason)}"
    )

    with {:ok, source} <- Procurement.get_procurement_source(source_id, actor_opts(actor)),
         true <- source.config_status in [:found, :pending] do
      _ = Procurement.config_fail_procurement_source(source, %{}, actor_opts(actor))
    end

    :error
  end

  defp format_reason(exception) when is_exception(exception), do: Exception.message(exception)
  defp format_reason({kind, reason}), do: "#{kind}: #{inspect(reason, pretty: true)}"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason, pretty: true)

  defp actor_opts(nil), do: []
  defp actor_opts(actor), do: [actor: actor]
end
