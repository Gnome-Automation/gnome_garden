defmodule GnomeHub.Agents.Tools.MemorySearch do
  @moduledoc """
  Search memories by namespace.

  Retrieves all memories within a specific namespace.
  """

  use Jido.Action,
    name: "memory_search",
    description: "Find all memories in a specific namespace. Use to retrieve organized groups of memories.",
    schema: [
      namespace: [type: :string, required: true, doc: "The namespace to search (e.g., 'project_x', 'global')"]
    ]

  alias GnomeHub.Agents.Memory
  require Ash.Query

  @impl true
  def run(params, _context) do
    namespace = Map.get(params, :namespace) || Map.get(params, "namespace")

    ash_query =
      Memory
      |> Ash.Query.for_read(:search, %{namespace: namespace})

    case Ash.read(ash_query) do
      {:ok, memories} when memories == [] ->
        {:ok, %{
          found: false,
          count: 0,
          namespace: namespace,
          memories: [],
          message: "No memories found in namespace '#{namespace}'"
        }}

      {:ok, memories} ->
        formatted = Enum.map(memories, fn m ->
          %{
            key: m.key,
            content: m.content,
            type: m.type
          }
        end)

        {:ok, %{
          found: true,
          count: length(memories),
          namespace: namespace,
          memories: formatted,
          message: "Found #{length(memories)} memories in namespace '#{namespace}'"
        }}

      {:error, error} ->
        {:error, "Failed to search memories: #{inspect(error)}"}
    end
  end
end
