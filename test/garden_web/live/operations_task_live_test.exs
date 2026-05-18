defmodule GnomeGardenWeb.OperationsTaskLiveTest do
  use GnomeGardenWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GnomeGarden.Agents
  alias GnomeGarden.Operations

  setup :register_and_log_in_user

  test "task actions publish Ash PubSub events" do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Task PubSub Account",
        organization_kind: :business,
        status: :prospect
      })

    GnomeGardenWeb.Endpoint.subscribe("task:created")
    GnomeGardenWeb.Endpoint.subscribe("task:updated")
    GnomeGardenWeb.Endpoint.subscribe("task:destroyed")
    GnomeGardenWeb.Endpoint.subscribe("task:organization:#{organization.id}")

    {:ok, task} =
      Operations.create_task(%{
        title: "Publish task event",
        task_type: :review,
        priority: :normal,
        organization_id: organization.id
      })

    GnomeGardenWeb.Endpoint.subscribe("task:updated:#{task.id}")
    GnomeGardenWeb.Endpoint.subscribe("task:destroyed:#{task.id}")

    assert_receive %{topic: "task:created"}
    assert_receive %{topic: "task:organization:" <> organization_id}
    assert organization_id == organization.id

    {:ok, started_task} = Operations.start_task(task)

    assert_receive %{topic: "task:updated"}
    assert_receive %{topic: "task:updated:" <> task_id}
    assert task_id == task.id
    assert_receive %{topic: "task:organization:" <> organization_id}
    assert organization_id == organization.id

    assert :ok = Operations.delete_task(started_task)

    assert_receive %{topic: "task:destroyed"}
    assert_receive %{topic: "task:destroyed:" <> task_id}
    assert task_id == task.id
    assert_receive %{topic: "task:organization:" <> organization_id}
    assert organization_id == organization.id
  end

  test "task index refreshes from Ash PubSub", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/operations/tasks")

    refute html =~ "PubSub refreshed task"

    {:ok, _task} =
      Operations.create_task(%{
        title: "PubSub refreshed task",
        task_type: :review,
        priority: :normal
      })

    assert_eventually(fn -> render(view) =~ "PubSub refreshed task" end)
  end

  test "task index counts come from task read actions", %{conn: conn} do
    {:ok, _open_task} =
      Operations.create_task(%{
        title: "Open count task",
        task_type: :review,
        priority: :normal
      })

    {:ok, _overdue_task} =
      Operations.create_task(%{
        title: "Overdue count task",
        task_type: :review,
        priority: :normal,
        due_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })

    {:ok, _today_task} =
      Operations.create_task(%{
        title: "Today count task",
        task_type: :review,
        priority: :normal,
        due_at: DateTime.new!(Date.utc_today(), ~T[23:59:00], "Etc/UTC")
      })

    {:ok, blocked_task} =
      Operations.create_task(%{
        title: "Blocked count task",
        task_type: :review,
        priority: :normal
      })

    {:ok, _blocked_task} =
      Operations.block_task(blocked_task, %{blocked_reason: "Waiting on another operator"})

    {:ok, completed_overdue_task} =
      Operations.create_task(%{
        title: "Completed overdue count task",
        task_type: :review,
        priority: :normal,
        due_at: DateTime.add(DateTime.utc_now(), -2, :day)
      })

    {:ok, completed_overdue_task} = Operations.start_task(completed_overdue_task)
    {:ok, _completed_overdue_task} = Operations.complete_task(completed_overdue_task)

    {:ok, _view, html} = live(conn, ~p"/operations/tasks")

    assert_stat(html, "Open", "4")
    assert_stat(html, "Overdue", "1")
    assert_stat(html, "Today", "1")
    assert_stat(html, "Blocked", "1")
  end

  test "related task panels refresh from scoped Ash PubSub", %{conn: conn} do
    {:ok, organization} =
      Operations.create_organization(%{
        name: "Scoped PubSub Account",
        organization_kind: :business,
        status: :prospect
      })

    {:ok, unrelated_organization} =
      Operations.create_organization(%{
        name: "Unrelated Scoped PubSub Account",
        organization_kind: :business,
        status: :prospect
      })

    {:ok, view, html} = live(conn, ~p"/operations/organizations/#{organization}")

    refute html =~ "Scoped related task"
    refute html =~ "Unrelated related task"

    {:ok, _unrelated_task} =
      Operations.create_task(%{
        title: "Unrelated related task",
        task_type: :review,
        priority: :normal,
        organization_id: unrelated_organization.id
      })

    Process.sleep(100)
    refute render(view) =~ "Unrelated related task"

    {:ok, _task} =
      Operations.create_task(%{
        title: "Scoped related task",
        task_type: :review,
        priority: :normal,
        organization_id: organization.id
      })

    assert_eventually(fn -> render(view) =~ "Scoped related task" end)
  end

  test "new task form accepts origin params and creates a linked agent run task", %{conn: conn} do
    {:ok, run} = agent_run()

    path =
      "/operations/tasks/new?" <>
        URI.encode_query(%{
          "title" => "Review agent run: #{run.deployment.name}",
          "task_type" => "agent_followup",
          "priority" => "high",
          "origin_domain" => "agents",
          "origin_resource" => "agent_run",
          "origin_id" => run.id,
          "origin_label" => run.deployment.name,
          "origin_url" => "/console/agents/runs/#{run.id}",
          "agent_run_id" => run.id,
          "return_to" => "/console/agents/runs/#{run.id}"
        })

    {:ok, view, html} = live(conn, path)

    assert html =~ "Review agent run: #{run.deployment.name}"
    assert has_element?(view, ~s(input[name="form[agent_run_id]"][value="#{run.id}"]))
    assert has_element?(view, ~s(input[name="form[origin_id]"][value="#{run.id}"]))

    {:error, {:live_redirect, %{to: task_path}}} =
      view
      |> form("#task-form", %{
        "form" => %{
          "title" => "Review agent run: #{run.deployment.name}",
          "task_type" => "agent_followup",
          "priority" => "high",
          "origin_domain" => "agents",
          "origin_resource" => "agent_run",
          "origin_id" => run.id,
          "origin_label" => run.deployment.name,
          "origin_url" => "/console/agents/runs/#{run.id}",
          "agent_run_id" => run.id
        }
      })
      |> render_submit()

    assert task_path =~ "/operations/tasks/"

    assert {:ok, [task]} =
             Operations.list_tasks_by_agent_run(run.id,
               load: [:status_variant, :priority_variant]
             )

    assert task.title == "Review agent run: #{run.deployment.name}"
    assert task.task_type == :agent_followup
    assert task.priority == :high
    assert task.origin_domain == :agents
  end

  test "task show gates lifecycle actions by state and supports blocking", %{conn: conn} do
    {:ok, task} =
      Operations.create_task(%{
        title: "Call site contact",
        task_type: :call,
        priority: :normal
      })

    {:ok, view, _html} = live(conn, ~p"/operations/tasks/#{task}")

    assert has_element?(view, ~s(button[phx-click="start"]))
    refute has_element?(view, ~s(button[phx-click="complete"]))
    assert has_element?(view, "#task-block-form")

    view
    |> form("#task-block-form", %{"task" => %{"blocked_reason" => "Waiting on source docs"}})
    |> render_submit()

    assert render(view) =~ "Task blocked"
    assert render(view) =~ "Waiting on source docs"
    assert has_element?(view, ~s(button[phx-click="start"]))
    refute has_element?(view, ~s(button[phx-click="complete"]))

    view
    |> element(~s(button[phx-click="start"]))
    |> render_click()

    assert has_element?(view, ~s(button[phx-click="complete"]))
  end

  defp agent_run do
    Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Procurement Source Scan #{System.unique_integer([:positive])}",
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

    Agents.get_agent_run(run.id, load: [:deployment])
  end

  defp assert_eventually(fun, attempts \\ 10)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      assert true
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_stat(html, title, value) do
    assert html =~
             ~r/<span[^>]*>\s*#{Regex.escape(value)}\s*<\/span>\s*<span[^>]*>\s*#{Regex.escape(title)}\s*<\/span>/s
  end
end
