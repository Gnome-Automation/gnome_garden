defmodule GnomeGarden.Agents.Tools.SaveLead do
  @moduledoc """
  Save a discovered company signal into the long-term operating model.

  Agent intake creates or updates the durable organization record first,
  optionally records a contact person, and always creates a commercial signal
  for human review before anything becomes owned pipeline.
  """

  use Jido.Action,
    name: "save_lead",
    description: """
    Save a discovered company into Operations + Commercial. Creates or updates
    the Organization first, optionally records a Person and affiliation, then
    creates a Commercial Signal for human review. Call this for every company
    you find that may need automation, controls, service, or software work.
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

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations

  @impl true
  def run(params, _context) do
    with {:ok, organization} <- upsert_organization(params),
         {:ok, person} <- maybe_upsert_person(params),
         {:ok, _affiliation} <- maybe_upsert_affiliation(person, organization, params),
         {:ok, signal} <- create_signal(params, organization, person) do
      {:ok,
       %{
         saved: true,
         organization_id: organization.id,
         person_id: person && person.id,
         signal_id: signal.id,
         company: params.company_name,
         message: "Organization + Signal saved for commercial review."
       }}
    else
      {:error, reason} ->
        {:error, "Failed to save lead: #{inspect(reason)}"}
    end
  end

  defp upsert_organization(params) do
    {city, state} = parse_location(params[:location])

    attrs =
      %{
        name: params.company_name,
        status: :prospect,
        relationship_roles: ["prospect"],
        website: normalize_website(params[:website]),
        primary_region: infer_region(city, state) |> to_string(),
        notes: build_organization_notes(params, city, state)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Operations.create_organization(
      attrs,
      upsert?: true,
      upsert_identity: :unique_name,
      upsert_fields: [:website, :primary_region, :notes]
    )
  end

  defp maybe_upsert_person(params) do
    {first, last} = split_name(params[:contact_first_name], params[:contact_last_name])
    email = blank_to_nil(params[:contact_email])
    phone = blank_to_nil(params[:contact_phone])

    cond do
      is_nil(email) and is_nil(first) and is_nil(last) ->
        {:ok, nil}

      true ->
        attrs =
          %{
            first_name: first || "Unknown",
            last_name: last || params.company_name,
            email: email,
            phone: phone,
            notes: params[:contact_title]
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()

        if email do
          Operations.create_person(
            attrs,
            upsert?: true,
            upsert_identity: :unique_email,
            upsert_fields: [:first_name, :last_name, :phone, :notes]
          )
        else
          Operations.create_person(attrs)
        end
    end
  end

  defp maybe_upsert_affiliation(nil, _organization, _params), do: {:ok, nil}

  defp maybe_upsert_affiliation(person, organization, params) do
    attrs =
      %{
        organization_id: organization.id,
        person_id: person.id,
        title: blank_to_nil(params[:contact_title]),
        contact_roles: infer_contact_roles(params[:contact_title]),
        is_primary: true
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Operations.create_organization_affiliation(
      attrs,
      upsert?: true,
      upsert_identity: :unique_active_affiliation,
      upsert_fields: [:title, :contact_roles, :is_primary]
    )
  end

  defp create_signal(params, organization, person) do
    signal_attrs = %{
      title: signal_title(params),
      description: params.company_description,
      signal_type: infer_signal_type(params.signal),
      source_channel: :agent_discovery,
      source_url: blank_to_nil(params[:source_url]),
      observed_at: DateTime.utc_now(),
      organization_id: organization.id,
      notes: params.signal,
      metadata: %{
        contact_person_id: person && person.id,
        company_name: params.company_name,
        industry: blank_to_nil(params[:industry]),
        location: blank_to_nil(params[:location]),
        website: normalize_website(params[:website]),
        employee_count: params[:employee_count],
        source: :save_lead
      }
    }

    Commercial.create_signal(signal_attrs)
  end

  defp split_name(nil, nil), do: {nil, nil}
  defp split_name(first, last) when is_binary(first) and is_binary(last), do: {first, last}
  defp split_name(first, nil) when is_binary(first) and first != "", do: {first, "Unknown"}
  defp split_name(nil, last) when is_binary(last) and last != "", do: {"Unknown", last}
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

  defp infer_signal_type(signal) when is_binary(signal) do
    signal
    |> String.downcase()
    |> then(fn text ->
      cond do
        String.contains?(text, ["renewal", "rebid"]) ->
          :renewal

        String.contains?(text, ["referral", "intro", "warm intro"]) ->
          :referral

        String.contains?(text, ["inbound", "contacted us", "reached out", "requested"]) ->
          :inbound_request

        true ->
          :outbound_target
      end
    end)
  end

  defp infer_signal_type(_), do: :outbound_target

  defp infer_contact_roles(title) when is_binary(title) do
    normalized = String.downcase(title)

    cond do
      String.contains?(normalized, [
        "engineer",
        "controls",
        "automation",
        "operations",
        "maintenance"
      ]) ->
        ["technical_contact"]

      String.contains?(normalized, ["buyer", "purchasing", "procurement", "sourcing"]) ->
        ["buyer"]

      true ->
        []
    end
  end

  defp infer_contact_roles(_), do: []

  defp signal_title(params) do
    "#{params.company_name} — #{String.trim(params.signal)}"
    |> String.slice(0, 120)
  end

  defp normalize_website(nil), do: nil
  defp normalize_website(""), do: nil

  defp normalize_website(website) when is_binary(website) do
    if String.starts_with?(website, "http"), do: website, else: "https://#{website}"
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp build_organization_notes(params, city, state) do
    [
      params[:company_description],
      city && state && "Location: #{city}, #{state}",
      params[:industry] && "Industry: #{params[:industry]}",
      params[:employee_count] && "Employee count: #{params[:employee_count]}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> blank_to_nil()
  end
end
