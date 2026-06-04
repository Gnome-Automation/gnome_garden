defmodule GnomeGardenWeb.MercuryTransactionExportControllerTest do
  use GnomeGardenWeb.ConnCase

  alias GnomeGarden.Mercury

  describe "GET /finance/mercury/batch-export" do
    test "redirects unauthenticated users", %{conn: conn} do
      conn = get(conn, ~p"/finance/mercury/batch-export?from=2024-01-01&to=2024-01-31&format=csv")
      assert redirected_to(conn) =~ "/sign-in"
    end

    test "redirects when date range is missing", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/mercury/batch-export?format=csv")
      assert redirected_to(conn) =~ "/finance/mercury"
    end

    test "returns CSV with header row for valid date range", %{conn: conn} do
      conn = log_in_user(conn)
      _txn = insert_transaction()
      conn = get(conn, ~p"/finance/mercury/batch-export?format=csv&from=2020-01-01&to=2099-12-31")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ ".csv"
      assert conn.resp_body =~ "occurred_at"
    end

    test "returns CSV with header only when no transactions match range", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/mercury/batch-export?format=csv&from=2000-01-01&to=2000-01-02")
      assert conn.status == 200
      assert conn.resp_body =~ "occurred_at"
    end

    test "returns HTML for PDF format", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/mercury/batch-export?format=pdf&from=2020-01-01&to=2099-12-31")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end
  end

  describe "GET /finance/mercury/transactions/:id/export" do
    test "redirects unauthenticated users", %{conn: conn} do
      conn = get(conn, ~p"/finance/mercury/transactions/00000000-0000-0000-0000-000000000001/export?format=csv")
      assert redirected_to(conn) =~ "/sign-in"
    end

    test "returns 404 for unknown transaction", %{conn: conn} do
      conn = log_in_user(conn)
      conn = get(conn, ~p"/finance/mercury/transactions/00000000-0000-0000-0000-000000000001/export?format=csv")
      assert conn.status == 404
    end

    test "returns CSV containing transaction data", %{conn: conn} do
      conn = log_in_user(conn)
      txn = insert_transaction()
      conn = get(conn, ~p"/finance/mercury/transactions/#{txn.id}/export?format=csv")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      assert conn.resp_body =~ "occurred_at"
      assert conn.resp_body =~ txn.mercury_id
    end

    test "returns HTML for PDF format", %{conn: conn} do
      conn = log_in_user(conn)
      txn = insert_transaction()
      conn = get(conn, ~p"/finance/mercury/transactions/#{txn.id}/export?format=pdf")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end
  end

  # --- Helpers ---

  defp log_in_user(conn) do
    user_id = Ecto.UUID.generate()
    {:ok, user_id_bin} = Ecto.UUID.dump(user_id)

    GnomeGarden.Repo.insert_all(
      "users",
      [%{
        id: user_id_bin,
        email: "test-#{user_id}@example.com",
        hashed_password: "$2b$12$placeholder_hash_for_test_only_do_not_use_in_prod"
      }],
      on_conflict: :nothing
    )

    user = Ash.get!(GnomeGarden.Accounts.User, user_id, authorize?: false, domain: GnomeGarden.Accounts)
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    conn
    |> Plug.Test.init_test_session(%{"user_token" => token})
    |> Plug.Conn.put_private(:phoenix_recycled, true)
  end

  defp insert_transaction do
    {:ok, account} =
      Mercury.create_mercury_account(%{
        name: "Test Checking #{System.unique_integer([:positive])}",
        mercury_id: "acc-#{System.unique_integer([:positive])}",
        kind: :checking,
        status: :active,
        current_balance: Decimal.new("1000.00"),
        available_balance: Decimal.new("1000.00")
      }, authorize?: false)

    {:ok, txn} =
      Mercury.create_mercury_transaction(%{
        account_id: account.id,
        mercury_id: "txn-#{System.unique_integer([:positive])}",
        amount: Decimal.new("500.00"),
        kind: :ach,
        status: :sent,
        counterparty_name: "Test Client",
        occurred_at: DateTime.utc_now()
      }, authorize?: false)

    txn
  end
end
