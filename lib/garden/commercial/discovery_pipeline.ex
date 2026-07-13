defmodule GnomeGarden.Commercial.DiscoveryPipeline do
  @moduledoc """
  Bounded live-search orchestration for commercial discovery programs.

  Production execution persists preview-safe Exa search telemetry, verifies a
  bounded candidate set, and admits only qualified companies as Findings.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.LeadPreview
  alias GnomeGarden.Commercial
  alias GnomeGarden.Commercial.DiscoveryProgram

  @type pipeline_result :: {:ok, map()} | {:error, term()}

  @doc "Describes the candidate source used by scheduled discovery execution."
  @spec execution_profile() :: map()
  def execution_profile do
    %{
      mode: :live_exa_verified,
      live_search?: true,
      candidate_source: :exa,
      preview_only?: false,
      finding_admission?: true
    }
  end

  @spec run_program(DiscoveryProgram.t() | Ecto.UUID.t(), keyword()) :: pipeline_result
  def run_program(program_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, program} <- fetch_program(program_or_id, actor),
         {:ok, program_source} <- resolve_program_source(program, opts, actor),
         {:ok, preview} <-
           LeadPreview.run_for_program(
             program,
             actor: actor,
             discovery_program_id: program.id,
             program_source_id: program_source.id,
             execution_policy_snapshot: Keyword.get(opts, :execution_policy_snapshot),
             budget_idempotency_key:
               Keyword.get_lazy(opts, :budget_idempotency_key, &Ecto.UUID.generate/0),
             persist: true
           ),
         {:ok, verification} <-
           GnomeGarden.Acquisition.verify_lead_preview_run(preview.run_id, actor: actor),
         {:ok, _program} <- Commercial.mark_discovery_program_ran(program, actor: actor) do
      {:ok,
       preview
       |> Map.merge(verification)
       |> Map.merge(%{
         program: program,
         mode: :live_exa_verified,
         total_cost:
           Decimal.add(Decimal.from_float(preview.total_cost), verification.enrichment_cost),
         failed_queries: preview.failed_queries + length(verification.errors),
         errors: preview.errors ++ verification.errors
       })}
    end
  end

  defp fetch_program(%DiscoveryProgram{id: id}, actor), do: fetch_program(id, actor)

  defp fetch_program(id, actor) when is_binary(id),
    do: Commercial.get_discovery_program(id, actor: actor)

  defp resolve_program_source(program, opts, actor) do
    case {Keyword.get(opts, :program_source_id), Keyword.get(opts, :execution_policy_snapshot)} do
      {program_source_id, %{"program_source_id" => program_source_id}}
      when is_binary(program_source_id) ->
        Acquisition.get_program_source(program_source_id, actor: actor)

      {nil, nil} ->
        program.id
        |> Acquisition.get_active_exa_program_source_for_discovery_program(actor: actor)
        |> normalize_program_source()

      {program_source_id, nil} ->
        with {:ok, program_source} <-
               Acquisition.get_program_source(program_source_id, actor: actor),
             true <- program_source.status == :active and program_source.enabled do
          {:ok, program_source}
        else
          _invalid -> {:error, :active_program_source_required}
        end

      _mismatch ->
        {:error, :invalid_program_source_snapshot}
    end
  end

  defp normalize_program_source({:ok, program_source}), do: {:ok, program_source}
  defp normalize_program_source({:error, _error}), do: {:error, :active_program_source_required}
end
