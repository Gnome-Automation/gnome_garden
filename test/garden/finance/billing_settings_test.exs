defmodule GnomeGarden.Finance.BillingSettingsTest do
  use GnomeGarden.DataCase, async: true

  alias GnomeGarden.Finance

  test "upsert_billing_settings creates a row on first call" do
    assert {:ok, settings} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    assert settings.reminder_days == [7, 14, 30]
  end

  test "upsert_billing_settings updates the existing row" do
    {:ok, _} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    {:ok, updated} = Finance.upsert_billing_settings(%{reminder_days: [5, 10]})
    assert updated.reminder_days == [5, 10]
  end

  test "get_billing_settings returns all rows (one row after upsert)" do
    {:ok, _} = Finance.upsert_billing_settings(%{reminder_days: [7, 14, 30]})
    {:ok, rows} = Finance.get_billing_settings()
    assert length(rows) == 1
    assert hd(rows).reminder_days == [7, 14, 30]
  end

  test "reminder_days must have at least one item" do
    assert {:error, _} = Finance.upsert_billing_settings(%{reminder_days: []})
  end

  test "upsert_billing_settings accepts session_timeout_minutes" do
    assert {:ok, settings} =
      Finance.upsert_billing_settings(%{session_timeout_minutes: 20})
    assert settings.session_timeout_minutes == 20
  end

  test "session_timeout_minutes defaults to 30" do
    {:ok, settings} = Finance.upsert_billing_settings(%{reminder_days: [7]})
    assert settings.session_timeout_minutes == 30
  end

  test "session_timeout_minutes of 0 disables timeout" do
    assert {:ok, settings} = Finance.upsert_billing_settings(%{session_timeout_minutes: 0})
    assert settings.session_timeout_minutes == 0
  end
end
