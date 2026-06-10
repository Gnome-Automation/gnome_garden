defmodule GnomeGarden.Agents.WorkflowToolset do
  @moduledoc """
  Narrow workflow-specific tool surface.

  This module is the enforcement layer between workflow definitions and future
  AshAI tool execution. It intentionally dispatches only explicitly supported
  actions that also appear in a workflow definition's allow-list.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentWorkflowDefinition
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement

  @get_procurement_source "GnomeGarden.Procurement.get_procurement_source"
  @list_active_memory_blocks_for_scope "GnomeGarden.Operations.list_active_memory_blocks_for_scope"
  @recall_memory_entries_for_scope "GnomeGarden.Operations.recall_memory_entries_for_scope"

  @type execution_result :: {:ok, term()} | {:error, term()}

  @spec available_action?(AgentWorkflowDefinition.t(), String.t()) :: boolean()
  def available_action?(%AgentWorkflowDefinition{} = definition, action) when is_binary(action) do
    action in definition.allowed_actions
  end

  @spec available_tool?(AgentWorkflowDefinition.t(), String.t()) :: boolean()
  def available_tool?(%AgentWorkflowDefinition{} = definition, tool) when is_binary(tool) do
    tool in definition.allowed_tools
  end

  @spec actions(AgentWorkflowDefinition.t()) :: [String.t()]
  def actions(%AgentWorkflowDefinition{} = definition), do: definition.allowed_actions

  @spec tools(AgentWorkflowDefinition.t()) :: [String.t()]
  def tools(%AgentWorkflowDefinition{} = definition), do: definition.allowed_tools

  @spec execute_action(AgentWorkflowDefinition.t(), String.t(), map(), keyword()) ::
          execution_result()
  def execute_action(%AgentWorkflowDefinition{} = definition, action, arguments, opts \\ [])
      when is_binary(action) and is_map(arguments) do
    if available_action?(definition, action) do
      execute_allowed_action(definition, action, arguments, opts)
    else
      {:error, {:forbidden_action, action}}
    end
  end

  defp execute_allowed_action(definition, action, arguments, opts) do
    actor = Keyword.get(opts, :actor)
    agent_run_id = Keyword.get(opts, :agent_run_id)
    audit_tool_call(agent_run_id, definition, action, arguments)

    result =
      case action do
        @get_procurement_source ->
          with {:ok, source_id} <- fetch_string(arguments, "source_id") do
            Procurement.get_procurement_source(source_id, actor: actor)
          end

        @list_active_memory_blocks_for_scope ->
          with {:ok, scope} <- fetch_atom(arguments, "scope"),
               {:ok, scope_key} <- fetch_string(arguments, "scope_key") do
            Operations.list_active_memory_blocks_for_scope(scope, scope_key, actor: actor)
          end

        @recall_memory_entries_for_scope ->
          with {:ok, scope} <- fetch_atom(arguments, "scope"),
               {:ok, scope_key} <- fetch_string(arguments, "scope_key") do
            Operations.recall_memory_entries_for_scope(scope, scope_key, actor: actor)
          end

        unsupported_action ->
          {:error, {:unsupported_action, unsupported_action}}
      end

    audit_tool_result(agent_run_id, definition, action, result)
    result
  end

  defp fetch_string(arguments, key) do
    case Map.get(arguments, key) || Map.get(arguments, String.to_atom(key)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_argument, key}}
    end
  end

  defp fetch_atom(arguments, key) do
    case Map.get(arguments, key) || Map.get(arguments, String.to_atom(key)) do
      value when is_atom(value) ->
        {:ok, value}

      value when is_binary(value) and value != "" ->
        {:ok, String.to_existing_atom(value)}

      _other ->
        {:error, {:missing_argument, key}}
    end
  rescue
    ArgumentError -> {:error, {:invalid_argument, key}}
  end

  defp audit_tool_call(nil, _definition, _action, _arguments), do: :ok

  defp audit_tool_call(agent_run_id, definition, action, arguments) do
    Agents.create_agent_message(%{
      agent_run_id: agent_run_id,
      role: :tool_call,
      content: action,
      metadata: audit_metadata(definition, action, "call", arguments)
    })

    :ok
  end

  defp audit_tool_result(nil, _definition, _action, _result), do: :ok

  defp audit_tool_result(agent_run_id, definition, action, result) do
    Agents.create_agent_message(%{
      agent_run_id: agent_run_id,
      role: :tool_result,
      content: action,
      metadata: audit_metadata(definition, action, result_status(result), %{})
    })

    :ok
  end

  defp audit_metadata(definition, action, status, arguments) do
    %{
      "workflow_definition_id" => definition.id,
      "workflow_key" => definition.key,
      "workflow_version" => definition.version,
      "action" => action,
      "status" => status,
      "arguments" => arguments
    }
  end

  defp result_status({:ok, _result}), do: "ok"
  defp result_status({:error, _error}), do: "error"
end
