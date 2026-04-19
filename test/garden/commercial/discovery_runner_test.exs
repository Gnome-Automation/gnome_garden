defmodule GnomeGarden.Commercial.DiscoveryRunnerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.Commercial

  test "launch_discovery_program ensures a durable deployment and records launch metadata" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "OC Packaging Sweep",
        description: "Look for packaging modernization and conveyor expansion signals.",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        search_terms: ["packaging line automation orange county"],
        watch_channels: ["job_board", "news_site"]
      })

    run_id = Ecto.UUID.generate()

    assert {:ok, %{program: refreshed_program, deployment: deployment, run: run}} =
             Commercial.launch_discovery_program(
               discovery_program,
               launch_fun: fn deployment_id, opts ->
                 assert is_binary(deployment_id)
                 assert opts[:task] =~ discovery_program.name
                 assert opts[:task] =~ discovery_program.id
                 assert opts[:task] =~ "packaging line automation orange county"

                 {:ok, %{id: run_id, deployment_id: deployment_id, state: :pending}}
               end
             )

    assert run.id == run_id
    assert deployment.name == "Commercial Target Discovery"
    assert refreshed_program.last_run_at
    assert metadata_value(refreshed_program.metadata, :last_agent_run_id) == run_id
    assert metadata_value(refreshed_program.metadata, :last_agent_deployment_id) == deployment.id

    assert metadata_value(refreshed_program.metadata, :last_agent_run_state) in [
             :pending,
             "pending"
           ]

    assert {:ok, template} = Agents.get_agent_template_by_name("target_discovery")
    assert {:ok, persisted_deployment} = Agents.get_agent_deployment_by_name(deployment.name)
    assert persisted_deployment.agent_id == template.id
  end

  test "launch_discovery_program refuses archived programs" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Archived Watch",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, archived_program} = Commercial.archive_discovery_program(discovery_program)

    assert {:error, "Archived discovery programs must be reopened before running."} =
             Commercial.launch_discovery_program(archived_program,
               launch_fun: fn _deployment_id, _opts ->
                 flunk("launch_fun should not be called for archived programs")
               end
             )
  end

  test "launch_discovery_program refuses to overlap an active program run" do
    _ = Agents.TemplateCatalog.sync_templates()

    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "Overlap Guard #{System.unique_integer([:positive])}",
        target_regions: ["oc"],
        target_industries: ["food_bev"]
      })

    {:ok, discovery_program} = Commercial.activate_discovery_program(discovery_program)
    {:ok, deployment} = Commercial.DiscoveryRunner.ensure_target_discovery_deployment()
    {:ok, template} = Agents.get_agent_template_by_name("target_discovery")

    {:ok, run} =
      Agents.create_agent_run(%{
        agent_id: template.id,
        deployment_id: deployment.id,
        task: "Discovery overlap guard",
        run_kind: :manual
      })

    {:ok, running_run} =
      Agents.start_agent_run(run, %{runtime_instance_id: Ecto.UUID.generate()})

    {:ok, discovery_program} =
      Commercial.update_discovery_program(discovery_program, %{
        metadata: %{"last_agent_run_id" => running_run.id}
      })

    assert {:error, :active_run_exists} =
             Commercial.launch_discovery_program(discovery_program,
               launch_fun: fn _deployment_id, _opts ->
                 flunk("launch_fun should not be called while a run is active")
               end
             )
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
