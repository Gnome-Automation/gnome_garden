defmodule GnomeGarden.Agents.Pipeline.QualifyBidAction do
  @moduledoc """
  Reacts to a new bid signal. If the bid scores HOT or WARM,
  creates/finds the agency Company, links the Bid to it,
  and creates a Sales.Lead.
  """
  use Jido.Action,
    name: "qualify_bid",
    description: "Evaluate a new bid and create company + lead if it qualifies",
    schema: [
      id: [type: :string, required: true, doc: "Bid ID"],
      title: [type: :string, doc: "Bid title"],
      score_tier: [type: :atom, doc: "Score tier: hot, warm, prospect"],
      score_total: [type: :integer, doc: "Total score"],
      agency: [type: :string, doc: "Agency name"],
      url: [type: :string, doc: "Bid URL"],
      region: [type: :atom, doc: "Region"],
      location: [type: :string, doc: "Location"],
      lead_source_id: [type: :string, doc: "Lead source that found this bid"]
    ]

  require Ash.Query

  @impl true
  def run(params, _context) do
    tier = params[:score_tier]

    if tier in [:hot, :warm] do
      create_company_and_lead(params, tier)
    else
      {:ok, %{action: :skipped, reason: :low_score, bid_id: params.id, tier: tier}}
    end
  end

  defp create_company_and_lead(params, tier) do
    with {:ok, company} <- find_or_create_agency(params),
         :ok <- link_bid_to_company(params.id, company.id) do
      # Bids surface directly in the Review Queue — no need to create
      # a duplicate Lead. The company link is the important part.
      {:ok,
       %{
         action: :company_linked,
         company_id: if(company, do: company.id),
         bid_id: params.id,
         tier: tier
       }}
    else
      {:error, reason} ->
        {:ok, %{action: :failed, bid_id: params.id, error: inspect(reason)}}
    end
  end

  defp find_or_create_agency(params) do
    name = params[:agency]
    if is_nil(name) or name == "", do: {:ok, nil}, else: do_find_or_create(name, params)
  end

  defp do_find_or_create(name, params) do
    query =
      GnomeGarden.Sales.Company
      |> Ash.Query.filter(name == ^name)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [company | _]} ->
        {:ok, company}

      {:ok, []} ->
        Ash.create(GnomeGarden.Sales.Company, %{
          name: name,
          company_type: :prospect,
          status: :active,
          region: params[:region]
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp link_bid_to_company(bid_id, nil), do: {:ok, bid_id}

  defp link_bid_to_company(bid_id, company_id) do
    case Ash.get(GnomeGarden.Agents.Bid, bid_id) do
      {:ok, bid} ->
        Ash.update(bid, %{agency_company_id: company_id}, action: :update)
        :ok

      _ ->
        :ok
    end
  end
end
