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
  alias GnomeGarden.Commercial.DiscoveryIdentityResolver
  alias GnomeGarden.Commercial.MarketFocus
  alias GnomeGarden.Operations
  alias GnomeGarden.Support.WebIdentity
  alias GnomeGarden.Agents.RunOutputLogger

  @impl true
  def run(params, context) do
    existing_target_account = existing_target_account(params)
    existing_observation = existing_observation(params)
    actor = context_actor(context)
    profile_context = context_profile(context, params)

    target_score =
      params
      |> with_profile_context(profile_context)
      |> MarketFocus.assess_target()

    with {:ok, organization_resolution} <- resolve_organization(params, actor),
         {:ok, person_resolution} <-
           resolve_person(params, organization_resolution.organization, actor),
         {:ok, _affiliation} <-
           maybe_upsert_affiliation(
             person_resolution.person,
             organization_resolution.organization,
             params,
             actor
           ),
         {:ok, target_account} <-
           upsert_target_account(
             params,
             organization_resolution,
             person_resolution,
             target_score,
             profile_context
           ),
         person = person_resolution.person,
         organization = organization_resolution.organization,
         {:ok, observation} <-
           upsert_target_observation(
             params,
             target_account,
             person,
             target_score,
             profile_context
           ) do
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
         organization_id: organization && organization.id,
         person_id: person && person.id,
         target_account_id: target_account.id,
         target_observation_id: observation.id,
         company: params.company_name,
         message: "Target saved for commercial review."
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

  defp resolve_organization(params, actor) do
    {city, state} = parse_location(params[:location])

    DiscoveryIdentityResolver.resolve_organization(
      %{
        name: params.company_name,
        status: :prospect,
        relationship_roles: ["prospect"],
        website: WebIdentity.normalize_website(params[:website]),
        primary_region: infer_region(city, state) |> to_string(),
        notes: build_organization_notes(params, city, state)
      },
      actor: actor
    )
  end

  defp resolve_person(params, organization, actor) do
    DiscoveryIdentityResolver.resolve_person(
      %{
        first_name: blank_to_nil(params[:contact_first_name]),
        last_name: blank_to_nil(params[:contact_last_name]),
        email: blank_to_nil(params[:contact_email]),
        phone: blank_to_nil(params[:contact_phone]),
        notes: blank_to_nil(params[:contact_title])
      },
      organization,
      actor: actor
    )
  end

  defp maybe_upsert_affiliation(nil, _organization, _params, _actor), do: {:ok, nil}
  defp maybe_upsert_affiliation(_person, nil, _params, _actor), do: {:ok, nil}

  defp maybe_upsert_affiliation(person, organization, params, actor) do
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
      actor: actor,
      upsert?: true,
      upsert_identity: :unique_active_affiliation,
      upsert_fields: [:title, :contact_roles, :is_primary]
    )
  end

  defp upsert_target_account(
         params,
         organization_resolution,
         person_resolution,
         target_score,
         profile_context
       ) do
    attrs = %{
      name: params.company_name,
      website: WebIdentity.normalize_website(params[:website]),
      location: blank_to_nil(params[:location]),
      region: infer_region_from_location(params[:location]),
      industry: blank_to_nil(params[:industry]),
      size_bucket: infer_size_bucket(params[:employee_count]),
      fit_score: target_score.fit_score,
      intent_score: target_score.intent_score,
      status: :new,
      notes: build_target_notes(params),
      discovery_program_id: blank_to_nil(params[:discovery_program_id]),
      organization_id:
        organization_resolution.organization && organization_resolution.organization.id,
      contact_person_id: person_resolution.person && person_resolution.person.id,
      metadata: %{
        employee_count: params[:employee_count],
        discovery_program_id: blank_to_nil(params[:discovery_program_id]),
        source: "save_target_account",
        market_focus: %{
          company_profile_key: profile_context.company_profile_key,
          company_profile_mode: profile_context.company_profile_mode,
          icp_matches: target_score.icp_matches,
          risk_flags: target_score.risk_flags,
          fit_rationale: target_score.fit_rationale,
          intent_signals: target_score.intent_signals
        },
        contact_snapshot: DiscoveryIdentityResolver.target_contact_snapshot(params),
        identity_review:
          DiscoveryIdentityResolver.target_identity_review(
            organization_resolution,
            person_resolution
          )
      }
    }

    case target_account_upsert_identity(attrs) do
      nil ->
        Commercial.create_target_account(attrs)

      upsert_identity ->
        Commercial.create_target_account(
          attrs,
          upsert?: true,
          upsert_identity: upsert_identity,
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
            :contact_person_id,
            :metadata
          ]
        )
    end
  end

  defp upsert_target_observation(
         params,
         target_account,
         person,
         target_score,
         profile_context
       ) do
    summary = params.signal

    attrs = %{
      target_account_id: target_account.id,
      observation_type: infer_observation_type(summary),
      source_channel: infer_observation_channel(params[:source_url]),
      external_ref: observation_external_ref(params),
      source_url: blank_to_nil(params[:source_url]),
      observed_at: DateTime.utc_now(),
      confidence_score: target_score.intent_score,
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
        source: "save_target_account",
        market_focus: %{
          company_profile_key: profile_context.company_profile_key,
          company_profile_mode: profile_context.company_profile_mode,
          icp_matches: target_score.icp_matches,
          risk_flags: target_score.risk_flags,
          intent_signals: target_score.intent_signals
        }
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

  defp target_account_upsert_identity(%{location: location}) when is_binary(location),
    do: :unique_name_key_location

  defp target_account_upsert_identity(_attrs), do: nil

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

  defp context_actor(context) when is_map(context) do
    Map.get(context, :actor) || get_in(context, [:tool_context, :actor])
  end

  defp context_actor(_context), do: nil

  defp context_profile(context, params) do
    tool_context = Map.get(context, :tool_context, %{})

    GnomeGarden.Commercial.CompanyProfileContext.resolve(
      profile_key:
        Map.get(params, :company_profile_key) ||
          nested_value(tool_context, [:company_profile_key]) ||
          nested_value(tool_context, [:deployment_config, :company_profile_key]),
      mode:
        Map.get(params, :company_profile_mode) ||
          nested_value(tool_context, [:company_profile_mode]) ||
          nested_value(tool_context, [:source_scope, :company_profile_mode])
    )
  end

  defp with_profile_context(params, profile_context) do
    params
    |> Map.put_new(:company_profile_key, profile_context.company_profile_key)
    |> Map.put_new(:company_profile_mode, profile_context.company_profile_mode)
  end

  defp nested_value(map, [key]) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp nested_value(map, [key | rest]) when is_map(map) do
    map
    |> nested_value([key])
    |> case do
      %{} = nested -> nested_value(nested, rest)
      _ -> nil
    end
  end

  defp nested_value(_map, _path), do: nil

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
