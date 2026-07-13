defmodule GnomeGarden.Procurement.SourceBrowserSessionTest do
  use GnomeGarden.DataCase, async: false

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BrowserSessionCustody

  test "encrypts, resolves, and temporarily materializes identity-bound storage state" do
    source = procurement_source()
    credential = source_credential(source)

    storage_state =
      Jason.encode!(%{"cookies" => [%{"name" => "sid", "value" => "cookie-secret"}]})

    valid = valid_session(source, credential, storage_state)

    assert valid.status == :valid
    assert is_map(valid.encrypted_storage_state)
    refute inspect(valid) =~ "cookie-secret"

    assert {:ok, ^storage_state} =
             Procurement.resolve_source_browser_session_state(
               valid.id,
               source.id,
               credential.id,
               authorize?: false
             )

    assert {:ok, [listed]} = Procurement.list_valid_source_browser_sessions_for_source(source.id)
    assert listed.id == valid.id

    assert :ok =
             BrowserSessionCustody.with_materialized(valid, fn path ->
               assert File.read!(path) == storage_state
               assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
               Process.put(:materialized_path, path)
               :ok
             end)

    refute File.exists?(Process.get(:materialized_path))
  end

  test "expired sessions are neither listed nor resolved" do
    source = procurement_source()
    credential = source_credential(source)

    valid =
      valid_session(source, credential, Jason.encode!(%{"cookies" => []}),
        expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      )

    assert {:ok, []} = Procurement.list_valid_source_browser_sessions_for_source(source.id)

    assert {:error, _error} =
             Procurement.resolve_source_browser_session_state(
               valid.id,
               source.id,
               credential.id,
               authorize?: false
             )

    assert {:ok, expired} =
             Procurement.expire_source_browser_session(
               valid,
               %{last_failure_reason: "Session TTL elapsed."}
             )

    assert expired.status == :expired
    assert is_nil(expired.encrypted_storage_state)
    assert is_nil(expired.credential_fingerprint)
  end

  test "rejects malformed storage state before persistence" do
    source = procurement_source()
    credential = source_credential(source)

    session =
      Procurement.create_source_browser_session!(%{
        procurement_source_id: source.id,
        source_credential_id: credential.id,
        provider: :bidnet,
        session_family: "bidnet"
      })

    assert {:error, error} =
             Procurement.mark_source_browser_session_valid(session, %{
               storage_state: "not-json",
               expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
             })

    assert inspect(error) =~ "must be a JSON object"
    assert {:ok, unchanged} = Procurement.get_source_browser_session(session.id)
    assert unchanged.status == :pending
    assert is_nil(unchanged.encrypted_storage_state)
  end

  test "credential rotation expires every bound browser session" do
    source = procurement_source()
    credential = source_credential(source)
    valid = valid_session(source, credential, Jason.encode!(%{"cookies" => []}))

    assert {:ok, rotated} =
             Procurement.rotate_source_credential(credential, %{password: "rotated-secret"},
               authorize?: false
             )

    assert rotated.password_fingerprint != credential.password_fingerprint
    assert {:ok, expired} = Procurement.get_source_browser_session(valid.id)
    assert expired.status == :expired
    assert is_nil(expired.encrypted_storage_state)

    assert {:error, _error} =
             Procurement.resolve_source_browser_session_state(
               valid.id,
               source.id,
               credential.id,
               authorize?: false
             )
  end

  test "credential compromise destroys bound session material" do
    source = procurement_source()
    credential = source_credential(source)
    valid = valid_session(source, credential, Jason.encode!(%{"cookies" => []}))

    assert {:ok, compromised_credential} =
             Procurement.compromise_source_credential(
               credential,
               %{last_failure_reason: "Operator reported account takeover."},
               authorize?: false
             )

    assert compromised_credential.status == :invalid
    assert {:ok, compromised} = Procurement.get_source_browser_session(valid.id)
    assert compromised.status == :compromised
    assert is_nil(compromised.encrypted_storage_state)
    assert is_nil(compromised.credential_fingerprint)
  end

  test "marks session failures without disabling the related credential" do
    source = procurement_source()
    credential = source_credential(source)

    session =
      Procurement.create_source_browser_session!(%{
        procurement_source_id: source.id,
        source_credential_id: credential.id,
        provider: :bidnet,
        session_family: "bidnet"
      })

    assert {:ok, failed} =
             Procurement.mark_source_browser_session_failed(session, %{
               last_failure_reason: "SAML challenge could not be completed"
             })

    assert failed.status == :invalid
    assert failed.last_refresh_completed_at

    assert {:ok, %{status: :active}} =
             Procurement.get_source_credential(credential.id, authorize?: false)
  end

  defp valid_session(source, credential, storage_state, opts \\ []) do
    session =
      Procurement.create_source_browser_session!(%{
        procurement_source_id: source.id,
        source_credential_id: credential.id,
        provider: :bidnet,
        session_family: "bidnet"
      })

    session =
      Procurement.mark_source_browser_session_refreshing!(session, %{
        source_credential_id: credential.id
      })

    Procurement.mark_source_browser_session_valid!(session, %{
      storage_state: storage_state,
      expires_at:
        Keyword.get(opts, :expires_at, DateTime.add(DateTime.utc_now(), 86_400, :second)),
      metadata: %{"final_url" => "https://www.bidnetdirect.com/private"}
    })
  end

  defp procurement_source do
    Procurement.create_procurement_source!(%{
      name: "BidNet Session Source #{System.unique_integer([:positive])}",
      url: "https://www.bidnetdirect.com/california/solicitations/open-bids",
      source_type: :bidnet,
      region: :ca,
      priority: :high,
      status: :approved
    })
  end

  defp source_credential(source) do
    Procurement.create_source_credential!(%{
      provider: :bidnet,
      credential_family: "bidnet",
      scope: :source,
      procurement_source_id: source.id,
      username: "operator@example.com",
      password: "secret"
    })
  end
end
