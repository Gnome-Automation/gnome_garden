defmodule GnomeGarden.Acquisition.LeadCandidateVerifier do
  @moduledoc """
  Verifies persisted Exa candidates and admits only evidenced companies.

  Cheap routing, dedupe, identity, and score gates run before paid enrichment.
  Exa Contents calls use provider reservations and cache their response for
  idempotent Oban retries.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.{FindingAdmissionPolicy, ProviderBudgetPolicy}
  alias GnomeGarden.Search.Exa
  alias GnomeGarden.Support.WebIdentity

  @summary_schema %{
    "type" => "object",
    "properties" => %{
      "company_name" => %{"type" => "string"},
      "business_description" => %{"type" => "string"},
      "is_operating_company" => %{"type" => "boolean"}
    },
    "required" => ["company_name", "business_description", "is_operating_company"]
  }

  def verify_run(lead_preview_run_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, preview_run} <- Acquisition.get_lead_preview_run(lead_preview_run_id, actor: actor),
         {:ok, program} <- acquisition_program(preview_run, actor),
         {:ok, policy} <- admission_policy(actor),
         {:ok, candidates} <-
           Acquisition.list_lead_preview_candidates_for_run(lead_preview_run_id, actor: actor) do
      case Enum.reduce_while(candidates, {:ok, initial_result()}, fn candidate, {:ok, result} ->
             case verify_candidate(candidate, preview_run, program, result, policy, actor) do
               {:ok, result} -> {:cont, {:ok, result}}
               {:error, error} -> {:halt, {:error, error}}
             end
           end) do
        {:ok, result} ->
          result = finalize_result(result)

          GnomeGarden.Acquisition.Telemetry.admission(
            %{
              verified_count: result.verified,
              admitted_count: result.admitted,
              unresolved_count: result.unresolved,
              ineligible_count: result.ineligible,
              enrichment_cost: Decimal.to_float(result.enrichment_cost)
            },
            %{lead_preview_run_id: lead_preview_run_id}
          )

          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp verify_candidate(candidate, preview_run, program, result, config, actor) do
    case eligibility(candidate, config) do
      :eligible when result.enrichment_attempts < config.candidate_limit ->
        enrich_and_admit(candidate, preview_run, program, result, config, actor)

      :eligible ->
        with {:ok, verification} <-
               record(candidate, :unresolved, :verification_limit_reached, %{}, nil, 0, actor) do
          {:ok, add_outcome(result, :unresolved, verification)}
        end

      {:ineligible, reason} ->
        with {:ok, verification} <- record(candidate, :ineligible, reason, %{}, nil, 0, actor) do
          {:ok, add_outcome(result, :ineligible, verification)}
        end
    end
  end

  defp enrich_and_admit(candidate, preview_run, program, result, config, actor) do
    reservation_key = contents_reservation_key(preview_run, candidate)
    result = %{result | enrichment_attempts: result.enrichment_attempts + 1}

    case budgeted_contents(candidate, reservation_key, actor) do
      {:ok, response, actual_cost} ->
        result = add_cost(result, actual_cost)

        case assess_evidence(candidate, response, config) do
          {:ok, evidence, verification_score} ->
            with {:ok, verification} <-
                   record(
                     candidate,
                     :verified,
                     :qualified,
                     evidence,
                     reservation_key,
                     actual_cost,
                     actor,
                     verification_score
                   ) do
              admit(verification, candidate, preview_run, program, result, config, actor)
            end

          {:error, reason, evidence} ->
            with {:ok, verification} <-
                   record(
                     candidate,
                     :ineligible,
                     reason,
                     evidence,
                     reservation_key,
                     actual_cost,
                     actor
                   ) do
              {:ok, add_outcome(result, :ineligible, verification)}
            end
        end

      {:error, :provider_budget_exhausted, reason, actual_cost} ->
        with {:ok, verification} <-
               record(
                 candidate,
                 :unresolved,
                 :provider_budget_exhausted,
                 %{"error" => inspect(reason)},
                 reservation_key,
                 actual_cost,
                 actor
               ) do
          result =
            result
            |> add_cost(actual_cost)
            |> add_outcome(:unresolved, verification)

          {:ok, result}
        end

      {:error, :provider_failure, reason, actual_cost} ->
        with {:ok, verification} <-
               record(
                 candidate,
                 :unresolved,
                 :provider_failure,
                 %{"error" => inspect(reason)},
                 reservation_key,
                 actual_cost,
                 actor
               ) do
          result =
            result
            |> add_cost(actual_cost)
            |> add_error(reason)
            |> add_outcome(:unresolved, verification)

          {:ok, result}
        end
    end
  end

  defp admit(verification, candidate, preview_run, program, result, config, actor) do
    case FindingAdmissionPolicy.admit(
           verification,
           candidate,
           preview_run,
           program,
           actor: actor,
           run_limit: config.finding_run_limit,
           daily_limit: config.finding_daily_limit
         ) do
      {:ok, %{admission: admission, reused?: reused?}} ->
        result =
          result
          |> add_outcome(:verified, verification)
          |> Map.update!(:admitted, &(&1 + 1))
          |> Map.update!(:reused_admissions, &(&1 + if(reused?, do: 1, else: 0)))
          |> Map.update!(:admission_ids, &[admission.id | &1])

        {:ok, result}

      {:error, error} ->
        result = add_outcome(result, :verified, verification)

        if FindingAdmissionPolicy.capacity_exceeded?(error) do
          {:ok, Map.update!(result, :capacity_deferred, &(&1 + 1))}
        else
          {:error, error}
        end
    end
  end

  defp eligibility(%{suppressed: true}, _config), do: {:ineligible, :suppressed}

  defp eligibility(%{dedupe_context: context}, _config) when context != :new,
    do: {:ineligible, :duplicate_context}

  defp eligibility(%{route: route}, _config) when route != :promote,
    do: {:ineligible, :not_promote_routed}

  defp eligibility(%{candidate_type: type}, _config) when type != :company,
    do: {:ineligible, :invalid_company_identity}

  defp eligibility(candidate, config) do
    domain = candidate.website_domain || WebIdentity.website_domain(candidate.url)
    score = search_score(candidate)

    cond do
      is_nil(domain) -> {:ineligible, :invalid_company_identity}
      is_nil(score) -> {:ineligible, :below_search_score}
      Decimal.compare(score, config.min_search_score) == :lt -> {:ineligible, :below_search_score}
      true -> :eligible
    end
  end

  defp budgeted_contents(candidate, reservation_key, actor) do
    with {:ok, request} <-
           ProviderBudgetPolicy.configured_request(
             "exa",
             "contents",
             reservation_key,
             metadata: %{"lead_preview_candidate_id" => candidate.id}
           ),
         {:ok, %{reservation: reservation}} <-
           Acquisition.reserve_provider_capacity(request, actor: actor) do
      case reservation.status do
        :reserved ->
          execute_contents(candidate, reservation, actor)

        :settled ->
          replay_contents(reservation)

        :failed ->
          {:error, :provider_failure, reservation.failure_reason, reservation.actual_cost}

        status ->
          {:error, :provider_failure, {:provider_reservation_finalized, status},
           reservation.actual_cost}
      end
    else
      {:error, reason} ->
        category =
          if ProviderBudgetPolicy.budget_exceeded?(reason),
            do: :provider_budget_exhausted,
            else: :provider_failure

        {:error, category, reason, Decimal.new(0)}
    end
  end

  defp execute_contents(candidate, reservation, actor) do
    options = [
      max_characters: 6_000,
      subpages: 2,
      subpage_target: ["about", "capabilities"],
      summary_schema: @summary_schema,
      summary_query: "Identify the operating company and summarize what it makes or does."
    ]

    case Exa.contents(candidate.url, options) do
      {:ok, %{cost: cost} = response} ->
        actual_cost = decimal(cost)

        case Acquisition.settle_provider_capacity(
               %{
                 idempotency_key: reservation.idempotency_key,
                 actual_cost: actual_cost,
                 actual_requests: 1,
                 status: :settled,
                 metadata: %{"response" => cache_response(response)}
               },
               actor: actor
             ) do
          {:ok, _settlement} -> {:ok, response, actual_cost}
          {:error, reason} -> {:error, :provider_failure, reason, actual_cost}
        end

      {:error, reason} ->
        accounting = ProviderBudgetPolicy.account_failure(reservation, reason, actor: actor)

        actual_cost =
          if ProviderBudgetPolicy.confirmed_zero_cost_failure?(reason),
            do: Decimal.new(0),
            else: reservation.estimated_cost

        case accounting do
          {:ok, _result} ->
            {:error, :provider_failure, reason, actual_cost}

          {:error, accounting_error} ->
            {:error, :provider_failure, {reason, accounting_error}, actual_cost}
        end
    end
  end

  defp replay_contents(%{metadata: %{"response" => response}, actual_cost: cost}) do
    {:ok, restore_response(response), cost}
  end

  defp replay_contents(reservation) do
    {:error, :provider_failure, :missing_replay_evidence, reservation.actual_cost}
  end

  defp assess_evidence(candidate, response, config) do
    domain = candidate.website_domain || WebIdentity.website_domain(candidate.url)

    matching =
      response.results
      |> Enum.flat_map(fn result -> [result | List.wrap(result.subpages)] end)
      |> Enum.filter(&(WebIdentity.website_domain(&1.url) == domain))

    citations =
      matching
      |> Enum.map(fn content ->
        %{
          "url" => content.url,
          "title" => content.title,
          "excerpt" => excerpt(content.text)
        }
      end)
      |> Enum.reject(&is_nil(&1["excerpt"]))

    evidence_characters = citations |> Enum.map(&String.length(&1["excerpt"])) |> Enum.sum()
    primary = List.first(matching)
    summary = summary_text(primary && primary.summary)

    evidence = %{
      "website_domain" => domain,
      "summary" => summary,
      "citations" => citations,
      "evidence_characters" => evidence_characters,
      "search_score" => decimal_string(search_score(candidate))
    }

    if primary && operating_company?(primary.summary) &&
         evidence_characters >= config.min_evidence_characters do
      {:ok, evidence, verification_score(candidate, evidence_characters, config)}
    else
      {:error, :insufficient_evidence, evidence}
    end
  end

  defp operating_company?(%{"is_operating_company" => true}), do: true
  defp operating_company?(%{is_operating_company: true}), do: true
  defp operating_company?(_summary), do: false

  defp summary_text(%{"business_description" => description}) when is_binary(description),
    do: description

  defp summary_text(%{business_description: description}) when is_binary(description),
    do: description

  defp summary_text(summary) when is_binary(summary), do: summary
  defp summary_text(_summary), do: nil

  defp excerpt(text) when is_binary(text) do
    text = String.trim(text)
    if text == "", do: nil, else: String.slice(text, 0, 1_000)
  end

  defp excerpt(_text), do: nil

  defp verification_score(candidate, evidence_characters, config) do
    search_points =
      candidate |> search_score() |> Decimal.to_float() |> Kernel.*(20) |> round() |> min(20)

    evidence_points =
      min(div(evidence_characters, max(config.min_evidence_characters, 1)) * 10, 20)

    min(60 + search_points + evidence_points, 100)
  end

  defp record(
         candidate,
         status,
         reason,
         evidence,
         reservation_key,
         actual_cost,
         actor,
         score \\ nil
       ) do
    Acquisition.record_lead_candidate_verification(
      %{
        lead_preview_candidate_id: candidate.id,
        status: status,
        reason: reason,
        website_domain: candidate.website_domain || WebIdentity.website_domain(candidate.url),
        search_score: search_score(candidate),
        verification_score: score,
        evidence: evidence,
        provider_reservation_key: reservation_key,
        actual_cost: actual_cost,
        verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      actor: actor
    )
  end

  defp acquisition_program(%{discovery_program_id: id}, actor) when is_binary(id),
    do: Acquisition.get_program_by_discovery_program(id, actor: actor)

  defp acquisition_program(_run, _actor), do: {:error, :lead_preview_run_has_no_discovery_program}

  defp search_score(candidate) do
    candidate.metadata
    |> Map.get("exa_score")
    |> decimal_or_nil()
  end

  defp contents_reservation_key(preview_run, candidate) do
    base =
      preview_run.idempotency_key ||
        preview_run.metadata["provider_budget_idempotency_key"] || preview_run.id

    identity =
      candidate.website_domain || WebIdentity.website_domain(candidate.url) || candidate.url

    digest = :crypto.hash(:sha256, identity) |> Base.encode16(case: :lower)
    "#{base}:contents:#{digest}"
  end

  defp cache_response(response) do
    %{
      "cost" => response.cost,
      "results" => Enum.map(response.results, &cache_content/1)
    }
  end

  defp cache_content(content) do
    %{
      "url" => content.url,
      "title" => content.title,
      "text" => content.text,
      "summary" => content.summary,
      "subpages" => Enum.map(List.wrap(content.subpages), &cache_content/1)
    }
  end

  defp restore_response(response) do
    %{
      cost: response["cost"],
      results: Enum.map(response["results"] || [], &restore_content/1)
    }
  end

  defp restore_content(content) do
    %{
      url: content["url"],
      title: content["title"],
      text: content["text"],
      summary: content["summary"],
      subpages: Enum.map(content["subpages"] || [], &restore_content/1)
    }
  end

  defp admission_policy(actor) do
    key = GnomeGarden.Acquisition.LeadAdmissionPolicy.default_key()

    case Acquisition.get_lead_admission_policy(key, actor: actor) do
      {:ok, policy} -> {:ok, policy}
      {:error, _not_found} -> Acquisition.ensure_lead_admission_policy(%{key: key}, actor: actor)
    end
  end

  defp initial_result do
    %{
      enrichment_attempts: 0,
      verified: 0,
      admitted: 0,
      ineligible: 0,
      unresolved: 0,
      capacity_deferred: 0,
      reused_admissions: 0,
      enrichment_cost: Decimal.new(0),
      verification_ids: [],
      admission_ids: [],
      errors: []
    }
  end

  defp add_outcome(result, outcome, verification) do
    result
    |> Map.update!(outcome, &(&1 + 1))
    |> Map.update!(:verification_ids, &[verification.id | &1])
  end

  defp add_cost(result, cost),
    do: Map.update!(result, :enrichment_cost, &Decimal.add(&1, decimal(cost)))

  defp add_error(result, error), do: Map.update!(result, :errors, &[inspect(error) | &1])

  defp finalize_result(result) do
    %{
      result
      | verification_ids: Enum.reverse(result.verification_ids),
        admission_ids: Enum.reverse(result.admission_ids),
        errors: Enum.reverse(result.errors)
    }
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(nil), do: Decimal.new(0)
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp decimal(value) when is_binary(value), do: Decimal.new(value)

  defp decimal_or_nil(nil), do: nil
  defp decimal_or_nil(value), do: decimal(value)
  defp decimal_string(nil), do: nil
  defp decimal_string(value), do: Decimal.to_string(value)
end
