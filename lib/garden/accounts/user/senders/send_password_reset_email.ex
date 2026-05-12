defmodule GnomeGarden.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc "Sends password reset instructions for password authentication."

  use AshAuthentication.Sender
  use GnomeGardenWeb, :verified_routes

  import Swoosh.Email
  alias GnomeGarden.Mailer

  @impl true
  def send(user, token, _opts) do
    reset_url = url(~p"/password-reset/#{token}")

    new()
    |> from({"Gnome Garden", "noreply@gnomeautomation.com"})
    |> to(to_string(user.email))
    |> subject("Reset your Gnome Garden password")
    |> html_body(body(user.email, reset_url))
    |> text_body(text_body(reset_url))
    |> Mailer.deliver!()
  end

  defp body(email, reset_url) do
    """
    <p>Hello #{email},</p>
    <p>Use this link to reset your Gnome Garden password:</p>
    <p><a href="#{reset_url}">Reset password</a></p>
    <p>If you did not request this, you can ignore this email.</p>
    """
  end

  defp text_body(reset_url) do
    """
    Use this link to reset your Gnome Garden password:

    #{reset_url}

    If you did not request this, you can ignore this email.
    """
  end
end
