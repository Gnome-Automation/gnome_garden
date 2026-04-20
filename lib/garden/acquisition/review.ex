defmodule GnomeGarden.Acquisition.Review do
  @moduledoc false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.Finding
  alias GnomeGarden.Commercial.DiscoveryReview
  alias GnomeGarden.Procurement.BidReview

  def start_review(finding_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         {:ok, _result} <- start_review_on_origin(finding, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor) do
      {:ok, refreshed_finding}
    end
  end

  def promote_to_signal(finding_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         {:ok, result} <- promote_origin(finding, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor) do
      {:ok, %{finding: refreshed_finding, result: result}}
    end
  end

  def accept(finding_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         {:ok, _result} <- maybe_start_review_on_origin(finding, actor),
         {:ok, _accepted_finding} <- Acquisition.accept_finding(finding, actor: actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor) do
      {:ok, refreshed_finding}
    end
  end

  def reject(finding_or_id, feedback \\ %{}, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         {:ok, _result} <- reject_origin(finding, feedback, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <- ensure_finding_status(refreshed_finding, :rejected, actor) do
      {:ok, final_finding}
    end
  end

  def suppress(finding_or_id, feedback \\ %{}, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         feedback <- suppress_feedback(finding, feedback),
         {:ok, _result} <- reject_origin(finding, feedback, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <- ensure_finding_status(refreshed_finding, :suppressed, actor) do
      {:ok, final_finding}
    end
  end

  def park(finding_or_id, feedback \\ %{}, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         {:ok, _result} <- park_origin(finding, feedback, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <- ensure_finding_status(refreshed_finding, :parked, actor) do
      {:ok, final_finding}
    end
  end

  def reopen(finding_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, finding} <- load_finding(finding_or_id, actor),
         {:ok, _result} <- reopen_origin(finding, actor),
         {:ok, refreshed_finding} <- reload_finding(finding, actor),
         {:ok, final_finding} <- ensure_finding_status(refreshed_finding, :new, actor) do
      {:ok, final_finding}
    end
  end

  defp load_finding(%Finding{id: id}, actor), do: load_finding(id, actor)

  defp load_finding(id, actor) when is_binary(id) do
    Acquisition.get_finding(
      id,
      actor: actor,
      load: [:source_bid, :source_discovery_record, :signal, :organization, :status_variant]
    )
  end

  defp start_review_on_origin(%{source_bid_id: bid_id}, actor) when is_binary(bid_id),
    do: BidReview.start_review(bid_id, actor)

  defp start_review_on_origin(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id),
       do: DiscoveryReview.start_review(discovery_record_id, actor)

  defp start_review_on_origin(finding, actor),
    do: Acquisition.review_finding(finding, actor: actor)

  defp maybe_start_review_on_origin(%{status: status}, _actor)
       when status in [:reviewing, :accepted, :promoted],
       do: {:ok, :already_reviewed}

  defp maybe_start_review_on_origin(finding, actor), do: start_review_on_origin(finding, actor)

  defp promote_origin(%{source_bid_id: bid_id}, actor) when is_binary(bid_id) do
    with {:ok, result} <- BidReview.open_signal(bid_id, actor),
         {:ok, _finding} <- Acquisition.sync_bid_finding(bid_id, actor: actor) do
      {:ok, result}
    end
  end

  defp promote_origin(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id) do
    with {:ok, result} <- DiscoveryReview.promote(discovery_record_id, actor),
         {:ok, _finding} <-
           Acquisition.sync_discovery_record_finding(discovery_record_id, actor: actor) do
      {:ok, result}
    end
  end

  defp promote_origin(%Finding{} = finding, actor),
    do: Acquisition.promote_finding(finding, actor: actor)

  defp reject_origin(%{source_bid_id: bid_id}, actor_feedback, actor) when is_binary(bid_id),
    do:
      BidReview.pass_bid(
        bid_id,
        normalize_feedback(actor_feedback, "Rejected from acquisition queue"),
        actor
      )

  defp reject_origin(%{source_discovery_record_id: discovery_record_id}, actor_feedback, actor)
       when is_binary(discovery_record_id),
       do:
         DiscoveryReview.reject(
           discovery_record_id,
           normalize_feedback(actor_feedback, "Rejected from acquisition queue"),
           actor
         )

  defp reject_origin(%Finding{} = finding, _feedback, actor),
    do: Acquisition.reject_finding(finding, actor: actor)

  defp park_origin(%{source_bid_id: bid_id}, feedback, actor) when is_binary(bid_id) do
    params = normalize_feedback(feedback, "Parked from acquisition queue")

    BidReview.park_bid(
      bid_id,
      params["reason"] || params[:reason],
      params["research"] || params[:research],
      actor
    )
  end

  defp park_origin(%{source_discovery_record_id: discovery_record_id}, feedback, actor)
       when is_binary(discovery_record_id) do
    params =
      feedback
      |> normalize_feedback("Keep watching, not ready")
      |> Map.put_new("reason_code", "not_ready_yet")

    DiscoveryReview.reject(discovery_record_id, params, actor)
  end

  defp park_origin(%Finding{} = finding, _feedback, actor),
    do: Acquisition.park_finding(finding, actor: actor)

  defp reopen_origin(%{source_bid_id: bid_id, status: :parked}, actor) when is_binary(bid_id),
    do: BidReview.unpark_bid(bid_id, actor)

  defp reopen_origin(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id),
       do: DiscoveryReview.reopen(discovery_record_id, actor)

  defp reopen_origin(%Finding{} = finding, actor),
    do: Acquisition.reopen_finding(finding, actor: actor)

  defp reload_finding(%{source_bid_id: bid_id}, actor) when is_binary(bid_id),
    do: sync_and_load_bid_finding(bid_id, actor)

  defp reload_finding(%{source_discovery_record_id: discovery_record_id}, actor)
       when is_binary(discovery_record_id),
       do: sync_and_load_discovery_record_finding(discovery_record_id, actor)

  defp reload_finding(%Finding{id: id}, actor), do: Acquisition.get_finding(id, actor: actor)

  defp sync_and_load_bid_finding(bid_id, actor) do
    with {:ok, finding} <- Acquisition.sync_bid_finding(bid_id, actor: actor) do
      Acquisition.get_finding(finding.id, actor: actor)
    end
  end

  defp sync_and_load_discovery_record_finding(discovery_record_id, actor) do
    with {:ok, finding} <-
           Acquisition.sync_discovery_record_finding(discovery_record_id, actor: actor) do
      Acquisition.get_finding(finding.id, actor: actor)
    end
  end

  defp suppress_feedback(%{finding_family: :procurement}, feedback) do
    feedback
    |> normalize_feedback("Suppressed as noisy procurement intake")
    |> Map.put_new("reason_code", "source_noise_or_misclassified")
    |> Map.put_new("feedback_scope", "source")
  end

  defp suppress_feedback(%{finding_family: :discovery}, feedback) do
    feedback
    |> normalize_feedback("Suppressed as noisy discovery intake")
    |> Map.put_new("reason_code", "source_noise_or_misclassified")
    |> Map.put_new("feedback_scope", "source")
  end

  defp suppress_feedback(_finding, feedback),
    do: normalize_feedback(feedback, "Suppressed from acquisition queue")

  defp normalize_feedback(%{} = feedback, default_reason) do
    feedback
    |> stringify_keys()
    |> Map.put_new("reason", default_reason)
  end

  defp normalize_feedback(nil, default_reason), do: %{"reason" => default_reason}

  defp normalize_feedback(reason, _default_reason) when is_binary(reason),
    do: %{"reason" => reason}

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp ensure_finding_status(%Finding{status: desired} = finding, desired, _actor),
    do: {:ok, finding}

  defp ensure_finding_status(%Finding{} = finding, :rejected, actor),
    do: Acquisition.reject_finding(finding, actor: actor)

  defp ensure_finding_status(%Finding{} = finding, :suppressed, actor),
    do: Acquisition.suppress_finding(finding, actor: actor)

  defp ensure_finding_status(%Finding{} = finding, :parked, actor),
    do: Acquisition.park_finding(finding, actor: actor)

  defp ensure_finding_status(%Finding{} = finding, :new, actor),
    do: Acquisition.reopen_finding(finding, actor: actor)
end
