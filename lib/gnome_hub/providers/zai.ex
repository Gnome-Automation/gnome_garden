defmodule GnomeHub.Providers.Zai do
  @moduledoc """
  Z.AI (Zhipu AI) provider - OpenAI-compatible Chat Completions API.

  Z.AI provides the GLM model family (GLM-4, GLM-4.7, GLM-5, etc.).
  The API is OpenAI-compatible at https://open.bigmodel.cn/api/paas/v4

  ## Configuration

      # Set your Z.AI API key
      ZAI_API_KEY=your-api-key

  ## Examples

      ReqLLM.generate_text("zai:glm-4.7", "Hello!")
      ReqLLM.generate_text("zai:glm-5", "Write code...")

  ## Available Models

  - glm-5 (flagship, 745B MoE, 200K context)
  - glm-5-turbo (agent-focused)
  - glm-4.7 (reasoning, 200K context)
  - glm-4.7-flash (fast, efficient)
  - glm-4.6 (200K context)
  - glm-4.5v (vision)
  """

  use ReqLLM.Provider,
    id: :zai,
    default_base_url: "https://open.bigmodel.cn/api/paas/v4",
    default_env_key: "ZAI_API_KEY"

  use ReqLLM.Provider.Defaults

  @provider_schema []
end
