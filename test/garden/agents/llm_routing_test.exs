defmodule GnomeGarden.Agents.LlmRoutingTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Agents.Templates

  test "ReqLLM uses Z.AI Coding Plan provider for coding models" do
    assert {:ok, %{provider: :zai_coding_plan, id: "glm-4.7"}} =
             ReqLLM.model("zai_coding_plan:glm-4.7")

    assert {:ok, ReqLLM.Providers.ZaiCodingPlan} = ReqLLM.provider(:zai_coding_plan)
    assert ReqLLM.Keys.env_var_name(:zai_coding_plan) == "ZAI_API_KEY"
  end

  test "standard Z.AI provider uses ReqLLM built-in provider" do
    assert {:ok, ReqLLM.Providers.Zai} = ReqLLM.provider(:zai)
  end

  test "only direct automation templates are registered" do
    assert {:ok, %{module: GnomeGarden.Agents.Workers.Procurement.SourceScan}} =
             Templates.get("procurement_source_scan")

    assert {:error, _} = Templates.get("coder")
  end
end
