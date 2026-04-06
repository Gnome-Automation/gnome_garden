defmodule GnomeGarden.Agents.CompanyScanner do
  @moduledoc """
  Scans company websites for contacts, hiring signals, and news.

  Unlike DeterministicScanner (which uses saved CSS selectors for procurement
  portals), CompanyScanner uses common URL patterns and page structure
  heuristics to extract useful information from any company website.

  Extracts:
  - Contacts from /about, /team, /contact pages
  - Hiring signals from /careers, /jobs pages
  - Expansion news from /news, /press pages

  Creates Sales.Contact + Sales.Employment for new contacts found,
  and Sales.Lead for hiring/expansion signals.
  """

  alias GnomeGarden.Agents.LeadSource
  alias GnomeGarden.Agents.Tools.Browser.{Navigate, Extract}

  require Logger

  @contact_paths ["/about", "/team", "/about-us", "/our-team", "/contact", "/contact-us"]
  @career_paths ["/careers", "/jobs", "/career", "/join-us", "/employment", "/work-with-us"]
  @news_paths ["/news", "/press", "/blog", "/press-releases", "/announcements"]

  def scan(%LeadSource{source_type: :company_site, company_id: company_id} = source)
      when not is_nil(company_id) do
    Logger.info("[CompanyScanner] Scanning #{source.name} at #{source.url}")

    base_url = extract_base_url(source.url)
    results = %{contacts: [], signals: [], errors: []}

    results =
      results
      |> scan_for_contacts(base_url, source)
      |> scan_for_careers(base_url, source)
      |> scan_for_news(base_url, source)

    Ash.update!(source, %{}, action: :mark_scanned)

    {:ok,
     %{
       source: source.name,
       contacts_found: length(results.contacts),
       signals_found: length(results.signals),
       errors: length(results.errors)
     }}
  rescue
    e ->
      Logger.error("[CompanyScanner] Failed for #{source.name}: #{Exception.message(e)}")
      Ash.update(source, %{}, action: :scan_fail)
      {:error, Exception.message(e)}
  end

  def scan(%LeadSource{} = source) do
    Logger.warning("[CompanyScanner] #{source.name} has no company_id, skipping")
    {:ok, %{skipped: true, reason: "no company_id"}}
  end

  defp scan_for_contacts(results, base_url, source) do
    Enum.reduce(@contact_paths, results, fn path, acc ->
      url = base_url <> path

      case try_extract_page(url) do
        {:ok, content} ->
          contacts = extract_contacts_from_content(content)
          save_contacts(contacts, source.company_id)
          %{acc | contacts: acc.contacts ++ contacts}

        :not_found ->
          acc

        {:error, reason} ->
          %{acc | errors: [{:contacts, path, reason} | acc.errors]}
      end
    end)
  end

  defp scan_for_careers(results, base_url, source) do
    Enum.reduce(@career_paths, results, fn path, acc ->
      url = base_url <> path

      case try_extract_page(url) do
        {:ok, content} ->
          signals = extract_hiring_signals(content, url)
          save_hiring_signals(signals, source)
          %{acc | signals: acc.signals ++ signals}

        :not_found ->
          acc

        {:error, reason} ->
          %{acc | errors: [{:careers, path, reason} | acc.errors]}
      end
    end)
  end

  defp scan_for_news(results, base_url, source) do
    Enum.reduce(@news_paths, results, fn path, acc ->
      url = base_url <> path

      case try_extract_page(url) do
        {:ok, content} ->
          signals = extract_expansion_signals(content, url)
          save_expansion_signals(signals, source)
          %{acc | signals: acc.signals ++ signals}

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

      {:error, reason} ->
        {:error, inspect(reason)}
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

  defp save_contacts(contacts, company_id) do
    Enum.each(contacts, fn %{email: email} ->
      # Only save if contact doesn't already exist with this email
      require Ash.Query

      existing =
        GnomeGarden.Sales.Contact
        |> Ash.Query.filter(email == ^email)
        |> Ash.Query.limit(1)
        |> Ash.read!()

      if existing == [] do
        case GnomeGarden.Sales.create_contact(%{
               first_name: "Unknown",
               last_name: email_to_name(email),
               email: email
             }) do
          {:ok, contact} ->
            Ash.create(GnomeGarden.Sales.Employment, %{
              contact_id: contact.id,
              company_id: company_id,
              is_current: true
            })

          _ ->
            :ok
        end
      end
    end)
  end

  defp save_hiring_signals([], _source), do: :ok

  defp save_hiring_signals(signals, source) do
    Enum.each(signals, fn signal ->
      GnomeGarden.Sales.create_lead(%{
        first_name: "Hiring",
        last_name: source.name,
        company_name: source.name,
        company_id: source.company_id,
        source: :other,
        source_details: "hiring signal: #{Enum.join(signal.keywords, ", ")} — #{signal.url}"
      })
    end)
  end

  defp save_expansion_signals([], _source), do: :ok

  defp save_expansion_signals(signals, source) do
    Enum.each(signals, fn signal ->
      GnomeGarden.Sales.create_lead(%{
        first_name: "Expansion",
        last_name: source.name,
        company_name: source.name,
        company_id: source.company_id,
        source: :other,
        source_details: "expansion signal: #{Enum.join(signal.keywords, ", ")} — #{signal.url}"
      })
    end)
  end

  defp extract_base_url(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}"
  end

  defp email_to_name(email) do
    email
    |> String.split("@")
    |> hd()
    |> String.split(~r/[._-]/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
