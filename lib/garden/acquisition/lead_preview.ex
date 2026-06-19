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

  require Logger

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.{LeadDedup, LeadPromote}
  alias GnomeGarden.Commercial
  alias GnomeGarden.Search.Exa
  alias GnomeGarden.Support.WebIdentity

  @default_max_queries 8
  @default_max_results 8
  @default_spend_ceiling 0.25

  # Automation vendors/integrators the tuning loop showed dominate "automation"
  # queries. Always excluded (operators can add more via :exclude_domains).
  @default_vendor_domains ~w(
    rockwellautomation.com fanucamerica.com fanuc.com emersonautomationexperts.com
    emerson.com eclipseautomation.com atsindustrialautomation.com atsautomation.com
    siemens.com schneider-electric.com honeywell.com
  )

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

  # Host substrings that mark a page as a signal (job board / press / portal /
  # social / bid portal), NOT the prospect's own company page.
  @signal_host_markers ~w(
    job jobs careers hiring greenhouse lever workable indeed ziprecruiter
    prnewswire businesswire globenewswire einpresswire prweb
    linkedin breakroom tealhq applytojob earnbetter
    facebook twitter crunchbase glassdoor
    planetbids bidnet demandstar bonfirehub publicpurchase opengov bidexpress periscope
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

    # Enforce the tuning lessons: always exclude known vendor domains; pass
    # recency (start_published_date) and category through when provided.
    search_opts =
      [
        num_results: max_results,
        type: "auto",
        exclude_domains: Enum.uniq(@default_vendor_domains ++ Keyword.get(opts, :exclude_domains, [])),
        category: Keyword.get(opts, :category),
        start_published_date: Keyword.get(opts, :start_published_date)
      ]

    %{cost: cost, candidates: raw, executed: executed, errors: errors} =
      search_all(queries, search_opts, ceiling)

    candidates =
      raw
      |> dedupe_within_run()
      |> Enum.map(fn candidate -> Map.put(candidate, :type, candidate_type(candidate)) end)

    ranked =
      candidates
      |> LeadDedup.classify_all(actor: actor)
      |> Enum.map(fn {candidate, dedupe} -> Map.put(candidate, :dedupe, dedupe) end)
      |> Enum.sort_by(&rank_key/1)
      |> Enum.with_index()
      |> Enum.map(fn {candidate, rank} ->
        candidate |> Map.put(:route, LeadPromote.route(candidate)) |> Map.put(:rank, rank)
      end)

    promotable = Enum.count(ranked, &(&1.route == :promote))
    needs_enrichment = Enum.count(ranked, &(&1.route == :needs_enrichment))
    suppressed = Enum.count(ranked, & &1.dedupe.suppress?)
    error_strings = errors |> Enum.reverse() |> Enum.map(&inspect/1)

    summary = %{
      executed: executed,
      cost: Float.round(cost, 4),
      promotable: promotable,
      needs_enrichment: needs_enrichment,
      suppressed: suppressed,
      errors: error_strings
    }

    run = persist_run(ranked, opts, summary)

    {:ok,
     %{
       run_id: run && run.id,
       queries_run: executed,
       total_cost: Float.round(cost, 4),
       candidate_count: length(ranked),
       promotable_count: promotable,
       needs_enrichment_count: needs_enrichment,
       kept_count: Enum.count(ranked, &(not &1.dedupe.suppress?)),
       suppressed_count: suppressed,
       failed_queries: length(errors),
       errors: error_strings,
       candidates: ranked
     }}
  end

  defp persist_run(ranked, opts, summary) do
    if Keyword.get(opts, :persist, true) do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      attrs = %{
        source: :exa,
        status: run_status(summary),
        started_at: now,
        finished_at: now,
        query_count: summary.executed,
        candidate_count: length(ranked),
        promotable_count: summary.promotable,
        needs_enrichment_count: summary.needs_enrichment,
        suppressed_count: summary.suppressed,
        total_cost: cost_decimal(summary.cost),
        errors: summary.errors,
        discovery_program_id: Keyword.get(opts, :discovery_program_id),
        created_by_id: actor_id(Keyword.get(opts, :actor)),
        candidates: Enum.map(ranked, &candidate_attrs/1)
      }

      case Acquisition.create_lead_preview_run(attrs, actor: Keyword.get(opts, :actor)) do
        {:ok, run} ->
          run

        {:error, reason} ->
          Logger.warning("LeadPreview: failed to persist run: #{inspect(reason)}")
          nil
      end
    end
  end

  defp candidate_attrs(candidate) do
    %{
      title: candidate[:title],
      url: candidate[:url],
      website_domain: WebIdentity.website_domain(candidate[:url]),
      query: candidate[:query],
      published_date: candidate[:published_date],
      candidate_type: candidate[:type],
      dedupe_context: candidate.dedupe.context,
      route: candidate.route,
      suppressed: candidate.dedupe.suppress?,
      recommendation: candidate.dedupe.recommendation,
      rank: candidate.rank,
      status: :pending,
      metadata: %{"related" => related_metadata(candidate.dedupe)}
    }
  end

  defp related_metadata(%{related: related}) when is_list(related) do
    Enum.map(related, fn r -> %{"kind" => to_string(r[:kind]), "id" => r[:id], "label" => r[:label]} end)
  end

  defp related_metadata(_dedupe), do: []

  defp run_status(%{executed: 0}), do: :failed

  defp run_status(%{errors: errors, promotable: p, needs_enrichment: n, suppressed: s}) do
    cond do
      errors == [] -> :completed
      p + n + s == 0 -> :failed
      true -> :partial_failure
    end
  end

  defp cost_decimal(cost) when is_float(cost), do: Decimal.from_float(cost)
  defp cost_decimal(cost), do: Decimal.new(cost)

  defp actor_id(%{id: id}), do: id
  defp actor_id(_actor), do: nil

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

  defp search_all(queries, search_opts, ceiling) do
    Enum.reduce_while(queries, %{cost: 0.0, candidates: [], executed: 0, errors: []}, fn query, acc ->
      if acc.cost >= ceiling do
        {:halt, acc}
      else
        case Exa.search(query.text, search_opts) do
          {:ok, %{cost: cost, results: results}} ->
            acc = %{
              acc
              | cost: acc.cost + (cost || 0.0),
                candidates: acc.candidates ++ tag(results, query),
                executed: acc.executed + 1
            }

            if acc.cost >= ceiling, do: {:halt, acc}, else: {:cont, acc}

          {:error, reason} ->
            # Don't let a failed query silently look like "no results" — record it.
            {:cont, %{acc | executed: acc.executed + 1, errors: [reason | acc.errors]}}
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

  # Type is decided by the PAGE/DOMAIN, not the query intent: a company's own
  # page found via a signal-shaped query is still a company (promotable), not a
  # signal page needing enrichment. Query intent only affects ranking/context.
  defp candidate_type(%{url: url}) do
    if signal_host?(WebIdentity.website_domain(url)), do: :signal, else: :company
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
