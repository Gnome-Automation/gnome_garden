defmodule GnomeGarden.Company.GrowthRecommendations do
  @moduledoc """
  The only path from observed capability gaps to a growth initiative.

  `scan_and_propose/1` turns repeated structured bid gaps into
  `Operations.LearningRecommendation` records for operator review. A durable
  episode key prevents the same evidence set from being proposed again after
  approval or rejection. `approve_into_initiative/2` is the transactional
  gate: approve, create or reuse the initiative, link supporting evidence,
  and mark the recommendation applied.
  """

  alias GnomeGarden.Company
  alias GnomeGarden.Company.CapabilityGap
  alias GnomeGarden.Company.GrowthInitiative
  alias GnomeGarden.Company.GrowthInitiativeEvidence
  alias GnomeGarden.Operations
  alias GnomeGarden.Operations.LearningRecommendation
  alias GnomeGarden.Procurement

  @default_window_days 90
  @default_repeat_threshold 2

  def scan_and_propose(opts \\ []) do
    window_days = Keyword.get(opts, :window_days, @default_window_days)
    threshold = Keyword.get(opts, :repeat_threshold, @default_repeat_threshold)

    with {:ok, bids} <- Procurement.list_bids_with_capability_gaps(window_days, authorize?: false),
         {:ok, existing} <-
           Operations.list_company_growth_gap_recommendations(authorize?: false) do
      existing_keys = MapSet.new(existing, & &1.dedupe_key)

      bids
      |> grouped_gap_evidence()
      |> Enum.filter(fn {_gap, gap_bids} -> length(gap_bids) >= threshold end)
      |> Enum.reject(fn {gap, gap_bids} ->
        MapSet.member?(existing_keys, episode_key(gap, gap_bids))
      end)
      |> Enum.reduce_while({:ok, []}, fn {gap, gap_bids}, {:ok, proposals} ->
        case propose(gap, gap_bids, window_days) do
          {:ok, recommendation} -> {:cont, {:ok, [recommendation | proposals]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> then(fn
        {:ok, proposals} -> {:ok, Enum.reverse(proposals)}
        error -> error
      end)
    end
  end

  def approve_into_initiative(recommendation, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    resources = [LearningRecommendation, GrowthInitiative, GrowthInitiativeEvidence]

    case Ash.transact(resources, fn -> approve_transaction(recommendation, actor) end) do
      {:ok, {:ok, {initiative, notifications}}} ->
        Ash.Notifier.notify(notifications)
        {:ok, initiative}

      {:error, error} ->
        {:error, error}
    end
  end

  defp approve_transaction(recommendation, actor) do
    with {:ok, gap} <- recommendation_gap(recommendation),
         {:ok, approved, notes1} <-
           Operations.approve_learning_recommendation(recommendation, %{},
             actor: actor,
             return_notifications?: true
           ),
         {:ok, initiative, notes2} <- find_or_create_initiative(approved, gap, actor),
         {:ok, notes3} <- link_evidence(initiative, approved, gap, actor),
         {:ok, _applied, notes4} <-
           Operations.apply_learning_recommendation(approved, %{},
             actor: actor,
             return_notifications?: true
           ) do
      {:ok, {initiative, notes1 ++ notes2 ++ notes3 ++ notes4}}
    end
  end

  defp grouped_gap_evidence(bids) do
    bids
    |> Enum.flat_map(fn bid -> Enum.map(bid.capability_gaps, &{&1, bid}) end)
    |> Enum.group_by(fn {gap, _bid} -> gap end, fn {_gap, bid} -> bid end)
    |> Enum.map(fn {gap, gap_bids} -> {gap, Enum.uniq_by(gap_bids, & &1.id)} end)
    |> Enum.sort_by(fn {gap, _bids} -> gap end)
  end

  defp propose(gap, bids, window_days) do
    with {:ok, definition} <- CapabilityGap.definition(gap) do
      Operations.propose_learning_recommendation(
        %{
          dedupe_key: episode_key(gap, bids),
          title:
            "#{definition.initiative_title} (#{length(bids)} bids blocked in #{window_days}d)",
          target_domain: :company,
          target_resource: "growth_initiative",
          target_action: "approve_into_initiative",
          source_type: :domain,
          proposed_change: %{
            "gap_category" => Atom.to_string(gap),
            "bid_ids" => Enum.map(bids, & &1.id),
            "blocked_count" => length(bids),
            "window_days" => window_days
          },
          evidence: %{
            "bids" =>
              Enum.map(bids, fn bid ->
                %{"id" => bid.id, "title" => bid.title, "status" => Atom.to_string(bid.status)}
              end)
          },
          impact_summary:
            "#{length(bids)} bids in the last #{window_days} days were blocked by this gap.",
          risk_level: :low
        },
        authorize?: false
      )
    end
  end

  defp find_or_create_initiative(recommendation, gap, actor) do
    {:ok, definition} = CapabilityGap.definition(gap)

    with {:ok, profile} <- Company.get_primary_company_profile(authorize?: false),
         {:ok, initiatives} <- Company.list_growth_initiatives(authorize?: false) do
      reusable =
        Enum.find(initiatives, fn initiative ->
          initiative.company_profile_id == profile.id and
            initiative.category == definition.initiative_category and
            initiative.status not in [:achieved, :declined]
        end)

      case reusable do
        nil ->
          Company.create_growth_initiative(
            %{
              company_profile_id: profile.id,
              title: definition.initiative_title,
              category: definition.initiative_category,
              description: recommendation.impact_summary,
              expected_benefit: "Unblocks bids repeatedly lost to this gap"
            },
            actor: actor,
            return_notifications?: true
          )

        initiative ->
          {:ok, initiative, []}
      end
    end
  end

  defp link_evidence(initiative, recommendation, gap, actor) do
    recommendation.proposed_change
    |> Map.get("bid_ids", [])
    |> Enum.reduce_while({:ok, []}, fn bid_id, {:ok, notifications} ->
      case Company.ensure_growth_initiative_bid_gap_evidence(
             %{
               growth_initiative_id: initiative.id,
               bid_id: bid_id,
               gap_category: gap,
               confidence: :high,
               note: "Linked automatically on recommendation approval"
             },
             actor: actor,
             return_notifications?: true
           ) do
        {:ok, _evidence, new_notifications} ->
          {:cont, {:ok, notifications ++ new_notifications}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp recommendation_gap(%{
         target_domain: :company,
         target_resource: "growth_initiative",
         target_action: "approve_into_initiative",
         proposed_change: %{"gap_category" => gap}
       }) do
    case CapabilityGap.normalize(gap) do
      [normalized] -> {:ok, normalized}
      _other -> {:error, :invalid_growth_recommendation}
    end
  end

  defp recommendation_gap(_recommendation), do: {:error, :invalid_growth_recommendation}

  defp episode_key(gap, bids) do
    evidence_hash =
      bids
      |> Enum.map(& &1.id)
      |> Enum.sort()
      |> Enum.join(":")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "company_growth_gap:#{gap}:#{evidence_hash}"
  end
end
