defmodule GnomeGardenWeb.Finance.BillingSettingsLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  setup :register_and_log_in_user

  setup do
    {:ok, _} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    :ok
  end

  test "renders billing settings page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/settings")
    assert html =~ "Billing Settings"
    assert html =~ "Payment Reminder Days"
  end

  test "shows current reminder days", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/settings")
    assert html =~ "7"
    assert html =~ "14"
    assert html =~ "30"
  end

  test "saves updated reminder days", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/finance/settings")

    html =
      view
      |> form("#billing-settings-form", billing_settings: %{reminder_days: "5, 10, 20"})
      |> render_submit()

    # Success banner is rendered inline in the LiveView (not in the layout flash)
    assert html =~ "Settings saved"

    {:ok, [settings]} = Finance.get_billing_settings()
    assert settings.reminder_days == [5, 10, 20]
  end

  test "shows error for empty reminder days", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/finance/settings")

    html =
      view
      |> form("#billing-settings-form", billing_settings: %{reminder_days: ""})
      |> render_submit()

    # Error banner is rendered inline in the LiveView
    assert html =~ "at least one"
  end
end
