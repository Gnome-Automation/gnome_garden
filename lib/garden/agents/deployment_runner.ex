defmodule GnomeGarden.Agents.DeploymentRunner do
  @moduledoc """
  Deployment-centric orchestration for runtime agent executions.

  The durable source of truth is `AgentRun`. `AgentTracker` is updated as a
  live cache for active runtime state on the current node.
  """

  require Logger

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentTracker
  alias GnomeGarden.Agents.Templates

  @default_timeout_ms 180_000

  @spec launch_manual_run(Ecto.UUID.t(), keyword()) ::
          {:ok, GnomeGarden.Agents.AgentRun.t()} | {:error, term()}
  def launch_manual_run(deployment_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    task_override = Keyword.get(opts, :task)
    metadata = Keyword.get(opts, :metadata, %{})

    with {:ok, deployment} <- fetch_deployment(deployment_id, actor),
         :ok <- ensure_enabled(deployment),
         {:ok, template} <- Templates.get(deployment.agent.template),
         {:ok, run} <- create_run(deployment, actor, task_override, :manual, metadata: metadata) do
      start_runtime(run, deployment, template, actor)
    end
  end

  @spec launch_scheduled_run(Ecto.UUID.t(), keyword()) ::
          {:launched, GnomeGarden.Agents.AgentRun.t()}
          | {:skipped, term()}
          | {:error, term()}
  def launch_scheduled_run(deployment_id, opts \\ []) do
    with {:ok, schedule_slot} <- fetch_schedule_slot(opts),
         {:ok, deployment} <- fetch_deployment(deployment_id, nil),
         :ok <- ensure_enabled(deployment),
         :ok <- ensure_no_active_run(deployment),
         :ok <- ensure_schedule_slot_available(deployment.id, schedule_slot),
         {:ok, template} <- Templates.get(deployment.agent.template),
         {:ok, run} <- create_run(deployment, nil, nil, :scheduled, schedule_slot: schedule_slot),
         {:ok, started_run} <- start_runtime(run, deployment, template, nil) do
      {:launched, started_run}
    else
      {:skip, reason} -> {:skipped, reason}
      {:error, error} -> {:error, error}
    end
  end

  @spec cancel_run(Ecto.UUID.t(), keyword()) ::
          {:ok, GnomeGarden.Agents.AgentRun.t()} | {:error, term()}
  def cancel_run(run_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, run} <- fetch_run(run_id),
         :ok <- ensure_active(run) do
      runtime_instance_id = run.runtime_instance_id || run.id

      AgentTracker.mark_complete(runtime_instance_id, :cancelled, "Cancelled by operator")
      _ = stop_runtime(runtime_instance_id)

      case Agents.cancel_agent_run(run, actor: actor) do
        {:ok, cancelled_run} ->
          persist_message(%{
            agent_run_id: cancelled_run.id,
            role: :system,
            content: "Run cancelled by operator.",
            metadata: %{runtime_instance_id: runtime_instance_id}
          })

          {:ok, cancelled_run}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp fetch_deployment(deployment_id, actor) do
    Agents.get_agent_deployment(
      deployment_id,
      actor: actor,
      load: [:agent, :run_count, :active_run_count, :last_run_state, :last_run_at]
    )
  end

  defp fetch_run(run_id) do
    Agents.get_agent_run(run_id, load: [:agent, :deployment])
  end

  defp ensure_enabled(%{enabled: true}), do: :ok

  defp ensure_enabled(_deployment),
    do: {:error, "Deployment is paused. Resume it before running."}

  defp ensure_active(%{state: state}) when state in [:pending, :running], do: :ok
  defp ensure_active(_run), do: {:error, "Run is no longer active."}

  defp ensure_no_active_run(%{active_run_count: count}) when is_integer(count) and count > 0 do
    {:skip, :active_run_exists}
  end

  defp ensure_no_active_run(_deployment), do: :ok

  defp ensure_schedule_slot_available(deployment_id, schedule_slot) do
    case Agents.list_scheduled_agent_runs_for_slot(deployment_id, schedule_slot) do
      {:ok, []} -> :ok
      {:ok, [_run | _]} -> {:skip, :already_launched}
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_schedule_slot(opts) do
    case Keyword.get(opts, :schedule_slot) do
      schedule_slot when is_binary(schedule_slot) and byte_size(schedule_slot) > 0 ->
        {:ok, schedule_slot}

      _ ->
        {:error, "Scheduled runs require a schedule slot."}
    end
  end

  defp create_run(deployment, actor, task_override, run_kind, opts) do
    schedule_slot = Keyword.get(opts, :schedule_slot)
    extra_metadata = Keyword.get(opts, :metadata, %{})
    requested_by_team_member_id = GnomeGarden.Operations.current_team_member_id(actor)

    metadata =
      %{
        deployment_name: deployment.name,
        deployment_visibility: deployment.visibility,
        schedule: deployment.schedule,
        schedule_slot: schedule_slot,
        template: deployment.agent.template,
        config: deployment.config,
        source_scope: deployment.source_scope,
        memory_namespace: deployment.memory_namespace
      }
      |> Map.merge(Map.new(extra_metadata))

    Agents.create_agent_run(
      %{
        agent_id: deployment.agent_id,
        deployment_id: deployment.id,
        task: task_override || default_task_for(deployment),
        run_kind: run_kind,
        schedule_slot: schedule_slot,
        requested_by_user_id: actor && actor.id,
        requested_by_team_member_id: requested_by_team_member_id,
        metadata: metadata
      },
      actor: actor
    )
  end

  defp start_runtime(run, deployment, template, actor) do
    runtime_instance_id = run.id

    if function_exported?(template.module, :execute_run, 1) do
      start_direct_runtime(run, deployment, template, actor, runtime_instance_id)
    else
      start_ai_runtime(run, deployment, template, actor, runtime_instance_id)
    end
  end

  defp start_ai_runtime(run, deployment, template, actor, runtime_instance_id) do
    case GnomeGarden.Jido.start_agent(template.module, id: runtime_instance_id) do
      {:ok, pid} ->
        AgentTracker.register(runtime_instance_id, pid, deployment.agent.template, run.task)

        with {:ok, started_run} <-
               Agents.start_agent_run(
                 run,
                 %{runtime_instance_id: runtime_instance_id},
                 actor: actor
               ) do
          persist_message(%{
            agent_run_id: started_run.id,
            role: :user,
            content: started_run.task,
            metadata: %{
              deployment_name: deployment.name,
              template: deployment.agent.template,
              run_kind: started_run.run_kind,
              schedule_slot: started_run.schedule_slot,
              requested_by_user_id: actor && actor.id,
              requested_by_team_member_id: started_run.requested_by_team_member_id
            }
          })

          Task.start(fn ->
            execute_run(started_run, deployment, template, pid, actor)
          end)

          {:ok, started_run}
        else
          {:error, error} ->
            AgentTracker.mark_complete(runtime_instance_id, :error, inspect(error))
            _ = stop_runtime(runtime_instance_id)
            fail_pending_run(run, error, actor)
        end

      {:error, reason} ->
        fail_pending_run(run, reason, actor)
    end
  end

  defp start_direct_runtime(run, deployment, template, actor, runtime_instance_id) do
    with {:ok, started_run} <-
           Agents.start_agent_run(
             run,
             %{runtime_instance_id: runtime_instance_id},
             actor: actor
           ),
         :ok <-
           persist_message(%{
             agent_run_id: started_run.id,
             role: :user,
             content: started_run.task,
             metadata: %{
               deployment_name: deployment.name,
               template: deployment.agent.template,
               run_kind: started_run.run_kind,
               schedule_slot: started_run.schedule_slot,
               requested_by_user_id: actor && actor.id,
               requested_by_team_member_id: started_run.requested_by_team_member_id
             }
           }),
         {:ok, pid} <-
           Task.start(fn ->
             execute_direct_run(
               started_run,
               deployment,
               template.module,
               actor,
               runtime_instance_id
             )
           end) do
      AgentTracker.register(runtime_instance_id, pid, deployment.agent.template, run.task)
      {:ok, started_run}
    else
      {:error, error} ->
        AgentTracker.mark_complete(runtime_instance_id, :error, inspect(error))
        fail_pending_run(run, error, actor)
    end
  end

  defp execute_run(run, deployment, template, pid, actor) do
    task = run.task
    runtime_instance_id = run.runtime_instance_id || run.id

    try do
      result =
        template.module.ask_sync(
          pid,
          task,
          timeout: timeout_for(deployment),
          tool_context: %{
            agent_run_id: run.id,
            actor_id: actor && actor.id,
            actor_email: actor && actor.email,
            deployment_id: deployment.id,
            deployment_name: deployment.name,
            run_id: run.id,
            runtime_instance_id: runtime_instance_id,
            memory_namespace: deployment.memory_namespace,
            source_scope: deployment.source_scope,
            deployment_config: deployment.config,
            project_dir: File.cwd!()
          }
        )

      case result do
        {:ok, response} ->
          handle_success(run, runtime_instance_id, response, actor)

        {:error, reason} ->
          handle_failure(run, runtime_instance_id, reason, actor)
      end
    rescue
      exception ->
        handle_failure(run, runtime_instance_id, exception, actor)
    catch
      kind, reason ->
        handle_failure(run, runtime_instance_id, {kind, reason}, actor)
    after
      _ = stop_runtime(runtime_instance_id)
    end
  end

  defp execute_direct_run(run, deployment, module, actor, runtime_instance_id) do
    try do
      result =
        module.execute_run(%{
          run: run,
          deployment: deployment,
          actor: actor,
          timeout_ms: timeout_for(deployment),
          tool_context: runtime_tool_context(run, deployment, actor, runtime_instance_id)
        })

      case result do
        {:ok, response} ->
          handle_success(run, runtime_instance_id, response, actor)

        {:error, reason} ->
          handle_failure(run, runtime_instance_id, reason, actor)
      end
    rescue
      exception ->
        handle_failure(run, runtime_instance_id, exception, actor)
    catch
      kind, reason ->
        handle_failure(run, runtime_instance_id, {kind, reason}, actor)
    end
  end

  defp handle_success(run, runtime_instance_id, response, actor) do
    usage = extract_usage(response)
    tracker_entry = AgentTracker.get_agent(runtime_instance_id)
    token_count = max(usage.total_tokens, (tracker_entry && tracker_entry.tokens) || 0)
    tool_count = (tracker_entry && tracker_entry.tool_calls) || 0
    result_text = extract_result_text(response)

    AgentTracker.track_tokens(runtime_instance_id, usage.total_tokens)
    AgentTracker.mark_complete(runtime_instance_id, :done, result_text)

    case Agents.complete_agent_run(
           run,
           %{
             result: result_text,
             result_summary: %{
               preview: String.slice(result_text || "", 0, 280),
               usage: usage
             },
             token_count: token_count,
             tool_count: tool_count
           },
           actor: actor
         ) do
      {:ok, _completed_run} ->
        persist_message(%{
          agent_run_id: run.id,
          role: :assistant,
          content: result_text,
          metadata: %{
            usage: usage,
            tool_count: tool_count
          }
        })

        :ok

      {:error, error} ->
        Logger.error("Failed to complete run #{run.id}: #{inspect(error)}")
        :error
    end
  end

  defp handle_failure(run, runtime_instance_id, reason, actor) do
    tracker_entry = AgentTracker.get_agent(runtime_instance_id)
    error_text = format_failure(reason)

    AgentTracker.mark_complete(runtime_instance_id, :error, error_text)

    case Agents.fail_agent_run(
           run,
           %{
             error: error_text,
             failure_details: failure_details(reason)
           },
           actor: actor
         ) do
      {:ok, _failed_run} ->
        persist_message(%{
          agent_run_id: run.id,
          role: :system,
          content: "Run failed: #{error_text}",
          metadata: %{
            failure_details: failure_details(reason),
            tool_count: (tracker_entry && tracker_entry.tool_calls) || 0
          }
        })

        :ok

      {:error, error} ->
        Logger.error("Failed to mark run #{run.id} as failed: #{inspect(error)}")
        :error
    end
  end

  defp fail_pending_run(run, reason, actor) do
    error_text = format_failure(reason)

    AgentTracker.mark_complete(run.id, :error, error_text)

    case Agents.fail_agent_run(
           run,
           %{
             error: error_text,
             failure_details: failure_details(reason)
           },
           actor: actor
         ) do
      {:ok, failed_run} ->
        persist_message(%{
          agent_run_id: failed_run.id,
          role: :system,
          content: "Run failed before startup: #{error_text}",
          metadata: %{failure_details: failure_details(reason)}
        })

        {:error, error_text}

      {:error, error} ->
        {:error, error}
    end
  end

  defp persist_message(attrs) do
    case Agents.create_agent_message(attrs) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.warning("Failed to persist agent message: #{inspect(error)}")
        {:error, error}
    end
  end

  defp stop_runtime(runtime_instance_id) do
    # Pi runners aren't Jido agents — try the PiRunner registry first.
    case GnomeGarden.Agents.PiRunner.cancel(runtime_instance_id) do
      :ok ->
        :ok

      {:error, :not_running} ->
        case GnomeGarden.Jido.stop_agent(runtime_instance_id) do
          :ok ->
            :ok

          {:error, :not_found} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to stop runtime #{runtime_instance_id}: #{inspect(reason)}")
        end
    end
  end

  defp timeout_for(%{config: %{"timeout_ms" => timeout_ms}})
       when is_integer(timeout_ms) and timeout_ms > 0,
       do: timeout_ms

  defp timeout_for(%{config: %{timeout_ms: timeout_ms}})
       when is_integer(timeout_ms) and timeout_ms > 0,
       do: timeout_ms

  defp timeout_for(_deployment), do: @default_timeout_ms

  defp runtime_tool_context(run, deployment, actor, runtime_instance_id) do
    %{
      agent_run_id: run.id,
      actor_id: actor && actor.id,
      actor_email: actor && actor.email,
      deployment_id: deployment.id,
      deployment_name: deployment.name,
      run_id: run.id,
      runtime_instance_id: runtime_instance_id,
      memory_namespace: deployment.memory_namespace,
      source_scope: deployment.source_scope,
      deployment_config: deployment.config,
      project_dir: File.cwd!()
    }
  end

  defp default_task_for(%{agent: %{template: "source_discovery"}} = deployment) do
    """
    Run the SourceDiscovery deployment "#{deployment.name}".

    Goal:
    Discover new procurement sources that should be tracked long-term.

    Source scope:
    #{inspect(deployment.source_scope, pretty: true, limit: :infinity)}

    Deployment config:
    #{inspect(deployment.config, pretty: true, limit: :infinity)}

    Save any strong candidates with clear notes and confidence.
    """
    |> String.trim()
  end

  defp default_task_for(%{agent: %{template: "bid_scanner"}} = deployment) do
    """
    Run the BidScanner deployment "#{deployment.name}".

    Goal:
    Scan the approved in-scope procurement sources for fresh opportunities.

    Source scope:
    #{inspect(deployment.source_scope, pretty: true, limit: :infinity)}

    Deployment config:
    #{inspect(deployment.config, pretty: true, limit: :infinity)}

    Score, save, and summarize the strongest bids you find.
    """
    |> String.trim()
  end

  defp default_task_for(%{agent: %{template: "target_discovery"}} = deployment) do
    """
    Run the TargetDiscovery deployment "#{deployment.name}".

    Goal:
    Find real companies that fit Gnome's automation, controls, service, or
    industrial software profile and save them as reviewable discovery findings.

    Source scope:
    #{inspect(deployment.source_scope, pretty: true, limit: :infinity)}

    Deployment config:
    #{inspect(deployment.config, pretty: true, limit: :infinity)}

    Verify the company is active, local enough to matter, and has a specific
    signal before saving it.
    """
    |> String.trim()
  end

  defp default_task_for(deployment) do
    """
    Run the "#{deployment.name}" deployment.

    Description:
    #{deployment.description || "No deployment description provided."}

    Config:
    #{inspect(deployment.config, pretty: true, limit: :infinity)}

    Source scope:
    #{inspect(deployment.source_scope, pretty: true, limit: :infinity)}
    """
    |> String.trim()
  end

  defp extract_result_text(%{last_answer: answer}) when is_binary(answer), do: answer
  defp extract_result_text(%{answer: answer}) when is_binary(answer), do: answer
  defp extract_result_text(%{text: text}) when is_binary(text), do: text
  defp extract_result_text(%{result: result}) when is_binary(result), do: result
  defp extract_result_text(result) when is_binary(result), do: result
  defp extract_result_text(nil), do: nil
  defp extract_result_text(result), do: inspect(result, pretty: true, limit: :infinity)

  defp extract_usage(%{usage: usage}) when is_map(usage), do: usage_struct(usage)
  defp extract_usage(%{meta: %{usage: usage}}) when is_map(usage), do: usage_struct(usage)
  defp extract_usage(_result), do: usage_struct(%{})

  defp usage_struct(usage) do
    input_tokens = Map.get(usage, :input_tokens, Map.get(usage, "input_tokens", 0))
    output_tokens = Map.get(usage, :output_tokens, Map.get(usage, "output_tokens", 0))

    total_tokens =
      Map.get(usage, :total_tokens, Map.get(usage, "total_tokens", input_tokens + output_tokens))

    %{
      input_tokens: max(input_tokens || 0, 0),
      output_tokens: max(output_tokens || 0, 0),
      total_tokens: max(total_tokens || 0, 0)
    }
  end

  defp format_failure(exception) when is_exception(exception), do: Exception.message(exception)
  defp format_failure({kind, reason}), do: "#{kind}: #{inspect(reason, pretty: true)}"
  defp format_failure(reason) when is_binary(reason), do: reason
  defp format_failure(reason), do: inspect(reason, pretty: true)

  defp failure_details(exception) when is_exception(exception) do
    %{
      type: inspect(exception.__struct__),
      message: Exception.message(exception)
    }
  end

  defp failure_details({kind, reason}) do
    %{
      kind: inspect(kind),
      reason: inspect(reason, pretty: true)
    }
  end

  defp failure_details(reason) when is_binary(reason), do: %{message: reason}
  defp failure_details(reason), do: %{reason: inspect(reason, pretty: true)}
end
