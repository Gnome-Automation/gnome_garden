defmodule GnomeGarden.Company.GrowthRecommendations do
  @moduledoc """
  The only path from observed capability gaps to a growth initiative.

  `scan_and_propose/1` turns repeated structured bid gaps into
  `Operations.LearningRecommendation` records for operator review — agents
  and sweeps never create or start initiatives directly.
  `approve_into_initiative/2` is the transactional gate: approve the
  recommendation, create or reuse the initiative, link every supporting
  evidence row, and mark the recommendation applied — all or nothing.
  """

  alias GnomeGarden.Company
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  @default_window_days 90
  @default_repeat_threshold 2

  @gap_initiatives %{
    missing_certification: {:certification, "Close certification gap"},
    bond_capacity: {:bonding, "Increase bonding capacity"},
    license_class: {:licensing, "Expand license classifications"},
    insurance_limit: {:insurance, "Raise insurance limits"},
    tech_platform: {:partner_program, "Add technology platform capability"}
  }

  def scan_and_propose(opts \\ []) do
    window_days = Keyword.get(opts, :window_days, @default_window_days)
    threshold = Keyword.get(opts, :repeat_threshold, @default_repeat_threshold)

    {:ok, bids} = Procurement.list_bids_with_capability_gaps(window_days, authorize?: false)
    {:ok, pending} = Operations.list_pending_learning_recommendations(authorize?: false)

    already_proposed =
      pending
      |> Enum.filter(&(&1.target_domain == :company))
      |> MapSet.new(& &1.proposed_change["gap_category"])

    proposals =
      bids
      |> Enum.flat_map(fn bid -> Enum.map(bid.capability_gaps, &{&1, bid}) end)
      |> Enum.group_by(fn {gap, _bid} -> gap end, fn {_gap, bid} -> bid end)
      |> Enum.filter(fn {gap, gap_bids} ->
        length(gap_bids) >= threshold and
          not MapSet.member?(already_proposed, Atom.to_string(gap))
      end)
      |> Enum.map(fn {gap, gap_bids} -> propose(gap, gap_bids, window_days) end)

    {:ok, proposals}
  end

  defp propose(gap, bids, window_days) do
    {_category, title} = Map.fetch!(@gap_initiatives, gap)

    {:ok, recommendation} =
      Operations.propose_learning_recommendation(
        %{
          title: "#{title} (#{length(bids)} bids blocked in #{window_days}d)",
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

    recommendation
  end

  def approve_into_initiative(recommendation, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    result =
      GnomeGarden.Repo.transaction(fn ->
        with {:ok, approved, notes1} <-
               Operations.approve_learning_recommendation(recommendation, %{},
                 actor: actor,
                 return_notifications?: true
               ),
             {:ok, initiative, notes2} <- find_or_create_initiative(approved, actor),
             {:ok, notes3} <- link_evidence(initiative, approved, actor),
             {:ok, _applied, notes4} <-
               Operations.apply_learning_recommendation(approved, %{},
                 actor: actor,
                 return_notifications?: true
               ) do
          {initiative, notes1 ++ notes2 ++ notes3 ++ notes4}
        else
          {:error, error} -> GnomeGarden.Repo.rollback(error)
        end
      end)

    with {:ok, {initiative, notifications}} <- result do
      Ash.Notifier.notify(notifications)
      {:ok, initiative}
    end
  end

  defp find_or_create_initiative(recommendation, actor) do
    gap = String.to_existing_atom(recommendation.proposed_change["gap_category"])
    {category, title} = Map.fetch!(@gap_initiatives, gap)

    {:ok, initiatives} = Company.list_growth_initiatives(authorize?: false)

    reusable =
      Enum.find(initiatives, fn initiative ->
        initiative.category == category and initiative.status not in [:achieved, :declined]
      end)

    case reusable do
      nil ->
        with {:ok, profile} <- Company.get_primary_company_profile(authorize?: false) do
          Company.create_growth_initiative(
            %{
              company_profile_id: profile.id,
              title: title,
              category: category,
              description: recommendation.impact_summary,
              expected_benefit: "Unblocks bids repeatedly lost to this gap"
            },
            actor: actor,
            return_notifications?: true
          )
        end

      initiative ->
        {:ok, initiative, []}
    end
  end

  defp link_evidence(initiative, recommendation, actor) do
    gap = String.to_existing_atom(recommendation.proposed_change["gap_category"])

    recommendation.proposed_change
    |> Map.get("bid_ids", [])
    |> Enum.reduce_while({:ok, []}, fn bid_id, {:ok, notifications} ->
      case Company.create_growth_initiative_evidence(
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
        {:ok, _evidence, new_notifications} -> {:cont, {:ok, notifications ++ new_notifications}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
