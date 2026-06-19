defmodule GnomeGarden.Acquisition.LeadPromote do
  @moduledoc """
  Promotes reviewed lead-preview candidates into the acquisition pipeline.

  This is the **explicit operator step** — never automatic. The preview is
  read-only; promotion is what actually brings a candidate into the system, and
  it routes by the `LeadDedup` classification rather than blindly creating:

    * `:new` (company page) → create a discovery record (which auto-syncs a
      Finding into the review queue via `SyncDiscoveryRecordFinding`).
    * `:known_organization_new_signal` → create the discovery record linked to
      the existing organization, so the signal attaches to a known company.
    * `:known_bid_source` / `:new` signal pages (job boards, agenda PDFs) →
      `:needs_enrichment` — the page domain isn't the prospect, so the company
      must be extracted (the contents+LLM layer) before a record is meaningful.
    * suppressed contexts (`:duplicate_existing_lead`,
      `:known_procurement_source`, `:existing_bid_related`) → `:skipped`.

  A promoted record still lands in the review queue as `:new`, so the human
  checkpoint is preserved — promotion means "bring into review", not "create a
  lead".
  """

  require Logger

  alias GnomeGarden.Commercial
  alias GnomeGarden.Support.WebIdentity

  @doc """
  Promotes one preview candidate (a map carrying a `:dedupe` classification).
  Returns `{:promoted, record}`, `{:needs_enrichment, candidate}`, or
  `{:skipped, %{context:, reason:}}`. Options: `:actor`, `:discovery_program_id`.
  """
  def promote(candidate, opts \\ []) when is_map(candidate) do
    dedupe = candidate[:dedupe] || %{context: :new, suppress?: false, related: []}

    cond do
      dedupe.suppress? ->
        {:skipped, %{context: dedupe.context, reason: dedupe[:recommendation]}}

      promotable?(candidate, dedupe) ->
        create_record(candidate, dedupe, opts)

      true ->
        {:needs_enrichment, candidate}
    end
  end

  @doc "Promotes many candidates; returns `{results, summary}`."
  def promote_all(candidates, opts \\ []) do
    results = Enum.map(candidates, fn candidate -> {candidate, promote(candidate, opts)} end)

    summary =
      Enum.reduce(results, %{promoted: 0, skipped: 0, needs_enrichment: 0}, fn {_c, outcome}, acc ->
        case outcome do
          {:promoted, _} -> %{acc | promoted: acc.promoted + 1}
          {:skipped, _} -> %{acc | skipped: acc.skipped + 1}
          {:needs_enrichment, _} -> %{acc | needs_enrichment: acc.needs_enrichment + 1}
        end
      end)

    {results, summary}
  end

  # A company page, or a domain we already matched to a known org, is safe to
  # promote with the candidate's own fields. Signal pages are not (the domain is
  # a job board / portal, not the prospect) — they need extraction first.
  defp promotable?(_candidate, %{context: :known_organization_new_signal}), do: true
  defp promotable?(%{type: :company}, _dedupe), do: true
  defp promotable?(_candidate, _dedupe), do: false

  defp create_record(candidate, dedupe, opts) do
    attrs =
      %{
        name: candidate[:title] || WebIdentity.website_domain(candidate[:url]),
        website: candidate[:url],
        record_type: :prospect,
        notes: "Promoted from Exa lead preview (#{dedupe.context}). Query: #{candidate[:query]}",
        metadata: %{
          "source_url" => candidate[:url],
          "preview_context" => to_string(dedupe.context),
          "preview_type" => to_string(candidate[:type])
        }
      }
      |> maybe_put(:organization_id, organization_id(dedupe))
      |> maybe_put(:discovery_program_id, Keyword.get(opts, :discovery_program_id))

    case Commercial.create_discovery_record(attrs, actor: Keyword.get(opts, :actor), authorize?: false) do
      {:ok, record} ->
        {:promoted, record}

      {:error, reason} ->
        Logger.warning("LeadPromote: failed to create discovery record: #{inspect(reason)}")
        {:skipped, %{context: dedupe.context, reason: "create failed: #{inspect(reason)}"}}
    end
  end

  defp organization_id(%{related: related}) when is_list(related) do
    Enum.find_value(related, fn
      %{kind: :organization, id: id} when not is_nil(id) -> id
      _ -> nil
    end)
  end

  defp organization_id(_dedupe), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
