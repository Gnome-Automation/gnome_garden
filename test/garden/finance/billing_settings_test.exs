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
end
