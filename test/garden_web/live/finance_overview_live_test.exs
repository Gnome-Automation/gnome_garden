defmodule GnomeGardenWeb.FinanceOverviewLiveTest do
  use GnomeGardenWeb.ConnCase

  setup :register_and_log_in_user

  import Phoenix.LiveViewTest

  test "renders the finance overview workspace", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance")

    assert html =~ "Finance"
    assert html =~ "Next Actions"
    assert html =~ "Workspaces"
    assert html =~ "Banking"
    assert html =~ "Receivables"
    assert html =~ "Work to Bill"
  end
end
