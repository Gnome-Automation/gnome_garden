defmodule GnomeGarden.Accounts.ClientUser.Senders.SendClientInviteEmail do
  @moduledoc """
  Sends a portal invitation email to a newly invited client.
  Called explicitly by the invite flow (not by AshAuthentication directly).
  """

  use GnomeGardenWeb, :verified_routes

  import Swoosh.Email
  alias GnomeGarden.Mailer

  @doc """
  Sends an invitation email with a magic link token.
  token is the raw magic link token string from AshAuthentication.
  """
  def send(email, token) do
    sign_in_url = url(~p"/portal/sign-in/#{token}")

    new()
    |> from({"Gnome Automation", "noreply@gnomeautomation.io"})
    |> to(to_string(email))
    |> subject("You've been invited to the Gnome Automation client portal")
    |> html_body("""
    <p>Hello,</p>
    <p>You've been invited to access the Gnome Automation client portal where you can view your invoices and agreements.</p>
    <p><a href="#{sign_in_url}">Accept invitation and sign in</a></p>
    <p>This link expires in 10 minutes. You can request a new sign-in link at any time from the portal login page.</p>
    """)
    |> Mailer.deliver!()
  end
end
