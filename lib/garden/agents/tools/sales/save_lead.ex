defmodule GnomeGarden.Agents.Tools.SaveLead do
  @moduledoc """
  Save a discovered lead to the CRM.

  Creates or finds the Company first, then creates the Lead linked to it.
  If contact info is provided, creates a Contact at the Company too.
  """

  use Jido.Action,
    name: "save_lead",
    description: """
    Save a discovered company as a lead in the CRM. Creates the Company record
    if it doesn't exist, then creates a Lead linked to it. Call this for every
    company you find that may need automation/controls/IT services.
    """,
    schema: [
      company_name: [type: :string, required: true, doc: "Company name"],
      company_description: [
        type: :string,
        required: true,
        doc:
          "What the company does, 2-3 sentences. Example: 'Craft brewery producing 50K barrels/year in Anaheim. Has 3 production lines with older Allen-Bradley PLCs. Recently expanded to a new canning line.'"
      ],
      industry: [
        type: :string,
        doc: "Industry: brewery, biotech, manufacturing, water, food_bev, etc."
      ],
      location: [type: :string, doc: "City, State"],
      website: [type: :string, doc: "Company website URL"],
      signal: [
        type: :string,
        required: true,
        doc:
          "Why this is a lead RIGHT NOW. Be specific: 'Hiring PLC programmer per Indeed posting 3/15', 'Expanding with new $2M production line per press release', 'Posted RFP for SCADA upgrade'"
      ],
      employee_count: [type: :integer, doc: "Approximate number of employees"],
      contact_first_name: [type: :string, doc: "Contact first name if found"],
      contact_last_name: [type: :string, doc: "Contact last name if found"],
      contact_title: [type: :string, doc: "Contact job title if found"],
      contact_email: [type: :string, doc: "Contact email if found"],
      contact_phone: [type: :string, doc: "Contact phone if found"],
      source_url: [type: :string, doc: "URL where you found this information"]
    ]

  require Ash.Query

  @impl true
  def run(params, _context) do
    with {:ok, company} <- find_or_create_company(params),
         {:ok, lead} <- create_lead(params, company),
         {:ok, _contact} <- maybe_create_contact(params, company),
         {:ok, _source} <- maybe_create_lead_source(params, company) do
      {:ok,
       %{
         saved: true,
         company_id: company.id,
         lead_id: lead.id,
         company: params.company_name,
         message: "Company + Lead + Source saved! Pipeline will auto-enrich and qualify."
       }}
    else
      {:error, reason} ->
        {:error, "Failed to save lead: #{inspect(reason)}"}
    end
  end

  defp find_or_create_company(params) do
    name = params.company_name

    query =
      GnomeGarden.Sales.Company
      |> Ash.Query.filter(name == ^name)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [company | _]} ->
        {:ok, company}

      {:ok, []} ->
        {city, state} = parse_location(params[:location])

        attrs = %{
          name: name,
          company_type: :prospect,
          status: :active,
          website: params[:website],
          description: params[:company_description],
          employee_count: params[:employee_count],
          city: city,
          state: state,
          region: infer_region(city, state)
        }

        Ash.create(GnomeGarden.Sales.Company, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_lead(params, company) do
    {first, last} = split_name(params[:contact_first_name], params[:contact_last_name])

    attrs = %{
      first_name: first || "Unknown",
      last_name: last || params.company_name,
      company_name: params.company_name,
      company_id: company.id,
      title: params[:contact_title],
      email: params[:contact_email],
      phone: params[:contact_phone],
      source: :other,
      source_details: params.signal,
      source_url: params[:source_url],
      description: params[:company_description]
    }

    GnomeGarden.Sales.create_lead(attrs)
  end

  defp maybe_create_contact(
         %{contact_first_name: first, contact_last_name: last} = params,
         company
       )
       when is_binary(first) and first != "" and is_binary(last) and last != "" do
    attrs = %{
      first_name: first,
      last_name: last,
      email: params[:contact_email],
      phone: params[:contact_phone]
    }

    # Create employment to link contact to company
    case GnomeGarden.Sales.create_contact(attrs) do
      {:ok, contact} ->
        Ash.create(GnomeGarden.Sales.Employment, %{
          contact_id: contact.id,
          company_id: company.id,
          title: params[:contact_title],
          is_current: true
        })

        {:ok, contact}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_create_contact(_, _), do: {:ok, nil}

  defp split_name(nil, nil), do: {nil, nil}
  defp split_name(first, last) when is_binary(first) and is_binary(last), do: {first, last}
  defp split_name(first, nil) when is_binary(first), do: {first, "Unknown"}
  defp split_name(nil, last) when is_binary(last), do: {"Unknown", last}
  defp split_name(_, _), do: {nil, nil}

  defp parse_location(nil), do: {nil, nil}

  defp parse_location(loc) when is_binary(loc) do
    case String.split(loc, ",", parts: 2) do
      [city, state] -> {String.trim(city), String.trim(state)}
      [city] -> {String.trim(city), nil}
      _ -> {nil, nil}
    end
  end

  defp infer_region(city, _state) when is_binary(city) do
    city_lower = String.downcase(city)

    cond do
      String.contains?(city_lower, "orange") or
          city_lower in ~w(irvine anaheim santa ana costa mesa huntington beach fullerton tustin) ->
        :oc

      String.contains?(city_lower, "los angeles") or
          city_lower in ~w(torrance carson compton downey) ->
        :la

      city_lower in ~w(riverside corona fontana ontario san bernardino rancho cucamonga) ->
        :ie

      city_lower in ~w(san diego oceanside carlsbad escondido) ->
        :sd

      true ->
        :socal
    end
  end

  defp infer_region(_, _), do: :socal

  defp maybe_create_lead_source(%{website: website}, company)
       when is_binary(website) and website != "" do
    # Normalize URL
    url = if String.starts_with?(website, "http"), do: website, else: "https://#{website}"

    # Check if source already exists
    existing =
      GnomeGarden.Procurement.ProcurementSource
      |> Ash.Query.filter(url == ^url)
      |> Ash.Query.limit(1)
      |> Ash.read!()

    case existing do
      [_source | _] ->
        {:ok, :already_exists}

      [] ->
        Ash.create(
          GnomeGarden.Procurement.ProcurementSource,
          %{
            name: company.name,
            url: url,
            source_type: :company_site,
            company_id: company.id,
            region: company.region || :socal,
            priority: :medium,
            scan_frequency_hours: 48,
            enabled: true
          },
          action: :create_for_company
        )
    end
  end

  defp maybe_create_lead_source(_, _), do: {:ok, :no_website}
end
