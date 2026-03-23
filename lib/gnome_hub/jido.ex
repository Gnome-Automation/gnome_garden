defmodule GnomeHub.Jido do
  @moduledoc """
  Jido runtime for GnomeHub.

  Provides agent orchestration capabilities through the Jido ecosystem.
  """

  use Jido, otp_app: :gnome_hub
end
