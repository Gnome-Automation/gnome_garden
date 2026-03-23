defmodule GnomeHub.Agents.Tools.SearchCode do
  @moduledoc """
  Search for a pattern in files using grep.

  Returns matching lines with file paths and line numbers.
  """

  use Jido.Action,
    name: "search_code",
    description: "Search for a pattern in files using grep. Returns matching lines with file paths and line numbers.",
    schema: [
      pattern: [type: :string, required: true, doc: "Search pattern (regex supported)"],
      path: [type: :string, default: ".", doc: "Directory to search in"],
      glob: [type: :string, doc: "File pattern filter (e.g. '*.ex', '*.ts')"],
      max_results: [type: :integer, default: 50, doc: "Max results to return"]
    ]

  @impl true
  def run(params, _context) do
    pattern = Map.get(params, :pattern) || Map.get(params, "pattern")
    path = Map.get(params, :path) || Map.get(params, "path", ".")
    max_results = Map.get(params, :max_results) || Map.get(params, "max_results", 50)

    args = ["-rn", "--color=never"]

    glob = Map.get(params, :glob) || Map.get(params, "glob")
    args =
      case glob do
        nil -> args
        g -> args ++ ["--include=#{g}"]
      end

    args = args ++ [pattern, path]

    case System.cmd("grep", args, stderr_to_stdout: true) do
      {output, 0} ->
        lines = String.split(output, "\n", trim: true)
        truncated = Enum.take(lines, max_results)
        total = length(lines)
        content = Enum.join(truncated, "\n")
        note = if total > max_results, do: "\n(#{total - max_results} more matches truncated)", else: ""
        {:ok, %{matches: content <> note, total_matches: total}}

      {_, 1} ->
        {:ok, %{matches: "", total_matches: 0}}

      {output, _code} ->
        {:error, "grep failed: #{String.slice(output, 0, 500)}"}
    end
  end
end
