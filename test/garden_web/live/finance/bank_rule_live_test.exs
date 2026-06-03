defmodule GnomeGardenWeb.Finance.BankRuleLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "Index" do
    test "renders the bank rules index page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules")
      assert render(view) =~ "Bank Rules"
    end

    test "shows empty state when no rules exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules")
      assert render(view) =~ "No bank rules yet"
    end

    test "has a new rule button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules")
      assert render(view) =~ "New Rule"
    end
  end

  describe "Form (new)" do
    test "renders the new bank rule form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules/new")
      assert render(view) =~ "New Bank Rule"
    end

    test "shows direction and category selects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules/new")
      html = render(view)
      assert html =~ "Direction"
      assert html =~ "Category"
    end

    test "shows counterparty contains field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finance/bank-rules/new")
      assert render(view) =~ "Counterparty"
    end
  end
end
