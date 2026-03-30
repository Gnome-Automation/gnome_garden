defmodule GnomeGarden.Agents.Tools.ReadFile do
  @moduledoc """
  Read file contents.

  Returns numbered lines for easy reference when editing.
  Supports offset and limit for large files.
  """

  use Jido.Action,
    name: "read_file",
    description:
      "Read file contents. Always read a file before editing it. Returns numbered lines.",
    schema: [
      path: [type: :string, required: true, doc: "Absolute or relative file path"],
      offset: [type: :integer, default: 0, doc: "Start line (0-indexed)"],
      limit: [type: :integer, default: 2000, doc: "Max lines to read"]
    ]

  @impl true
  def run(params, _context) do
    path = Map.get(params, :path) || Map.get(params, "path")
    offset = Map.get(params, :offset) || Map.get(params, "offset", 0)
    limit = Map.get(params, :limit) || Map.get(params, "limit", 2000)

    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        total = length(lines)

        numbered =
          lines
          |> Enum.with_index(1)
          |> Enum.drop(offset)
          |> Enum.take(limit)
          |> Enum.map(fn {line, n} ->
            "#{String.pad_leading(Integer.to_string(n), 4)} | #{line}"
          end)
          |> Enum.join("\n")

        {:ok, %{path: path, content: numbered, total_lines: total}}

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{inspect(reason)}"}
    end
  end
end
