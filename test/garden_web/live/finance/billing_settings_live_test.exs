defmodule GnomeGardenWeb.Finance.BillingSettingsLiveTest do
  use GnomeGardenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GnomeGarden.Finance

  setup :register_and_log_in_user

  setup do
    {:ok, _} =
      Finance.upsert_billing_settings(%{
        reminder_days: [7, 14, 30],
        late_fee_enabled: false,
        late_fee_days: 30,
        late_fee_type: :percent,
        late_fee_value: Decimal.new("1.5")
      })

    :ok
  end

  test "renders billing settings page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/finance/settings")
    assert html =~ "Billing Settings"
    assert html =~ "Payment Reminders"
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
      |> form("#billing-settings-form", billing_settings: %{interval: "5", max_reminders: "3"})
      |> render_submit()

    # Success banner is rendered inline in the LiveView (not in the layout flash)
    assert html =~ "Settings saved"

    {:ok, [settings]} = Finance.get_billing_settings()
    assert settings.reminder_days == [5, 10, 15]
  end

  test "shows error for invalid reminder settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/finance/settings")

    html =
      view
      |> form("#billing-settings-form", billing_settings: %{interval: "0", max_reminders: "3"})
      |> render_submit()

    # Error banner is rendered inline in the LiveView
    assert html =~ "valid numbers"
  end

  test "renders late fees section", %{conn: conn} do
    {:ok, _} =
      Finance.upsert_billing_settings(%{
        late_fee_enabled: false,
        late_fee_days: 30,
        late_fee_type: :percent,
        late_fee_value: Decimal.new("1.5")
      })

    {:ok, _view, html} = live(conn, ~p"/finance/settings")
    assert html =~ "Late Fees"
    assert html =~ "late_fee_enabled"
    assert html =~ "late_fee_days"
  end

  test "saves late fee settings", %{conn: conn} do
    {:ok, _} =
      Finance.upsert_billing_settings(%{
        late_fee_enabled: false,
        late_fee_days: 30,
        late_fee_type: :percent,
        late_fee_value: Decimal.new("1.5")
      })

    {:ok, view, _html} = live(conn, ~p"/finance/settings")

    html =
      view
      |> form("#late-fee-form", late_fee: %{
           late_fee_enabled: "true",
           late_fee_days: "14",
           late_fee_type: "flat",
           late_fee_value: "50.00"
         })
      |> render_submit()

    assert html =~ "Settings saved"

    {:ok, [settings]} = Finance.get_billing_settings()
    assert settings.late_fee_enabled == true
    assert settings.late_fee_days == 14
    assert settings.late_fee_type == :flat
    assert Decimal.equal?(settings.late_fee_value, Decimal.new("50.00"))
  end
end
