defmodule GnomeGardenWeb.HealthController do
  use GnomeGardenWeb, :controller

  def show(conn, _params) do
    text(conn, "ok")
  end
end
