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

  @doc "Returns the default per-preview provider spend ceiling."
  def default_spend_ceiling, do: Decimal.from_float(@default_spend_ceiling)

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

    with {:ok, run} <- persist_run(ranked, opts, summary) do
      ranked = attach_persisted_ids(ranked, run)

      GnomeGarden.Acquisition.Telemetry.candidate_routing(
        %{
          candidate_count: length(ranked),
          promotable_count: promotable,
          needs_enrichment_count: needs_enrichment,
          suppressed_count: suppressed,
          failed_query_count: length(errors),
          cost: Float.round(cost, 4)
        },
        %{lead_preview_run_id: run && run.id}
      )

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
        idempotency_key: Keyword.fetch!(opts, :budget_idempotency_key),
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
        metadata:
          %{
            "provider_budget_idempotency_key" => Keyword.fetch!(opts, :budget_idempotency_key)
          }
          |> Map.merge(Keyword.get(opts, :execution_policy_snapshot, %{})),
        discovery_program_id: Keyword.get(opts, :discovery_program_id),
        created_by_id: actor_id(Keyword.get(opts, :actor)),
        candidates: Enum.map(ranked, &candidate_attrs/1)
      }

      actor = Keyword.get(opts, :actor)
      idempotency_key = Keyword.fetch!(opts, :budget_idempotency_key)

      case Acquisition.get_lead_preview_run_by_key(idempotency_key, actor: actor) do
        {:ok, run} -> Acquisition.get_lead_preview_run(run.id, actor: actor)
        {:error, _not_found} -> Acquisition.create_lead_preview_run(attrs, actor: actor)
      end
    else
      {:ok, nil}
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
      metadata: %{
        "related" => related_metadata(candidate.dedupe),
        "exa_score" => candidate[:score]
      }
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
    with {:ok, policy_opts} <- typed_policy_opts(program, opts) do
      run(Keyword.merge(opts, policy_opts))
    end
  end

  def run_for_program(id, opts) when is_binary(id) do
    case Commercial.get_discovery_program(id, actor: Keyword.get(opts, :actor)) do
      {:ok, program} -> run_for_program(program, opts)
      error -> error
    end
  end

  defp typed_policy_opts(program, opts) do
    actor = Keyword.get(opts, :actor)

    case Keyword.get(opts, :execution_policy_snapshot) do
      %{} = snapshot -> snapshot_policy_opts(snapshot)
      nil -> current_policy_opts(program, opts, actor)
    end
  end

  defp current_policy_opts(program, opts, actor) do
    with {:ok, policy} <- resolve_program_source(program, opts, actor) do
      {:ok,
       [
         search_terms: policy.query_templates,
         regions: [],
         industries: [],
         max_queries: policy.max_queries_per_run,
         max_results_per_query: policy.max_results_per_query,
         spend_ceiling: Decimal.to_float(policy.spend_limit_per_run.amount),
         execution_policy_snapshot: %{
           "program_source_id" => policy.id,
           "source_id" => policy.source_id,
           "query_templates" => policy.query_templates,
           "cadence_minutes" => policy.cadence_minutes,
           "max_queries_per_run" => policy.max_queries_per_run,
           "max_results_per_query" => policy.max_results_per_query,
           "enrichment_policy" => to_string(policy.enrichment_policy),
           "max_enrichments_per_run" => policy.max_enrichments_per_run,
           "finding_limit_per_run" => policy.finding_limit_per_run,
           "finding_limit_per_day" => policy.finding_limit_per_day
         }
       ]}
    end
  end

  defp snapshot_policy_opts(snapshot) do
    with {:ok, spend_ceiling} <- parse_snapshot_float(snapshot, "spend_limit_per_run"),
         true <- is_binary(snapshot["program_source_id"]),
         true <- is_binary(snapshot["source_id"]),
         [_ | _] = query_templates <- snapshot["query_templates"] do
      {:ok,
       [
         search_terms: query_templates,
         regions: [],
         industries: [],
         max_queries: snapshot["max_queries_per_run"],
         max_results_per_query: snapshot["max_results_per_query"],
         spend_ceiling: spend_ceiling,
         execution_policy_snapshot: snapshot
       ]}
    else
      _invalid -> {:error, :invalid_program_source_snapshot}
    end
  end

  defp parse_snapshot_float(snapshot, key) do
    case Float.parse(to_string(snapshot[key])) do
      {value, ""} when value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_program_source_snapshot}
    end
  end

  defp resolve_program_source(program, opts, actor) do
    case Keyword.get(opts, :program_source_id) do
      nil ->
        Acquisition.get_active_exa_program_source_for_discovery_program(program.id, actor: actor)

      program_source_id ->
        with {:ok, policy} <- Acquisition.get_program_source(program_source_id, actor: actor),
             true <- active_exa_policy?(policy, program.id) do
          {:ok, policy}
        else
          _invalid_policy -> {:error, :active_program_source_required}
        end
    end
  end

  defp active_exa_policy?(%{status: :active, enabled: true} = policy, discovery_program_id) do
    policy = Ash.load!(policy, [:program, :source])

    policy.program.discovery_program_id == discovery_program_id and
      policy.program.status == :active and policy.source.enabled and
      policy.source.status == :active and policy.source.external_ref == "provider:exa:search"
  end

  defp active_exa_policy?(_policy, _discovery_program_id), do: false

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

            {:skip, cost} ->
              {:cont, %{acc | cost: acc.cost + cost, executed: acc.executed + 1}}

            {:failed_skip, cost, reason} ->
              {:cont,
               %{
                 acc
                 | cost: acc.cost + cost,
                   executed: acc.executed + 1,
                   errors: [reason | acc.errors]
               }}

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
         {:ok, %{reservation: reservation}} <-
           Acquisition.reserve_provider_capacity(request, actor: actor) do
      case reservation.status do
        :reserved -> execute_budgeted_search(query, search_opts, reservation, actor)
        _finalized -> replay_settled_search(reservation)
      end
    else
      {:error, reason} ->
        {:error, {:provider_budget, reason}}
    end
  end

  defp execute_budgeted_search(query, search_opts, reservation, actor) do
    case Exa.search(query.text, search_opts) do
      {:ok, %{cost: cost} = response} ->
        case Acquisition.settle_provider_capacity(
               %{
                 idempotency_key: reservation.idempotency_key,
                 actual_cost: cost || 0,
                 actual_requests: 1,
                 status: :settled,
                 metadata: %{"response" => cache_response(response)}
               },
               actor: actor
             ) do
          {:ok, _settlement} -> {:ok, response}
          {:error, reason} -> {:error, {:provider_budget, reason}}
        end

      {:error, reason} ->
        account_provider_failure(reservation, reason, actor)
        {:error, reason}
    end
  end

  defp replay_settled_search(%{status: :settled, metadata: %{"response" => response}}) do
    {:ok, restore_response(response)}
  end

  defp replay_settled_search(%{status: :settled, actual_cost: actual_cost}) do
    {:skip, Decimal.to_float(actual_cost)}
  end

  defp replay_settled_search(%{
         status: status,
         actual_cost: actual_cost,
         failure_reason: reason
       })
       when status in [:partial_failure, :failed] do
    {:failed_skip, Decimal.to_float(actual_cost), reason || Atom.to_string(status)}
  end

  defp replay_settled_search(reservation) do
    {:error, {:provider_budget, {:provider_reservation_finalized, reservation.status}}}
  end

  defp account_provider_failure(reservation, reason, actor) do
    result = ProviderBudgetPolicy.account_failure(reservation, reason, actor: actor)

    case result do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        Logger.warning("LeadPreview: provider accounting failed: #{inspect(error)}")
    end
  end

  defp cache_response(response) do
    %{
      "cost" => response.cost,
      "resolved_type" => response[:resolved_type],
      "results" =>
        Enum.map(response.results, fn result ->
          %{
            "title" => result.title,
            "url" => result.url,
            "published_date" => result.published_date,
            "score" => result[:score]
          }
        end)
    }
  end

  defp restore_response(response) do
    %{
      cost: response["cost"],
      resolved_type: response["resolved_type"],
      results:
        Enum.map(response["results"] || [], fn result ->
          %{
            title: result["title"],
            url: result["url"],
            published_date: result["published_date"],
            score: result["score"]
          }
        end)
    }
  end

  defp tag(results, query) do
    Enum.map(results, fn result ->
      %{
        title: result.title,
        url: result.url,
        published_date: result.published_date,
        score: result[:score],
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
