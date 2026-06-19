defmodule GnomeGarden.Search.Corpus do
  @moduledoc """
  Lightweight keyword search across the lead/bid corpus we already have:
  organizations, discovery records, findings, bids, procurement sources, and
  acquisition sources.

  This is the free, explainable "search what we've collected" surface — the
  first stop before paying Exa for net-new candidates. It is case-insensitive
  substring matching (Postgres `ILIKE`) over each resource's key text fields;
  semantic / vector search is a later phase.

  Returns a map keyed by corpus type, each a capped list, plus the total count:

      %{
        query: "scada",
        total: 7,
        results: %{
          organizations: [...], discovery_records: [...], findings: [...],
          bids: [...], procurement_sources: [...], sources: [...]
        }
      }
  """

  alias GnomeGarden.{Acquisition, Commercial, Operations, Procurement}

  @doc """
  Searches the corpus for `query`. Options: `:actor`, and `:types` to restrict
  which corpus types are searched (defaults to all).
  """
  def search(query, opts \\ []) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      empty_result(query)
    else
      actor = Keyword.get(opts, :actor)
      types = Keyword.get(opts, :types, all_types())

      results =
        types
        |> Map.new(fn type -> {type, run(type, query, actor)} end)

      %{query: query, total: results |> Map.values() |> Enum.map(&length/1) |> Enum.sum(), results: results}
    end
  end

  defp all_types,
    do: [:organizations, :discovery_records, :findings, :bids, :procurement_sources, :sources]

  defp run(:organizations, query, actor), do: list(Operations.search_organizations(query, actor: actor, authorize?: false))
  defp run(:discovery_records, query, actor), do: list(Commercial.search_discovery_records(query, actor: actor, authorize?: false))
  defp run(:findings, query, actor), do: list(Acquisition.search_findings(query, actor: actor, authorize?: false))
  defp run(:bids, query, actor), do: list(Procurement.search_bids(query, actor: actor, authorize?: false))
  defp run(:procurement_sources, query, actor), do: list(Procurement.search_procurement_sources(query, actor: actor, authorize?: false))
  defp run(:sources, query, actor), do: list(Acquisition.search_sources(query, actor: actor, authorize?: false))
  defp run(_unknown, _query, _actor), do: []

  defp list({:ok, records}) when is_list(records), do: records
  defp list(_), do: []

  defp empty_result(query),
    do: %{query: query, total: 0, results: Map.new(all_types(), &{&1, []})}
end
