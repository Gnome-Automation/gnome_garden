defmodule GnomeGarden.Commercial.DiscoveryRunner do
  @moduledoc """
  Bridges commercial discovery programs onto preview-safe live search.

  Manual and scheduled launches enqueue the same durable Oban execution path.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryExecution
  alias GnomeGarden.Acquisition

  @type launch_result :: map()

  @spec launch_program(Ecto.UUID.t() | GnomeGarden.Commercial.DiscoveryProgram.t(), keyword()) ::
          {:ok, launch_result()} | {:error, term()}
  def launch_program(program_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, program} <- load_program(program_or_id, actor),
         :ok <- ensure_runnable(program),
         {:ok, program_source} <- resolve_program_source(program, opts, actor),
         {:ok, result} <-
           DiscoveryExecution.enqueue(program,
             actor: actor,
             program_source: program_source,
             trigger: if(Keyword.get(opts, :scheduled?, false), do: :scheduled, else: :manual),
             idempotency_key: Keyword.get(opts, :idempotency_key, Ecto.UUID.generate()),
             scheduled_at: Keyword.get(opts, :scheduled_at)
           ) do
      {:ok, result}
    end
  end

  defp load_program(%{id: id}, actor), do: load_program(id, actor)

  defp load_program(id, actor) when is_binary(id) do
    Commercial.get_discovery_program(id, actor: actor)
  end

  defp ensure_runnable(%{status: :active}), do: :ok

  defp ensure_runnable(_program),
    do: {:error, "Discovery programs must be active before running."}

  defp resolve_program_source(program, opts, actor) do
    case Keyword.get(opts, :program_source) do
      %{status: :active, enabled: true} = program_source ->
        with {:ok, active_program_source} <-
               Acquisition.get_active_exa_program_source_for_discovery_program(program.id,
                 actor: actor
               ),
             true <- active_program_source.id == program_source.id do
          {:ok, active_program_source}
        else
          _invalid -> {:error, :active_program_source_required}
        end

      nil ->
        program.id
        |> Acquisition.get_active_exa_program_source_for_discovery_program(actor: actor)
        |> normalize_program_source()

      _invalid ->
        {:error, :active_program_source_required}
    end
  end

  defp normalize_program_source({:ok, program_source}), do: {:ok, program_source}
  defp normalize_program_source({:error, _error}), do: {:error, :active_program_source_required}
end
