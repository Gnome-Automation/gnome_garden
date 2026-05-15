defmodule GnomeGarden.Acquisition.RunnerTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Acquisition
  alias GnomeGarden.Agents.DefaultDeployments

  setup do
    _ = DefaultDeployments.ensure_defaults()
    :ok
  end

  test "launch_source_run routes acquisition-native sources through the default deployment" do
    {:ok, source} =
      Acquisition.create_source(%{
        name: "Automation Directory",
        external_ref: "source-#{System.unique_integer([:positive])}",
        url: "https://example.com/automation",
        source_family: :discovery,
        source_kind: :directory,
        status: :active,
        enabled: true,
        scan_strategy: :agentic
      })

    run_id = Ecto.UUID.generate()

    assert {:ok, %{source: refreshed_source, deployment: deployment, run: run}} =
             Acquisition.launch_source_run(source,
               deployment_launch_fun: fn deployment_id, opts ->
                 assert opts[:task] =~ source.name
                 assert opts[:task] =~ source.url
                 assert opts[:metadata].acquisition_source_id == source.id
                 assert opts[:metadata].source_family == :discovery

                 {:ok, %{id: run_id, deployment_id: deployment_id, state: :pending}}
               end
             )

    assert run.id == run_id
    assert deployment.name == "Commercial Target Discovery"
    assert refreshed_source.last_run_at
    assert metadata_value(refreshed_source.metadata, :last_agent_run_id) == run_id
    assert metadata_value(refreshed_source.metadata, :last_agent_deployment_id) == deployment.id
  end

  test "launch_program_run routes acquisition-native programs through the default deployment" do
    {:ok, program} =
      Acquisition.create_program(%{
        name: "Controls Market Sweep",
        external_ref: "program-#{System.unique_integer([:positive])}",
        description: "Find controls and automation expansion signals.",
        program_family: :discovery,
        program_type: :market_sweep,
        status: :active,
        scope: %{"regions" => ["oc"], "industries" => ["manufacturing"]}
      })

    run_id = Ecto.UUID.generate()

    assert {:ok, %{program: refreshed_program, deployment: deployment, run: run}} =
             Acquisition.launch_program_run(program,
               deployment_launch_fun: fn deployment_id, opts ->
                 assert opts[:task] =~ program.name
                 assert opts[:task] =~ program.id
                 assert opts[:metadata].acquisition_program_id == program.id
                 assert opts[:metadata].program_family == :discovery

                 {:ok, %{id: run_id, deployment_id: deployment_id, state: :pending}}
               end
             )

    assert run.id == run_id
    assert deployment.name == "Commercial Target Discovery"
    assert refreshed_program.last_run_at
    assert metadata_value(refreshed_program.metadata, :last_agent_run_id) == run_id
    assert metadata_value(refreshed_program.metadata, :last_agent_deployment_id) == deployment.id
  end

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, to_string(key))
  end
end
