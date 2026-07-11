defmodule GnomeGarden.Commercial.DiscoveryRunnerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.Acquisition
  alias GnomeGarden.Commercial
  alias GnomeGarden.Search.Exa

  test "launch_discovery_program searches Exa and persists preview telemetry only" do
    Req.Test.stub(Exa, fn conn ->
      Req.Test.json(conn, %{
        "costDollars" => %{"total" => 0.012},
        "results" => [
          %{
            "title" => "Acme Packaging Automation",
            "url" => "https://acme-packaging.example",
            "publishedDate" => nil
          }
        ]
      })
    end)

    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "OC Packaging Sweep",
        description: "Look for packaging modernization and conveyor expansion signals.",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        search_terms: ["packaging line automation orange county"],
        watch_channels: ["company_site"]
      })

    assert {:ok, result} = Commercial.launch_discovery_program(discovery_program)
    assert result.mode == :live_exa_preview
    assert result.candidate_count == 1
    assert result.queries_run == 5
    assert result.total_cost == 0.06
    assert is_binary(result.run_id)

    assert {:ok, [candidate]} =
             Acquisition.list_lead_preview_candidates_for_run(result.run_id)

    assert {:ok, run} = Acquisition.get_lead_preview_run(result.run_id)
    assert candidate.url == "https://acme-packaging.example"
    refute inspect(result) =~ "test-exa-key"
    refute inspect(run) =~ "test-exa-key"
    refute inspect(candidate) =~ "test-exa-key"
    assert {:ok, []} = Acquisition.list_findings()
    assert {:ok, []} = Commercial.list_discovery_records()
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
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Discovery Overlap Guard #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

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
end
