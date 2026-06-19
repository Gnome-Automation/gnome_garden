defmodule GnomeGarden.Agents.Procurement.SourceConfigurator do
  @moduledoc """
  Runs bounded source inspection for procurement sources that do not have a
  known deterministic provider configuration.

  Unknown public sources are inspected and recorded in crawl traversal storage;
  if the system cannot derive a deterministic configuration, the source is moved
  to `:config_failed` with a clear operator-facing error.
  """

  require Logger

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.SourceInspector

  @default_timeout 60_000

  @type start_result ::
          {:ok, %{source: ProcurementSource.t(), mode: :started | :already_pending}}
          | {:error, term()}

  @spec discover_source(ProcurementSource.t() | Ecto.UUID.t(), keyword()) :: start_result
  def discover_source(source_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    async? = Keyword.get(opts, :async?, true)

    with {:ok, source} <- fetch_source(source_or_id, actor),
         :ok <- ensure_discoverable(source),
         {:ok, prepared_source, mode} <- prepare_source(source, actor),
         :ok <- maybe_run_discovery(prepared_source, actor, async?, mode) do
      {:ok, %{source: prepared_source, mode: mode}}
    else
      :error -> {:error, "Browser discovery could not get clear data from this source."}
      error -> error
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

  defp maybe_run_discovery(_source, _actor, _async?, :already_pending), do: :ok

  defp maybe_run_discovery(source, actor, false, :started) do
    run_discovery(source.id, actor)
  end

  defp maybe_run_discovery(source, actor, true, :started) do
    case Task.Supervisor.start_child(GnomeGarden.AsyncSupervisor, fn ->
           run_discovery(source.id, actor)
         end) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_discovery(source_id, actor) do
    case Procurement.get_procurement_source(source_id, actor_opts(actor)) do
      {:ok, source} ->
        case SourceInspector.inspect_source(source,
               actor: actor,
               timeout_ms: @default_timeout,
               max_links: 150
             ) do
          {:ok, %{inspection: %{"requires_login" => true}}} ->
            mark_discovery_failed(
              source_id,
              actor,
              "Credentials are required before this source can be configured."
            )

          {:ok, %{run: run}} ->
            mark_discovery_failed(
              source_id,
              actor,
              "Source inspection completed in crawl run #{run.id}, but no deterministic public listing pattern could be derived automatically."
            )

          {:error, reason} ->
            mark_discovery_failed(source_id, actor, reason)
        end

      {:error, reason} ->
        mark_discovery_failed(source_id, actor, reason)
    end
  end

  defp mark_discovery_failed(source_id, actor, reason) do
    formatted_reason = format_reason(reason)

    Logger.error("[SourceConfigurator] Discovery failed for #{source_id}: #{formatted_reason}")

    with {:ok, source} <- Procurement.get_procurement_source(source_id, actor_opts(actor)),
         true <- source.config_status in [:found, :pending] do
      metadata =
        source.metadata
        |> Map.put("last_config_error", clear_data_error_message(formatted_reason))
        |> Map.put("last_config_error_at", DateTime.utc_now() |> DateTime.to_iso8601())

      source =
        case Procurement.update_procurement_source(
               source,
               %{metadata: metadata},
               actor_opts(actor)
             ) do
          {:ok, updated_source} -> updated_source
          {:error, _error} -> source
        end

      _ = Procurement.config_fail_procurement_source(source, %{}, actor_opts(actor))
    end

    :error
  end

  defp clear_data_error_message(reason) do
    "Browser discovery could not identify a reliable listing pattern for this source. #{reason}"
  end

  defp format_reason(exception) when is_exception(exception), do: Exception.message(exception)
  defp format_reason({kind, reason}), do: "#{kind}: #{inspect(reason, pretty: true)}"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason, pretty: true)

  defp actor_opts(nil), do: []
  defp actor_opts(actor), do: [actor: actor]
end
