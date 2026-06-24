defmodule GnomeGarden.Procurement.SourceBrowserSessionTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement

  test "records and resolves a valid browser session for a procurement source" do
    source = procurement_source()
    credential = source_credential(source)

    assert {:ok, session} =
             Procurement.create_source_browser_session(%{
               procurement_source_id: source.id,
               source_credential_id: credential.id,
               provider: :bidnet,
               session_family: "bidnet",
               storage_state_path: "/tmp/gnome-garden/browser-sessions/bidnet/state.json",
               expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
             })

    assert session.status == :pending
    assert session.browser_name == "chromium"

    assert {:ok, refreshing} =
             Procurement.mark_source_browser_session_refreshing(session, %{
               source_credential_id: credential.id
             })

    assert refreshing.status == :refreshing
    assert refreshing.last_refresh_started_at
    refute refreshing.last_failure_reason

    assert {:ok, valid} =
             Procurement.mark_source_browser_session_valid(refreshing, %{
               storage_state_path: "/tmp/gnome-garden/browser-sessions/bidnet/state-v2.json",
               storage_state_fingerprint: "fingerprint",
               expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second),
               trace_path: "/tmp/gnome-garden/browser-sessions/bidnet/trace.zip",
               screenshot_path: "/tmp/gnome-garden/browser-sessions/bidnet/screenshot.png",
               metadata: %{"final_url" => "https://www.bidnetdirect.com/private"}
             })

    assert valid.status == :valid
    assert valid.verified_at
    assert valid.last_refresh_completed_at
    refute valid.last_failure_reason

    assert {:ok, [valid_session]} =
             Procurement.list_valid_source_browser_sessions_for_source(source.id)

    assert valid_session.id == valid.id
  end

  test "marks session failures without disabling the related credential" do
    source = procurement_source()
    credential = source_credential(source)

    assert {:ok, session} =
             Procurement.create_source_browser_session(%{
               procurement_source_id: source.id,
               source_credential_id: credential.id,
               provider: :bidnet,
               session_family: "bidnet"
             })

    assert {:ok, failed} =
             Procurement.mark_source_browser_session_failed(session, %{
               last_failure_reason: "SAML challenge could not be completed",
               trace_path: "/tmp/trace.zip"
             })

    assert failed.status == :invalid
    assert failed.last_refresh_completed_at
    assert failed.last_failure_reason == "SAML challenge could not be completed"

    assert {:ok, unchanged_credential} =
             Procurement.get_source_credential(credential.id, authorize?: false)

    assert unchanged_credential.status == :active
  end

  defp procurement_source do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "BidNet Session Source #{System.unique_integer([:positive])}",
        url: "https://www.bidnetdirect.com/california/solicitations/open-bids",
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved
      })

    source
  end

  defp source_credential(source) do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :bidnet,
        credential_family: "bidnet",
        scope: :source,
        procurement_source_id: source.id,
        username: "operator@example.com",
        password: "secret"
      })

    credential
  end
end
