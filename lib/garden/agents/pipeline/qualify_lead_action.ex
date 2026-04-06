defmodule GnomeGarden.Agents.Pipeline.QualifyLeadAction do
  @moduledoc """
  Reacts to an enriched lead signal. Decides whether to qualify
  or disqualify the lead based on enrichment data, then fires
  the appropriate Ash action.
  """
  use Jido.Action,
    name: "qualify_lead",
    description: "Auto-qualify or disqualify an enriched lead",
    schema: [
      lead_id: [type: :string, required: true, doc: "Lead ID"],
      matched_company_id: [type: :string, doc: "Matched CRM company ID"],
      needs_research: [type: :boolean, default: false, doc: "Whether more research is needed"],
      region: [type: :atom, doc: "Region from enrichment"],
      company_type: [type: :atom, doc: "Company type from enrichment"]
    ]

  @impl true
  def run(params, _context) do
    lead_id = params.lead_id

    case GnomeGarden.Sales.get_lead(lead_id) do
      {:ok, lead} ->
        decision = decide(params, lead)
        apply_decision(lead, decision)

      {:error, reason} ->
        {:ok, %{action: :failed, lead_id: lead_id, error: inspect(reason)}}
    end
  end

  defp decide(params, lead) do
    cond do
      # Already has a matching company in CRM — strong signal
      params[:matched_company_id] != nil ->
        :qualify

      # From a bid source with details — likely worth pursuing
      lead.source == :bid and lead.source_details != nil ->
        :qualify

      # Needs more research — leave as-is for now
      params[:needs_research] ->
        :hold

      # Default — leave for manual review
      true ->
        :hold
    end
  end

  defp apply_decision(lead, :qualify) do
    case Ash.update(lead, %{}, action: :qualify) do
      {:ok, updated} ->
        {:ok, %{action: :qualified, lead_id: updated.id, status: :qualified}}

      {:error, reason} ->
        {:ok, %{action: :qualify_failed, lead_id: lead.id, error: inspect(reason)}}
    end
  end

  defp apply_decision(lead, :hold) do
    {:ok, %{action: :held, lead_id: lead.id, reason: :needs_manual_review}}
  end
end
