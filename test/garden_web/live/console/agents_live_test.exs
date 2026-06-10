defmodule GnomeGardenWeb.Console.AgentsLiveTest do
  use GnomeGardenWeb.ConnCase
  use Oban.Testing, repo: GnomeGarden.Repo

  import Phoenix.LiveViewTest

  alias GnomeGarden.Agents.AgentEvalSweepWorker
  alias GnomeGarden.Agents.AgentEvalRunner

  setup :register_and_log_in_user

  test "renders eval coverage health from runnable cases", %{conn: conn} do
    fixture_url = "https://secure.example.com/#{System.unique_integer([:positive])}/login"

    assert {:ok, _prepared} =
             AgentEvalRunner.prepare_procurement_inspection_fixture(source_url: fixture_url)

    {:ok, _view, html} = live(conn, ~p"/console/agents")

    assert html =~ "Eval Coverage"
    assert html =~ "Eval Sweeps"
    assert html =~ "Runnable active eval cases."
  end

  test "renders eval sweep queue health", %{conn: conn} do
    assert {:ok, _job} = AgentEvalSweepWorker.enqueue()

    {:ok, _view, html} = live(conn, ~p"/console/agents")

    assert html =~ "Eval Sweeps"
    assert html =~ "queued"
    assert html =~ "Queue 1/0"
  end
end
