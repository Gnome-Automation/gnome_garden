defmodule GnomeGarden.Agents.Tools.ListDirectory do
  @moduledoc """
  List files and directories at a path.

  Returns file names with type indicators.
  Supports glob patterns for filtering.
  """

  use Jido.Action,
    name: "list_directory",
    description: "List files and directories at a path. Returns file names with type indicators.",
    schema: [
      path: [type: :string, default: ".", doc: "Directory path to list"],
      pattern: [type: :string, doc: "Optional glob pattern (e.g. '**/*.ex')"],
      max_results: [type: :integer, default: 200, doc: "Max entries to return"]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    # Handle both atom and string keys
    path = Map.get(params, :path) || Map.get(params, "path", ".")
    max_results = Map.get(params, :max_results) || Map.get(params, "max_results", 200)
    pattern = Map.get(params, :pattern) || Map.get(params, "pattern")

    Logger.info(
      "ListDirectory: path=#{inspect(path)}, max_results=#{inspect(max_results)}, pattern=#{inspect(pattern)}"
    )

    entries = list_entries(path, pattern)

    result =
      case entries do
        {:error, _} = err ->
          err

        list ->
          truncated = Enum.take(list, max_results)
          total = length(list)
          content = Enum.join(truncated, "\n")

          note =
            if total > max_results,
              do: "\n(#{total - max_results} more entries truncated)",
              else: ""

          {:ok, %{path: path, entries: content <> note, total: total}}
      end

    Logger.info("ListDirectory result: #{inspect(result)}")
    result
  end

  defp list_entries(path, nil) do
    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.sort()
        |> Enum.map(fn f ->
          full = Path.join(path, f)
          type = if File.dir?(full), do: "dir", else: "file"
          "#{type}  #{f}"
        end)

      {:error, reason} ->
        {:error, "Cannot list #{path}: #{inspect(reason)}"}
    end
  end

  defp list_entries(path, glob) do
    full_pattern = Path.join(path, glob)

    Path.wildcard(full_pattern)
    |> Enum.sort()
    |> Enum.map(fn f ->
      rel = Path.relative_to(f, path)
      type = if File.dir?(f), do: "dir", else: "file"
      "#{type}  #{rel}"
    end)
  end
end
