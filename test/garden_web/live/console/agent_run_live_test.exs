defmodule GnomeGardenWeb.Console.AgentRunLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.RunFailure

  setup :register_and_log_in_user

  test "renders failure classification and recovery hint", %{conn: conn} do
    {:ok, run} = failed_run()

    {:ok, _view, html} = live(conn, ~p"/console/agents/runs/#{run.id}")

    assert html =~ "Timed Out"
    assert html =~ "Retryable"
    assert html =~ "Reduce the task scope"
    assert html =~ "timeout"
    assert html =~ "runtime"
  end

  test "renders scan diagnostics for runs that save no candidates", %{conn: conn} do
    {:ok, run} = running_run()

    {:ok, _output} =
      Agents.create_agent_run_output(%{
        agent_run_id: run.id,
        output_type: :procurement_source,
        output_id: Ecto.UUID.generate(),
        event: :updated,
        label: "RCTC PlanetBids",
        summary: "Scanned RCTC PlanetBids: 0 saved from 30 extracted",
        metadata: %{
          diagnostics: %{
            diagnosis: "scored_but_below_save_threshold",
            saved_examples: [],
            top_unsaved: [
              %{
                title: "Landscape Maintenance Services",
                score_total: 49,
                score_tier: :cold,
                save_candidate: false,
                reason: "Below save threshold",
                packet_status: "packet listed",
                matched: ["maintenance"],
                rejected: [],
                risk_flags: ["low automation fit"]
              }
            ]
          }
        }
      })

    {:ok, _view, html} = live(conn, ~p"/console/agents/runs/#{run.id}")

    assert html =~ "Scan Diagnostics"
    assert html =~ "scored but below save threshold"
    assert html =~ "Landscape Maintenance Services"
    assert html =~ "Below save threshold"
    assert html =~ "score 49"
    assert html =~ "Matched: maintenance"
    assert html =~ "Risks: low automation fit"
  end

  defp failed_run do
    {:ok, run} = running_run()

    Agents.fail_agent_run(run, %{
      error: "request timeout while scanning source",
      failure_details: RunFailure.details({:timeout, :checkout}, phase: :runtime)
    })
  end

  defp running_run do
    Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Failed Run #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    {:ok, run} =
      Agents.create_agent_run(%{
        agent_id: template.id,
        deployment_id: deployment.id,
        task: "scan source",
        run_kind: :manual
      })

    {:ok, run} = Agents.start_agent_run(run, %{runtime_instance_id: Ecto.UUID.generate()})
    {:ok, run}
  end
end
