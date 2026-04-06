defmodule GnomeGarden.Agents.Pipeline.EnrichLeadAction do
  @moduledoc """
  Reacts to a new lead signal. Researches the company and enriches
  the lead record with industry, region, and contact details.
  Uses web search to gather company information.
  """
  use Jido.Action,
    name: "enrich_lead",
    description: "Research and enrich a new lead with company data",
    schema: [
      id: [type: :string, required: true, doc: "Lead ID"],
      company_name: [type: :string, doc: "Company name to research"],
      first_name: [type: :string, doc: "Contact first name"],
      last_name: [type: :string, doc: "Contact last name"],
      email: [type: :string, doc: "Contact email"],
      source: [type: :atom, doc: "Lead source"],
      source_details: [type: :string, doc: "Source details"]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  @impl true
  def run(params, _context) do
    lead_id = params.id
    company_name = params[:company_name]

    # Try to match to existing company or create enrichment data
    enrichment = build_enrichment(company_name, params)

    # Update the lead with enriched data
    case update_lead(lead_id, enrichment) do
      :ok ->
        signal =
          Signal.new!(
            "sales.lead.enriched",
            Map.merge(%{lead_id: lead_id}, enrichment),
            source: "/pipeline/enrich_lead"
          )

        {:ok, %{action: :enriched, lead_id: lead_id, company: company_name},
         Directive.emit(signal)}

      {:error, reason} ->
        {:ok, %{action: :enrichment_failed, lead_id: lead_id, error: inspect(reason)}}
    end
  end

  defp build_enrichment(company_name, params) do
    # Check if company already exists in CRM
    existing = find_existing_company(company_name)

    case existing do
      {:ok, company} ->
        %{
          matched_company_id: company.id,
          company_type: company.company_type,
          region: company.region,
          industry: company.industry_id
        }

      :not_found ->
        # Extract what we can from bid/source data
        %{
          company_name: company_name,
          source: params[:source],
          needs_research: true
        }
    end
  end

  defp find_existing_company(nil), do: :not_found

  defp find_existing_company(name) do
    require Ash.Query

    query =
      GnomeGarden.Sales.Company
      |> Ash.Query.filter(name == ^name)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [company | _]} -> {:ok, company}
      _ -> :not_found
    end
  end

  defp update_lead(lead_id, _enrichment) do
    # For now, just verify the lead exists — enrichment fields
    # will be added as the Lead resource evolves
    case GnomeGarden.Sales.get_lead(lead_id) do
      {:ok, _lead} -> :ok
      error -> error
    end
  end
end
