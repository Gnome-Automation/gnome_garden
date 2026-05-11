defmodule Mix.Tasks.GnomeGarden.ProdCheck do
  @moduledoc """
  Checks production environment variables before building or deploying.

      MIX_ENV=prod mix gnome_garden.prod_check

  The task intentionally checks only external configuration that must be set in
  the deployment environment. Database migrations, route reachability, and
  storage connectivity are still verified by the release/deploy process.
  """

  use Mix.Task

  @shortdoc "Check production readiness environment variables"

  @required_env [
    "DATABASE_URL",
    "SECRET_KEY_BASE",
    "PHX_HOST",
    "TOKEN_SIGNING_SECRET",
    "PI_SERVICE_TOKEN",
    "MERCURY_WEBHOOK_SECRET",
    "GARAGE_ACCESS_KEY",
    "GARAGE_SECRET_KEY",
    "GARAGE_BUCKET",
    "GARAGE_ENDPOINT_URL"
  ]

  @optional_agent_env [
    "ZAI_API_KEY",
    "BRAVE_API_KEY"
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Checking production environment...")

    missing_required =
      @required_env
      |> Enum.reject(&present_env?/1)
      |> maybe_allow_local_storage()

    missing_optional = Enum.reject(@optional_agent_env, &present_env?/1)

    if missing_required == [] do
      Mix.shell().info("Required production environment is present.")
      report_optional(missing_optional)
    else
      Mix.raise("""
      Missing required production environment:
      #{Enum.map_join(missing_required, "\n", &"  - #{&1}")}
      """)
    end
  end

  defp present_env?(name) do
    case System.get_env(name) do
      nil -> false
      "" -> false
      _value -> true
    end
  end

  defp maybe_allow_local_storage(missing_required) do
    if System.get_env("ALLOW_LOCAL_STORAGE_IN_PROD") == "true" do
      missing_required --
        ["GARAGE_ACCESS_KEY", "GARAGE_SECRET_KEY", "GARAGE_BUCKET", "GARAGE_ENDPOINT_URL"]
    else
      missing_required
    end
  end

  defp report_optional([]), do: :ok

  defp report_optional(missing_optional) do
    Mix.shell().info("""
    Optional agent/search environment not set:
    #{Enum.map_join(missing_optional, "\n", &"  - #{&1}")}
    """)
  end
end
