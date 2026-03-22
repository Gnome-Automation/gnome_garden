defmodule GnomeHubWeb.PageController do
  use GnomeHubWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
