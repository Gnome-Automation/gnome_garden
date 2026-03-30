defmodule GnomeGardenWeb.PageController do
  use GnomeGardenWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      layout: {GnomeGardenWeb.Layouts, :app},
      page_title: "Dashboard",
      current_user: conn.assigns[:current_user],
      current_path: conn.request_path
    )
  end
end
