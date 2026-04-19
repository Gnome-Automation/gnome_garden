defmodule GnomeGarden.Agents.Tools.Commercial.SaveTargetAccount do
  @moduledoc """
  Save a discovered company into the durable commercial discovery model.

  Agent intake creates or updates the durable organization record first,
  optionally records a contact person, then creates or updates a commercial
  target account plus a raw observation for human review before anything
  becomes owned pipeline.
  """

  use Jido.Action,
    name: "save_target_account",
    description: """
    Save a discovered company into Operations + Commercial. Creates or updates
    the Organization first, optionally records a Person and affiliation, then
    creates or updates a Commercial Target Account plus a raw observation for
    human review. Call this for every company you find that may need automation,
    controls, service, or software work.
    """,
    schema: [
      company_name: [type: :string, required: true, doc: "Company name"],
      discovery_program_id: [
        type: :string,
        doc: "Optional Commercial.DiscoveryProgram id to attach this discovery result to"
      ],
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
          "Why this target matters RIGHT NOW. Be specific: 'Hiring PLC programmer per Indeed posting 3/15', 'Expanding with new $2M production line per press release', 'Posted RFP for SCADA upgrade'"
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
  alias GnomeGarden.Support.WebIdentity
  alias GnomeGarden.Agents.RunOutputLogger

  @impl true
  def run(params, context) do
    existing_target_account = existing_target_account(params)
    existing_observation = existing_observation(params)

    with {:ok, organization} <- upsert_organization(params),
         {:ok, person} <- maybe_upsert_person(params),
         {:ok, _affiliation} <- maybe_upsert_affiliation(person, organization, params),
         {:ok, target_account} <- upsert_target_account(params, organization, person),
         {:ok, observation} <- upsert_target_observation(params, target_account, person) do
      log_target_output(
        context,
        target_account,
        observation,
        existing_target_account,
        existing_observation
      )

      {:ok,
       %{
         saved: true,
         organization_id: organization.id,
         person_id: person && person.id,
         target_account_id: target_account.id,
         target_observation_id: observation.id,
         company: params.company_name,
         message: "Organization + Target saved for commercial review."
       }}
    else
      {:error, reason} ->
        {:error, "Failed to save target account: #{inspect(reason)}"}
    end
  end

  defp existing_target_account(params) do
    params[:website]
    |> WebIdentity.website_domain()
    |> case do
      nil ->
        nil

      website_domain ->
        case Commercial.get_target_account_by_website_domain(website_domain) do
          {:ok, target_account} -> target_account
          _ -> nil
        end
    end
  end

  defp existing_observation(params) do
    case Commercial.get_target_observation_by_external_ref(observation_external_ref(params)) do
      {:ok, observation} -> observation
      _ -> nil
    end
  end

  defp upsert_organization(params) do
    {city, state} = parse_location(params[:location])

    attrs =
      %{
        name: params.company_name,
        status: :prospect,
        relationship_roles: ["prospect"],
        website: WebIdentity.normalize_website(params[:website]),
        primary_region: infer_region(city, state) |> to_string(),
        notes: build_organization_notes(params, city, state)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Operations.create_organization(
      attrs,
      upsert?: true,
      upsert_identity: organization_upsert_identity(attrs),
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

  defp upsert_target_account(params, organization, person) do
    attrs = %{
      name: params.company_name,
      website: WebIdentity.normalize_website(params[:website]),
      location: blank_to_nil(params[:location]),
      region: infer_region_from_location(params[:location]),
      industry: blank_to_nil(params[:industry]),
      size_bucket: infer_size_bucket(params[:employee_count]),
      fit_score: fit_score(params),
      intent_score: intent_score(params[:signal]),
      status: :new,
      notes: build_target_notes(params),
      discovery_program_id: blank_to_nil(params[:discovery_program_id]),
      organization_id: organization.id,
      metadata: %{
        employee_count: params[:employee_count],
        contact_person_id: person && person.id,
        discovery_program_id: blank_to_nil(params[:discovery_program_id]),
        source: "save_target_account"
      }
    }

    Commercial.create_target_account(
      attrs,
      upsert?: true,
      upsert_identity: target_account_upsert_identity(attrs),
      upsert_fields: [
        :website,
        :location,
        :region,
        :industry,
        :size_bucket,
        :fit_score,
        :intent_score,
        :notes,
        :organization_id,
        :metadata
      ]
    )
  end

  defp upsert_target_observation(params, target_account, person) do
    summary = params.signal

    attrs = %{
      target_account_id: target_account.id,
      observation_type: infer_observation_type(summary),
      source_channel: infer_observation_channel(params[:source_url]),
      external_ref: observation_external_ref(params),
      source_url: blank_to_nil(params[:source_url]),
      observed_at: DateTime.utc_now(),
      confidence_score: intent_score(summary),
      summary: summary,
      raw_excerpt: params.company_description,
      evidence_points: observation_evidence_points(params),
      discovery_program_id: blank_to_nil(params[:discovery_program_id]),
      metadata: %{
        company_name: params.company_name,
        industry: blank_to_nil(params[:industry]),
        location: blank_to_nil(params[:location]),
        website: WebIdentity.normalize_website(params[:website]),
        employee_count: params[:employee_count],
        contact_person_id: person && person.id,
        discovery_program_id: blank_to_nil(params[:discovery_program_id]),
        source: "save_target_account"
      }
    }

    Commercial.create_target_observation(
      attrs,
      upsert?: true,
      upsert_identity: :unique_external_ref,
      upsert_fields: [
        :source_url,
        :observed_at,
        :confidence_score,
        :summary,
        :raw_excerpt,
        :evidence_points,
        :metadata
      ]
    )
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

  defp infer_observation_type(signal) when is_binary(signal) do
    signal
    |> String.downcase()
    |> then(fn text ->
      cond do
        String.contains?(text, ["hiring", "job posting", "controls engineer", "plc programmer"]) ->
          :hiring

        String.contains?(text, ["expansion", "new line", "modernization", "capital improvement"]) ->
          :expansion

        String.contains?(text, ["legacy", "slc 500", "panelview", "outdated"]) ->
          :legacy_stack

        String.contains?(text, ["referral", "intro", "warm intro"]) ->
          :referral

        true ->
          :other
      end
    end)
  end

  defp infer_observation_type(_), do: :other

  defp infer_observation_channel(nil), do: :agent_discovery

  defp infer_observation_channel(source_url) when is_binary(source_url) do
    normalized_url = String.downcase(source_url)

    cond do
      String.contains?(normalized_url, [
        "indeed.",
        "ziprecruiter.",
        "linkedin.com/jobs",
        "greenhouse.io"
      ]) ->
        :job_board

      String.contains?(normalized_url, ["directory", "yellowpages", "thomasnet", "industrynet"]) ->
        :directory

      true ->
        :news_site
    end
  end

  defp infer_observation_channel(_source_url), do: :agent_discovery

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

  defp infer_size_bucket(employee_count) when is_integer(employee_count) and employee_count < 50,
    do: :small

  defp infer_size_bucket(employee_count) when is_integer(employee_count) and employee_count < 200,
    do: :medium

  defp infer_size_bucket(employee_count) when is_integer(employee_count) and employee_count < 500,
    do: :large

  defp infer_size_bucket(employee_count) when is_integer(employee_count), do: :enterprise
  defp infer_size_bucket(_employee_count), do: nil

  defp fit_score(params) do
    industry_score =
      case blank_to_nil(params[:industry]) do
        industry when industry in ["brewery", "biotech", "water", "food_bev", "packaging"] -> 80
        "manufacturing" -> 70
        _ -> 55
      end

    size_bonus =
      case infer_size_bucket(params[:employee_count]) do
        :medium -> 10
        :large -> 8
        :small -> 4
        :enterprise -> -5
        _ -> 0
      end

    min(industry_score + size_bonus, 100)
  end

  defp intent_score(signal) when is_binary(signal) do
    signal
    |> String.downcase()
    |> then(fn text ->
      cond do
        String.contains?(text, [
          "hiring",
          "controls engineer",
          "plc programmer",
          "modernization initiative",
          "rfp",
          "scada upgrade"
        ]) ->
          85

        String.contains?(text, [
          "expansion",
          "new line",
          "capacity increase",
          "capital improvement"
        ]) ->
          75

        String.contains?(text, ["legacy", "manual process", "downtime", "reporting gaps"]) ->
          65

        true ->
          50
      end
    end)
  end

  defp intent_score(_signal), do: 50

  defp infer_region_from_location(nil), do: nil

  defp infer_region_from_location(location),
    do:
      location
      |> parse_location()
      |> then(fn {city, state} -> infer_region(city, state) |> to_string() end)

  defp build_target_notes(params) do
    [params[:company_description], params[:signal]]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp observation_external_ref(params) do
    source_ref = blank_to_nil(params[:source_url]) || "manual"
    company_ref = params.company_name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")

    signal_ref =
      params.signal
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.slice(0, 80)

    "save_target_account:#{company_ref}:#{signal_ref}:#{source_ref}"
  end

  defp observation_evidence_points(params) do
    [
      blank_to_nil(params[:signal]),
      blank_to_nil(params[:source_url]),
      params[:industry] && "Industry: #{params[:industry]}",
      params[:employee_count] && "Employees: #{params[:employee_count]}"
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp target_account_upsert_identity(%{website: website}) when is_binary(website),
    do: :unique_website_domain

  defp target_account_upsert_identity(_attrs), do: :unique_name_location

  defp organization_upsert_identity(%{website: website}) when is_binary(website),
    do: :unique_website_domain

  defp organization_upsert_identity(_attrs), do: :unique_name

  defp log_target_output(
         context,
         target_account,
         observation,
         existing_target_account,
         existing_observation
       ) do
    event =
      cond do
        existing_observation -> :existing
        existing_target_account -> :updated
        true -> :created
      end

    RunOutputLogger.log(context, %{
      output_type: :target_account,
      output_id: target_account.id,
      event: event,
      label: target_account.name,
      summary: "#{event_label(event)} discovery target #{target_account.name}",
      metadata: %{
        website: target_account.website,
        website_domain: target_account.website_domain,
        organization_id: target_account.organization_id,
        discovery_program_id: target_account.discovery_program_id,
        target_observation_id: observation.id
      }
    })
  end

  defp event_label(:created), do: "Created"
  defp event_label(:existing), do: "Reused existing"
  defp event_label(:updated), do: "Updated"

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
