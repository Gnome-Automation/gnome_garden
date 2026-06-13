defmodule GnomeGardenWeb.PageController do
  use GnomeGardenWeb, :controller

  alias GnomeGarden.Operations

  def access_denied(conn, _params) do
    conn
    |> put_status(:forbidden)
    |> text("Admin access required")
  end

  def agent_redirect(conn, _params) do
    redirect(conn, to: ~p"/console/agents")
  end

  def eval_procurement_public_bids(conn, _params) do
    html(conn, """
    <!doctype html>
    <html>
      <head><title>City Bid Opportunities</title></head>
      <body>
        <header>
          <a href="/sign-in">Vendor Login</a>
        </header>
        <main>
          <h1>Open Bids</h1>
          <p>Current public works and technology solicitations.</p>
          <ul>
            <li><a href="/eval-fixtures/procurement/public-bids/scada-controls">SCADA Controls Upgrade RFP</a></li>
            <li><a href="/eval-fixtures/procurement/public-bids/pump-maintenance">Pump Station Maintenance IFB</a></li>
          </ul>
        </main>
      </body>
    </html>
    """)
  end

  def eval_procurement_irrelevant(conn, _params) do
    html(conn, """
    <!doctype html>
    <html>
      <head><title>Parks Bulletin</title></head>
      <body>
        <main>
          <h1>Parks Bulletin</h1>
          <p>Library hours, park events, and neighborhood announcements.</p>
          <a href="/contact">Contact staff</a>
        </main>
      </body>
    </html>
    """)
  end

  def home(conn, _params) do
    actor = conn.assigns[:current_user]
    workspace = Operations.operations_workspace(actor: actor)

    render(
      conn,
      :home,
      [
        layout: {GnomeGardenWeb.Layouts, :app},
        page_title: "Operations Workspace",
        current_user: actor,
        current_path: conn.request_path
      ] ++ Map.to_list(workspace)
    )
  end
end
