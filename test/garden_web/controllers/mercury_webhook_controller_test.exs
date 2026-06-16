defmodule GnomeGardenWeb.MercuryWebhookControllerTest do
  use GnomeGardenWeb.ConnCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Finance

  @test_secret "test-webhook-secret"

  setup do
    Application.put_env(:gnome_garden, :mercury_webhook_secret, @test_secret)
    on_exit(fn -> Application.delete_env(:gnome_garden, :mercury_webhook_secret) end)
    :ok
  end

  defp sign(body, secret) do
    timestamp = System.system_time(:second) |> Integer.to_string()
    signed = "#{timestamp}.#{body}"
    hmac = :crypto.mac(:hmac, :sha256, secret, signed) |> Base.encode16(case: :lower)
    "t=#{timestamp},v1=#{hmac}"
  end

  defp webhook_post(conn, body_map, secret \\ @test_secret) do
    body = Jason.encode!(body_map)
    sig = sign(body, secret)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("mercury-signature", sig)
    |> post("/webhooks/mercury", body)
  end

  test "rejects request with missing signature header", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/webhooks/mercury", Jason.encode!(%{"type" => "balance.updated"}))

    assert conn.status == 401
  end

  test "rejects request with wrong signature", %{conn: conn} do
    conn = webhook_post(conn, %{"type" => "balance.updated"}, "wrong-secret")
    assert conn.status == 401
  end

  test "rejects request with expired timestamp", %{conn: conn} do
    body = Jason.encode!(%{"type" => "balance.updated"})
    old_ts = System.system_time(:second) - 400
    signed = "#{old_ts}.#{body}"
    hmac = :crypto.mac(:hmac, :sha256, @test_secret, signed) |> Base.encode16(case: :lower)
    sig = "t=#{old_ts},v1=#{hmac}"

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mercury-signature", sig)
      |> post("/webhooks/mercury", body)

    assert conn.status == 401
  end

  test "returns 200 for unknown event type", %{conn: conn} do
    conn = webhook_post(conn, %{"type" => "some.future.event", "id" => "x"})
    assert conn.status == 200
  end

  test "transaction.created records integration event and enqueues sync", %{conn: conn} do
    payload = %{
      "type" => "transaction.created",
      "id" => "txn-new-#{System.unique_integer([:positive])}",
      "accountId" => "acct-webhook",
      "amount" => 1000.0,
      "kind" => "ach",
      "status" => "sent",
      "occurredAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, events} = Finance.list_bank_integration_events()
    assert Enum.any?(events, &(&1.provider_event_id == payload["id"]))

    assert_enqueued(
      worker: GnomeGarden.Finance.BankSyncWorker,
      args: %{"provider" => "mercury", "environment" => "production", "source" => "webhook"}
    )
  end

  test "transaction.created does not require a local account", %{conn: conn} do
    payload = %{
      "type" => "transaction.created",
      "id" => "txn-#{System.unique_integer([:positive])}",
      "accountId" => "nonexistent-mercury-id",
      "amount" => 500.0,
      "kind" => "wire",
      "status" => "pending",
      "occurredAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200
  end

  test "transaction.updated records integration event", %{conn: conn} do
    payload = %{
      "type" => "transaction.updated",
      "id" => "txn-update-#{System.unique_integer([:positive])}",
      "status" => "sent"
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, events} = Finance.list_bank_integration_events()
    assert Enum.any?(events, &(&1.provider_event_id == payload["id"]))
  end

  test "balance.updated records integration event", %{conn: conn} do
    payload = %{
      "type" => "balance.updated",
      "accountId" => "acct-balance-#{System.unique_integer([:positive])}",
      "currentBalance" => 50000.0,
      "availableBalance" => 49000.0
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, events} = Finance.list_bank_integration_events()
    assert Enum.any?(events, &(&1.event_type == "balance.updated"))
  end
end
