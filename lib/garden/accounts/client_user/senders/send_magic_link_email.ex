defmodule GnomeGarden.Accounts.ClientUser.Senders.SendMagicLinkEmail do
  @moduledoc """
  Stub sender for client user magic link emails.
  Full implementation added in Task 2.
  """

  use AshAuthentication.Sender

  def send(_user, _token, _opts), do: :ok
end
