defmodule GnomeGarden.Agents.AgentEvalSweepTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalRunner
  alias GnomeGarden.Agents.AgentEvalSweep
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspection
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspectionEval
  alias GnomeGarden.Procurement

  defmodule FakeLoginBrowser do
    def inspect_page(_url, _opts) do
      {:ok,
       %{
         final_url: "https://secure.example.com/login",
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
    end
  end

  defmodule FakeTimeoutBrowser do
    def inspect_page(_url, opts) do
      if Keyword.get(opts, :timeout_ms) == GnomeGarden.Agents.AgentEvalSweep.default_timeout_ms() do
        {:ok,
         %{
           final_url: "https://secure.example.com/login",
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
      else
        {:error, "expected default eval timeout"}
      end
    end
  end

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

  test "skips active cases that are not runnable" do
    {:ok, eval_case} = ProcurementSourceInspectionEval.ensure_case()

    assert {:ok, result} = AgentEvalSweep.run(eval_cases: [eval_case])

    assert result.attempted == 0
    assert result.skipped == 1
    assert [%{outcome: :skipped, eval_case_id: eval_case_id}] = result.results
    assert eval_case_id == eval_case.id
  end

  test "runs runnable cases and summarizes pass counts" do
    deployment = deployment_fixture()

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Eval Sweep Credential Portal",
        url: "https://secure.example.com/login",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, workflow_definition} = ProcurementSourceInspection.ensure_definition()

    {:ok, eval_case} =
      ProcurementSourceInspectionEval.ensure_case(
        key: "agent-eval-sweep-credentials",
        workflow_definition: workflow_definition,
        input: %{"source_id" => source.id, "deployment_id" => deployment.id},
        expected_output: %{"mode" => "credentials_needed"}
      )

    assert {:ok, result} = AgentEvalSweep.run(eval_cases: [eval_case], browser: FakeLoginBrowser)

    assert result.attempted == 1
    assert result.passed == 1
    assert result.failed == 0
    assert result.errored == 0
    assert result.skipped == 0

    assert [
             %{
               outcome: :passed,
               status: :passed,
               eval_run_id: eval_run_id,
               agent_run_id: agent_run_id
             }
           ] = result.results

    assert is_binary(eval_run_id)
    assert is_binary(agent_run_id)
  end

  test "applies a bounded default source inspection timeout" do
    deployment = deployment_fixture()

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Eval Sweep Timeout Portal",
        url: "https://secure.example.com/default-timeout",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, workflow_definition} = ProcurementSourceInspection.ensure_definition()

    {:ok, eval_case} =
      ProcurementSourceInspectionEval.ensure_case(
        key: "agent-eval-sweep-default-timeout",
        workflow_definition: workflow_definition,
        input: %{"source_id" => source.id, "deployment_id" => deployment.id},
        expected_output: %{"mode" => "credentials_needed"}
      )

    assert {:ok, result} =
             AgentEvalSweep.run(eval_cases: [eval_case], browser: FakeTimeoutBrowser)

    assert result.passed == 1
    assert [%{outcome: :passed}] = result.results
  end

  test "runs prepared procurement fixture cases through the sweep" do
    assert {:ok, prepared} =
             AgentEvalRunner.prepare_procurement_inspection_fixtures(
               fixture_base_url: "https://fixtures.example.com",
               deployment_name: "Eval Sweep Fixtures #{System.unique_integer([:positive])}"
             )

    assert {:ok, result} =
             AgentEvalSweep.run(eval_cases: prepared.eval_cases, browser: FakeFixtureBrowser)

    assert result.attempted == 3
    assert result.passed == 3
    assert result.failed == 0
    assert result.errored == 0
    assert result.skipped == 0

    assert result.results
           |> Enum.map(&{&1.eval_case_key, &1.outcome})
           |> Enum.sort() == [
             {"procurement-source-inspection.credentials-needed", :passed},
             {"procurement-source-inspection.irrelevant-page", :passed},
             {"procurement-source-inspection.public-bids", :passed}
           ]
  end

  defp deployment_fixture do
    _templates = Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Eval Sweep #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    deployment
  end
end
