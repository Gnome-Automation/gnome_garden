defmodule GnomeGarden.Agents.LlmRoutingTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Templates
  alias GnomeGarden.Agents.Workers.Coder

  test "coding alias resolves to ReqLLM Z.AI Coding Plan provider" do
    model = Jido.AI.resolve_model(:coding)

    assert model == "zai_coding_plan:glm-4.7"
    assert {:ok, %{provider: :zai_coding_plan, id: "glm-4.7"}} = ReqLLM.model(model)
    assert {:ok, ReqLLM.Providers.ZaiCodingPlan} = ReqLLM.provider(:zai_coding_plan)
    assert ReqLLM.Keys.env_var_name(:zai_coding_plan) == "ZAI_API_KEY"
  end

  test "standard Z.AI provider uses ReqLLM built-in provider" do
    assert {:ok, ReqLLM.Providers.Zai} = ReqLLM.provider(:zai)
  end

  test "coder template and worker use the coding model alias" do
    assert {:ok, %{model: :coding}} = Templates.get("coder")
    assert Keyword.fetch!(Coder.strategy_opts(), :model) == :coding
  end
end
