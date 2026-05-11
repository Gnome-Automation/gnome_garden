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

  defp failed_run do
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

    Agents.fail_agent_run(run, %{
      error: "request timeout while scanning source",
      failure_details: RunFailure.details({:timeout, :checkout}, phase: :runtime)
    })
  end
end
