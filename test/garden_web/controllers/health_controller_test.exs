defmodule GnomeGardenWeb.HealthControllerTest do
  use GnomeGardenWeb.ConnCase, async: true

  test "GET /health returns a simple unauthenticated status", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert text_response(conn, 200) == "ok"
  end
end
