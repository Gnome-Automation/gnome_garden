defmodule GnomeGarden.Sales do
  @moduledoc """
  Sales domain for CRM and pipeline management.

  Manages companies, contacts, activities, and notes — the relationship
  management side of the business. Pipeline resources (Opportunity,
  Proposal, Contract) will be added in a future phase.
  """

  use Ash.Domain,
    otp_app: :gnome_garden,
    extensions: [AshAdmin.Domain, AshPhoenix]

  admin do
    show? true
  end

  resources do
    resource GnomeGarden.Sales.Industry

    resource GnomeGarden.Sales.Company do
      define :list_companies, action: :read
      define :get_company, action: :read, get_by: [:id]
      define :create_company, action: :create
      define :update_company, action: :update
    end

    resource GnomeGarden.Sales.Contact do
      define :list_contacts, action: :read
      define :get_contact, action: :read, get_by: [:id]
      define :create_contact, action: :create
      define :update_contact, action: :update
    end

    resource GnomeGarden.Sales.Activity
    resource GnomeGarden.Sales.Note

    resource GnomeGarden.Sales.Event do
      define :log_event, action: :log
    end

    resource GnomeGarden.Sales.Address
    resource GnomeGarden.Sales.CompanyRelationship

    resource GnomeGarden.Sales.Task do
      define :list_tasks, action: :read
      define :get_task, action: :read, get_by: [:id]
      define :create_task, action: :create
      define :update_task, action: :update
    end

    resource GnomeGarden.Sales.Opportunity do
      define :list_opportunities, action: :read
      define :get_opportunity, action: :read, get_by: [:id]
      define :create_opportunity, action: :create
      define :update_opportunity, action: :update
      define :advance_to_review, action: :advance_to_review
      define :advance_to_qualification, action: :advance_to_qualification
      define :advance_to_drafting, action: :advance_to_drafting
      define :advance_to_submitted, action: :advance_to_submitted
      define :advance_to_research, action: :advance_to_research
      define :advance_to_outreach, action: :advance_to_outreach
      define :advance_to_meeting, action: :advance_to_meeting
      define :advance_to_proposal, action: :advance_to_proposal
      define :advance_to_negotiation, action: :advance_to_negotiation
      define :close_opportunity_won, action: :close_won
      define :close_opportunity_lost, action: :close_lost
    end

    resource GnomeGarden.Sales.Lead do
      define :list_leads, action: :read
      define :get_lead, action: :read, get_by: [:id]
      define :create_lead, action: :create
      define :update_lead, action: :update
      define :quick_add_lead, action: :quick_add
    end

    resource GnomeGarden.Sales.ResearchRequest
    resource GnomeGarden.Sales.ResearchLink
    resource GnomeGarden.Sales.Employment
  end

  @doc """
  Accept any review queue item → find-or-create Company + create Opportunity.

  Params:
    - company_name (required) — used to find or create Company
    - opportunity_name (required) — name for the new Opportunity
    - source (atom) — :bid, :prospect, :referral, etc.
    - description, amount, expected_close_date (optional)
    - bid_id, lead_id, prospect_id (optional) — source record to link

  Returns {:ok, %{company: company, opportunity: opportunity}} or {:error, reason}
  """
  def accept_review_item(params, opts \\ []) do
    _actor = Keyword.get(opts, :actor)
    company_name = params[:company_name] || params["company_name"]

    with {:ok, company} <- resolve_company(company_name, params),
         {:ok, opportunity} <- create_opportunity_from(company, params),
         :ok <- link_source_record(params, opportunity, company) do
      # Log the pursue event
      log_pipeline_event(%{
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
      })

      {:ok, %{company: company, opportunity: opportunity}}
    end
  end

  @doc """
  Log an event to the pipeline audit trail.
  """
  def log_pipeline_event(attrs) do
    Ash.create(GnomeGarden.Sales.Event, attrs)
  end

  require Ash.Query

  defp resolve_company(name, params) do
    bid_id = params[:bid_id] || params["bid_id"]

    # First: check if the source bid already has a linked company
    if bid_id do
      case Ash.get(GnomeGarden.Agents.Bid, bid_id) do
        {:ok, %{agency_company_id: cid}} when not is_nil(cid) ->
          Ash.get(GnomeGarden.Sales.Company, cid)

        _ ->
          find_or_create_company(name, params)
      end
    else
      find_or_create_company(name, params)
    end
  end

  defp find_or_create_company(name, params) do
    case GnomeGarden.Sales.Company |> Ash.Query.filter(name == ^name) |> Ash.read() do
      {:ok, [company | _]} ->
        {:ok, company}

      {:ok, []} ->
        source = params[:source] || params["source"]
        region = params[:region] || params["region"]

        Ash.create(GnomeGarden.Sales.Company, %{
          name: name,
          company_type: :prospect,
          source: source,
          region: region
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_opportunity_from(company, params) do
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

    Ash.create(GnomeGarden.Sales.Opportunity, attrs)
  end

  defp workflow_from_source(:bid), do: :bid_response
  defp workflow_from_source(:prospect), do: :outreach
  defp workflow_from_source(:outbound), do: :outreach
  defp workflow_from_source(:referral), do: :inbound
  defp workflow_from_source(:inbound), do: :inbound
  defp workflow_from_source(_), do: :inbound

  defp link_source_record(params, opportunity, company) do
    bid_id = params[:bid_id] || params["bid_id"]
    lead_id = params[:lead_id] || params["lead_id"]
    prospect_id = params[:prospect_id] || params["prospect_id"]

    cond do
      bid_id ->
        bid = Ash.get!(GnomeGarden.Agents.Bid, bid_id)
        Ash.update!(bid, %{opportunity_id: opportunity.id}, action: :convert_to_opportunity)
        :ok

      lead_id ->
        lead = Ash.get!(GnomeGarden.Sales.Lead, lead_id)
        Ash.update!(lead, %{}, action: :screen)
        :ok

      prospect_id ->
        prospect = Ash.get!(GnomeGarden.Agents.Prospect, prospect_id)
        Ash.update!(prospect, %{company_id: company.id}, action: :convert_to_company)
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
