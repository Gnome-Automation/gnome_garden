defmodule GnomeGarden.Agents.WorkflowMemoryContext do
  @moduledoc """
  Collects governed Operations memory for workflow execution.

  This module deliberately reads app-wide memory through `GnomeGarden.Operations`
  code interfaces. Agents can consume memory context, but they do not own the
  memory model.
  """

  alias GnomeGarden.Operations

  @default_max_items 8
  @content_limit 500

  @type scope :: %{scope: atom(), scope_key: String.t()}
  @type context :: %{
          scopes: [map()],
          memory_blocks: [map()],
          memory_entries: [map()],
          memory_block_count: non_neg_integer(),
          memory_entry_count: non_neg_integer(),
          errors: [map()]
        }

  @spec collect(keyword()) :: {:ok, context()}
  def collect(opts) when is_list(opts) do
    actor = Keyword.get(opts, :actor)
    max_items = Keyword.get(opts, :max_items, @default_max_items)
    scopes = workflow_scopes(opts)
    namespaces = workflow_namespaces(opts)

    {block_results, block_errors} =
      scopes
      |> Enum.map(&read_memory_blocks(&1, actor))
      |> split_results()

    {entry_scope_results, entry_scope_errors} =
      scopes
      |> Enum.map(&read_memory_entries_for_scope(&1, actor))
      |> split_results()

    {entry_namespace_results, entry_namespace_errors} =
      namespaces
      |> Enum.map(&read_memory_entries_for_namespace(&1, actor))
      |> split_results()

    blocks =
      block_results
      |> List.flatten()
      |> uniq_by_id()
      |> Enum.take(max_items)
      |> Enum.map(&serialize_block/1)

    entries =
      (entry_scope_results ++ entry_namespace_results)
      |> List.flatten()
      |> uniq_by_id()
      |> Enum.take(max_items)
      |> Enum.map(&serialize_entry/1)

    {:ok,
     %{
       scopes: Enum.map(scopes, &serialize_scope/1),
       namespaces: namespaces,
       memory_blocks: blocks,
       memory_entries: entries,
       memory_block_count: length(blocks),
       memory_entry_count: length(entries),
       errors: block_errors ++ entry_scope_errors ++ entry_namespace_errors
     }}
  end

  @spec render(context()) :: String.t()
  def render(context) when is_map(context) do
    cond do
      context.memory_block_count == 0 and context.memory_entry_count == 0 ->
        "Workflow memory context\n\nNo approved memory matched the workflow scopes."

      true ->
        [
          "Workflow memory context",
          render_scopes(context),
          render_blocks(context.memory_blocks || []),
          render_entries(context.memory_entries || [])
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n\n")
    end
  end

  defp workflow_scopes(opts) do
    [
      %{scope: :global, scope_key: "global"},
      domain_scope(Keyword.get(opts, :domain)),
      agent_scope(Keyword.get(opts, :workflow_key)),
      agent_scope(Keyword.get(opts, :memory_namespace)),
      record_scope(Keyword.get(opts, :record_type), Keyword.get(opts, :record_id))
      | Keyword.get(opts, :scopes, [])
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_scope/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.scope, &1.scope_key})
  end

  defp workflow_namespaces(opts) do
    [
      Keyword.get(opts, :memory_namespace)
      | Keyword.get(opts, :namespaces, [])
    ]
    |> List.flatten()
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp domain_scope(nil), do: nil

  defp domain_scope(domain) when is_atom(domain),
    do: %{scope: :domain, scope_key: Atom.to_string(domain)}

  defp domain_scope(domain) when is_binary(domain), do: %{scope: :domain, scope_key: domain}

  defp agent_scope(nil), do: nil

  defp agent_scope(value) when is_binary(value) and value != "",
    do: %{scope: :agent, scope_key: value}

  defp agent_scope(_value), do: nil

  defp record_scope(_record_type, nil), do: nil
  defp record_scope(nil, _record_id), do: nil

  defp record_scope(record_type, record_id) when is_binary(record_id) do
    %{scope: :record, scope_key: "#{record_type}:#{record_id}"}
  end

  defp normalize_scope(%{scope: scope, scope_key: scope_key})
       when is_atom(scope) and is_binary(scope_key) and scope_key != "" do
    %{scope: scope, scope_key: scope_key}
  end

  defp normalize_scope({scope, scope_key}) when is_atom(scope) and is_binary(scope_key) do
    normalize_scope(%{scope: scope, scope_key: scope_key})
  end

  defp normalize_scope(_scope), do: nil

  defp read_memory_blocks(scope, actor) do
    case Operations.list_active_memory_blocks_for_scope(scope.scope, scope.scope_key,
           actor: actor
         ) do
      {:ok, records} -> {:ok, records}
      {:error, error} -> {:error, read_error(:memory_blocks, scope, error)}
    end
  end

  defp read_memory_entries_for_scope(scope, actor) do
    case Operations.recall_memory_entries_for_scope(scope.scope, scope.scope_key, actor: actor) do
      {:ok, records} -> {:ok, records}
      {:error, error} -> {:error, read_error(:memory_entries, scope, error)}
    end
  end

  defp read_memory_entries_for_namespace(namespace, actor) do
    case Operations.list_memory_entries_by_namespace(namespace, actor: actor) do
      {:ok, records} -> {:ok, records}
      {:error, error} -> {:error, read_error(:memory_entries, %{namespace: namespace}, error)}
    end
  end

  defp split_results(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, records}, {records_acc, errors_acc} -> {[records | records_acc], errors_acc}
      {:error, error}, {records_acc, errors_acc} -> {records_acc, [error | errors_acc]}
    end)
  end

  defp uniq_by_id(records), do: Enum.uniq_by(records, & &1.id)

  defp serialize_scope(scope) do
    %{"scope" => Atom.to_string(scope.scope), "scope_key" => scope.scope_key}
  end

  defp serialize_block(block) do
    %{
      "id" => block.id,
      "key" => block.key,
      "label" => block.label,
      "scope" => Atom.to_string(block.scope),
      "scope_key" => block.scope_key,
      "memory_type" => Atom.to_string(block.memory_type),
      "content" => truncate(block.content)
    }
  end

  defp serialize_entry(entry) do
    %{
      "id" => entry.id,
      "title" => entry.title,
      "namespace" => entry.namespace,
      "scope" => Atom.to_string(entry.scope),
      "scope_key" => entry.scope_key,
      "memory_type" => Atom.to_string(entry.memory_type),
      "content" => truncate(entry.content)
    }
  end

  defp read_error(kind, scope, error) do
    %{
      "kind" => Atom.to_string(kind),
      "scope" => inspect(scope),
      "error" => error_message(error)
    }
  end

  defp render_scopes(context) do
    scopes =
      context.scopes
      |> Enum.map(&"#{&1["scope"]}/#{&1["scope_key"]}")
      |> Enum.join(", ")

    "Scopes: #{scopes}"
  end

  defp render_blocks([]), do: nil

  defp render_blocks(blocks) do
    body =
      blocks
      |> Enum.map(fn block ->
        "- [#{block["memory_type"]}] #{block["label"]}: #{block["content"]}"
      end)
      |> Enum.join("\n")

    "Memory blocks:\n#{body}"
  end

  defp render_entries([]), do: nil

  defp render_entries(entries) do
    body =
      entries
      |> Enum.map(fn entry ->
        title = entry["title"] || entry["namespace"]
        "- [#{entry["memory_type"]}] #{title}: #{entry["content"]}"
      end)
      |> Enum.join("\n")

    "Archival memory:\n#{body}"
  end

  defp truncate(nil), do: nil

  defp truncate(value) when is_binary(value) do
    if String.length(value) > @content_limit do
      String.slice(value, 0, @content_limit) <> "..."
    else
      value
    end
  end

  defp error_message(error) when is_binary(error), do: error

  defp error_message(%{__struct__: _} = error) do
    Exception.message(error)
  rescue
    Protocol.UndefinedError -> inspect(error)
  end

  defp error_message(error), do: inspect(error)
end
