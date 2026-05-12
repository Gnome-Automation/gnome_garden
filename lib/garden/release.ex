defmodule GnomeGarden.Release do
  @moduledoc """
  Release-time database operations.

  Mix is not available inside assembled releases, so production deploys should
  call these functions through `bin/gnome_garden eval`.
  """

  @app :gnome_garden

  alias GnomeGarden.Agents.DefaultDeployments
  alias GnomeGarden.Accounts
  alias GnomeGarden.Commercial.DefaultCompanyProfiles
  alias GnomeGarden.Operations

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

  @spec bootstrap_admins() :: :ok
  def bootstrap_admins do
    [repo | _repos] = repos()

    {:ok, _result, _apps} =
      Ecto.Migrator.with_repo(repo, fn _repo ->
        pc = ensure_admin!("PC", "GARDEN_ADMIN_PC")
        bhammoud = ensure_admin!("Bhammoud", "GARDEN_ADMIN_BHAMMOUD")

        IO.puts("""
        Bootstrapped Garden admin accounts.
        Admin: #{pc.display_name} <#{pc.email}>
        Admin: #{bhammoud.display_name} <#{bhammoud.email}>
        """)

        :ok
      end)

    :ok
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

  defp ensure_admin!(default_display_name, env_prefix) do
    email = fetch_env!("#{env_prefix}_EMAIL")
    password = fetch_env!("#{env_prefix}_PASSWORD")
    display_name = System.get_env("#{env_prefix}_DISPLAY_NAME", default_display_name)

    user = ensure_user_password!(email, password)
    team_member = ensure_admin_team_member!(user, display_name)

    %{email: email, display_name: team_member.display_name}
  end

  defp ensure_user_password!(email, password) do
    params = %{
      email: email,
      password: password,
      password_confirmation: password
    }

    case Accounts.get_user_by_email(email, authorize?: false) do
      {:ok, user} ->
        {:ok, user} =
          Accounts.set_user_password(user, Map.take(params, [:password, :password_confirmation]),
            authorize?: false
          )

        user

      {:error, error} ->
        if not_found_error?(error) do
          {:ok, user} = Accounts.create_user_with_password(params, authorize?: false)
          user
        else
          raise "Failed to load admin user #{email}: #{Exception.message(error)}"
        end
    end
  end

  defp ensure_admin_team_member!(user, display_name) do
    params = %{
      user_id: user.id,
      display_name: display_name,
      role: :admin,
      status: :active
    }

    case Operations.get_team_member_by_user(user.id) do
      {:ok, team_member} ->
        {:ok, team_member} = Operations.update_team_member(team_member, params)
        team_member

      {:error, error} ->
        if not_found_error?(error) do
          {:ok, team_member} = Operations.create_team_member(params)
          team_member
        else
          raise "Failed to load admin team member for #{user.email}: #{Exception.message(error)}"
        end
    end
  end

  defp not_found_error?(%Ash.Error.Query.NotFound{}), do: true

  defp not_found_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1))
  end

  defp not_found_error?(_error), do: false

  defp fetch_env!(name) do
    case System.fetch_env(name) do
      {:ok, value} when value != "" -> value
      _ -> raise "Missing required environment variable #{name}"
    end
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
