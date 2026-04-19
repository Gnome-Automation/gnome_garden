defmodule GnomeGarden.Procurement.BidReview do
  @moduledoc """
  Operator-facing orchestration for bid review actions.

  This keeps cross-domain bid review behavior out of LiveViews so the index and
  detail pages use the same transitions, signal handling, and research side
  effects.
  """

  alias GnomeGarden.CRM.PipelineEvents
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.Bid
  alias GnomeGarden.Sales

  def start_review(bid_or_id, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor) do
      Procurement.review_bid(bid, actor: actor)
    end
  end

  def open_signal(bid_or_id, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal]),
         {:ok, signal} <- ensure_signal_for_bid(bid, actor),
         {:ok, refreshed_bid} <- load_bid(bid.id, actor, [:signal]) do
      {:ok, %{bid: refreshed_bid, signal: signal}}
    end
  end

  def pass_bid(bid_or_id, reason, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal]),
         {:ok, rejected_bid} <- Procurement.reject_bid(bid, %{notes: reason}, actor: actor),
         :ok <- maybe_reject_signal(bid.signal, reason, actor),
         :ok <- log_event(:passed, bid, reason, "rejected", actor),
         {:ok, refreshed_bid} <- load_bid(rejected_bid.id, actor, [:signal]) do
      {:ok, refreshed_bid}
    end
  end

  def park_bid(bid_or_id, reason, research_note \\ nil, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal]),
         {:ok, parked_bid} <- Procurement.park_bid(bid, %{notes: reason}, actor: actor),
         :ok <- maybe_archive_signal(bid.signal, actor),
         {:ok, event} <- log_park_event(bid, reason, actor),
         :ok <- maybe_create_research_request(bid, event, reason, research_note),
         {:ok, refreshed_bid} <- load_bid(parked_bid.id, actor, [:signal]) do
      {:ok, refreshed_bid}
    end
  end

  def unpark_bid(bid_or_id, actor \\ nil) do
    with {:ok, bid} <- load_bid(bid_or_id, actor, [:signal]),
         {:ok, unparked_bid} <- Procurement.unpark_bid(bid, actor: actor),
         :ok <- maybe_reopen_signal(bid.signal, actor),
         {:ok, refreshed_bid} <- load_bid(unparked_bid.id, actor, [:signal]) do
      {:ok, refreshed_bid}
    end
  end

  defp load_bid(bid_or_id, actor, load \\ [])

  defp load_bid(%Bid{id: id}, actor, load), do: load_bid(id, actor, load)

  defp load_bid(id, actor, load) when is_binary(id) do
    Procurement.get_bid(id, actor: actor, load: load)
  end

  defp ensure_signal_for_bid(%{signal: signal} = _bid, _actor) when not is_nil(signal),
    do: {:ok, signal}

  defp ensure_signal_for_bid(%Bid{id: id}, actor) do
    Commercial.create_signal_from_bid(id, actor: actor)
  end

  defp maybe_reject_signal(nil, _reason, _actor), do: :ok

  defp maybe_reject_signal(signal, reason, actor) when signal.status in [:new, :reviewing] do
    case Commercial.reject_signal(signal, %{notes: reason}, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_reject_signal(_signal, _reason, _actor), do: :ok

  defp maybe_archive_signal(nil, _actor), do: :ok

  defp maybe_archive_signal(signal, actor)
       when signal.status in [:new, :reviewing, :accepted] do
    case Commercial.archive_signal(signal, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_archive_signal(_signal, _actor), do: :ok

  defp maybe_reopen_signal(nil, _actor), do: :ok

  defp maybe_reopen_signal(signal, actor) when signal.status in [:archived, :rejected] do
    case Commercial.reopen_signal(signal, actor: actor) do
      {:ok, _signal} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp maybe_reopen_signal(_signal, _actor), do: :ok

  defp log_event(event_type, bid, reason, to_state, actor) do
    case PipelineEvents.log(
           %{
             event_type: event_type,
             subject_type: "bid",
             subject_id: bid.id,
             summary: "#{event_summary(event_type)} #{bid.title}",
             reason: reason,
             from_state: to_string(bid.status),
             to_state: to_state,
             actor_id: actor && actor.id
           },
           actor: actor
         ) do
      {:ok, _event} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp log_park_event(bid, reason, actor) do
    PipelineEvents.log(
      %{
        event_type: :parked,
        subject_type: "bid",
        subject_id: bid.id,
        summary: "Parked — #{bid.title}",
        reason: reason,
        from_state: to_string(bid.status),
        to_state: "parked",
        actor_id: actor && actor.id
      },
      actor: actor
    )
  end

  defp maybe_create_research_request(_bid, _event, _reason, research_note)
       when research_note in [nil, ""] do
    :ok
  end

  defp maybe_create_research_request(bid, event, reason, research_note) do
    with {:ok, research} <-
           Sales.create_research_request(%{
             research_type: :qualification,
             priority: :normal,
             notes: research_note,
             researchable_type: "bid",
             researchable_id: bid.id
           }),
         {:ok, _link} <-
           Sales.create_research_link(%{
             research_request_id: research.id,
             bid_id: bid.id,
             event_id: event.id,
             context: reason
           }) do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end

  defp event_summary(:passed), do: "Passed —"
  defp event_summary(:parked), do: "Parked —"
end
