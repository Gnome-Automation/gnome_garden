defmodule GnomeGarden.Procurement.BidNetProviderTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BidNetProvider

  defmodule RefreshRunner do
    def run(_action, _payload, _opts) do
      send(Process.get(:test_pid), :bidnet_refresh)

      {:ok,
       %{
         "finalUrl" => "https://www.bidnetdirect.com/private",
         "title" => "BidNet Direct",
         "status" => 200,
         secret_envelope:
           GnomeGarden.Procurement.PlaywrightRunner.envelope(%{
             "storageState" => %{
               "cookies" => [%{"name" => "sid", "value" => "refreshed-cookie"}]
             }
           })
       }}
    end
  end

  setup do
    Process.put(:test_pid, self())
    :ok
  end

  test "reuses a valid encrypted session without logging in again" do
    source = bidnet_source()
    credential = verified_credential(source)
    session = valid_session(source, credential, "existing-cookie")

    assert {:ok, session_id} =
             BidNetProvider.with_session(source, %{}, fn context ->
               assert Bitwise.band(File.stat!(context.bidnet_storage_state_path).mode, 0o777) ==
                        0o600

               assert File.read!(context.bidnet_storage_state_path) =~ "existing-cookie"
               {:ok, context.bidnet_session_id}
             end)

    assert session_id == session.id
    refute_received :bidnet_refresh
  end

  test "distinguishes missing and invalid credentials" do
    missing_source = bidnet_source()

    assert {:error, {:bidnet_credentials, :missing}} =
             BidNetProvider.with_session(missing_source, %{}, fn _context -> :unreachable end)

    invalid_source = bidnet_source()
    credential = bidnet_credential(invalid_source)

    assert {:ok, _credential} =
             Procurement.mark_source_credential_failed(
               credential,
               %{last_failure_reason: "Rejected."},
               authorize?: false
             )

    assert {:error, {:bidnet_credentials, :invalid}} =
             BidNetProvider.with_session(invalid_source, %{}, fn _context -> :unreachable end)

    pending_source = bidnet_source()
    _credential = bidnet_credential(pending_source)

    assert {:error, {:bidnet_credentials, :pending}} =
             BidNetProvider.with_session(pending_source, %{}, fn _context -> :unreachable end)
  end

  test "expires stale state, refreshes once, and materializes the replacement" do
    source = bidnet_source()
    credential = verified_credential(source)

    {:ok, stale} =
      Procurement.create_source_browser_session(%{
        procurement_source_id: source.id,
        source_credential_id: credential.id,
        provider: :bidnet,
        session_family: "bidnet"
      })

    {:ok, stale} =
      Procurement.mark_source_browser_session_valid(stale, %{
        storage_state: Jason.encode!(%{"cookies" => []}),
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    assert {:ok, :scanned} =
             BidNetProvider.with_session(
               source,
               %{bidnet_session_runner: RefreshRunner},
               fn context ->
                 assert File.read!(context.bidnet_storage_state_path) =~ "refreshed-cookie"
                 {:ok, :scanned}
               end
             )

    assert_receive :bidnet_refresh
    assert {:ok, expired} = Procurement.get_source_browser_session(stale.id, authorize?: false)
    assert expired.status == :expired

    assert {:ok, [replacement]} =
             Procurement.list_valid_source_browser_sessions_for_source(source.id,
               authorize?: false
             )

    assert replacement.id != stale.id
  end

  defp bidnet_source do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "BidNet Provider #{System.unique_integer([:positive])}",
        url: "https://www.bidnetdirect.com/california/solicitations/open-bids",
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    source
  end

  defp verified_credential(source) do
    credential = bidnet_credential(source)

    {:ok, credential} =
      Procurement.mark_source_credential_verified(credential, %{}, authorize?: false)

    credential
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

  defp valid_session(source, credential, cookie) do
    {:ok, session} =
      Procurement.create_source_browser_session(%{
        procurement_source_id: source.id,
        source_credential_id: credential.id,
        provider: :bidnet,
        session_family: "bidnet"
      })

    {:ok, session} =
      Procurement.mark_source_browser_session_valid(session, %{
        storage_state:
          Jason.encode!(%{
            "cookies" => [%{"name" => "sid", "value" => cookie}]
          }),
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    session
  end
end
