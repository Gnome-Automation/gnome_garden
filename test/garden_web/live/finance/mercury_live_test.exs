defmodule GnomeGardenWeb.Finance.MercuryLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Mercury

  setup :register_and_log_in_user

  test "renders the Mercury page with no account data", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/mercury")
    assert html =~ "Mercury"
    assert html =~ "No account data"
  end

  test "renders account balance when an account exists", %{conn: conn} do
    {:ok, _account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acc-#{System.unique_integer([:positive])}",
        name: "Gnome Checking",
        status: :active,
        kind: :checking,
        current_balance: Decimal.new("15000.00"),
        available_balance: Decimal.new("14500.00")
      })

    {:ok, _view, html} = live(conn, ~p"/finance/mercury")
    assert html =~ "Gnome Checking"
    assert html =~ "15000"
    assert html =~ "Active"
  end
end
