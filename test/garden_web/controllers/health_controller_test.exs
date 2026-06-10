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
               "document_storage" => %{"status" => "ok", "mode" => "test"},
               "background_jobs" => %{
                 "status" => "ok"
               },
               "agent_operating_system" => %{
                 "status" => "ok",
                 "active_agent_runs" => _active_runs,
                 "recent_failed_agent_runs" => _failed_runs,
                 "pending_memory_blocks" => _pending_memory_blocks,
                 "pending_memory_entries" => _pending_memory_entries,
                 "pending_learning_recommendations" => _pending_learning,
                 "eval_runs" => %{
                   "recent" => _eval_recent,
                   "passed" => _eval_passed,
                   "failed" => _eval_failed,
                   "error" => _eval_error
                 },
                 "workflow_definitions" => %{
                   "total" => _workflow_total,
                   "published" => _workflow_published,
                   "disabled" => _workflow_disabled
                 },
                 "credential_blockers" => _credential_blockers
               }
             }
           } = json_response(conn, 200)
  end
end
