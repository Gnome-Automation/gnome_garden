defmodule GnomeGarden.Commercial.DiscoveryExecution do
  @moduledoc "Creates idempotent discovery runs and enqueues their durable worker."

  alias GnomeGarden.Commercial
  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.ProgramSource
  alias GnomeGarden.Commercial.DiscoveryRun
  alias GnomeGarden.Commercial.DiscoveryRunWorker

  def enqueue(program, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    key = Keyword.get_lazy(opts, :idempotency_key, &Ecto.UUID.generate/0)
    program_source = Keyword.fetch!(opts, :program_source)
    policy_snapshot = policy_snapshot(program_source)

    attrs = %{
      discovery_program_id: program.id,
      program_source_id: program_source.id,
      idempotency_key: key,
      trigger: Keyword.get(opts, :trigger, :manual),
      requested_by_id: actor_id(actor),
      reserved_cost: program_source.spend_limit_per_run.amount,
      query_provenance: policy_snapshot
    }

    case Commercial.get_discovery_run_by_key(key, actor: actor) do
      {:ok, run} -> enqueue_job(run, program)
      {:error, _not_found} -> create_and_enqueue(attrs, program, program_source, actor, opts)
    end
  end

  defp create_and_enqueue(attrs, program, program_source, actor, opts) do
    with :ok <- ensure_no_active_run(program.id, actor),
         {:ok, %{run: run, job: job}} <-
           transact(fn ->
             with {:ok, run} <- Commercial.create_discovery_run(attrs, actor: actor),
                  {:ok, job} <- insert_job(run, opts),
                  {:ok, program_source} <- maybe_mark_scheduled(program_source, actor, opts) do
               {:ok, %{run: run, job: job, program_source: program_source}}
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

  defp maybe_mark_scheduled(program_source, actor, opts) do
    case {Keyword.get(opts, :trigger), Keyword.get(opts, :scheduled_at)} do
      {:scheduled, %DateTime{} = scheduled_at} ->
        Acquisition.mark_program_source_scheduled(
          program_source,
          scheduled_at,
          actor: actor
        )

      _manual_or_unspecified ->
        {:ok, program_source}
    end
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
    case Ash.transact([DiscoveryRun, ProgramSource], function) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, error}} -> {:error, error}
      result -> result
    end
  end

  defp actor_id(%{id: id}), do: id
  defp actor_id(_actor), do: nil

  defp policy_snapshot(program_source) do
    snapshot = %{
      "program_source_id" => program_source.id,
      "source_id" => program_source.source_id,
      "query_templates" => program_source.query_templates,
      "cadence_minutes" => program_source.cadence_minutes,
      "max_queries_per_run" => program_source.max_queries_per_run,
      "max_results_per_query" => program_source.max_results_per_query,
      "spend_limit_per_run" => Decimal.to_string(program_source.spend_limit_per_run.amount),
      "spend_limit_per_day" => Decimal.to_string(program_source.spend_limit_per_day.amount),
      "currency" => to_string(program_source.spend_limit_per_run.currency),
      "enrichment_policy" => to_string(program_source.enrichment_policy),
      "max_enrichments_per_run" => program_source.max_enrichments_per_run,
      "finding_limit_per_run" => program_source.finding_limit_per_run,
      "finding_limit_per_day" => program_source.finding_limit_per_day,
      "adapter" => "exa",
      "adapter_version" => "1",
      "capability_manifest" => ["exa.search", "exa.contents"]
    }

    Map.put(snapshot, "policy_hash", policy_hash(snapshot))
  end

  defp policy_hash(snapshot) do
    snapshot
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
