defmodule GnomeGardenWeb.ClientPortal.SessionController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Accounts
  alias GnomeGarden.Operations

  def new(conn, _params) do
    render(conn, :new, layout: {GnomeGardenWeb.Layouts, :root}, page_title: "Sign In")
  end

  def create(conn, %{"email" => email}) do
    # Always respond with the same message to prevent email enumeration
    maybe_send_magic_link(email)

    conn
    |> put_flash(:info, "If you have an account, check your email for a sign-in link.")
    |> render(:new, layout: {GnomeGardenWeb.Layouts, :root}, page_title: "Sign In")
  end

  defp maybe_send_magic_link(email) do
    with {:ok, person} <- Operations.get_person_by_email(email),
         {:ok, affiliations} <- Operations.list_affiliations_for_person(person.id),
         [affiliation | _] <- Enum.filter(affiliations, &(&1.status == :active)),
         {:ok, client_user} <- Accounts.invite_client_user(email, affiliation.organization_id) do
      strategy =
        AshAuthentication.Info.strategy_for_action!(
          GnomeGarden.Accounts.ClientUser,
          :request_magic_link
        )

      case AshAuthentication.Strategy.MagicLink.request_token_for(strategy, client_user) do
        {:ok, token} ->
          GnomeGarden.Accounts.ClientUser.Senders.SendMagicLinkEmail.send(client_user, token, [])

        _ ->
          :ok
      end
    else
      _ -> :ok
    end
  end
end
