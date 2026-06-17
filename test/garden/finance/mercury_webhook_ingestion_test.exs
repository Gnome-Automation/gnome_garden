defmodule GnomeGarden.Finance.MercuryWebhookIngestionTest do
  use GnomeGarden.DataCase, async: true
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Finance

  test "records known Mercury webhook events and enqueues provider pull sync" do
    payload = %{
      "type" => "transaction.created",
      "id" => "evt-known-#{System.unique_integer([:positive])}"
    }

    assert {:ok, result} = Finance.ingest_mercury_webhook_event("transaction.created", payload)
    assert result.sync_enqueued?
    assert result.event.provider == :mercury
    assert result.event.provider_event_id == payload["id"]
    assert result.event.status == :received

    assert_enqueued(
      worker: GnomeGarden.Finance.BankSyncWorker,
      args: %{"provider" => "mercury", "environment" => "production", "source" => "webhook"}
    )
  end

  test "links webhook events to a local bank account when accountId is known" do
    {:ok, connection} =
      Finance.create_bank_connection(%{
        provider: :mercury,
        name: "Mercury #{System.unique_integer([:positive])}",
        status: :active,
        environment: :production
      })

    {:ok, account} =
      Finance.create_bank_account(%{
        bank_connection_id: connection.id,
        provider: :mercury,
        provider_account_id: "acct-webhook-known",
        name: "Operating Checking",
        status: :active,
        kind: :checking
      })

    payload = %{
      "type" => "balance.updated",
      "id" => "evt-account-#{System.unique_integer([:positive])}",
      "accountId" => account.provider_account_id
    }

    assert {:ok, result} = Finance.ingest_mercury_webhook_event("balance.updated", payload)
    assert result.event.bank_account_id == account.id
  end

  test "records unknown Mercury webhook events as ignored without enqueueing sync" do
    payload = %{
      "type" => "some.future.event",
      "id" => "evt-unknown-#{System.unique_integer([:positive])}"
    }

    assert {:ok, result} = Finance.ingest_mercury_webhook_event("some.future.event", payload)
    refute result.sync_enqueued?
    assert result.event.status == :ignored
    assert result.event.error_message =~ "Unknown Mercury webhook event"

    refute_enqueued(worker: GnomeGarden.Finance.BankSyncWorker)
  end
end
