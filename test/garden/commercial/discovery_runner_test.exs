defmodule GnomeGarden.Commercial.DiscoveryRunnerTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Agents
  alias GnomeGarden.Commercial

  test "launch_discovery_program processes seed candidates through AshLua discovery pipeline" do
    {:ok, discovery_program} =
      Commercial.create_discovery_program(%{
        name: "OC Packaging Sweep",
        description: "Look for packaging modernization and conveyor expansion signals.",
        target_regions: ["oc"],
        target_industries: ["packaging"],
        search_terms: ["packaging line automation orange county"],
        watch_channels: ["job_board", "news_site"],
        metadata: %{
          "seed_candidates" => [
            %{
              "company_name" => "Acme Packaging Automation",
              "website" => "https://acme-packaging.example",
              "location" => "Anaheim, CA",
              "industry" => "packaging",
              "signal" => "Hiring controls engineers for packaging line modernization.",
              "company_description" =>
                "Packaging manufacturer with PLC and SCADA modernization signals.",
              "source_url" => "https://acme-packaging.example/careers"
            }
          ]
        }
      })

    assert {:ok, result} = Commercial.launch_discovery_program(discovery_program)
    assert result.mode == "processed_seed_candidates"
    assert result.candidate_count == 1
    assert result.saved == 1

    assert [%{ok: true, discovery_record_id: discovery_record_id, finding_id: finding_id}] =
             result.results

    assert {:ok, discovery_record} = Commercial.get_discovery_record(discovery_record_id)
    assert discovery_record.name == "Acme Packaging Automation"
    assert {:ok, finding} = GnomeGarden.Acquisition.get_finding(finding_id)
    assert finding.source_discovery_record_id == discovery_record.id
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
