defmodule GnomeGarden.Agents.AgentEvalRunner do
  @moduledoc """
  Dispatches governed agent evaluation cases to their workflow-specific runner.

  The runner is intentionally narrow. It only executes cases whose workflow key
  has a registered implementation and whose persisted input includes the
  business record IDs required by that implementation.
  """

  alias GnomeGarden.Agents
  alias GnomeGarden.Agents.AgentEvalCase
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspection
  alias GnomeGarden.Agents.WorkflowRunners.ProcurementSourceInspectionEval
  alias GnomeGarden.Procurement

  @procurement_fixture_deployment_name "Procurement Inspection Eval Fixture"

  @spec seed_known_cases(keyword()) :: {:ok, [AgentEvalCase.t()]} | {:error, term()}
  def seed_known_cases(opts \\ []) do
    ProcurementSourceInspectionEval.ensure_known_cases(opts)
  end

  @spec prepare_procurement_inspection_fixture(keyword()) ::
          {:ok, map()} | {:error, term()}
  def prepare_procurement_inspection_fixture(opts \\ []) do
    prepare_procurement_inspection_fixture(
      List.first(ProcurementSourceInspectionEval.case_definitions()),
      opts
    )
  end

  @spec prepare_procurement_inspection_fixtures(keyword()) ::
          {:ok, map()} | {:error, term()}
  def prepare_procurement_inspection_fixtures(opts \\ []) do
    with {:ok, workflow_definition} <- ProcurementSourceInspection.ensure_definition(opts),
         {:ok, deployment} <-
           ensure_procurement_fixture_deployment(opts, Keyword.get(opts, :actor)) do
      prepare_fixture_cases(
        ProcurementSourceInspectionEval.case_definitions(),
        workflow_definition,
        deployment,
        opts
      )
    end
  end

  defp prepare_procurement_inspection_fixture(definition, opts) do
    actor = Keyword.get(opts, :actor)

    with {:ok, workflow_definition} <- ProcurementSourceInspection.ensure_definition(opts),
         {:ok, source} <- ensure_procurement_fixture_source(definition, opts, actor),
         {:ok, deployment} <- ensure_procurement_fixture_deployment(opts, actor),
         {:ok, eval_case} <-
           ProcurementSourceInspectionEval.ensure_case(
             Keyword.merge(opts,
               workflow_definition: workflow_definition,
               definition: definition,
               input: %{
                 "source_fixture" => definition.fixture_key,
                 "expected_mode" => definition.expected_output["mode"],
                 "source_id" => source.id,
                 "deployment_id" => deployment.id
               },
               expected_output: definition.expected_output
             )
           ) do
      {:ok,
       %{
         eval_case: eval_case,
         source: source,
         deployment: deployment,
         workflow_definition: workflow_definition
       }}
    end
  end

  defp prepare_fixture_cases(definitions, workflow_definition, deployment, opts) do
    actor = Keyword.get(opts, :actor)

    definitions
    |> Enum.reduce_while({:ok, []}, fn definition, {:ok, prepared_fixtures} ->
      with {:ok, source} <- ensure_procurement_fixture_source(definition, opts, actor),
           {:ok, eval_case} <-
             ProcurementSourceInspectionEval.ensure_case(
               Keyword.merge(opts,
                 workflow_definition: workflow_definition,
                 definition: definition,
                 input: %{
                   "source_fixture" => definition.fixture_key,
                   "expected_mode" => definition.expected_output["mode"],
                   "source_id" => source.id,
                   "deployment_id" => deployment.id
                 },
                 expected_output: definition.expected_output
               )
             ) do
        prepared = %{
          eval_case: eval_case,
          source: source,
          deployment: deployment,
          workflow_definition: workflow_definition
        }

        {:cont, {:ok, [prepared | prepared_fixtures]}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, prepared_fixtures} ->
        {:ok,
         %{
           eval_cases: prepared_fixtures |> Enum.reverse() |> Enum.map(& &1.eval_case),
           fixtures: Enum.reverse(prepared_fixtures),
           deployment: deployment,
           workflow_definition: workflow_definition
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec prepare_and_run_procurement_inspection_fixture(keyword()) ::
          {:ok, map()} | {:error, term()}
  def prepare_and_run_procurement_inspection_fixture(opts \\ []) do
    with {:ok, prepared} <- prepare_procurement_inspection_fixture(opts),
         {:ok, run_result} <- run_case(prepared.eval_case, opts) do
      {:ok, Map.put(prepared, :run_result, run_result)}
    end
  end

  @spec prepare_and_run_procurement_inspection_fixtures(keyword()) ::
          {:ok, map()} | {:error, term()}
  def prepare_and_run_procurement_inspection_fixtures(opts \\ []) do
    with {:ok, prepared} <- prepare_procurement_inspection_fixtures(opts),
         {:ok, sweep_result} <-
           GnomeGarden.Agents.AgentEvalSweep.run(
             Keyword.put(opts, :eval_cases, prepared.eval_cases)
           ) do
      {:ok, Map.put(prepared, :sweep_result, sweep_result)}
    end
  end

  @spec run_case(Ecto.UUID.t() | AgentEvalCase.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_case(eval_case_or_id, opts \\ [])

  def run_case(%AgentEvalCase{} = eval_case, opts) do
    with :ok <- ensure_supported_runner(eval_case),
         {:ok, runner_opts} <- runner_opts(eval_case) do
      ProcurementSourceInspectionEval.run_case(eval_case, Keyword.merge(runner_opts, opts))
    end
  end

  def run_case(eval_case_id, opts) when is_binary(eval_case_id) do
    actor = Keyword.get(opts, :actor)

    with {:ok, eval_case} <- Agents.get_agent_eval_case(eval_case_id, actor: actor) do
      run_case(eval_case, opts)
    end
  end

  @spec runnable?(AgentEvalCase.t()) :: boolean()
  def runnable?(%AgentEvalCase{workflow_key: workflow_key, input: input}) when is_map(input) do
    workflow_key == ProcurementSourceInspection.workflow_key() &&
      present?(input_value(input, "source_id")) &&
      present?(input_value(input, "deployment_id"))
  end

  def runnable?(_eval_case), do: false

  defp ensure_supported_runner(%AgentEvalCase{workflow_key: workflow_key}) do
    if workflow_key == ProcurementSourceInspection.workflow_key() do
      :ok
    else
      {:error, "No eval runner is registered for #{workflow_key}."}
    end
  end

  defp runner_opts(%AgentEvalCase{input: input}) when is_map(input) do
    with {:ok, source_id} <- required_input(input, "source_id"),
         {:ok, deployment_id} <- required_input(input, "deployment_id") do
      {:ok, [source_id: source_id, deployment_id: deployment_id]}
    end
  end

  defp runner_opts(_eval_case),
    do: {:error, "Eval case input must include source_id and deployment_id."}

  defp required_input(input, key) do
    case input_value(input, key) do
      nil -> {:error, "Eval case input is missing #{key}."}
      value -> {:ok, value}
    end
  end

  defp input_value(input, "source_id"),
    do: Map.get(input, "source_id") || Map.get(input, :source_id)

  defp input_value(input, "deployment_id"),
    do: Map.get(input, "deployment_id") || Map.get(input, :deployment_id)

  defp present?(value), do: is_binary(value) and value != ""

  defp ensure_procurement_fixture_source(definition, opts, actor) do
    url = fixture_source_url(definition, opts)

    cond do
      not present?(url) ->
        {:error,
         "Procurement inspection eval fixture requires :source_url, :source_urls, or :fixture_base_url."}

      match?({:ok, _source}, Procurement.get_procurement_source_by_url(url, actor: actor)) ->
        Procurement.get_procurement_source_by_url(url, actor: actor)

      true ->
        Procurement.create_procurement_source(
          %{
            name: source_name(definition, opts),
            url: url,
            source_type: :custom,
            region: :oc,
            priority: :low,
            status: :approved,
            enabled: false,
            requires_login: false,
            metadata: %{
              "eval_fixture" => true,
              "fixture_key" => definition.fixture_key,
              "eval_case_key" => definition.key
            },
            notes:
              "Disabled local fixture used by the procurement source inspection eval harness."
          },
          actor: actor
        )
    end
  end

  defp ensure_procurement_fixture_deployment(opts, actor) do
    name = Keyword.get(opts, :deployment_name, @procurement_fixture_deployment_name)

    case Agents.get_agent_deployment_by_name(name, actor: actor) do
      {:ok, deployment} ->
        {:ok, deployment}

      {:error, _error} ->
        create_procurement_fixture_deployment(name, opts, actor)
    end
  end

  defp create_procurement_fixture_deployment(name, opts, actor) do
    _templates = Agents.TemplateCatalog.sync_templates()

    with {:ok, template} <-
           Agents.get_agent_template_by_name("procurement_source_scan", actor: actor) do
      Agents.create_agent_deployment(
        %{
          name: name,
          description:
            "Disabled deployment used by runnable procurement inspection eval fixtures.",
          visibility: :system,
          enabled: false,
          config: %{"eval_fixture" => true},
          source_scope: %{"fixture_key" => ProcurementSourceInspectionEval.case_key()},
          memory_namespace:
            Keyword.get(opts, :memory_namespace, "eval.procurement_source_inspection"),
          agent_id: template.id
        },
        actor: actor
      )
    end
  end

  defp fixture_source_url(definition, opts) do
    source_urls = Keyword.get(opts, :source_urls, %{})

    cond do
      is_map(source_urls) and is_binary(source_urls[definition.key]) ->
        source_urls[definition.key]

      is_binary(Keyword.get(opts, :fixture_base_url)) ->
        URI.merge(Keyword.fetch!(opts, :fixture_base_url), definition.fixture_path)
        |> URI.to_string()

      definition.key == ProcurementSourceInspectionEval.case_key() ->
        Keyword.get(opts, :source_url)

      true ->
        nil
    end
  end

  defp source_name(definition, opts) do
    if definition.key == ProcurementSourceInspectionEval.case_key() do
      Keyword.get(opts, :source_name, definition.source_name)
    else
      definition.source_name
    end
  end
end
