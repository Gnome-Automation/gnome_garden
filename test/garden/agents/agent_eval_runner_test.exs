defmodule GnomeGarden.Agents.AgentEvalRunnerTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalRunner
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

  test "seeds known eval cases" do
    assert {:ok, eval_cases} = AgentEvalRunner.seed_known_cases()

    assert Enum.map(eval_cases, & &1.key) == [
             ProcurementSourceInspectionEval.case_key(),
             "procurement-source-inspection.public-bids",
             "procurement-source-inspection.irrelevant-page"
           ]

    assert Enum.all?(eval_cases, &(&1.workflow_key == ProcurementSourceInspection.workflow_key()))
  end

  test "refuses to run eval cases without explicit source and deployment input" do
    {:ok, eval_case} = ProcurementSourceInspectionEval.ensure_case()

    refute AgentEvalRunner.runnable?(eval_case)

    assert {:error, "Eval case input is missing source_id."} =
             AgentEvalRunner.run_case(eval_case)
  end

  test "prepares a runnable procurement source inspection fixture" do
    fixture_url = "https://secure.example.com/#{System.unique_integer([:positive])}/login"

    assert {:ok,
            %{
              eval_case: eval_case,
              source: source,
              deployment: deployment,
              workflow_definition: workflow_definition
            }} =
             AgentEvalRunner.prepare_procurement_inspection_fixture(
               source_url: fixture_url,
               deployment_name: "Eval Fixture #{System.unique_integer([:positive])}"
             )

    assert source.url == fixture_url
    refute source.enabled
    assert deployment.enabled == false
    assert workflow_definition.key == ProcurementSourceInspection.workflow_key()
    assert eval_case.input["source_id"] == source.id
    assert eval_case.input["deployment_id"] == deployment.id
    assert AgentEvalRunner.runnable?(eval_case)
  end

  test "prepares runnable procurement source inspection fixtures" do
    fixture_base_url = "https://fixtures.example.com"

    assert {:ok,
            %{
              eval_cases: eval_cases,
              fixtures: fixtures,
              deployment: deployment,
              workflow_definition: workflow_definition
            }} =
             AgentEvalRunner.prepare_procurement_inspection_fixtures(
               fixture_base_url: fixture_base_url,
               deployment_name: "Eval Fixtures #{System.unique_integer([:positive])}"
             )

    assert length(eval_cases) == 3
    assert length(fixtures) == 3
    assert deployment.enabled == false
    assert workflow_definition.key == ProcurementSourceInspection.workflow_key()

    assert Enum.map(eval_cases, & &1.key) == [
             ProcurementSourceInspectionEval.case_key(),
             "procurement-source-inspection.public-bids",
             "procurement-source-inspection.irrelevant-page"
           ]

    assert Enum.all?(eval_cases, &AgentEvalRunner.runnable?/1)
    assert Enum.all?(eval_cases, &(&1.input["deployment_id"] == deployment.id))

    assert Enum.map(fixtures, & &1.source.url) == [
             "https://fixtures.example.com/sign-in",
             "https://fixtures.example.com/eval-fixtures/procurement/public-bids",
             "https://fixtures.example.com/eval-fixtures/procurement/irrelevant"
           ]
  end

  test "prepares and runs the procurement source inspection fixture" do
    fixture_url = "https://secure.example.com/#{System.unique_integer([:positive])}/login"

    assert {:ok, %{eval_case: eval_case, run_result: %{eval_run: eval_run, failures: []}}} =
             AgentEvalRunner.prepare_and_run_procurement_inspection_fixture(
               source_url: fixture_url,
               deployment_name: "Eval Local Check #{System.unique_integer([:positive])}",
               browser: FakeLoginBrowser
             )

    assert AgentEvalRunner.runnable?(eval_case)
    assert eval_run.status == :passed
    assert eval_run.output_snapshot["mode"] == "credentials_needed"
  end

  test "prepares and runs all procurement source inspection fixtures" do
    assert {:ok, %{eval_cases: eval_cases, sweep_result: result}} =
             AgentEvalRunner.prepare_and_run_procurement_inspection_fixtures(
               fixture_base_url: "https://fixtures.example.com",
               deployment_name: "Eval Local Checks #{System.unique_integer([:positive])}",
               browser: FakeFixtureBrowser
             )

    assert length(eval_cases) == 3
    assert result.attempted == 3
    assert result.passed == 3
    assert result.failed == 0
    assert result.errored == 0
    assert result.skipped == 0

    assert Enum.map(result.results, & &1.eval_case_key) == [
             ProcurementSourceInspectionEval.case_key(),
             "procurement-source-inspection.public-bids",
             "procurement-source-inspection.irrelevant-page"
           ]
  end

  test "dispatches runnable procurement source inspection eval case by id" do
    deployment = deployment_fixture()

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Eval Runner Credential Portal",
        url: "https://secure.example.com/login",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, workflow_definition} = ProcurementSourceInspection.ensure_definition()

    {:ok, eval_case} =
      ProcurementSourceInspectionEval.ensure_case(
        key: "agent-eval-runner-credentials",
        workflow_definition: workflow_definition,
        input: %{"source_id" => source.id, "deployment_id" => deployment.id},
        expected_output: %{"mode" => "credentials_needed"}
      )

    assert AgentEvalRunner.runnable?(eval_case)

    assert {:ok, %{eval_run: eval_run, agent_run: agent_run, failures: []}} =
             AgentEvalRunner.run_case(eval_case.id, browser: FakeLoginBrowser)

    assert eval_run.status == :passed
    assert eval_run.agent_run_id == agent_run.id
    assert eval_run.output_snapshot["mode"] == "credentials_needed"
  end

  defp deployment_fixture do
    _templates = Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Eval Runner #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    deployment
  end
end
