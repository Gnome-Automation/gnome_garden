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
  alias GnomeGarden.Procurement

  @procurement_source_create_fields [
    :name,
    :url,
    :source_type,
    :portal_id,
    :region,
    :priority,
    :api_available,
    :requires_login,
    :scrape_selector,
    :scan_frequency_hours,
    :enabled,
    :metadata,
    :added_by,
    :notes,
    :status
  ]

  @procurement_source_atom_fields %{
    source_type: [
      :planetbids,
      :opengov,
      :bidnet,
      :sam_gov,
      :cal_eprocure,
      :utility,
      :school,
      :port,
      :custom,
      :company_site,
      :job_board,
      :directory
    ],
    region: [:oc, :la, :ie, :sd, :socal, :norcal, :ca, :national],
    priority: [:high, :medium, :low],
    added_by: [:manual, :agent, :import],
    status: [:candidate, :approved, :ignored, :blocked]
  }

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

  @doc """
  Prints the configured fixed admin accounts and their team-member state.

  This is intentionally release-safe: it starts only the repo through
  `Ecto.Migrator.with_repo/2`, so it can run while the web server is already
  bound to the production port.
  """
  @spec audit_admins() :: :ok
  def audit_admins do
    [repo | _repos] = repos()

    {:ok, _result, _apps} =
      Ecto.Migrator.with_repo(repo, fn _repo ->
        IO.puts("Garden admin accounts:")

        "GARDEN_ADMIN_PC"
        |> audit_admin!("PC")
        |> IO.puts()

        "GARDEN_ADMIN_BHAMMOUD"
        |> audit_admin!("Bhammoud")
        |> IO.puts()

        :ok
      end)

    :ok
  end

  @doc """
  Rotates the fixed admin passwords to the values currently in the environment.

  This is a semantic alias for `bootstrap_admins/0`: the bootstrap path is
  already idempotent and updates existing users to the supplied password.
  """
  @spec rotate_admin_passwords() :: :ok
  def rotate_admin_passwords, do: bootstrap_admins()

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

  @doc """
  Imports procurement sources from a JSON export.

  The importer uses the Procurement Ash code interface so source upserts also
  rebuild linked acquisition sources through the resource change.
  """
  @spec import_procurement_sources!(Path.t()) :: :ok
  def import_procurement_sources!(path) do
    [repo | _repos] = repos()

    {:ok, _result, _apps} =
      Ecto.Migrator.with_repo(repo, fn _repo ->
        path
        |> File.read!()
        |> Jason.decode!()
        |> import_procurement_source_rows!()
      end)

    :ok
  end

  defp import_procurement_source_rows!(rows) when is_list(rows) do
    result =
      Enum.reduce(rows, %{imported: 0, failed: []}, fn row, acc ->
        case import_procurement_source_row(row) do
          {:ok, _source} ->
            %{acc | imported: acc.imported + 1}

          {:error, error} ->
            %{acc | failed: [{Map.get(row, "url"), error} | acc.failed]}
        end
      end)

    IO.puts("Imported procurement sources: #{result.imported}")

    if result.failed != [] do
      for {url, error} <- Enum.reverse(result.failed) do
        IO.puts("Failed procurement source #{url}: #{inspect(error)}")
      end

      raise "Failed to import #{length(result.failed)} procurement sources"
    end

    :ok
  end

  defp import_procurement_source_rows!(_rows) do
    raise "Procurement source import must be a JSON array"
  end

  defp import_procurement_source_row(row) when is_map(row) do
    with {:ok, source} <-
           row
           |> procurement_source_create_attrs()
           |> Procurement.create_procurement_source(authorize?: false),
         {:ok, source} <- maybe_restore_procurement_source_config(source, row),
         {:ok, source} <- maybe_restore_procurement_source_scan(source, row) do
      {:ok, source}
    end
  end

  defp procurement_source_create_attrs(row) do
    Map.new(@procurement_source_create_fields, fn field ->
      value = Map.get(row, Atom.to_string(field))
      {field, normalize_procurement_source_value(field, value)}
    end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_procurement_source_value(field, value)
       when is_map_key(@procurement_source_atom_fields, field) do
    allowed = Map.fetch!(@procurement_source_atom_fields, field)

    cond do
      is_nil(value) ->
        nil

      is_atom(value) and value in allowed ->
        value

      is_binary(value) ->
        atom_value = Enum.find(allowed, &(Atom.to_string(&1) == value))

        atom_value ||
          raise "Invalid procurement source #{field}: #{inspect(value)}"

      true ->
        raise "Invalid procurement source #{field}: #{inspect(value)}"
    end
  end

  defp normalize_procurement_source_value(_field, value), do: value

  defp maybe_restore_procurement_source_config(source, %{"config_status" => config_status} = row)
       when config_status in ["configured", "manual"] do
    scrape_config = Map.get(row, "scrape_config") || %{}

    if scrape_config == %{} or source.config_status in [:configured, :manual] do
      {:ok, source}
    else
      source
      |> Procurement.configure_procurement_source(%{scrape_config: scrape_config},
        authorize?: false,
        return_notifications?: true
      )
      |> unwrap_notification_result()
    end
  end

  defp maybe_restore_procurement_source_config(source, _row), do: {:ok, source}

  defp maybe_restore_procurement_source_scan(source, %{"last_scanned_at" => last_scanned_at})
       when is_binary(last_scanned_at) and last_scanned_at != "" do
    source
    |> Procurement.update_procurement_source(%{last_scanned_at: last_scanned_at},
      authorize?: false,
      return_notifications?: true
    )
    |> unwrap_notification_result()
  end

  defp maybe_restore_procurement_source_scan(source, _row), do: {:ok, source}

  defp unwrap_notification_result({:ok, record, _notifications}), do: {:ok, record}
  defp unwrap_notification_result(result), do: result

  defp audit_admin!(env_prefix, default_display_name) do
    email = System.get_env("#{env_prefix}_EMAIL")

    cond do
      is_nil(email) or email == "" ->
        "#{default_display_name}: missing #{env_prefix}_EMAIL"

      true ->
        case Accounts.get_user_by_email(email, authorize?: false) do
          {:ok, user} ->
            describe_admin_user(default_display_name, user)

          {:error, error} ->
            if not_found_error?(error) do
              "#{default_display_name}: user #{email} is missing"
            else
              raise "Failed to load admin user #{email}: #{Exception.message(error)}"
            end
        end
    end
  end

  defp describe_admin_user(default_display_name, user) do
    case Operations.get_team_member_by_user(user.id) do
      {:ok, team_member} ->
        "#{default_display_name}: #{user.email} -> #{team_member.role}, #{team_member.status}, #{team_member.display_name}"

      {:error, error} ->
        if not_found_error?(error) do
          "#{default_display_name}: #{user.email} has no team member"
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
