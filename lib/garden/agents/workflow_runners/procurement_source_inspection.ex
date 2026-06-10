defmodule GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspection do
  @moduledoc """
  Versioned workflow runner for procurement source inspection.

  This runner executes a published `AgentWorkflowDefinition` through the
  existing bounded procurement `SourcePipeline` Lua surface and records the
  attempt as an `AgentRun`.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentWorkflowDefinition
  alias GnomeGarden.Agents.WorkflowMemoryContext
  alias GnomeGarden.Operations
  alias GnomeGarden.Procurement.SourcePipeline

  @workflow_key "procurement_source_inspection"
  @lua_source """
  local inspection = source.inspect(source_context.id)

  if not inspection.ok then
    return inspection
  end

  if inspection.requires_login then
    inspection.mode = "credentials_needed"
  elseif inspection.diagnosis == "page_unavailable" then
    inspection.mode = "page_unavailable"
  else
    inspection.mode = "inspected"
  end

  return inspection
  """

  @spec workflow_key() :: String.t()
  def workflow_key, do: @workflow_key

  @spec default_definition_attrs() :: map()
  def default_definition_attrs do
    %{
      key: @workflow_key,
      name: "Procurement source inspection",
      description: "Inspect one procurement source through the bounded AshLua source surface.",
      version: 1,
      lua_source: @lua_source,
      input_schema: %{
        "type" => "object",
        "required" => ["source_id"],
        "properties" => %{"source_id" => %{"type" => "string", "format" => "uuid"}}
      },
      output_schema: %{
        "type" => "object",
        "properties" => %{
          "ok" => %{"type" => "boolean"},
          "mode" => %{"type" => "string"},
          "source_id" => %{"type" => "string"}
        }
      },
      allowed_domains: ["GnomeGarden.Procurement", "GnomeGarden.Operations"],
      allowed_actions: [
        "GnomeGarden.Procurement.get_procurement_source",
        "GnomeGarden.Procurement.update_procurement_source",
        "GnomeGarden.Operations.list_active_memory_blocks_for_scope",
        "GnomeGarden.Operations.recall_memory_entries_for_scope"
      ],
      allowed_tools: ["source.inspect"],
      risk_level: :medium,
      metadata: %{"runner" => inspect(__MODULE__)}
    }
  end

  @spec ensure_definition(keyword()) :: {:ok, AgentWorkflowDefinition.t()} | {:error, term()}
  def ensure_definition(opts \\ []) do
    actor = Keyword.get(opts, :actor)

    case Agents.get_published_agent_workflow_definition(@workflow_key, actor: actor) do
      {:ok, %AgentWorkflowDefinition{} = definition} ->
        {:ok, definition}

      {:error, _error} ->
        with {:ok, draft} <-
               Agents.create_agent_workflow_definition(default_definition_attrs(), actor: actor),
             {:ok, validated} <- Agents.validate_agent_workflow_definition(draft, actor: actor),
             {:ok, published} <- Agents.publish_agent_workflow_definition(validated, actor: actor) do
          {:ok, published}
        end
    end
  end

  @spec execute(Ecto.UUID.t() | struct(), keyword()) ::
          {:ok, map()} | {:error, GnomeGarden.Agents.AgentRun.t(), term()} | {:error, term()}
  def execute(source_or_id, opts) do
    actor = Keyword.get(opts, :actor)

    with {:ok, deployment} <- fetch_deployment(opts, actor),
         {:ok, workflow_definition} <- fetch_workflow_definition(opts),
         {:ok, run} <- create_run(deployment, source_or_id, workflow_definition, actor),
         {:ok, memory_context} <-
           collect_memory_context(deployment, workflow_definition, source_or_id, actor),
         {:ok, started_run} <- start_run_with_memory(run, memory_context, actor),
         :ok <- persist_memory_context_message(started_run, workflow_definition, memory_context),
         result <-
           SourcePipeline.inspect_source_with_workflow(source_or_id, workflow_definition, opts) do
      complete_from_result(result, started_run, workflow_definition, source_or_id, actor)
    end
  end

  defp fetch_deployment(opts, actor) do
    case Keyword.fetch(opts, :deployment_id) do
      {:ok, deployment_id} ->
        Agents.get_agent_deployment(deployment_id, actor: actor)

      :error ->
        {:error, "Versioned source inspection requires a deployment_id for AgentRun audit."}
    end
  end

  defp fetch_workflow_definition(opts) do
    case Keyword.fetch(opts, :workflow_definition) do
      {:ok, %AgentWorkflowDefinition{} = definition} -> {:ok, definition}
      :error -> ensure_definition(opts)
    end
  end

  defp create_run(deployment, source_or_id, workflow_definition, actor) do
    source_id = source_id(source_or_id)

    Agents.create_agent_run(
      %{
        agent_id: deployment.agent_id,
        deployment_id: deployment.id,
        task:
          "Inspect procurement source with #{workflow_definition.key} v#{workflow_definition.version}",
        run_kind: :manual,
        requested_by_user_id: actor && actor.id,
        requested_by_team_member_id: Operations.current_team_member_id(actor),
        metadata: %{
          "workflow_definition_id" => workflow_definition.id,
          "workflow_key" => workflow_definition.key,
          "workflow_version" => workflow_definition.version,
          "procurement_source_id" => source_id
        }
      },
      actor: actor
    )
  end

  defp collect_memory_context(deployment, workflow_definition, source_or_id, actor) do
    WorkflowMemoryContext.collect(
      actor: actor,
      workflow_key: workflow_definition.key,
      domain: :procurement,
      memory_namespace: deployment.memory_namespace,
      record_type: "procurement_source",
      record_id: source_id(source_or_id)
    )
  end

  defp start_run_with_memory(run, memory_context, actor) do
    metadata =
      run.metadata
      |> Kernel.||(%{})
      |> Map.put("memory_context", memory_context_summary(memory_context))

    Agents.start_agent_run(run, %{metadata: metadata}, actor: actor)
  end

  defp persist_memory_context_message(run, workflow_definition, memory_context) do
    case Agents.create_agent_message(%{
           agent_run_id: run.id,
           role: :system,
           content: WorkflowMemoryContext.render(memory_context),
           metadata: %{
             "message_type" => "workflow_memory_context",
             "workflow_definition_id" => workflow_definition.id,
             "workflow_key" => workflow_definition.key,
             "workflow_version" => workflow_definition.version,
             "memory_context" => memory_context
           }
         }) do
      {:ok, _message} -> :ok
      {:error, _error} -> :ok
    end
  end

  defp complete_from_result({:ok, result}, run, workflow_definition, source_or_id, actor) do
    summary = result_summary(result, run, workflow_definition, source_or_id)

    case Agents.complete_agent_run(
           run,
           %{
             result: "Procurement source inspection completed.",
             result_summary: summary,
             tool_count: 1
           },
           actor: actor
         ) do
      {:ok, completed_run} ->
        {:ok, %{run: completed_run, workflow_definition: workflow_definition, result: result}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp complete_from_result({:error, reason}, run, workflow_definition, source_or_id, actor) do
    details = failure_details(reason, workflow_definition, source_or_id)

    case Agents.fail_agent_run(
           run,
           %{error: error_message(reason), failure_details: details},
           actor: actor
         ) do
      {:ok, failed_run} -> {:error, failed_run, reason}
      {:error, error} -> {:error, error}
    end
  end

  defp result_summary(result, run, workflow_definition, source_or_id) do
    pipeline = Map.get(result, :pipeline, %{})

    %{
      "workflow_definition_id" => workflow_definition.id,
      "workflow_key" => workflow_definition.key,
      "workflow_version" => workflow_definition.version,
      "procurement_source_id" => source_id(source_or_id),
      "mode" => Map.get(pipeline, "mode"),
      "diagnosis" => Map.get(pipeline, "diagnosis"),
      "requires_login" => Map.get(pipeline, "requires_login", false),
      "memory_context" => Map.get(run.metadata || %{}, "memory_context")
    }
  end

  defp memory_context_summary(memory_context) do
    %{
      "scopes" => memory_context.scopes,
      "namespaces" => memory_context.namespaces,
      "memory_block_count" => memory_context.memory_block_count,
      "memory_entry_count" => memory_context.memory_entry_count,
      "memory_block_ids" => Enum.map(memory_context.memory_blocks, & &1["id"]),
      "memory_entry_ids" => Enum.map(memory_context.memory_entries, & &1["id"]),
      "errors" => memory_context.errors
    }
  end

  defp failure_details(reason, workflow_definition, source_or_id) do
    %{
      "workflow_definition_id" => workflow_definition.id,
      "workflow_key" => workflow_definition.key,
      "workflow_version" => workflow_definition.version,
      "procurement_source_id" => source_id(source_or_id),
      "reason" => error_message(reason)
    }
  end

  defp source_id(%{id: id}), do: id
  defp source_id(id), do: id

  defp error_message(error) when is_binary(error), do: error

  defp error_message(%{__struct__: _} = error) do
    Exception.message(error)
  rescue
    Protocol.UndefinedError -> inspect(error)
  end

  defp error_message(error), do: inspect(error)
end
