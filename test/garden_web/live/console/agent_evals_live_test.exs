defmodule GnomeGardenWeb.Console.AgentEvalsLiveTest do
  use GnomeGardenWeb.ConnCase
  use Oban.Testing, repo: GnomeGarden.Repo

  import Phoenix.LiveViewTest

  alias GnomeGarden.Agents.AgentEvalSweepWorker
  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspection
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspectionEval

  setup :register_and_log_in_user

  defmodule FakeFixtureBrowser do
    def inspect_page(url, _opts) do
      cond do
        String.ends_with?(url, "/sign-in") ->
          {:ok,
           %{
             final_url: url,
             title: "Vendor Login",
             text: "Please sign in to continue.",
             headings: ["Vendor Login"],
             forms: [
               %{
                 "action" => "/login",
                 "method" => "post",
                 "text" => "Username Password Login",
                 "inputs" => [
                   %{"type" => "text", "name" => "username"},
                   %{"type" => "password", "name" => "password"}
                 ],
                 "buttons" => ["Login"]
               }
             ],
             links: []
           }}

        String.ends_with?(url, "/eval-fixtures/procurement/public-bids") ->
          {:ok,
           %{
             final_url: url,
             title: "City Bid Opportunities",
             text: "Current public works and technology solicitations.",
             headings: ["Open Bids"],
             forms: [],
             links: [
               %{"href" => "/sign-in", "text" => "Vendor Login"},
               %{
                 "href" => "/eval-fixtures/procurement/public-bids/scada-controls",
                 "text" => "SCADA Controls Upgrade RFP"
               },
               %{
                 "href" => "/eval-fixtures/procurement/public-bids/pump-maintenance",
                 "text" => "Pump Station Maintenance IFB"
               }
             ]
           }}

        String.ends_with?(url, "/eval-fixtures/procurement/irrelevant") ->
          {:ok,
           %{
             final_url: url,
             title: "Parks Bulletin",
             text: "Library hours, park events, and neighborhood announcements.",
             headings: ["Parks Bulletin"],
             forms: [],
             links: [%{"href" => "/contact", "text" => "Contact staff"}]
           }}
      end
    end
  end

  test "renders eval console empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/console/agents/evals")

    assert html =~ "Agent Evaluations"
    assert html =~ "Coverage Breakdown"
    assert html =~ "No active eval cases yet."
    assert html =~ "No eval runs recorded yet."
  end

  test "seeds procurement inspection eval cases", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console/agents/evals")

    html =
      view
      |> element("button", "Seed Inspection Eval")
      |> render_click()

    assert html =~ "Procurement inspection eval cases are ready."
    assert render(view) =~ "Procurement source inspection: credentials needed"
    assert render(view) =~ "Procurement source inspection: public bid listing"
    assert render(view) =~ "Procurement source inspection: irrelevant page"
    assert render(view) =~ "credentials_needed"
    assert render(view) =~ "Needs source input"
    assert render(view) =~ "Coverage Breakdown"
    assert render(view) =~ "procurement_source_inspection"
    assert render(view) =~ "3 cases · 0 runnable · 3 need input"
  end

  test "runs sweep and reports skipped non-runnable cases", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console/agents/evals")

    view
    |> element("button", "Seed Inspection Eval")
    |> render_click()

    html =
      view
      |> element("button", "Run Runnable Evals")
      |> render_click()

    assert html =~ "Eval sweep ran 0, passed 0, failed 0, errored 0, skipped 3."
    assert render(view) =~ "Needs source input"
  end

  test "queues background eval sweep", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console/agents/evals")

    html =
      view
      |> element("button", "Queue Eval Sweep")
      |> render_click()

    assert html =~ "Eval sweep queued."
    assert render(view) =~ "Sweep Queue"
    assert render(view) =~ "Sweep Health"
    assert render(view) =~ "queued"
    assert render(view) =~ "1/0"

    assert_enqueued(
      worker: AgentEvalSweepWorker,
      args: %{"mode" => "manual"}
    )
  end

  test "prepares procurement inspection fixture for runnable evals", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console/agents/evals")

    html =
      view
      |> element("button", "Prepare Local Fixture")
      |> render_click()

    assert html =~ "Runnable procurement inspection fixtures are ready."
    assert render(view) =~ "Procurement source inspection: credentials needed"
    assert render(view) =~ "Procurement source inspection: public bid listing"
    assert render(view) =~ "Procurement source inspection: irrelevant page"
    assert render(view) =~ "Runnable"
    assert render(view) =~ "Run Eval"
    assert render(view) =~ "Run Local Checks"
    assert render(view) =~ "Queue Local Sweep"
    refute render(view) =~ "Needs source input"
  end

  test "runs all local procurement inspection fixture checks", %{conn: conn} do
    original_browser = Application.get_env(:gnome_garden, :agent_eval_fixture_browser)
    Application.put_env(:gnome_garden, :agent_eval_fixture_browser, FakeFixtureBrowser)

    on_exit(fn ->
      if original_browser do
        Application.put_env(:gnome_garden, :agent_eval_fixture_browser, original_browser)
      else
        Application.delete_env(:gnome_garden, :agent_eval_fixture_browser)
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/console/agents/evals")

    html =
      view
      |> element("button", "Run Local Checks")
      |> render_click()

    assert html =~
             "Local procurement inspection checks ran 3, passed 3, failed 0, errored 0, skipped 0."

    html = render(view)
    assert html =~ "Procurement source inspection: credentials needed"
    assert html =~ "Procurement source inspection: public bid listing"
    assert html =~ "Procurement source inspection: irrelevant page"
    assert html =~ "Last run: passed"
    assert html =~ "mode: credentials_needed"
    assert html =~ "mode: inspected"
    assert html =~ "Coverage Breakdown"
    assert html =~ "Covered"
    assert html =~ "3 cases · 3 runnable · 0 need input"
    assert html =~ "passed 3"
    assert html =~ "unrun 0"
  end

  test "queues local procurement inspection fixture sweep", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console/agents/evals")

    html =
      view
      |> element("button", "Queue Local Sweep")
      |> render_click()

    assert html =~ "Local procurement inspection sweep queued."
    assert render(view) =~ "queued"
    assert render(view) =~ "1/0"

    assert_enqueued(
      worker: AgentEvalSweepWorker,
      args: %{
        "mode" => "local_fixture",
        "timeout_ms" => 5_000,
        "fixture_base_url" => "http://localhost:4000/"
      }
    )
  end

  test "renders recent eval run evidence", %{conn: conn} do
    {:ok, workflow_definition} = ProcurementSourceInspection.ensure_definition()

    {:ok, eval_case} =
      ProcurementSourceInspectionEval.ensure_case(workflow_definition: workflow_definition)

    {:ok, eval_run} =
      Agents.create_agent_eval_run(%{
        eval_case_id: eval_case.id,
        workflow_definition_id: workflow_definition.id,
        input_snapshot: %{"source_fixture" => "credential_login_portal"}
      })

    {:ok, running_eval} = Agents.start_agent_eval_run(eval_run)

    {:ok, _passed_eval} =
      Agents.pass_agent_eval_run(running_eval, %{
        output_snapshot: %{"mode" => "credentials_needed"},
        observed_actions: ["source.inspect"],
        score: Decimal.new("1.0"),
        reviewer_notes: "Fixture matched expected credential blocker."
      })

    {:ok, _view, html} = live(conn, ~p"/console/agents/evals")

    assert html =~ "Procurement source inspection: credentials needed"
    assert html =~ "Last run: passed"
    assert html =~ "passed"
    assert html =~ "1.0"
    assert html =~ "mode: credentials_needed"
  end
end
