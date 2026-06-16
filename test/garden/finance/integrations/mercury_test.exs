defmodule GnomeGarden.Finance.Integrations.MercuryTest do
  use ExUnit.Case, async: false

  alias GnomeGarden.Finance.Integrations.Mercury

  describe "remote reads" do
    test "lists accounts through ReqMercury and extracts the account list" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v1/accounts"

        Req.Test.json(conn, %{
          "accounts" => [%{"id" => "acct-1", "name" => "Operating"}],
          "page" => %{}
        })
      end)

      assert {:ok, [%{"id" => "acct-1", "name" => "Operating"}]} =
               Mercury.list_accounts(
                 api_key: "secret-token:test",
                 sandbox?: true,
                 plug: {Req.Test, __MODULE__}
               )
    end

    test "lists transactions through ReqMercury and extracts the transaction list" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v1/accounts/acct-1/transactions"

        Req.Test.json(conn, %{
          "transactions" => [%{"id" => "txn-1", "amount" => "-12.34"}],
          "total" => 1
        })
      end)

      assert {:ok, [%{"id" => "txn-1", "amount" => "-12.34"}]} =
               Mercury.list_transactions("acct-1",
                 api_key: "secret-token:test",
                 sandbox?: true,
                 plug: {Req.Test, __MODULE__}
               )
    end
  end

  describe "account_attrs/2" do
    test "normalizes Mercury account payloads for Finance bank accounts" do
      attrs =
        Mercury.account_attrs(
          %{
            "id" => "acct-1",
            "name" => "Operating",
            "nickname" => "Ops",
            "legalBusinessName" => "Gnome Automation LLC",
            "status" => "active",
            "kind" => "checking",
            "currency" => "USD",
            "currentBalance" => "1000.50",
            "availableBalance" => "950.25",
            "routingNumber" => "121145433",
            "wireRoutingNumber" => "121145433",
            "accountNumber" => "303582790913224",
            "dashboardId" => "dash-acct-1"
          },
          provider: :mercury,
          bank_connection_id: "connection-id"
        )

      assert attrs.bank_connection_id == "connection-id"
      assert attrs.provider == :mercury
      assert attrs.provider_account_id == "acct-1"
      assert attrs.name == "Operating"
      assert attrs.status == :active
      assert attrs.kind == :checking
      assert attrs.account_number_last4 == "3224"
      assert attrs.account_number_encrypted == "303582790913224"
      assert %DateTime{} = attrs.balance_as_of
      assert attrs.raw_provider_payload["id"] == "acct-1"
    end
  end

  describe "transaction_attrs/2" do
    test "normalizes Mercury transaction payloads for Finance bank transactions" do
      attrs =
        Mercury.transaction_attrs(
          %{
            "id" => "txn-1",
            "amount" => "-42.13",
            "kind" => "ach",
            "status" => "sent",
            "occurredAt" => "2026-06-11T12:34:56Z",
            "postedDate" => "2026-06-12",
            "bankDescription" => "ACH TRANSFER",
            "externalMemo" => "Invoice INV-123",
            "counterpartyId" => "cp-1",
            "counterpartyName" => "ACME Corp",
            "counterpartyAccountNumber" => "000123456789",
            "dashboardLink" => "https://app.mercury.com/transactions/txn-1"
          },
          provider: :mercury,
          bank_account_id: "bank-account-id"
        )

      assert attrs.bank_account_id == "bank-account-id"
      assert attrs.provider == :mercury
      assert attrs.provider_transaction_id == "txn-1"
      assert attrs.direction == :debit
      assert attrs.kind == :ach
      assert attrs.status == :posted
      assert attrs.description == "ACH TRANSFER"
      assert attrs.memo == "Invoice INV-123"
      assert attrs.counterparty_name == "ACME Corp"
      assert attrs.counterparty_account_last4 == "6789"
      assert attrs.occurred_at == ~U[2026-06-11 12:34:56Z]
      assert attrs.posted_at == ~U[2026-06-12 00:00:00Z]
      assert attrs.raw_provider_payload["id"] == "txn-1"
    end
  end
end
