defmodule GnomeGarden.Jido do
  @moduledoc """
  Jido runtime for GnomeGarden.

  Provides agent orchestration capabilities through the Jido ecosystem.
  """

  use Jido, otp_app: :gnome_garden
end
