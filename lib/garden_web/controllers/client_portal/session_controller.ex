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
         {:ok, _client_user} <- Accounts.invite_client_user(email, affiliation.organization_id) do
      # Request magic link — AshAuthentication sends it via SendMagicLinkEmail sender
      Accounts.request_client_portal_access(email)
    else
      _ -> :ok  # silently succeed — no information leak
    end
  end
end
