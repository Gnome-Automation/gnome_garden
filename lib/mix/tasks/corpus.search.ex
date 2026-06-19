defmodule Mix.Tasks.Corpus.Search do
  @shortdoc "Keyword-search the existing bids/sources/findings/orgs corpus"

  @moduledoc """
  Search what we've already collected — organizations, discovery records,
  findings, bids, and sources — by keyword. Free (local Postgres), the first
  stop before paying Exa for net-new candidates.

      mix corpus.search "scada water district"
      mix corpus.search "controls engineer"
  """

  use Mix.Task

  alias GnomeGarden.Search.Corpus

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    query = argv |> Enum.join(" ") |> String.trim()

    if query == "" do
      Mix.shell().error(~s(Usage: mix corpus.search "your terms"))
      exit({:shutdown, 1})
    end

    result = Corpus.search(query)
    Mix.shell().info("\nQuery: #{result.query}    Matches: #{result.total}\n")

    Enum.each(result.results, fn
      {_type, []} ->
        :ok

      {type, records} ->
        Mix.shell().info("#{type} (#{length(records)}):")
        Enum.each(records, fn record -> Mix.shell().info("  - #{label(type, record)}") end)
        Mix.shell().info("")
    end)
  end

  defp label(:organizations, r), do: "#{r.name} · #{r.website || "(no site)"}"
  defp label(:bids, r), do: "#{r.title} · #{r.agency || "?"}"
  defp label(:findings, r), do: r.title
  defp label(:discovery_records, r), do: "#{r.name} · #{r.location || ""}"
  defp label(:procurement_sources, r), do: "#{r.name} · #{r.url}"
  defp label(:sources, r), do: "#{r.name} · #{r.url}"
  defp label(_type, r), do: r.id
end
