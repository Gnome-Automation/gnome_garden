defmodule Mix.Tasks.Exa.Preview do
  @shortdoc "Dry-run lead preview: signal queries -> Exa -> classified, ranked candidates"

  @moduledoc """
  Preview lead candidates for a set of discovery inputs. Generates signal-shaped
  queries, searches Exa within caps + a spend ceiling, classifies every
  candidate against the existing bids/sources/findings/orgs, and prints a ranked
  preview. Creates nothing.

      mix exa.preview --industry "food processing" --region "orange county"
      mix exa.preview --industry "manufacturing" --region "southern california" \\
        --max-queries 6 --max-results 5 --ceiling 0.10

  Pass `--industry` / `--region` / `--term` multiple times. Requires EXA_API_KEY.
  """

  use Mix.Task

  alias GnomeGarden.Acquisition.LeadPreview

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          industry: :keep,
          region: :keep,
          term: :keep,
          max_queries: :integer,
          max_results: :integer,
          ceiling: :float
        ]
      )

    run_opts =
      [
        industries: Keyword.get_values(opts, :industry),
        regions: Keyword.get_values(opts, :region),
        search_terms: Keyword.get_values(opts, :term)
      ]
      |> put_if(:max_queries, opts[:max_queries])
      |> put_if(:max_results_per_query, opts[:max_results])
      |> put_if(:spend_ceiling, opts[:ceiling])

    {:ok, preview} = LeadPreview.run(run_opts)
    print(preview)
  end

  defp print(preview) do
    Mix.shell().info("""

    Queries: #{preview.queries_run}    Candidates: #{preview.candidate_count}    \
    Kept: #{preview.kept_count}    Suppressed: #{preview.suppressed_count}    \
    Cost: $#{preview.total_cost}
    """)

    preview.candidates
    |> Enum.with_index(1)
    |> Enum.each(fn {candidate, index} ->
      flag = if candidate.dedupe.suppress?, do: "·", else: "✓"

      Mix.shell().info(
        "#{flag} #{String.pad_leading(to_string(index), 2)}. [#{candidate.type}/#{candidate.dedupe.context}] #{candidate.title || "(no title)"}"
      )

      Mix.shell().info("       #{candidate.url}")
      Mix.shell().info("       → #{candidate.dedupe.recommendation}")
    end)

    Mix.shell().info("")
  end

  defp put_if(opts, _key, nil), do: opts
  defp put_if(opts, key, value), do: Keyword.put(opts, key, value)
end
