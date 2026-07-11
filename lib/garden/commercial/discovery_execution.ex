defmodule GnomeGarden.Commercial.DiscoveryExecution do
  @moduledoc "Creates idempotent discovery runs and enqueues their durable worker."

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryRunWorker

  def enqueue(program, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    key = Keyword.get_lazy(opts, :idempotency_key, &Ecto.UUID.generate/0)

    attrs = %{
      discovery_program_id: program.id,
      idempotency_key: key,
      trigger: Keyword.get(opts, :trigger, :manual),
      requested_by_id: actor_id(actor),
      reserved_cost: Decimal.new("0.25"),
      query_provenance: %{
        "search_terms" => program.search_terms,
        "regions" => program.target_regions,
        "industries" => program.target_industries
      }
    }

    with {:ok, run} <- Commercial.create_discovery_run(attrs, actor: actor),
         {:ok, job} <- %{run_id: run.id} |> DiscoveryRunWorker.new() |> Oban.insert() do
      {:ok, %{run: run, job: job, program: program}}
    end
  end

  defp actor_id(%{id: id}), do: id
  defp actor_id(_actor), do: nil
end
