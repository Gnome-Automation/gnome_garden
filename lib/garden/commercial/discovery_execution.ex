defmodule GnomeGarden.Commercial.DiscoveryExecution do
  @moduledoc "Creates idempotent discovery runs and enqueues their durable worker."

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryRun
  alias GnomeGarden.Commercial.DiscoveryRunWorker

  def enqueue(program, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    key = Keyword.get_lazy(opts, :idempotency_key, &Ecto.UUID.generate/0)

    attrs = %{
      discovery_program_id: program.id,
      idempotency_key: key,
      trigger: Keyword.get(opts, :trigger, :manual),
      requested_by_id: actor_id(actor),
      reserved_cost: GnomeGarden.Acquisition.LeadPreview.default_spend_ceiling(),
      query_provenance: %{
        "search_terms" => program.search_terms,
        "regions" => program.target_regions,
        "industries" => program.target_industries
      }
    }

    case Commercial.get_discovery_run_by_key(key, actor: actor) do
      {:ok, run} -> enqueue_job(run, program)
      {:error, _not_found} -> create_and_enqueue(attrs, program, actor, opts)
    end
  end

  defp create_and_enqueue(attrs, program, actor, opts) do
    with :ok <- ensure_no_active_run(program.id, actor),
         {:ok, %{run: run, job: job}} <-
           transact(fn ->
             with {:ok, run} <- Commercial.create_discovery_run(attrs, actor: actor),
                  {:ok, job} <- insert_job(run, opts) do
               {:ok, %{run: run, job: job}}
             end
           end) do
      {:ok, %{run: run, job: job, program: program}}
    else
      {:error, error} -> normalize_enqueue_error(error, program.id, actor)
    end
  end

  defp enqueue_job(run, program) do
    with {:ok, job} <- %{run_id: run.id} |> DiscoveryRunWorker.new() |> Oban.insert() do
      {:ok, %{run: run, job: job, program: program}}
    end
  end

  defp insert_job(run, opts) do
    insert_fun = Keyword.get(opts, :insert_fun, &Oban.insert/1)
    insert_fun.(DiscoveryRunWorker.new(%{run_id: run.id}))
  end

  defp ensure_no_active_run(program_id, actor) do
    case Commercial.get_active_discovery_run_for_program(program_id, actor: actor) do
      {:ok, _run} -> {:error, :active_run_exists}
      {:error, _not_found} -> :ok
    end
  end

  defp normalize_enqueue_error(:active_run_exists, _program_id, _actor),
    do: {:error, :active_run_exists}

  defp normalize_enqueue_error(error, program_id, actor) do
    case Commercial.get_active_discovery_run_for_program(program_id, actor: actor) do
      {:ok, _run} -> {:error, :active_run_exists}
      {:error, _not_found} -> {:error, error}
    end
  end

  defp transact(function) do
    case Ash.transact([DiscoveryRun], function) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, error}} -> {:error, error}
      result -> result
    end
  end

  defp actor_id(%{id: id}), do: id
  defp actor_id(_actor), do: nil
end
