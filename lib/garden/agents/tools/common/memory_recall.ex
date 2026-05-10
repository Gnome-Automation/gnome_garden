defmodule GnomeGarden.Agents.Tools.MemoryRecall do
  @moduledoc """
  Search and retrieve memories by query.

  Searches memory content and keys for matching text.
  """

  use Jido.Action,
    name: "memory_recall",
    description:
      "Search memories by a query string. Finds memories where the key or content contains the query.",
    schema: [
      query: [type: :string, required: true, doc: "Search text to find in memory keys or content"]
    ]

  alias GnomeGarden.Agents

  @impl true
  def run(params, _context) do
    query = Map.get(params, :query) || Map.get(params, "query")

    case Agents.recall_memories(query) do
      {:ok, memories} when memories == [] ->
        {:ok,
         %{
           found: false,
           count: 0,
           memories: [],
           message: "No memories found matching '#{query}'"
         }}

      {:ok, memories} ->
        formatted =
          Enum.map(memories, fn m ->
            %{
              key: m.key,
              content: m.content,
              type: m.type,
              namespace: m.namespace
            }
          end)

        {:ok,
         %{
           found: true,
           count: length(memories),
           memories: formatted,
           message: "Found #{length(memories)} memories matching '#{query}'"
         }}

      {:error, error} ->
        {:error, "Failed to recall memories: #{inspect(error)}"}
    end
  end
end
