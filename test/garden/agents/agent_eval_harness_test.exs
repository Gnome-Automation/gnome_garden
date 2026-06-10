defmodule GnomeGarden.Agents.AgentEvalHarnessTest do
  use GnomeGarden.DataCase

  alias GnomeGarden.Agents
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

  test "creates eval cases and records eval run lifecycle" do
    {:ok, eval_case} =
      Agents.create_agent_eval_case(%{
        key: "source-login-detection",
        name: "Source login detection",
        workflow_key: ProcurementSourceInspection.workflow_key(),
        input: %{"source_url" => "https://secure.example.com/login"},
        expected_output: %{"mode" => "credentials_needed"},
        expected_actions: ["source.inspect"],
        forbidden_actions: ["GnomeGarden.Procurement.delete_procurement_source"],
        tags: ["procurement", "credentials"]
      })

    assert eval_case.status == :active

    assert {:ok, run} =
             Agents.create_agent_eval_run(%{
               eval_case_id: eval_case.id,
               input_snapshot: eval_case.input
             })

    assert run.status == :pending

    assert {:ok, running} = Agents.start_agent_eval_run(run)
    assert running.status == :running
    assert running.started_at

    assert {:ok, passed} =
             Agents.pass_agent_eval_run(running, %{
               output_snapshot: %{"mode" => "credentials_needed"},
               observed_actions: ["source.inspect"],
               score: Decimal.new("1.0"),
               reviewer_notes: "Fixture matched expected credential blocker."
             })

    assert passed.status == :passed
    assert passed.completed_at
    assert passed.score == Decimal.new("1.0")
  end

  test "runs fixture-backed procurement workflow eval through the eval runner" do
    deployment = deployment_fixture()

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Eval Credential Portal",
        url: "https://secure.example.com/login",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, workflow_definition} = ProcurementSourceInspection.ensure_definition()

    assert {:ok, eval_case} =
             ProcurementSourceInspectionEval.ensure_case(workflow_definition: workflow_definition)

    assert {:ok, %{eval_run: eval_run, agent_run: agent_run, failures: []}} =
             ProcurementSourceInspectionEval.run_case(eval_case,
               source: source,
               deployment_id: deployment.id,
               workflow_definition: workflow_definition,
               browser: FakeLoginBrowser
             )

    assert eval_run.status == :passed
    assert eval_run.agent_run_id == agent_run.id
    assert eval_run.output_snapshot["mode"] == "credentials_needed"
    assert eval_run.output_snapshot["pipeline"]["requires_login"] == true
    assert eval_run.observed_actions == ["source.inspect"]
    assert eval_run.score == Decimal.new("1.0")
  end

  test "records fixture-backed procurement workflow eval failures" do
    deployment = deployment_fixture()

    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Eval Mismatch Portal",
        url: "https://secure.example.com/login",
        source_type: :custom,
        region: :oc,
        priority: :medium,
        status: :approved
      })

    {:ok, workflow_definition} = ProcurementSourceInspection.ensure_definition()

    assert {:ok, eval_case} =
             ProcurementSourceInspectionEval.ensure_case(
               key: "procurement-source-inspection-mismatch",
               workflow_definition: workflow_definition,
               expected_output: %{"mode" => "inspected"}
             )

    assert {:ok, %{eval_run: eval_run, failures: failures}} =
             ProcurementSourceInspectionEval.run_case(eval_case,
               source: source,
               deployment_id: deployment.id,
               workflow_definition: workflow_definition,
               browser: FakeLoginBrowser
             )

    assert eval_run.status == :failed
    assert eval_run.output_snapshot["mode"] == "credentials_needed"
    assert eval_run.score == Decimal.new("0.0")
    assert Enum.any?(failures, &(&1 =~ "Expected mode"))
  end

  defp deployment_fixture do
    _templates = Agents.TemplateCatalog.sync_templates()
    {:ok, template} = Agents.get_agent_template_by_name("procurement_source_scan")

    {:ok, deployment} =
      Agents.create_agent_deployment(%{
        name: "Eval Harness #{System.unique_integer([:positive])}",
        agent_id: template.id,
        enabled: true
      })

    deployment
  end
end
