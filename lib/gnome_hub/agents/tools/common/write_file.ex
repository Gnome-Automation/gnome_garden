defmodule GnomeHub.Agents.Tools.WriteFile do
  @moduledoc """
  Create or overwrite a file.

  Creates parent directories if needed.
  """

  use Jido.Action,
    name: "write_file",
    description: "Create or overwrite a file. Creates parent directories if needed.",
    schema: [
      path: [type: :string, required: true, doc: "File path to write"],
      content: [type: :string, required: true, doc: "File content"]
    ]

  @impl true
  def run(params, _context) do
    path = Map.get(params, :path) || Map.get(params, "path")
    content = Map.get(params, :content) || Map.get(params, "content")
    dir = Path.dirname(path)

    with :ok <- ensure_dir(dir),
         :ok <- File.write(path, content) do
      lines = content |> String.split("\n") |> length()
      {:ok, %{path: path, lines_written: lines}}
    else
      {:error, reason} ->
        {:error, "Cannot write #{path}: #{inspect(reason)}"}
    end
  end

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      error -> error
    end
  end
end
