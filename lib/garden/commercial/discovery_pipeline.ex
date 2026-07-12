defmodule GnomeGarden.Commercial.DiscoveryPipeline do
  @moduledoc """
  Bounded live-search orchestration for commercial discovery programs.

  Production execution persists preview-safe Exa search telemetry, verifies a
  bounded candidate set, and admits only qualified companies as Findings.
  """

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
         {:ok, preview} <-
           LeadPreview.run_for_program(
             program,
             actor: actor,
             discovery_program_id: program.id,
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
           Float.round(preview.total_cost + Decimal.to_float(verification.enrichment_cost), 4),
         failed_queries: preview.failed_queries + length(verification.errors),
         errors: preview.errors ++ verification.errors
       })}
    end
  end

  defp fetch_program(%DiscoveryProgram{id: id}, actor), do: fetch_program(id, actor)

  defp fetch_program(id, actor) when is_binary(id),
    do: Commercial.get_discovery_program(id, actor: actor)
end
