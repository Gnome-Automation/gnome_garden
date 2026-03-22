defmodule GnomeHub.Repo do
  use Ecto.Repo,
    otp_app: :gnome_hub,
    adapter: Ecto.Adapters.Postgres
end
