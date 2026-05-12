defmodule GnomeGarden.Release do
  @moduledoc """
  Release-time database operations.

  Mix is not available inside assembled releases, so production deploys should
  call these functions through `bin/gnome_garden eval`.
  """

  @app :gnome_garden

  alias GnomeGarden.Agents.DefaultDeployments
  alias GnomeGarden.Commercial.DefaultCompanyProfiles

  @spec migrate() :: :ok
  def migrate do
    for repo <- repos() do
      {:ok, _migrations, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @spec rollback(module(), non_neg_integer()) :: :ok
  def rollback(repo \\ GnomeGarden.Repo, version) do
    {:ok, _migrations, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  @spec seed() :: :ok
  def seed do
    [repo | _repos] = repos()

    {:ok, _result, _apps} =
      Ecto.Migrator.with_repo(repo, fn _repo ->
        seed_data()
      end)

    :ok
  end

  @spec setup() :: :ok
  def setup do
    migrate()
    seed()
  end

  defp seed_data do
    company_profile = DefaultCompanyProfiles.ensure_default()
    deployments = DefaultDeployments.ensure_defaults()

    IO.puts("""
    Seeded release defaults.
    Agent deployments created: #{Enum.join(deployments.created, ", ")}
    Agent deployments existing: #{Enum.join(deployments.existing, ", ")}
    Company profile created: #{company_profile.created?}
    Company profile: #{company_profile.profile.name} (#{company_profile.profile.key})
    """)

    :ok
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
