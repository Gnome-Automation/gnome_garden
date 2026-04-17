defmodule GnomeGarden.CRM.Review do
  @moduledoc """
  Review and conversion workflows for agent- and CRM-sourced work.
  """

  alias GnomeGarden.Procurement.Bid
  alias GnomeGarden.Agents.Prospect
  alias GnomeGarden.CRM.PipelineEvents
  alias GnomeGarden.Sales.Company
  alias GnomeGarden.Sales.Lead
  alias GnomeGarden.Sales.Opportunity

  require Ash.Query

  def accept_review_item(params, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    company_name = params[:company_name] || params["company_name"]

    with {:ok, company} <- resolve_company(company_name, params, actor),
         {:ok, opportunity} <- create_opportunity_from(company, params, actor),
         :ok <- link_source_record(params, opportunity, company, actor) do
      PipelineEvents.log(
        %{
          event_type: :pursued,
          subject_type: source_type_from(params),
          subject_id: source_id_from(params),
          summary: "Pursued — #{opportunity.name}",
          reason: params[:reason],
          from_state: "new",
          to_state: "discovery",
          opportunity_id: opportunity.id,
          company_id: company.id,
          metadata: %{workflow: opportunity.workflow, source: opportunity.source}
        },
        actor: actor
      )

      {:ok, %{company: company, opportunity: opportunity}}
    end
  end

  defp resolve_company(name, params, actor) do
    bid_id = params[:bid_id] || params["bid_id"]

    if bid_id do
      case Ash.get(Bid, bid_id, actor: actor) do
        {:ok, %{agency_company_id: cid}} when not is_nil(cid) ->
          Ash.get(Company, cid, actor: actor)

        _ ->
          find_or_create_company(name, params, actor)
      end
    else
      find_or_create_company(name, params, actor)
    end
  end

  defp find_or_create_company(name, params, actor) do
    query = Company |> Ash.Query.filter(name == ^name)

    case Ash.read(query, actor: actor) do
      {:ok, [company | _]} ->
        {:ok, company}

      {:ok, []} ->
        source = params[:source] || params["source"]
        region = params[:region] || params["region"]

        Ash.create(
          Company,
          %{
            name: name,
            company_type: :prospect,
            source: source,
            region: region
          },
          actor: actor
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_opportunity_from(company, params, actor) do
    opp_name = params[:opportunity_name] || params["opportunity_name"]
    source = params[:source] || params["source"]
    description = params[:description] || params["description"]
    amount = params[:amount] || params["amount"]
    expected_close = params[:expected_close_date] || params["expected_close_date"]
    bid_id = params[:bid_id] || params["bid_id"]
    workflow = params[:workflow] || params["workflow"] || workflow_from_source(source)

    attrs =
      %{
        name: opp_name,
        company_id: company.id,
        source: source,
        workflow: workflow,
        description: description
      }
      |> maybe_put(:amount, amount)
      |> maybe_put(:expected_close_date, expected_close)
      |> maybe_put(:bid_id, bid_id)

    Ash.create(Opportunity, attrs, actor: actor)
  end

  defp workflow_from_source(:bid), do: :bid_response
  defp workflow_from_source(:prospect), do: :outreach
  defp workflow_from_source(:outbound), do: :outreach
  defp workflow_from_source(:referral), do: :inbound
  defp workflow_from_source(:inbound), do: :inbound
  defp workflow_from_source(_), do: :inbound

  defp link_source_record(params, opportunity, company, actor) do
    bid_id = params[:bid_id] || params["bid_id"]
    lead_id = params[:lead_id] || params["lead_id"]
    prospect_id = params[:prospect_id] || params["prospect_id"]

    cond do
      bid_id ->
        bid = Ash.get!(Bid, bid_id, actor: actor)
        Ash.update!(bid, %{opportunity_id: opportunity.id}, action: :convert_to_opportunity, actor: actor)
        :ok

      lead_id ->
        lead = Ash.get!(Lead, lead_id, actor: actor)
        Ash.update!(lead, %{}, action: :screen, actor: actor)
        :ok

      prospect_id ->
        prospect = Ash.get!(Prospect, prospect_id, actor: actor)
        Ash.update!(prospect, %{company_id: company.id}, action: :convert_to_company, actor: actor)
        :ok

      true ->
        :ok
    end
  end

  defp source_type_from(params) do
    cond do
      params[:bid_id] -> "bid"
      params[:lead_id] -> "lead"
      params[:prospect_id] -> "prospect"
      true -> "unknown"
    end
  end

  defp source_id_from(params) do
    params[:bid_id] || params[:lead_id] || params[:prospect_id]
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
