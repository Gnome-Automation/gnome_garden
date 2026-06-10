defmodule GnomeGarden.Agents.AgentEvalSweepWorkerTest do
  use GnomeGarden.DataCase
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalSweepWorker
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspectionEval

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

  test "enqueues a unique eval sweep job" do
    assert {:ok, _job} = AgentEvalSweepWorker.enqueue()

    assert_enqueued(
      worker: AgentEvalSweepWorker,
      args: %{"mode" => "manual"}
    )
  end

  test "enqueues a scoped eval sweep job" do
    assert {:ok, _job} =
             AgentEvalSweepWorker.enqueue("manual",
               timeout_ms: 2_000,
               eval_case_keys: ["procurement-source-inspection.credentials-needed"]
             )

    assert_enqueued(
      worker: AgentEvalSweepWorker,
      args: %{
        "mode" => "manual",
        "timeout_ms" => 2_000,
        "eval_case_keys" => ["procurement-source-inspection.credentials-needed"]
      }
    )
  end

  test "enqueues a local fixture sweep job" do
    assert {:ok, _job} =
             AgentEvalSweepWorker.enqueue("local_fixture",
               timeout_ms: 5_000,
               fixture_base_url: "http://fixture.test/"
             )

    assert_enqueued(
      worker: AgentEvalSweepWorker,
      args: %{
        "mode" => "local_fixture",
        "timeout_ms" => 5_000,
        "fixture_base_url" => "http://fixture.test/"
      }
    )
  end

  test "runs active eval cases through the sweep module" do
    {:ok, eval_case} = ProcurementSourceInspectionEval.ensure_case()

    assert :ok =
             AgentEvalSweepWorker.perform(%Oban.Job{
               args: %{"mode" => "scheduled", "eval_case_keys" => [eval_case.key]}
             })
  end

  test "prepares and runs local fixture sweep jobs" do
    original_browser = Application.get_env(:gnome_garden, :agent_eval_fixture_browser)
    Application.put_env(:gnome_garden, :agent_eval_fixture_browser, FakeFixtureBrowser)

    on_exit(fn ->
      if original_browser do
        Application.put_env(:gnome_garden, :agent_eval_fixture_browser, original_browser)
      else
        Application.delete_env(:gnome_garden, :agent_eval_fixture_browser)
      end
    end)

    assert :ok =
             AgentEvalSweepWorker.perform(%Oban.Job{
               args: %{
                 "mode" => "local_fixture",
                 "timeout_ms" => 5_000,
                 "fixture_base_url" => "http://fixture.test/"
               }
             })

    assert {:ok, eval_runs} =
             Agents.list_recent_agent_eval_runs(10, query: [load: [:eval_case]])

    passed_fixture_keys =
      eval_runs
      |> Enum.filter(&(&1.status == :passed))
      |> Enum.map(& &1.eval_case.key)

    assert "procurement-source-inspection.credentials-needed" in passed_fixture_keys
    assert "procurement-source-inspection.public-bids" in passed_fixture_keys
    assert "procurement-source-inspection.irrelevant-page" in passed_fixture_keys
  end

  test "sets a finite Oban job timeout" do
    assert AgentEvalSweepWorker.timeout(%Oban.Job{}) == :timer.seconds(60)
  end
end
