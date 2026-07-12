defmodule GnomeGarden.Commercial.DiscoveryRunner do
  @moduledoc """
  Bridges commercial discovery programs onto preview-safe live search.

  Manual and scheduled launches enqueue the same durable Oban execution path.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryExecution

  @type launch_result :: map()

  @spec launch_program(Ecto.UUID.t() | GnomeGarden.Commercial.DiscoveryProgram.t(), keyword()) ::
          {:ok, launch_result()} | {:error, term()}
  def launch_program(program_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, program} <- load_program(program_or_id, actor),
         :ok <- ensure_runnable(program),
         {:ok, result} <-
           DiscoveryExecution.enqueue(program,
             actor: actor,
             trigger: if(Keyword.get(opts, :scheduled?, false), do: :scheduled, else: :manual),
             idempotency_key: Keyword.get(opts, :idempotency_key, Ecto.UUID.generate())
           ) do
      {:ok, result}
    end
  end

  defp load_program(%{id: id}, actor), do: load_program(id, actor)

  defp load_program(id, actor) when is_binary(id) do
    Commercial.get_discovery_program(id, actor: actor)
  end

  defp ensure_runnable(%{status: :archived}),
    do: {:error, "Archived discovery programs must be reopened before running."}

  defp ensure_runnable(_program), do: :ok
end
