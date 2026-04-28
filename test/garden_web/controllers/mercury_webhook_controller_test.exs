defmodule GnomeGardenWeb.MercuryWebhookControllerTest do
  use GnomeGardenWeb.ConnCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Mercury

  @test_secret "test-webhook-secret"

  setup do
    Application.put_env(:gnome_garden, :mercury_webhook_secret, @test_secret)
    on_exit(fn -> Application.delete_env(:gnome_garden, :mercury_webhook_secret) end)
    :ok
  end

  defp sign(body, secret \\ @test_secret) do
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

  defp make_account do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        mercury_id: "acct-#{System.unique_integer([:positive])}",
        name: "Checking",
        status: :active,
        kind: :checking
      })
    account
  end

  defp make_transaction(account) do
    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        account_id: account.id,
        amount: Decimal.new("500.00"),
        kind: :ach,
        status: :pending,
        occurred_at: DateTime.utc_now()
      })
    txn
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

  test "transaction.created inserts transaction and enqueues job", %{conn: conn} do
    account = make_account()

    payload = %{
      "type" => "transaction.created",
      "id" => "txn-new-#{System.unique_integer([:positive])}",
      "accountId" => account.mercury_id,
      "amount" => 1000.0,
      "kind" => "ach",
      "status" => "sent",
      "occurredAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, txn} = Mercury.get_mercury_transaction_by_mercury_id(payload["id"])
    assert txn.status == :sent

    assert_enqueued(
      worker: GnomeGarden.Mercury.PaymentMatcherWorker,
      args: %{"transaction_id" => txn.id}
    )
  end

  test "transaction.created returns 422 when account not found", %{conn: conn} do
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
    assert conn.status == 422
  end

  test "transaction.updated updates transaction status", %{conn: conn} do
    account = make_account()
    txn = make_transaction(account)

    payload = %{
      "type" => "transaction.updated",
      "id" => txn.mercury_id,
      "status" => "sent"
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, updated} = Mercury.get_mercury_transaction_by_mercury_id(txn.mercury_id)
    assert updated.status == :sent
  end

  test "transaction.updated returns 422 when transaction not found", %{conn: conn} do
    payload = %{
      "type" => "transaction.updated",
      "id" => "nonexistent-txn-id",
      "status" => "sent"
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 422
  end

  test "balance.updated updates account balances", %{conn: conn} do
    account = make_account()

    payload = %{
      "type" => "balance.updated",
      "accountId" => account.mercury_id,
      "currentBalance" => 50000.0,
      "availableBalance" => 49000.0
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 200

    assert {:ok, updated} = Mercury.get_mercury_account_by_mercury_id(account.mercury_id)
    assert Decimal.equal?(updated.current_balance, Decimal.new("50000.0"))
    assert Decimal.equal?(updated.available_balance, Decimal.new("49000.0"))
  end

  test "balance.updated returns 422 when account not found", %{conn: conn} do
    payload = %{
      "type" => "balance.updated",
      "accountId" => "nonexistent-account-id",
      "currentBalance" => 100.0,
      "availableBalance" => 100.0
    }

    conn = webhook_post(conn, payload)
    assert conn.status == 422
  end
end
