defmodule GnomeGardenWeb.HealthControllerTest do
  use GnomeGardenWeb.ConnCase, async: true

  test "GET /health returns a simple unauthenticated status", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert text_response(conn, 200) == "ok"
  end

  test "GET /ready returns readiness checks", %{conn: conn} do
    conn = get(conn, ~p"/ready")

    assert %{
             "status" => "ok",
             "checks" => %{
               "database" => %{"status" => "ok"},
               "document_storage" => %{"status" => "ok", "mode" => "test"}
             }
           } = json_response(conn, 200)
  end
end
