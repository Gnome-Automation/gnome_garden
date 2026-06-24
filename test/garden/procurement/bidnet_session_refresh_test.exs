defmodule GnomeGarden.Procurement.BidNetSessionRefreshTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement

  defmodule SuccessfulRunner do
    def run(action, payload, opts) do
      send(Process.get(:test_pid), {:runner, action, payload, opts})

      {:ok,
       %{
         "finalUrl" => "https://www.bidnetdirect.com/private",
         "title" => "BidNet Direct",
         "status" => 200,
         "storageStatePath" => payload.storage_state_path,
         "tracePath" => payload.trace_path,
         "screenshotPath" => payload.screenshot_path
       }}
    end
  end

  defmodule FailingRunner do
    def run(action, payload, opts) do
      send(Process.get(:test_pid), {:runner, action, payload, opts})

      {:error,
       %{"code" => "invalid_credentials", "error" => "BidNet rejected these credentials."}}
    end
  end

  setup do
    Process.put(:test_pid, self())
    :ok
  end

  test "refreshes a BidNet session using saved credentials and marks it valid" do
    source = bidnet_source()
    credential = bidnet_credential(source)

    assert {:ok, _credential} =
             Procurement.mark_source_credential_manual_verification_required(credential, %{
               last_failure_reason: "Generic browser verifier cannot validate BidNet."
             })

    assert {:ok, session} =
             Procurement.refresh_bidnet_source_session(source,
               runner: SuccessfulRunner,
               timeout_ms: 15_000
             )

    assert_receive {:runner, :bidnet_login, payload, runner_opts}
    assert payload.url == source.url
    assert payload.username == "operator@example.com"
    assert payload.password == "source-secret"
    assert payload.storage_state_path =~ session.id
    assert Keyword.fetch!(runner_opts, :timeout_ms) == 15_000

    assert session.status == :valid
    assert session.provider == :bidnet
    assert session.session_family == "bidnet"
    assert session.source_credential_id == credential.id
    assert session.storage_state_path =~ "storage-state.json"
    assert session.trace_path =~ "trace.zip"
    assert session.screenshot_path =~ "session.png"
    assert session.verified_at
    assert session.expires_at
    assert session.metadata["final_url"] == "https://www.bidnetdirect.com/private"
  end

  test "records a failed BidNet session refresh without invalidating credentials" do
    source = bidnet_source()
    credential = bidnet_credential(source)

    assert {:ok, _credential} =
             Procurement.mark_source_credential_manual_verification_required(credential, %{
               last_failure_reason: "Generic browser verifier cannot validate BidNet."
             })

    assert {:error, %{session: failed, reason: "BidNet rejected these credentials."}} =
             Procurement.refresh_bidnet_source_session(source, runner: FailingRunner)

    assert_receive {:runner, :bidnet_login, payload, _runner_opts}
    assert payload.password == "source-secret"

    assert failed.status == :invalid
    assert failed.last_failure_reason == "BidNet rejected these credentials."
    assert failed.metadata["failure_code"] == "invalid_credentials"
    refute inspect(failed.metadata) =~ "source-secret"

    assert {:ok, unchanged_credential} =
             Procurement.get_source_credential(credential.id, authorize?: false)

    assert unchanged_credential.status == :active
  end

  test "rejects non-BidNet sources" do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "County Portal #{System.unique_integer([:positive])}",
        url: "https://example.com/bids",
        source_type: :custom,
        region: :ca,
        priority: :medium,
        status: :approved
      })

    assert {:error, "Only BidNet sources support BidNet session refresh."} =
             Procurement.refresh_bidnet_source_session(source, runner: SuccessfulRunner)
  end

  defp bidnet_source do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "BidNet Session Refresh #{System.unique_integer([:positive])}",
        url: "https://www.bidnetdirect.com/california/solicitations/open-bids",
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved
      })

    source
  end

  defp bidnet_credential(source) do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :bidnet,
        credential_family: "bidnet",
        scope: :source,
        procurement_source_id: source.id,
        username: "operator@example.com",
        password: "source-secret"
      })

    credential
  end
end
