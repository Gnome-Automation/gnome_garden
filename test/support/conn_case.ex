defmodule GnomeGardenWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use GnomeGardenWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint GnomeGardenWeb.Endpoint

      use GnomeGardenWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import GnomeGardenWeb.ConnCase
    end
  end

  setup tags do
    GnomeGarden.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def register_and_log_in_client_user(%{conn: conn} = context) do
    org = Ash.Seed.seed!(GnomeGarden.Operations.Organization, %{name: "Test Client Org #{System.unique_integer()}"})
    email = "client-#{System.unique_integer([:positive, :monotonic])}@example.com"

    client_user =
      Ash.Seed.seed!(GnomeGarden.Accounts.ClientUser, %{
        email: email,
        organization_id: org.id
      })

    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(client_user)
    client_user = Ash.Resource.put_metadata(client_user, :token, token)

    new_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(client_user)

    context
    |> Map.put(:conn, new_conn)
    |> Map.put(:current_client_user, client_user)
    |> Map.put(:organization, org)
  end

  def register_and_log_in_user(%{conn: conn} = context) do
    email = "operator-#{System.unique_integer([:positive, :monotonic])}@example.com"
    password = "valid-password-#{System.unique_integer([:positive, :monotonic])}"

    {:ok, user} =
      GnomeGarden.Accounts.create_user_with_password(%{
        email: email,
        password: password,
        password_confirmation: password
      })

    team_member_role = Map.get(context, :team_member_role, :admin)

    team_member =
      Ash.Seed.seed!(GnomeGarden.Operations.TeamMember, %{
        user_id: user.id,
        display_name: "Operator #{System.unique_integer([:positive, :monotonic])}",
        role: team_member_role,
        status: :active
      })

    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    user = Ash.Resource.put_metadata(user, :token, token)

    new_conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    context
    |> Map.put(:conn, new_conn)
    |> Map.put(:current_user, user)
    |> Map.put(:current_team_member, team_member)
  end
end
