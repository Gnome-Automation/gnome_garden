defmodule GnomeGarden.Acquisition.Runner do
  @moduledoc """
  Acquisition-native launch routing for sources and programs.

  This module keeps procurement, commercial discovery, Pi, and Jido details
  behind the acquisition boundary. Durable business state remains in Ash
  resources; runtimes are selected per source/program.
  """

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Acquisition.{Program, Source}
  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.DeploymentRunner
  alias GnomeGarden.Commercial
  alias GnomeGarden.Procurement

  @source_defaults %{
    discovery: "Commercial Target Discovery",
    procurement: "SoCal Bid Scanner",
    company_site: "Commercial Target Discovery",
    directory: "Commercial Target Discovery",
    job_board: "Commercial Target Discovery",
    news_feed: "Commercial Target Discovery"
  }

  @program_defaults %{
    discovery: "Commercial Target Discovery",
    procurement: "SoCal Source Discovery"
  }

  def launch_source(source_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    procurement_launch_fun =
      Keyword.get(opts, :procurement_launch_fun, &Procurement.launch_procurement_source_scan/2)

    deployment_launch_fun =
      Keyword.get(opts, :deployment_launch_fun, &DeploymentRunner.launch_manual_run/2)

    with {:ok, source} <- load_source(source_or_id, actor),
         :ok <- ensure_source_runnable(source) do
      if is_binary(source.procurement_source_id) do
        procurement_launch_fun.(source.procurement_source_id, actor: actor)
      else
        launch_source_deployment(source, actor, deployment_launch_fun)
      end
    end
  end

  def launch_program(program_or_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    commercial_launch_fun =
      Keyword.get(opts, :commercial_launch_fun, &Commercial.launch_discovery_program/2)

    deployment_launch_fun =
      Keyword.get(opts, :deployment_launch_fun, &DeploymentRunner.launch_manual_run/2)

    with {:ok, program} <- load_program(program_or_id, actor),
         :ok <- ensure_program_runnable(program) do
      if is_binary(program.discovery_program_id) do
        commercial_launch_fun.(program.discovery_program_id, actor: actor)
      else
        launch_program_deployment(program, actor, deployment_launch_fun)
      end
    end
  end

  defp load_source(%Source{id: id}, actor), do: load_source(id, actor)

  defp load_source(id, actor) when is_binary(id) do
    Acquisition.get_source(id, actor: actor, load: [:procurement_source, :runnable])
  end

  defp load_program(%Program{id: id}, actor), do: load_program(id, actor)

  defp load_program(id, actor) when is_binary(id) do
    Acquisition.get_program(id, actor: actor, load: [:runnable])
  end

  defp ensure_source_runnable(%{runnable: true}), do: :ok
  defp ensure_source_runnable(_source), do: {:error, "Source is not launchable yet."}

  defp ensure_program_runnable(%{runnable: true}), do: :ok
  defp ensure_program_runnable(_program), do: {:error, "Program is not launchable yet."}

  defp launch_source_deployment(source, actor, launch_fun) do
    with {:ok, deployment} <- source_deployment(source, actor),
         {:ok, run} <-
           launch_fun.(deployment.id,
             actor: actor,
             task: source_task(source, deployment),
             metadata: %{
               acquisition_source_id: source.id,
               source_url: source.url,
               source_family: source.source_family,
               source_kind: source.source_kind
             }
           ),
         {:ok, refreshed_source} <- persist_source_launch(source, deployment, run, actor) do
      {:ok, %{source: refreshed_source, deployment: deployment, run: run}}
    end
  end

  defp launch_program_deployment(program, actor, launch_fun) do
    with {:ok, deployment} <- program_deployment(program, actor),
         {:ok, run} <-
           launch_fun.(deployment.id,
             actor: actor,
             task: program_task(program, deployment),
             metadata: %{
               acquisition_program_id: program.id,
               program_family: program.program_family,
               program_type: program.program_type
             }
           ),
         {:ok, refreshed_program} <- persist_program_launch(program, deployment, run, actor) do
      {:ok, %{program: refreshed_program, deployment: deployment, run: run}}
    end
  end

  defp source_deployment(source, actor) do
    deployment_from_metadata(source.metadata, actor) ||
      deployment_by_name(default_source_deployment_name(source), actor)
  end

  defp program_deployment(program, actor) do
    deployment_from_metadata(program.metadata, actor) ||
      deployment_by_name(default_program_deployment_name(program), actor)
  end

  defp deployment_from_metadata(metadata, actor) when is_map(metadata) do
    cond do
      id = metadata_value(metadata, "agent_deployment_id") ->
        Agents.get_agent_deployment(id, actor: actor, load: [:agent])

      name = metadata_value(metadata, "agent_deployment_name") ->
        Agents.get_agent_deployment_by_name(name, actor: actor, load: [:agent])

      template = metadata_value(metadata, "agent_template") ->
        deployment_by_template(template, actor)

      true ->
        nil
    end
  end

  defp deployment_from_metadata(_metadata, _actor), do: nil

  defp deployment_by_template(template, actor) when is_binary(template) do
    case Agents.list_console_agent_deployments(actor: actor, load: [:agent]) do
      {:ok, deployments} ->
        case Enum.find(deployments, &(&1.agent && &1.agent.template == template)) do
          nil -> {:error, "No deployment found for template #{inspect(template)}."}
          deployment -> {:ok, deployment}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp deployment_by_name(nil, _actor), do: {:error, "No agent deployment route configured."}

  defp deployment_by_name(name, actor) do
    Agents.get_agent_deployment_by_name(name, actor: actor, load: [:agent])
  end

  defp default_source_deployment_name(source) do
    Map.get(@source_defaults, source.source_kind) ||
      Map.get(@source_defaults, source.source_family)
  end

  defp default_program_deployment_name(program) do
    Map.get(@program_defaults, program.program_family)
  end

  defp source_task(source, deployment) do
    metadata_task(source.metadata) ||
      """
      Run acquisition source "#{source.name}" using deployment "#{deployment.name}".

      Source:
      - ID: #{source.id}
      - URL: #{source.url}
      - Family: #{source.source_family}
      - Kind: #{source.source_kind}

      Find current automation, controls, industrial software, procurement, or commercial signals from this source. Save every qualifying result through the available Ash-backed tools so it enters the acquisition review queue.
      """
      |> String.trim()
  end

  defp program_task(program, deployment) do
    metadata_task(program.metadata) ||
      """
      Run acquisition program "#{program.name}" using deployment "#{deployment.name}".

      Program:
      - ID: #{program.id}
      - Family: #{program.program_family}
      - Type: #{program.program_type}
      - Scope: #{inspect(program.scope, pretty: true, limit: :infinity)}

      Work the program scope and save every qualifying result through the available Ash-backed tools so it enters the acquisition review queue.
      """
      |> String.trim()
  end

  defp metadata_task(metadata) when is_map(metadata) do
    case metadata_value(metadata, "agent_task") do
      task when is_binary(task) and task != "" -> task
      _ -> nil
    end
  end

  defp metadata_task(_metadata), do: nil

  defp persist_source_launch(source, deployment, run, actor) do
    metadata =
      source.metadata
      |> Map.new()
      |> put_run_metadata(deployment, run, actor)

    Acquisition.update_source(
      source,
      %{
        last_run_at: DateTime.utc_now(),
        metadata: metadata
      },
      actor: actor
    )
  end

  defp persist_program_launch(program, deployment, run, actor) do
    metadata =
      program.metadata
      |> Map.new()
      |> put_run_metadata(deployment, run, actor)

    Acquisition.update_program(
      program,
      %{
        last_run_at: DateTime.utc_now(),
        metadata: metadata
      },
      actor: actor
    )
  end

  defp put_run_metadata(metadata, deployment, run, actor) do
    metadata
    |> Map.put("last_agent_run_id", run.id)
    |> Map.put("last_agent_deployment_id", deployment.id)
    |> Map.put("last_agent_run_state", run.state)
    |> Map.put("last_agent_triggered_by_user_id", actor && actor.id)
  end

  defp metadata_value(metadata, "agent_deployment_id"),
    do: Map.get(metadata, "agent_deployment_id") || Map.get(metadata, :agent_deployment_id)

  defp metadata_value(metadata, "agent_deployment_name"),
    do: Map.get(metadata, "agent_deployment_name") || Map.get(metadata, :agent_deployment_name)

  defp metadata_value(metadata, "agent_template"),
    do: Map.get(metadata, "agent_template") || Map.get(metadata, :agent_template)

  defp metadata_value(metadata, "agent_task"),
    do: Map.get(metadata, "agent_task") || Map.get(metadata, :agent_task)
end
