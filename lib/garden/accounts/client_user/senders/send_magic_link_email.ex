defmodule GnomeGarden.Accounts.ClientUser.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a portal sign-in magic link to a client.
  Called by AshAuthentication when request_magic_link is triggered.
  """

  use AshAuthentication.Sender
  use GnomeGardenWeb, :verified_routes

  import Swoosh.Email
  alias GnomeGarden.Mailer

  @impl true
  def send(client_user_or_email, token, _opts) do
    email =
      case client_user_or_email do
        %{email: email} -> email
        email -> email
      end

    sign_in_url = url(~p"/portal/sign-in/#{token}")

    new()
    |> from({"Gnome Automation", "noreply@gnomeautomation.io"})
    |> to(to_string(email))
    |> subject("Your portal sign-in link")
    |> html_body("""
    <p>Hello,</p>
    <p>Click the link below to sign in to your client portal. This link expires in 10 minutes.</p>
    <p><a href="#{sign_in_url}">Sign in to your portal</a></p>
    <p>If you did not request this link, you can safely ignore this email.</p>
    """)
    |> Mailer.deliver!()
  end
end
