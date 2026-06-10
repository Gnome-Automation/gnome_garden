defmodule GnomeGardenWeb.Console.AgentAttentionLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.RunFailure
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspection
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspectionEval
  alias GnomeGarden.Operations

  setup :register_and_log_in_user

  test "renders failed runs and failed evals needing attention", %{conn: conn} do
    {:ok, run} = failed_run()
    {:ok, _eval_run} = failed_eval_run(run)

    {:ok, _view, html} = live(conn, ~p"/console/agents/attention")

    assert html =~ "Agent Attention"
    assert html =~ "Failure Clusters"
    assert html =~ "Failed Agent Runs"
    assert html =~ "Failed Evaluations"
    assert html =~ "Agent runs"
    assert html =~ "Eval runs"
    assert html =~ "Timed Out"
    assert html =~ "Retryable"
    assert html =~ "Procurement source inspection: credentials needed"
    assert html =~ "failed: Observed mode: inspected"
    assert html =~ "Observed mode: inspected"
    assert html =~ ~p"/console/agents/runs/#{run.id}"
  end

  test "agents console links to attention surface", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/console/agents")

    assert html =~ "Agent Attention"
    assert html =~ ~p"/console/agents/attention"
  end

  test "creates an operations task for a failed agent run", %{conn: conn} do
    {:ok, run} = failed_run()
    {:ok, view, _html} = live(conn, ~p"/console/agents/attention")

    view
    |> element(~s(button[phx-click="create_run_task"][phx-value-id="#{run.id}"]), "Create Task")
    |> render_click()

    assert render(view) =~ "Task created: Review failed agent run"

    assert {:ok, [task]} =
             Operations.list_tasks_by_agent_run(run.id,
               load: [:status_variant, :priority_variant]
             )

    assert task.title == "Review failed agent run: #{run.deployment.name}"
    assert task.task_type == :agent_followup
    assert task.priority == :high
    assert task.origin_domain == :agents
    assert task.origin_resource == "agent_run"
    assert task.origin_id == run.id
    assert task.origin_url == ~p"/console/agents/runs/#{run.id}"

    html = render(view)
    assert html =~ "Open Task"
    assert html =~ ~p"/operations/tasks/#{task.id}"
  end

  test "creates an operations task for a failed eval run", %{conn: conn} do
    {:ok, run} = failed_run()
    {:ok, eval_run} = failed_eval_run(run)
    {:ok, view, _html} = live(conn, ~p"/console/agents/attention")

    view
    |> element(
      ~s(button[phx-click="create_eval_task"][phx-value-id="#{eval_run.id}"]),
      "Create Task"
    )
    |> render_click()

    assert render(view) =~ "Task created: Review failed agent eval"

    assert {:ok, [task]} =
             Operations.list_tasks_by_origin(:agents, "agent_eval_run", eval_run.id,
               load: [:status_variant, :priority_variant]
             )

    assert task.title ==
             "Review failed agent eval: Procurement source inspection: credentials needed"

    assert task.task_type == :agent_followup
    assert task.priority == :high
    assert task.origin_domain == :agents
    assert task.origin_resource == "agent_eval_run"
    assert task.origin_id == eval_run.id
    assert task.agent_run_id == run.id

    html = render(view)
    assert html =~ "Open Task"
    assert html =~ ~p"/operations/tasks/#{task.id}"
  end

  test "resolves an operations task from a failed eval row", %{conn: conn} do
    {:ok, run} = failed_run()
    {:ok, eval_run} = failed_eval_run(run)
    {:ok, view, _html} = live(conn, ~p"/console/agents/attention")

    view
    |> element(
      ~s(button[phx-click="create_eval_task"][phx-value-id="#{eval_run.id}"]),
      "Create Task"
    )
    |> render_click()

    assert {:ok, [task]} =
             Operations.list_tasks_by_origin(:agents, "agent_eval_run", eval_run.id)

    html =
      view
      |> element(~s(button[phx-click="resolve_task"][phx-value-id="#{task.id}"]), "Mark Resolved")
      |> render_click()

    assert {:ok, completed_task} = Operations.get_task(task.id)
    assert completed_task.status == :completed
    assert completed_task.completed_at
    assert html =~ "Resolved"
  end

  test "filters failed evals to resolved follow-up tasks", %{conn: conn} do
    {:ok, run} = failed_run()
    {:ok, eval_run} = failed_eval_run(run)
    {:ok, view, _html} = live(conn, ~p"/console/agents/attention")

    view
    |> element(
      ~s(button[phx-click="create_eval_task"][phx-value-id="#{eval_run.id}"]),
      "Create Task"
    )
    |> render_click()

    assert {:ok, [task]} =
             Operations.list_tasks_by_origin(:agents, "agent_eval_run", eval_run.id)

    view
    |> element(~s(button[phx-click="resolve_task"][phx-value-id="#{task.id}"]), "Mark Resolved")
    |> render_click()

    html =
      view
      |> form("#agent-attention-filters", %{
        "filters" => %{"runs" => "all", "evals" => "resolved", "group" => "task_state"}
      })
      |> render_change()

    assert html =~ "Resolved:"
    assert html =~ "Resolved"
    assert html =~ ~p"/operations/tasks/#{task.id}"
    refute html =~ ~s(phx-click="create_eval_task")
  end

  test "creates missing operations tasks for a failed eval cluster", %{conn: conn} do
    {:ok, first_run} = failed_run()
    {:ok, first_eval_run} = failed_eval_run(first_run)
    {:ok, second_run} = failed_run()
    {:ok, second_eval_run} = failed_eval_run(second_run)

    {:ok, view, html} = live(conn, ~p"/console/agents/attention")

    assert html =~ "Failure Clusters"
    assert html =~ "in trend window"
    assert html =~ "Create Missing Tasks"

    view
    |> element(
      ~s(button[phx-click="create_cluster_tasks"][phx-value-kind="eval"]),
      "Create Missing Tasks"
    )
    |> render_click()

    assert {:ok, [_first_task]} =
             Operations.list_tasks_by_origin(:agents, "agent_eval_run", first_eval_run.id)

    assert {:ok, [_second_task]} =
             Operations.list_tasks_by_origin(:agents, "agent_eval_run", second_eval_run.id)
  end

  test "drills into a failed eval cluster and clears it", %{conn: conn} do
    {:ok, first_run} = failed_run()
    {:ok, _first_eval_run} = failed_eval_run(first_run)
    {:ok, second_run} = failed_run()
    {:ok, _second_eval_run} = failed_eval_run(second_run)
    {:ok, error_run} = failed_run()
    {:ok, _error_eval_run} = error_eval_run(error_run)

    {:ok, view, html} = live(conn, ~p"/console/agents/attention")

    assert html =~ "recent failed or errored evals."
    assert html =~ "Observed mode: inspected"
    assert html =~ "Fixture browser crashed."

    html =
      view
      |> element(
        ~s(button[phx-click="view_cluster"][phx-value-failure="failed: Observed mode: inspected"]),
        "View Cluster"
      )
      |> render_click()

    assert html =~ "Viewing cluster:"
    assert html =~ "Clear Cluster"
    assert html =~ "Observed mode: inspected"

    html =
      view
      |> element("button", "Clear Cluster")
      |> render_click()

    refute html =~ "Viewing cluster:"
    assert html =~ "recent failed or errored evals."
    assert html =~ "Fixture browser crashed."
  end

  test "filters failed runs by task state and shows group counts", %{conn: conn} do
    {:ok, needs_task_run} = failed_run()
    {:ok, has_task_run} = failed_run()

    {:ok, task} =
      Operations.create_task_from_agent_run(%{
        title: "Existing follow-up task",
        task_type: :agent_followup,
        priority: :high,
        origin_id: has_task_run.id,
        origin_label: has_task_run.deployment.name,
        origin_url: ~p"/console/agents/runs/#{has_task_run.id}",
        agent_run_id: has_task_run.id
      })

    {:ok, view, html} = live(conn, ~p"/console/agents/attention")

    assert html =~ "Task open:"
    assert html =~ "Needs task:"
    assert html =~ needs_task_run.deployment.name
    assert html =~ has_task_run.deployment.name
    assert html =~ ~p"/operations/tasks/#{task.id}"

    html =
      view
      |> form("#agent-attention-filters", %{
        "filters" => %{"runs" => "needs_task", "evals" => "all", "group" => "task_state"}
      })
      |> render_change()

    assert html =~ "Showing 1 of 2 recent failed runs."
    assert html =~ needs_task_run.deployment.name
    refute html =~ has_task_run.deployment.name

    html =
      view
      |> form("#agent-attention-filters", %{
        "filters" => %{"runs" => "has_task", "evals" => "all", "group" => "task_state"}
      })
      |> render_change()

    assert html =~ "Showing 1 of 2 recent failed runs."
    assert html =~ has_task_run.deployment.name
    refute html =~ needs_task_run.deployment.name
  end

  test "filters failed evals by status", %{conn: conn} do
    {:ok, failed_agent_run} = failed_run()
    {:ok, _failed_eval} = failed_eval_run(failed_agent_run)
    {:ok, error_agent_run} = failed_run()
    {:ok, error_eval} = error_eval_run(error_agent_run)

    {:ok, view, html} = live(conn, ~p"/console/agents/attention")

    assert html =~ "recent failed or errored evals."
    assert html =~ "Observed mode: inspected"
    assert html =~ "Fixture browser crashed."

    html =
      view
      |> form("#agent-attention-filters", %{
        "filters" => %{"runs" => "all", "evals" => "error", "group" => "failure"}
      })
      |> render_change()

    assert html =~ "recent failed or errored evals."
    assert html =~ "Failure Clusters"
    assert html =~ "error:"
    assert html =~ "error: Fixture browser crashed."
    assert html =~ "Fixture browser crashed."
    refute html =~ "Observed mode: inspected"
    assert html =~ ~p"/console/agents/runs/#{error_eval.agent_run_id}"
    refute html =~ "Expected credential blocker."
  end

  defp failed_eval_run(agent_run) do
    {:ok, workflow_definition} = ProcurementSourceInspection.ensure_definition()

    {:ok, eval_case} =
      ProcurementSourceInspectionEval.ensure_case(workflow_definition: workflow_definition)

    {:ok, eval_run} =
      Agents.create_agent_eval_run(%{
        eval_case_id: eval_case.id,
        workflow_definition_id: workflow_definition.id,
        agent_run_id: agent_run.id,
        input_snapshot: %{"source_fixture" => "credential_login_portal"}
      })

    {:ok, running_eval} = Agents.start_agent_eval_run(eval_run)

    Agents.fail_agent_eval_run(running_eval, %{
      agent_run_id: agent_run.id,
      output_snapshot: %{"mode" => "inspected"},
      observed_actions: ["source.inspect"],
      score: Decimal.new("0.0"),
      reviewer_notes: "Expected credential blocker."
    })
  end

  defp error_eval_run(agent_run) do
    {:ok, workflow_definition} = ProcurementSourceInspection.ensure_definition()

    {:ok, eval_case} =
      ProcurementSourceInspectionEval.ensure_case(workflow_definition: workflow_definition)

    {:ok, eval_run} =
      Agents.create_agent_eval_run(%{
        eval_case_id: eval_case.id,
        workflow_definition_id: workflow_definition.id,
        agent_run_id: agent_run.id,
        input_snapshot: %{"source_fixture" => "credential_login_portal"}
      })

    {:ok, running_eval} = Agents.start_agent_eval_run(eval_run)

    Agents.error_agent_eval_run(running_eval, %{
      agent_run_id: agent_run.id,
      output_snapshot: %{},
      reviewer_notes: "Fixture browser crashed."
    })
  end

  defp failed_run do
    Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Attention Failed Run #{System.unique_integer([:positive])}",
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

    {:ok, run} =
      Agents.fail_agent_run(run, %{
        error: "request timeout while scanning source",
        failure_details: RunFailure.details({:timeout, :checkout}, phase: :runtime)
      })

    {:ok, Agents.get_agent_run!(run.id, load: [:deployment])}
  end
end
