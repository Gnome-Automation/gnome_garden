defmodule GnomeGardenWeb.DevAuthController do
  use GnomeGardenWeb, :controller

  import AshAuthentication.Plug.Helpers, only: [store_in_session: 2]

  alias GnomeGarden.Accounts
  alias GnomeGarden.Operations

  @default_email "dev-admin@example.com"
  @default_password "dev-admin-password"
  @default_display_name "Dev Admin"

  def sign_in(conn, params) do
    with {:ok, user} <- ensure_dev_user(),
         {:ok, _team_member} <- ensure_admin_team_member(user),
         {:ok, token, _claims} <- AshAuthentication.Jwt.token_for_user(user) do
      user = Ash.Resource.put_metadata(user, :token, token)
      return_to = Map.get(params, "return_to", ~p"/acquisition/sources")

      conn
      |> store_in_session(user)
      |> assign(:current_user, user)
      |> put_flash(:info, "Signed in as #{user.email}")
      |> redirect(to: return_to)
    else
      {:error, error} ->
        conn
        |> put_flash(:error, "Dev sign-in failed: #{inspect(error)}")
        |> redirect(to: ~p"/sign-in")
    end
  end

  defp ensure_dev_user do
    email = System.get_env("GARDEN_DEV_EMAIL", @default_email)
    password = System.get_env("GARDEN_DEV_PASSWORD", @default_password)

    case Accounts.get_user_by_email(email, authorize?: false) do
      {:ok, user} ->
        {:ok, user}

      {:error, error} ->
        if not_found_error?(error) do
          Accounts.create_user_with_password(
            %{
              email: email,
              password: password,
              password_confirmation: password
            },
            authorize?: false
          )
        else
          {:error, error}
        end
    end
  end

  defp ensure_admin_team_member(user) do
    attrs = %{
      user_id: user.id,
      display_name: System.get_env("GARDEN_DEV_DISPLAY_NAME", @default_display_name),
      role: :admin,
      status: :active
    }

    case Operations.get_team_member_by_user(user.id, authorize?: false) do
      {:ok, team_member} ->
        Operations.update_team_member(team_member, attrs, authorize?: false)

      {:error, error} ->
        if not_found_error?(error) do
          Operations.create_team_member(attrs, authorize?: false)
        else
          {:error, error}
        end
    end
  end

  defp not_found_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1))
  end

  defp not_found_error?(%Ash.Error.Query.NotFound{}), do: true
  defp not_found_error?(_error), do: false
end
