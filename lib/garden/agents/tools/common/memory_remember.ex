defmodule GnomeGarden.Agents.Tools.MemoryRemember do
  @moduledoc """
  Store a memory that persists across sessions.

  Creates a persistent memory entry with a key, content, optional type,
  and namespace for organization.
  """

  use Jido.Action,
    name: "memory_remember",
    description:
      "Store information in persistent memory for later recall. Use for facts, patterns, decisions, or preferences you want to remember.",
    schema: [
      key: [
        type: :string,
        required: true,
        doc: "A unique identifier for this memory (e.g., 'user_preference_theme')"
      ],
      content: [type: :string, required: true, doc: "The information to remember"],
      type: [
        type: :string,
        default: "fact",
        doc: "Type: fact, pattern, decision, preference, or context"
      ],
      namespace: [
        type: :string,
        default: "global",
        doc: "Namespace for organizing memories (e.g., 'project_x')"
      ]
    ]

  alias GnomeGarden.Agents.Memory

  @impl true
  def run(params, _context) do
    key = Map.get(params, :key) || Map.get(params, "key")
    content = Map.get(params, :content) || Map.get(params, "content")
    type_str = Map.get(params, :type) || Map.get(params, "type", "fact")
    namespace = Map.get(params, :namespace) || Map.get(params, "namespace", "global")

    type = normalize_type(type_str)

    case Ash.create(
           Memory,
           %{
             key: key,
             content: content,
             type: type,
             namespace: namespace
           }, action: :remember) do
      {:ok, memory} ->
        {:ok,
         %{
           stored: true,
           id: memory.id,
           key: memory.key,
           type: memory.type,
           namespace: memory.namespace,
           message: "Memory stored successfully with key '#{key}'"
         }}

      {:error, error} ->
        {:error, "Failed to store memory: #{inspect(error)}"}
    end
  end

  defp normalize_type(type) when is_atom(type), do: type
  defp normalize_type("fact"), do: :fact
  defp normalize_type("pattern"), do: :pattern
  defp normalize_type("decision"), do: :decision
  defp normalize_type("preference"), do: :preference
  defp normalize_type("context"), do: :context
  defp normalize_type(_), do: :fact
end
