defmodule GnomeGarden.Acquisition.LeadPreview do
  @moduledoc """
  Dry-run lead preview. Turns discovery inputs (search terms / regions /
  industries) into firmographic Exa queries, searches within hard caps and a
  spend ceiling, dedupes within the run, classifies every candidate against the
  data we already have (`LeadDedup`), and returns a ranked preview.

  **Preview creates no business records** (no findings, organizations, or
  discovery records) — only the operator's explicit promote does. It does,
  however, persist preview *telemetry* by default: a `LeadPreviewRun` + its
  `LeadPreviewCandidate`s, so cost/quality/split history accrues. Pass
  `persist: false` for a pure dry-run (e.g. the mix task's `--no-persist`).

  Strategy: find the prospect COMPANIES themselves on their own sites
  (`category: "company"` + the firmographic `@company_templates`), so a promoted
  candidate carries a real company domain. It deliberately avoids news/press,
  expansion, and hiring framing — those surfaced articles and vendors, not
  reachable prospects. News/media and vendor domains are excluded outright and,
  if any slip through, classified as `:signal` (never promoted). Edit
  `@company_templates` to retune.
  """

  require Logger

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.{LeadDedup, LeadPromote, ProviderBudgetPolicy}
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

  # Firmographic company-discovery templates: find the prospect companies
  # themselves on their own sites (paired with Exa's `category: "company"`).
  # Deliberately NO expansion / hiring / news framing — those surface articles
  # and vendors, not the companies we want to reach directly. `{industry}` /
  # `{region}` are filled per combination.
  @company_templates [
    {:company, "{industry} manufacturer {region}"},
    {:company, "{industry} company {region}"},
    {:company, "contract {industry} manufacturer {region}"},
    {:company, "{industry} production facility {region}"}
  ]

  # Host substrings that mark a page as NOT the prospect's own company page —
  # news/media, press wires, job boards, social, and bid portals. These are
  # classified as :signal (never promoted as a company) and excluded from search.
  @signal_host_markers ~w(
    job jobs careers hiring greenhouse lever workable indeed ziprecruiter
    prnewswire businesswire globenewswire einpresswire prweb prweb
    linkedin breakroom tealhq applytojob earnbetter
    facebook twitter crunchbase glassdoor
    planetbids bidnet demandstar bonfirehub publicpurchase opengov bidexpress periscope
    ocbj.com chapelboro morningstar thepacker flexpackvoice bizjournals reuters
    bloomberg prweb yahoo forbes inc.com news- -news
  )

  # News/media domains excluded from search by default (belt-and-suspenders with
  # category: "company"). News is not a useful discovery channel here.
  @default_news_domains ~w(
    prnewswire.com businesswire.com globenewswire.com einpresswire.com prweb.com
    ocbj.com chapelboro.com morningstar.com thepacker.com flexpackvoice.com
    bizjournals.com reuters.com bloomberg.com yahoo.com forbes.com
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
    opts = Keyword.put_new_lazy(opts, :budget_idempotency_key, &Ecto.UUID.generate/0)
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
        # Bias toward company homepages (not articles); news is excluded outright.
        category: Keyword.get(opts, :category, "company"),
        exclude_domains:
          Enum.uniq(
            @default_vendor_domains ++
              @default_news_domains ++ Keyword.get(opts, :exclude_domains, [])
          ),
        start_published_date: Keyword.get(opts, :start_published_date)
      ]

    %{cost: cost, candidates: raw, executed: executed, errors: errors} =
      search_all(
        queries,
        search_opts,
        ceiling,
        Keyword.fetch!(opts, :budget_idempotency_key),
        actor
      )

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
    ranked = attach_persisted_ids(ranked, run)

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
       budget_idempotency_key: Keyword.fetch!(opts, :budget_idempotency_key),
       candidates: ranked
     }}
  end

  defp attach_persisted_ids(ranked, nil), do: ranked

  defp attach_persisted_ids(ranked, run) do
    case Acquisition.list_lead_preview_candidates_for_run(run.id) do
      {:ok, persisted} ->
        by_url = Map.new(persisted, &{&1.url, &1.id})

        Enum.map(ranked, fn candidate ->
          Map.put(candidate, :id, Map.get(by_url, candidate[:url]))
        end)

      _ ->
        ranked
    end
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
        metadata: %{
          "provider_budget_idempotency_key" => Keyword.fetch!(opts, :budget_idempotency_key)
        },
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
    Enum.map(related, fn r ->
      %{"kind" => to_string(r[:kind]), "id" => r[:id], "label" => r[:label]}
    end)
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
      for {intent, template} <- @company_templates,
          industry <- industries || [""],
          region <- regions || [""] do
        %{intent: intent, text: fill(template, industry, region)}
      end

    raw = for term <- terms || [], do: %{intent: :company, text: String.trim(term)}

    (raw ++ templated)
    |> Enum.reject(&(&1.text == ""))
    |> Enum.uniq_by(& &1.text)
  end

  # --- search with caps + spend ceiling ---

  defp search_all(queries, search_opts, ceiling, budget_idempotency_key, actor) do
    queries
    |> Enum.with_index()
    |> Enum.reduce_while(
      %{cost: 0.0, candidates: [], executed: 0, errors: []},
      fn {query, query_index}, acc ->
        if acc.cost >= ceiling do
          {:halt, acc}
        else
          reservation_key = "#{budget_idempotency_key}:search:#{query_index}"

          case budgeted_search(query, search_opts, reservation_key, query_index, actor) do
            {:ok, %{cost: cost, results: results}} ->
              acc = %{
                acc
                | cost: acc.cost + (cost || 0.0),
                  candidates: acc.candidates ++ tag(results, query),
                  executed: acc.executed + 1
              }

              if acc.cost >= ceiling, do: {:halt, acc}, else: {:cont, acc}

            {:error, {:provider_budget, reason}} ->
              {:halt, %{acc | errors: [reason | acc.errors]}}

            {:error, reason} ->
              {:cont, %{acc | executed: acc.executed + 1, errors: [reason | acc.errors]}}
          end
        end
      end
    )
  end

  defp budgeted_search(query, search_opts, reservation_key, query_index, actor) do
    with {:ok, request} <-
           ProviderBudgetPolicy.configured_request(
             "exa",
             "search",
             reservation_key,
             metadata: %{"query_index" => query_index}
           ),
         {:ok, %{reservation: %{status: :reserved}}} <-
           Acquisition.reserve_provider_capacity(request, actor: actor) do
      case Exa.search(query.text, search_opts) do
        {:ok, %{cost: cost} = response} ->
          case Acquisition.settle_provider_capacity(
                 %{
                   idempotency_key: reservation_key,
                   actual_cost: cost || 0,
                   actual_requests: 1,
                   status: :settled
                 },
                 actor: actor
               ) do
            {:ok, _settlement} -> {:ok, response}
            {:error, reason} -> {:error, {:provider_budget, reason}}
          end

        {:error, reason} ->
          _ =
            Acquisition.release_provider_capacity(
              %{
                idempotency_key: reservation_key,
                failure_reason: inspect(reason)
              },
              actor: actor
            )

          {:error, reason}
      end
    else
      {:ok, %{reservation: reservation}} ->
        {:error, {:provider_budget, {:provider_reservation_finalized, reservation.status}}}

      {:error, reason} ->
        {:error, {:provider_budget, reason}}
    end
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

  # Dedupe by registrable domain (falling back to URL) so the same company
  # surfaced via several pages collapses to one candidate.
  defp dedupe_within_run(candidates) do
    Enum.uniq_by(candidates, fn candidate ->
      WebIdentity.website_domain(candidate.url) || candidate.url
    end)
  end

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

  defp present(list) when is_list(list),
    do: list |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))

  defp present(_), do: nil
end
