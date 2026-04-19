defmodule GnomeGarden.Agents.Commercial.SiteScanner do
  @moduledoc """
  Scans company websites for contacts, hiring signals, and news.

  Unlike `ListingScanner` (which uses saved CSS selectors for procurement
  portals), `SiteScanner` uses common URL patterns and page structure
  heuristics to extract useful information from any company website.

  Extracts:
  - Contacts from /about, /team, /contact pages
  - Hiring signals from /careers, /jobs pages
  - Expansion news from /news, /press pages

  Persists contacts into Operations people/affiliations and records
  hiring/expansion discoveries as Commercial signals for human review.
  """

  alias GnomeGarden.Commercial
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Support.WebIdentity
  alias GnomeGarden.Agents.Tools.Browser.{Navigate, Extract}

  require Logger

  @contact_paths ["/about", "/team", "/about-us", "/our-team", "/contact", "/contact-us"]
  @career_paths ["/careers", "/jobs", "/career", "/join-us", "/employment", "/work-with-us"]
  @news_paths ["/news", "/press", "/blog", "/press-releases", "/announcements"]

  def scan(%ProcurementSource{source_type: :company_site} = source) do
    Logger.info("[SiteScanner] Scanning #{source.name} at #{source.url}")

    base_url = extract_base_url(source.url)
    organization = ensure_organization!(source)
    target_account = ensure_target_account!(source, organization)
    results = %{contacts: [], observations: [], errors: []}

    results =
      results
      |> scan_for_contacts(base_url, source, organization)
      |> scan_for_careers(base_url, source, organization, target_account)
      |> scan_for_news(base_url, source, organization, target_account)

    Procurement.mark_procurement_source_scanned!(source, %{})

    {:ok,
     %{
       source: source.name,
       contacts_found: length(results.contacts),
       observations_found: length(results.observations),
       errors: length(results.errors)
     }}
  rescue
    e ->
      Logger.error("[SiteScanner] Failed for #{source.name}: #{Exception.message(e)}")
      Procurement.scan_fail_procurement_source(source, %{})
      {:error, Exception.message(e)}
  end

  def scan(%ProcurementSource{} = source) do
    Logger.warning("[SiteScanner] #{source.name} is not a company_site source, skipping")
    {:ok, %{skipped: true, reason: "not_company_site"}}
  end

  defp scan_for_contacts(results, base_url, source, organization) do
    Enum.reduce(@contact_paths, results, fn path, acc ->
      url = base_url <> path

      case try_extract_page(url) do
        {:ok, content} ->
          contacts = extract_contacts_from_content(content)
          save_contacts(contacts, organization, source, url)
          %{acc | contacts: acc.contacts ++ contacts}

        :not_found ->
          acc

        {:error, reason} ->
          %{acc | errors: [{:contacts, path, reason} | acc.errors]}
      end
    end)
  end

  defp scan_for_careers(results, base_url, source, organization, target_account) do
    Enum.reduce(@career_paths, results, fn path, acc ->
      url = base_url <> path

      case try_extract_page(url) do
        {:ok, content} ->
          signals = extract_hiring_signals(content, url)
          save_hiring_signals(signals, source, organization, target_account)
          %{acc | observations: acc.observations ++ signals}

        :not_found ->
          acc

        {:error, reason} ->
          %{acc | errors: [{:careers, path, reason} | acc.errors]}
      end
    end)
  end

  defp scan_for_news(results, base_url, source, organization, target_account) do
    Enum.reduce(@news_paths, results, fn path, acc ->
      url = base_url <> path

      case try_extract_page(url) do
        {:ok, content} ->
          signals = extract_expansion_signals(content, url)
          save_expansion_signals(signals, source, organization, target_account)
          %{acc | observations: acc.observations ++ signals}

        :not_found ->
          acc

        {:error, reason} ->
          %{acc | errors: [{:news, path, reason} | acc.errors]}
      end
    end)
  end

  defp try_extract_page(url) do
    case Navigate.run(%{url: url, wait_for_network: false}, %{}) do
      {:ok, %{status: :ok}} ->
        Process.sleep(2000)

        js = """
        (function() {
          const title = document.title || '';
          const body = document.body?.innerText?.substring(0, 5000) || '';
          const is404 = title.toLowerCase().includes('not found') ||
                        title.toLowerCase().includes('404') ||
                        body.toLowerCase().includes('page not found');
          return { title, body, is404 };
        })()
        """

        case Extract.run(%{js: js}, %{}) do
          {:ok, %{data: %{"is404" => true}}} -> :not_found
          {:ok, %{data: %{"body" => body}}} when byte_size(body) > 100 -> {:ok, body}
          {:ok, _} -> :not_found
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{status: :error}} ->
        :not_found
    end
  end

  defp extract_contacts_from_content(content) do
    content_lower = String.downcase(content)

    # Look for email patterns
    emails =
      Regex.scan(~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, content)
      |> List.flatten()
      |> Enum.reject(&String.contains?(&1, ["example.com", "noreply", "no-reply", "wixpress"]))
      |> Enum.uniq()

    # Look for common title patterns near names
    has_engineering =
      String.contains?(content_lower, ["engineer", "controls", "automation", "operations"])

    Enum.map(emails, fn email ->
      %{email: email, has_engineering_context: has_engineering}
    end)
  end

  defp extract_hiring_signals(content, url) do
    content_lower = String.downcase(content)

    keywords =
      ~w(controls engineer plc scada automation electrical instrumentation maintenance technician)

    matches =
      Enum.filter(keywords, &String.contains?(content_lower, &1))

    if length(matches) > 0 do
      [%{type: :hiring, keywords: matches, url: url}]
    else
      []
    end
  end

  defp extract_expansion_signals(content, url) do
    content_lower = String.downcase(content)

    expansion_terms =
      ~w(expansion new facility production line upgrade modernization capital improvement)

    matches =
      Enum.filter(expansion_terms, &String.contains?(content_lower, &1))

    if length(matches) > 0 do
      [%{type: :expansion, keywords: matches, url: url}]
    else
      []
    end
  end

  defp save_contacts(contacts, organization, source, discovered_url) do
    Enum.each(contacts, fn %{email: email, has_engineering_context: has_engineering_context} ->
      {first_name, last_name} = contact_name_from_email(email)

      case Operations.create_person(
             %{
               first_name: first_name,
               last_name: last_name,
               email: email,
               notes: "Discovered by SiteScanner from #{discovered_url}"
             },
             upsert?: true,
             upsert_identity: :unique_email,
             upsert_fields: [:first_name, :last_name, :notes]
           ) do
        {:ok, person} ->
          Operations.create_organization_affiliation(
            %{
              organization_id: organization.id,
              person_id: person.id,
              title:
                if(has_engineering_context, do: "Engineering contact", else: "Website contact"),
              contact_roles:
                if(has_engineering_context, do: ["technical_contact"], else: ["general_contact"]),
              is_primary: false,
              notes: "Discovered from company website source #{source.name}"
            },
            upsert?: true,
            upsert_identity: :unique_active_affiliation,
            upsert_fields: [:title, :contact_roles, :notes]
          )

        {:error, error} ->
          Logger.warning(
            "[SiteScanner] Failed to upsert person #{email} for #{source.name}: #{inspect(error)}"
          )
      end
    end)
  end

  defp save_hiring_signals([], _source, _organization, _target_account), do: :ok

  defp save_hiring_signals(signals, source, organization, target_account) do
    Enum.each(signals, fn signal ->
      create_observation_if_missing(
        source,
        organization,
        target_account,
        signal,
        "hiring",
        "Hiring signal found on company site"
      )
    end)
  end

  defp save_expansion_signals([], _source, _organization, _target_account), do: :ok

  defp save_expansion_signals(signals, source, organization, target_account) do
    Enum.each(signals, fn signal ->
      create_observation_if_missing(
        source,
        organization,
        target_account,
        signal,
        "expansion",
        "Expansion signal found on company site"
      )
    end)
  end

  defp create_observation_if_missing(
         source,
         organization,
         target_account,
         signal,
         signal_kind,
         description_prefix
       ) do
    external_ref = "#{source.id}:#{signal_kind}:#{signal.url}"

    Commercial.create_target_observation(
      %{
        target_account_id: target_account.id,
        observation_type: observation_type(signal_kind),
        source_channel: :company_website,
        external_ref: external_ref,
        source_url: signal.url,
        observed_at: DateTime.utc_now(),
        confidence_score: confidence_for_signal(signal_kind, signal.keywords),
        summary: "#{description_prefix}: #{Enum.join(signal.keywords, ", ")}",
        raw_excerpt: "#{signal_kind} signal: #{Enum.join(signal.keywords, ", ")} — #{signal.url}",
        evidence_points: signal.keywords,
        discovery_program_id: discovery_program_id(source),
        metadata: %{
          source: "company_scanner",
          scan_type: signal_kind,
          keywords: signal.keywords,
          discovery_program_id: discovery_program_id(source),
          procurement_source_id: source.id,
          organization_id: organization.id
        }
      },
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

  defp ensure_organization!(source) do
    {:ok, organization} =
      Operations.create_organization(
        %{
          name: source.name,
          status: :prospect,
          relationship_roles: ["prospect"],
          website: WebIdentity.normalize_website(source.url),
          primary_region: source.region |> to_string(),
          notes: source.notes || "Discovered from company website monitoring source"
        },
        upsert?: true,
        upsert_identity: :unique_name,
        upsert_fields: [:website, :primary_region, :notes]
      )

    organization
  end

  defp ensure_target_account!(source, organization) do
    {:ok, target_account} =
      Commercial.create_target_account(
        %{
          name: source.name,
          website: WebIdentity.normalize_website(source.url),
          region: source.region && to_string(source.region),
          fit_score: 70,
          intent_score: 55,
          status: :new,
          discovery_program_id: discovery_program_id(source),
          organization_id: organization.id,
          notes: source.notes || "Discovered from monitored company website source",
          metadata: %{
            source: "company_scanner",
            discovery_program_id: discovery_program_id(source),
            procurement_source_id: source.id
          }
        },
        upsert?: true,
        upsert_identity:
          if(WebIdentity.website_domain(source.url),
            do: :unique_website_domain,
            else: :unique_name_location
          ),
        upsert_fields: [:region, :fit_score, :intent_score, :organization_id, :notes, :metadata]
      )

    target_account
  end

  defp extract_base_url(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}"
  end

  defp observation_type("hiring"), do: :hiring
  defp observation_type("expansion"), do: :expansion
  defp observation_type(_), do: :other

  defp confidence_for_signal("hiring", keywords) when is_list(keywords),
    do: min(70 + length(keywords) * 5, 95)

  defp confidence_for_signal("expansion", keywords) when is_list(keywords),
    do: min(65 + length(keywords) * 5, 90)

  defp confidence_for_signal(_, _), do: 60

  defp discovery_program_id(%ProcurementSource{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, :discovery_program_id) || Map.get(metadata, "discovery_program_id")
  end

  defp discovery_program_id(_source), do: nil

  defp contact_name_from_email(email) do
    email
    |> String.split("@")
    |> hd()
    |> String.split(~r/[._-]/)
    |> case do
      [first, last | _rest] -> {String.capitalize(first), String.capitalize(last)}
      [single] -> {String.capitalize(single), "Unknown"}
      _ -> {"Unknown", "Unknown"}
    end
  end
end
