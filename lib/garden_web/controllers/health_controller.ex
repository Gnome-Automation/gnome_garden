defmodule GnomeGardenWeb.HealthController do
  use GnomeGardenWeb, :controller

  alias Ecto.Adapters.SQL
  alias GnomeGarden.Agents
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement
  alias GnomeGarden.Repo

  def show(conn, _params) do
    text(conn, "ok")
  end

  def ready(conn, _params) do
    checks = %{
      database: database_check(),
      document_storage: document_storage_check(),
      background_jobs: background_jobs_check(),
      agent_operating_system: agent_operating_system_check()
    }

    status =
      if ready?(checks) do
        :ok
      else
        :service_unavailable
      end

    conn
    |> put_status(status)
    |> json(%{
      status: status_label(status),
      checks: checks
    })
  end

  defp database_check do
    case SQL.query(Repo, "SELECT 1", [], timeout: 1_000, log: false) do
      {:ok, _result} -> %{status: "ok"}
      {:error, error} -> %{status: "error", message: Exception.message(error)}
    end
  end

  defp document_storage_check do
    storage_config = document_storage_config()

    case Keyword.get(storage_config, :service) do
      {AshStorage.Service.S3, opts} ->
        s3_storage_check(opts)

      {AshStorage.Service.Test, _opts} ->
        %{status: "ok", mode: "test"}

      {AshStorage.Service.Disk, _opts} ->
        %{status: "ok", mode: "local"}

      {_service, _opts} ->
        %{status: "ok", mode: "configured"}

      nil ->
        fallback_storage_check()
    end
  end

  defp background_jobs_check do
    case Oban.Registry.whereis(Oban) do
      pid when is_pid(pid) ->
        queue_names = oban_queue_names()

        %{status: "ok"}
        |> maybe_put_non_empty(:queues, queue_names)
        |> maybe_add_stale_executing_jobs()

      nil ->
        %{status: "error", message: "Oban supervisor is not running"}
    end
  end

  defp oban_queue_names do
    Oban
    |> Oban.config()
    |> Map.get(:queues, [])
    |> Keyword.keys()
    |> Enum.map(&to_string/1)
  end

  defp maybe_add_stale_executing_jobs(check) do
    case stale_executing_jobs() do
      {:ok, []} ->
        check

      {:ok, jobs} ->
        check
        |> Map.put(:status, "error")
        |> Map.put(:message, "Oban has jobs stuck executing for more than 60 minutes")
        |> Map.put(:stale_executing_jobs, jobs)

      {:error, error} ->
        check
        |> Map.put(:status, "error")
        |> Map.put(:message, Exception.message(error))
    end
  end

  defp stale_executing_jobs do
    query = """
    SELECT id, queue, worker, scheduled_at, attempted_at
    FROM oban_jobs
    WHERE state = 'executing'
      AND attempted_at < now() - interval '60 minutes'
    ORDER BY attempted_at ASC
    LIMIT 5
    """

    case SQL.query(Repo, query, [], timeout: 1_000, log: false) do
      {:ok, %{rows: rows}} ->
        jobs =
          Enum.map(rows, fn [id, queue, worker, scheduled_at, attempted_at] ->
            %{
              id: id,
              queue: queue,
              worker: worker,
              scheduled_at: scheduled_at,
              attempted_at: attempted_at
            }
          end)

        {:ok, jobs}

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_put_non_empty(map, _key, []), do: map
  defp maybe_put_non_empty(map, key, value), do: Map.put(map, key, value)

  defp agent_operating_system_check do
    %{
      status: "ok",
      active_agent_runs: count_or_zero(&Agents.list_active_agent_runs/1),
      recent_failed_agent_runs:
        count_or_zero(fn opts -> Agents.list_recent_failed_agent_runs(10, opts) end),
      pending_memory_blocks: count_or_zero(&Operations.list_pending_memory_blocks/1),
      pending_memory_entries: count_or_zero(&Operations.list_pending_memory_entries/1),
      pending_learning_recommendations:
        count_or_zero(&Operations.list_pending_learning_recommendations/1),
      eval_runs: eval_run_counts(),
      workflow_definitions: workflow_definition_counts(),
      credential_blockers:
        count_or_zero(&Procurement.list_credential_blocked_procurement_sources/1)
    }
  end

  defp workflow_definition_counts do
    case Agents.list_agent_workflow_definitions(query: [select: [:id, :status]]) do
      {:ok, definitions} ->
        %{
          total: length(definitions),
          published: Enum.count(definitions, &(&1.status == :published)),
          disabled: Enum.count(definitions, &(&1.status == :disabled))
        }

      {:error, _error} ->
        %{total: 0, published: 0, disabled: 0}
    end
  end

  defp eval_run_counts do
    case Agents.list_recent_agent_eval_runs(20, query: [select: [:id, :status]]) do
      {:ok, runs} ->
        %{
          recent: length(runs),
          passed: Enum.count(runs, &(&1.status == :passed)),
          failed: Enum.count(runs, &(&1.status == :failed)),
          error: Enum.count(runs, &(&1.status == :error))
        }

      {:error, _error} ->
        %{recent: 0, passed: 0, failed: 0, error: 0}
    end
  end

  defp count_or_zero(fun) do
    case fun.(query: [select: [:id]]) do
      {:ok, records} -> length(records)
      {:error, _error} -> 0
    end
  end

  defp document_storage_config do
    :gnome_garden
    |> Application.get_env(GnomeGarden.Acquisition.Document, [])
    |> Keyword.get(:storage, [])
  end

  defp s3_storage_check(opts) do
    missing =
      [:bucket, :access_key_id, :secret_access_key]
      |> Enum.reject(&present_option?(opts, &1))

    if missing == [] do
      %{status: "ok", mode: "external", service: "s3"}
    else
      %{
        status: "error",
        mode: "external",
        service: "s3",
        message: "missing S3 storage options: #{Enum.join(missing, ", ")}"
      }
    end
  end

  defp fallback_storage_check do
    if Application.get_env(:gnome_garden, :serve_local_storage?, false) do
      %{status: "ok", mode: "local"}
    else
      %{status: "error", message: "document storage service is not configured"}
    end
  end

  defp present_option?(opts, key) do
    case Keyword.get(opts, key) do
      nil -> false
      "" -> false
      _value -> true
    end
  end

  defp ready?(checks) do
    Enum.all?(checks, fn {_name, check} -> check.status == "ok" end)
  end

  defp status_label(:ok), do: "ok"
  defp status_label(:service_unavailable), do: "error"
end
