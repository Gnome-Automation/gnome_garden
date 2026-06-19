defmodule GnomeGarden.Acquisition.LeadPreview do
  @moduledoc """
  Dry-run lead preview. Turns discovery inputs (search terms / regions /
  industries) into signal-shaped Exa queries, searches within hard caps and a
  spend ceiling, dedupes within the run, classifies every candidate against the
  data we already have (`LeadDedup`), and returns a ranked preview.

  **Preview only — it never creates findings.** It is the surface for proving
  query quality before any contents fetch, extraction, or lead creation.

  Query phrasing deliberately targets operational SIGNALS (expansion, new
  production line, hiring controls/maintenance, capital projects, public-sector
  agendas) and avoids the word "automation", which the tuning loop showed
  surfaces vendors rather than prospects. Edit `@signal_templates` to retune.
  """

  alias GnomeGarden.Acquisition.LeadDedup
  alias GnomeGarden.Commercial
  alias GnomeGarden.Search.Exa
  alias GnomeGarden.Support.WebIdentity

  @default_max_queries 8
  @default_max_results 8
  @default_spend_ceiling 0.25

  # {intent, template}. `{industry}` / `{region}` are filled per combination.
  @signal_templates [
    {:signal, "{industry} company expanding production {region}"},
    {:signal, "{industry} new production line {region}"},
    {:signal, "{industry} facility expansion {region}"},
    {:signal, "{industry} plant hiring controls engineer {region}"},
    {:signal, "{industry} plant hiring maintenance technician {region}"},
    {:signal, "{industry} capital project {region}"}
  ]

  @public_sector_templates [
    {:signal, "{region} water district SCADA upgrade board agenda"}
  ]

  # Host substrings that mark a page as a signal (job board / press / portal),
  # not a company homepage.
  @signal_host_markers ~w(
    job jobs careers hiring greenhouse lever workable indeed ziprecruiter
    prnewswire businesswire globenewswire einpresswire prweb
    linkedin breakroom tealhq applytojob earnbetter
  )

  @context_rank %{
    new: 0,
    known_organization_new_signal: 1,
    known_bid_source: 2,
    existing_bid_related: 3,
    known_procurement_source: 4,
    duplicate_existing_lead: 5
  }

  @doc """
  Runs a preview. Options:

    * `:search_terms` / `:regions` / `:industries` — lists of strings
    * `:max_queries` (default #{@default_max_queries})
    * `:max_results_per_query` (default #{@default_max_results})
    * `:spend_ceiling` — dollars; stop issuing queries once reached (default #{@default_spend_ceiling})
    * `:actor`
  """
  def run(opts \\ []) do
    max_queries = Keyword.get(opts, :max_queries, @default_max_queries)
    max_results = Keyword.get(opts, :max_results_per_query, @default_max_results)
    ceiling = Keyword.get(opts, :spend_ceiling, @default_spend_ceiling)
    actor = Keyword.get(opts, :actor)

    queries = opts |> build_queries() |> Enum.take(max_queries)

    %{cost: cost, candidates: raw, executed: executed} = search_all(queries, max_results, ceiling)

    candidates =
      raw
      |> dedupe_within_run()
      |> Enum.map(fn candidate -> Map.put(candidate, :type, candidate_type(candidate)) end)

    ranked =
      candidates
      |> LeadDedup.classify_all(actor: actor)
      |> Enum.map(fn {candidate, dedupe} -> Map.put(candidate, :dedupe, dedupe) end)
      |> Enum.sort_by(&rank_key/1)

    {:ok,
     %{
       queries_run: executed,
       total_cost: Float.round(cost, 4),
       candidate_count: length(ranked),
       kept_count: Enum.count(ranked, &(not &1.dedupe.suppress?)),
       suppressed_count: Enum.count(ranked, & &1.dedupe.suppress?),
       candidates: ranked
     }}
  end

  @doc "Runs a preview from a `DiscoveryProgram`'s terms/regions/industries."
  def run_for_program(program, opts \\ [])

  def run_for_program(%{} = program, opts) do
    run(
      Keyword.merge(
        [
          search_terms: List.wrap(program.search_terms),
          regions: List.wrap(program.target_regions),
          industries: List.wrap(program.target_industries)
        ],
        opts
      )
    )
  end

  def run_for_program(id, opts) when is_binary(id) do
    case Commercial.get_discovery_program(id, actor: Keyword.get(opts, :actor)) do
      {:ok, program} -> run_for_program(program, opts)
      error -> error
    end
  end

  @doc "Builds the (deduped) list of `%{text:, intent:}` queries from inputs."
  def build_queries(opts) do
    industries = present(Keyword.get(opts, :industries, []))
    regions = present(Keyword.get(opts, :regions, []))
    terms = present(Keyword.get(opts, :search_terms, []))

    templated =
      for {intent, template} <- @signal_templates,
          industry <- industries || [""],
          region <- regions || [""] do
        %{intent: intent, text: fill(template, industry, region)}
      end

    public_sector =
      for {intent, template} <- @public_sector_templates, region <- regions || [""] do
        %{intent: intent, text: fill(template, "", region)}
      end

    raw = for term <- terms || [], do: %{intent: :company, text: String.trim(term)}

    (raw ++ templated ++ public_sector)
    |> Enum.reject(&(&1.text == ""))
    |> Enum.uniq_by(& &1.text)
  end

  # --- search with caps + spend ceiling ---

  defp search_all(queries, max_results, ceiling) do
    Enum.reduce_while(queries, %{cost: 0.0, candidates: [], executed: 0}, fn query, acc ->
      if acc.cost >= ceiling do
        {:halt, acc}
      else
        case Exa.search(query.text, num_results: max_results, type: "auto") do
          {:ok, %{cost: cost, results: results}} ->
            acc = %{
              acc
              | cost: acc.cost + (cost || 0.0),
                candidates: acc.candidates ++ tag(results, query),
                executed: acc.executed + 1
            }

            if acc.cost >= ceiling, do: {:halt, acc}, else: {:cont, acc}

          {:error, _reason} ->
            {:cont, %{acc | executed: acc.executed + 1}}
        end
      end
    end)
  end

  defp tag(results, query) do
    Enum.map(results, fn result ->
      %{
        title: result.title,
        url: result.url,
        published_date: result.published_date,
        intent: query.intent,
        query: query.text
      }
    end)
  end

  defp dedupe_within_run(candidates), do: Enum.uniq_by(candidates, & &1.url)

  defp candidate_type(%{url: url, intent: intent}) do
    if signal_host?(WebIdentity.website_domain(url)) or intent == :signal, do: :signal, else: :company
  end

  defp signal_host?(nil), do: false

  defp signal_host?(domain) do
    String.ends_with?(domain, [".gov", ".us"]) or
      Enum.any?(@signal_host_markers, &String.contains?(domain, &1))
  end

  defp rank_key(row) do
    {if(row.dedupe.suppress?, do: 1, else: 0), Map.get(@context_rank, row.dedupe.context, 9)}
  end

  defp fill(template, industry, region) do
    template
    |> String.replace("{industry}", industry)
    |> String.replace("{region}", region)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp present([]), do: nil
  defp present(list) when is_list(list), do: list |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
  defp present(_), do: nil
end
