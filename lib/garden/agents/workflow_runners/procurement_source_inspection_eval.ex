defmodule GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspectionEval do
  @moduledoc """
  Evaluation runner for the procurement source inspection workflow.

  The eval runner keeps test-case ownership in `AgentEvalCase` and records every
  execution in `AgentEvalRun`. It does not create business fixtures; callers
  provide the source and deployment to keep production data setup explicit.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalCase
  alias GnomeGarden.Agents.AgentWorkflowDefinition
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspection
  alias GnomeGarden.Procurement

  @case_key "procurement-source-inspection.credentials-needed"
  @case_definitions [
    %{
      key: @case_key,
      name: "Procurement source inspection: credentials needed",
      description: "Fixture-backed eval for a credential-gated procurement source.",
      fixture_key: "credential_login_portal",
      fixture_path: "/sign-in",
      source_name: "Local Sign-in Eval Fixture",
      expected_output: %{
        "mode" => "credentials_needed",
        "requires_login" => true,
        "pipeline" => %{
          "password_inputs" => 1,
          "public_listing_links" => 0
        }
      },
      tags: ["procurement", "workflow", "credentials"]
    },
    %{
      key: "procurement-source-inspection.public-bids",
      name: "Procurement source inspection: public bid listing",
      description: "Fixture-backed eval for a public bid listing with a non-gating login link.",
      fixture_key: "public_bid_listing",
      fixture_path: "/eval-fixtures/procurement/public-bids",
      source_name: "Local Public Bid Listing Eval Fixture",
      expected_output: %{
        "mode" => "inspected",
        "requires_login" => false,
        "pipeline" => %{
          "candidate_links" => 2,
          "public_listing_links" => 2
        }
      },
      tags: ["procurement", "workflow", "public_listing"]
    },
    %{
      key: "procurement-source-inspection.irrelevant-page",
      name: "Procurement source inspection: irrelevant page",
      description: "Fixture-backed eval for a public page with no procurement opportunities.",
      fixture_key: "irrelevant_public_page",
      fixture_path: "/eval-fixtures/procurement/irrelevant",
      source_name: "Local Irrelevant Page Eval Fixture",
      expected_output: %{
        "mode" => "inspected",
        "requires_login" => false,
        "pipeline" => %{
          "candidate_links" => 0,
          "public_listing_links" => 0,
          "procurement_evidence" => false
        }
      },
      tags: ["procurement", "workflow", "false_positive_control"]
    }
  ]

  @spec case_key() :: String.t()
  def case_key, do: @case_key

  def case_definitions, do: @case_definitions

  @spec ensure_known_cases(keyword()) :: {:ok, [AgentEvalCase.t()]} | {:error, term()}
  def ensure_known_cases(opts \\ []) do
    with {:ok, workflow_definition} <- fetch_workflow_definition(opts) do
      @case_definitions
      |> Enum.reduce_while({:ok, []}, fn definition, {:ok, eval_cases} ->
        case ensure_case(
               Keyword.merge(opts,
                 workflow_definition: workflow_definition,
                 definition: definition
               )
             ) do
          {:ok, eval_case} -> {:cont, {:ok, [eval_case | eval_cases]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, eval_cases} -> {:ok, Enum.reverse(eval_cases)}
        {:error, error} -> {:error, error}
      end
    end
  end

  @spec ensure_case(keyword()) :: {:ok, AgentEvalCase.t()} | {:error, term()}
  def ensure_case(opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, workflow_definition} <- fetch_workflow_definition(opts) do
      attrs = default_case_attrs(workflow_definition, opts)

      case Agents.get_agent_eval_case_by_key(attrs.key, actor: actor) do
        {:ok, %AgentEvalCase{} = eval_case} ->
          Agents.update_agent_eval_case(eval_case, attrs, actor: actor)

        {:error, _error} ->
          Agents.create_agent_eval_case(attrs, actor: actor)
      end
    end
  end

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) do
    with {:ok, eval_case} <- ensure_case(opts) do
      run_case(eval_case, opts)
    end
  end

  @spec run_case(AgentEvalCase.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_case(%AgentEvalCase{} = eval_case, opts) do
    actor = Keyword.get(opts, :actor)

    with {:ok, workflow_definition} <- fetch_workflow_definition(eval_case, opts),
         {:ok, source} <- fetch_source(eval_case, opts, actor),
         {:ok, eval_run} <- create_eval_run(eval_case, workflow_definition, source, opts, actor),
         {:ok, running_eval_run} <- Agents.start_agent_eval_run(eval_run, actor: actor) do
      execute_and_record(running_eval_run, eval_case, workflow_definition, source, opts, actor)
    end
  end

  defp fetch_workflow_definition(opts) do
    case Keyword.get(opts, :workflow_definition) do
      %AgentWorkflowDefinition{} = definition -> {:ok, definition}
      _other -> ProcurementSourceInspection.ensure_definition(opts)
    end
  end

  defp fetch_workflow_definition(eval_case, opts) do
    case Keyword.get(opts, :workflow_definition) do
      %AgentWorkflowDefinition{} = definition ->
        {:ok, definition}

      _other ->
        case eval_case.workflow_definition_id do
          nil -> ProcurementSourceInspection.ensure_definition(opts)
          id -> Agents.get_agent_workflow_definition(id, actor: Keyword.get(opts, :actor))
        end
    end
  end

  defp default_case_attrs(workflow_definition, opts) do
    definition = Keyword.get(opts, :definition, List.first(@case_definitions))
    expected_output = Keyword.get(opts, :expected_output, definition.expected_output)

    %{
      key: Keyword.get(opts, :key, definition.key),
      name: Keyword.get(opts, :name, definition.name),
      description: Keyword.get(opts, :description, definition.description),
      workflow_key: workflow_definition.key,
      workflow_definition_id: workflow_definition.id,
      input:
        Keyword.get(opts, :input, %{
          "source_fixture" => definition.fixture_key,
          "expected_mode" => expected_output["mode"] || expected_output[:mode]
        }),
      expected_output: expected_output,
      expected_actions: Keyword.get(opts, :expected_actions, ["source.inspect"]),
      forbidden_actions:
        Keyword.get(opts, :forbidden_actions, [
          "GnomeGarden.Procurement.delete_procurement_source",
          "GnomeGarden.Procurement.scan_procurement_source"
        ]),
      tags: Keyword.get(opts, :tags, definition.tags),
      status: :active,
      metadata:
        Keyword.get(opts, :metadata, %{
          "runner" => inspect(__MODULE__),
          "workflow_definition_version" => workflow_definition.version
        })
    }
  end

  defp fetch_source(_eval_case, opts, _actor) do
    case Keyword.fetch(opts, :source) do
      {:ok, %{id: _id} = source} -> {:ok, source}
      :error -> fetch_source_by_id(opts)
    end
  end

  defp fetch_source_by_id(opts) do
    actor = Keyword.get(opts, :actor)

    case Keyword.fetch(opts, :source_id) do
      {:ok, source_id} -> Procurement.get_procurement_source(source_id, actor: actor)
      :error -> {:error, "Procurement source inspection eval requires :source or :source_id."}
    end
  end

  defp create_eval_run(eval_case, workflow_definition, source, opts, actor) do
    Agents.create_agent_eval_run(
      %{
        eval_case_id: eval_case.id,
        workflow_definition_id: workflow_definition.id,
        input_snapshot: input_snapshot(eval_case, source, opts),
        metadata: %{
          "runner" => inspect(__MODULE__),
          "workflow_key" => workflow_definition.key,
          "workflow_version" => workflow_definition.version
        }
      },
      actor: actor
    )
  end

  defp input_snapshot(eval_case, source, opts) do
    eval_case.input
    |> Kernel.||(%{})
    |> Map.put("source_id", source.id)
    |> Map.put("deployment_id", Keyword.get(opts, :deployment_id))
  end

  defp execute_and_record(eval_run, eval_case, workflow_definition, source, opts, actor) do
    workflow_opts =
      opts
      |> Keyword.drop([:source, :source_id, :key, :name, :description, :expected_output])
      |> Keyword.put(:workflow_definition, workflow_definition)

    case ProcurementSourceInspection.execute(source, workflow_opts) do
      {:ok, %{run: agent_run, result: result}} ->
        record_result(eval_run, eval_case, agent_run, result, actor)

      {:error, agent_run, reason} ->
        record_error(eval_run, agent_run, reason, actor)

      {:error, reason} ->
        record_error(eval_run, nil, reason, actor)
    end
  end

  defp record_result(eval_run, eval_case, agent_run, result, actor) do
    output_snapshot = output_snapshot(agent_run, result)
    observed_actions = observed_actions(result, output_snapshot)

    forbidden_action_hits =
      Enum.filter(eval_case.forbidden_actions || [], &(&1 in observed_actions))

    failures =
      expectation_failures(eval_case, output_snapshot, observed_actions, forbidden_action_hits)

    attrs = %{
      agent_run_id: agent_run.id,
      output_snapshot: output_snapshot,
      observed_actions: observed_actions,
      score: score(failures),
      reviewer_notes: reviewer_notes(failures),
      metadata: %{"evaluated_by" => inspect(__MODULE__)}
    }

    if failures == [] do
      with {:ok, passed} <- Agents.pass_agent_eval_run(eval_run, attrs, actor: actor) do
        {:ok, %{eval_run: passed, agent_run: agent_run, failures: []}}
      end
    else
      attrs = Map.put(attrs, :forbidden_action_hits, forbidden_action_hits)

      with {:ok, failed} <- Agents.fail_agent_eval_run(eval_run, attrs, actor: actor) do
        {:ok, %{eval_run: failed, agent_run: agent_run, failures: failures}}
      end
    end
  end

  defp record_error(eval_run, agent_run, reason, actor) do
    attrs = %{
      agent_run_id: agent_run && agent_run.id,
      output_snapshot: %{"error" => error_message(reason)},
      reviewer_notes: "Workflow execution errored: #{error_message(reason)}",
      metadata: %{"evaluated_by" => inspect(__MODULE__)}
    }

    with {:ok, errored} <- Agents.error_agent_eval_run(eval_run, attrs, actor: actor) do
      {:ok, %{eval_run: errored, agent_run: agent_run, failures: [attrs.reviewer_notes]}}
    end
  end

  defp output_snapshot(agent_run, result) do
    pipeline =
      result
      |> Map.get(:pipeline, %{})
      |> stringify_keys()

    (agent_run.result_summary || %{})
    |> stringify_keys()
    |> Map.put("agent_run_id", agent_run.id)
    |> Map.put("pipeline", pipeline)
  end

  defp observed_actions(result, output_snapshot) do
    if Map.get(result, :pipeline) || output_snapshot["mode"] do
      ["source.inspect"]
    else
      []
    end
  end

  defp expectation_failures(eval_case, output_snapshot, observed_actions, forbidden_action_hits) do
    output_failures =
      eval_case.expected_output
      |> Kernel.||(%{})
      |> Enum.flat_map(fn {key, expected} ->
        actual = value(output_snapshot, key)

        if equivalent?(actual, expected) do
          []
        else
          ["Expected #{key} to be #{inspect(expected)}, got #{inspect(actual)}."]
        end
      end)

    missing_actions = (eval_case.expected_actions || []) -- observed_actions

    action_failures =
      Enum.map(missing_actions, &"Expected action #{&1} was not observed.")

    forbidden_failures =
      Enum.map(forbidden_action_hits, &"Forbidden action #{&1} was observed.")

    output_failures ++ action_failures ++ forbidden_failures
  end

  defp score([]), do: Decimal.new("1.0")
  defp score(_failures), do: Decimal.new("0.0")

  defp reviewer_notes([]), do: "Eval matched expected workflow behavior."
  defp reviewer_notes(failures), do: Enum.join(failures, " ")

  defp equivalent?(actual, expected) when is_map(actual) and is_map(expected) do
    Enum.all?(expected, fn {key, expected_value} ->
      actual
      |> value(key)
      |> equivalent?(expected_value)
    end)
  end

  defp equivalent?(actual, expected), do: stringify_scalar(actual) == stringify_scalar(expected)

  defp stringify_scalar(value) when is_boolean(value), do: value
  defp stringify_scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_scalar(value), do: value

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp value(map, key) when is_map(map) do
    with :error <- Map.fetch(map, to_string(key)),
         :error <- Map.fetch(map, key) do
      nil
    else
      {:ok, value} -> value
    end
  end

  defp error_message(error) when is_binary(error), do: error

  defp error_message(%{__struct__: _} = error) do
    Exception.message(error)
  rescue
    Protocol.UndefinedError -> inspect(error)
  end

  defp error_message(error), do: inspect(error)
end
