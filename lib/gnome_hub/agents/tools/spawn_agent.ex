defmodule GnomeHub.Agents.Tools.SpawnAgent do
  @moduledoc """
  Spawn a child agent from a template to work on a task.

  The child agent works independently and results can be collected
  with get_agent_result.
  """

  use Jido.Action,
    name: "spawn_agent",
    description: "Spawn a child agent from a template to work on a task. Available templates: coder, test_runner, reviewer, docs_writer, researcher, refactorer. The child agent works independently and results can be collected with get_agent_result.",
    schema: [
      template: [type: :string, required: true, doc: "Agent template name (coder, test_runner, reviewer, docs_writer, researcher, refactorer)"],
      task: [type: :string, required: true, doc: "The task description for the child agent to work on"],
      tag: [type: :string, required: false, doc: "Optional unique ID for this agent (auto-generated if not provided)"]
    ]

  alias GnomeHub.Agents.{AgentTracker, Templates}

  @impl true
  def run(params, context) do
    template_name = Map.get(params, :template) || Map.get(params, "template")
    task = Map.get(params, :task) || Map.get(params, "task")
    tag = Map.get(params, :tag) || Map.get(params, "tag") || "#{template_name}_#{:erlang.unique_integer([:positive])}"

    # Get project_dir from tool context if available
    project_dir = get_in(context, [:tool_context, :project_dir]) || File.cwd!()

    case Templates.get(template_name) do
      {:ok, template} ->
        case GnomeHub.Jido.start_agent(template.module, id: tag) do
          {:ok, pid} ->
            # Register with AgentTracker for tracking
            AgentTracker.register(tag, pid, template_name, task)

            # Send task async - don't block the main agent
            spawn(fn ->
              try do
                result = template.module.ask_sync(pid, task,
                  timeout: 120_000,
                  tool_context: %{project_dir: project_dir}
                )

                AgentTracker.mark_complete(tag, :done, result)
              rescue
                e ->
                  AgentTracker.mark_complete(tag, :error, Exception.message(e))
              catch
                _, reason ->
                  AgentTracker.mark_complete(tag, :error, inspect(reason))
              end
            end)

            {:ok, %{
              agent_id: tag,
              template: template_name,
              description: template.description,
              status: "spawned",
              message: "Agent '#{tag}' spawned with template '#{template_name}'. Use get_agent_result to collect the result when done."
            }}

          {:error, reason} ->
            {:error, "Failed to spawn agent: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
