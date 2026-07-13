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
         secret_envelope:
           GnomeGarden.Procurement.PlaywrightRunner.envelope(%{
             "storageState" => %{
               "cookies" => [%{"name" => "sid", "value" => "cookie-secret"}]
             }
           })
       }}
    end
  end

  defmodule FailingRunner do
    def run(action, payload, opts) do
      send(Process.get(:test_pid), {:runner, action, payload, opts})

      {:error,
       %{
         "code" => "invalid_credentials",
         "error" => "BidNet rejected source-secret for operator@example.com."
       }}
    end
  end

  defmodule RetryRunner do
    def run(action, payload, opts) do
      attempt = Process.get(:bidnet_retry_attempt, 0) + 1
      Process.put(:bidnet_retry_attempt, attempt)
      send(Process.get(:test_pid), {:runner_attempt, attempt, action, payload, opts})

      if attempt == 1 do
        {:error, %{"code" => "timeout", "error" => "BidNet timed out."}}
      else
        SuccessfulRunner.run(action, payload, opts)
      end
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
    refute Map.has_key?(payload, :username)
    refute Map.has_key?(payload, :password)
    refute inspect(runner_opts) =~ "source-secret"
    assert Keyword.fetch!(runner_opts, :timeout_ms) == 15_000

    assert session.status == :valid
    assert session.provider == :bidnet
    assert session.session_family == "bidnet"
    assert session.source_credential_id == credential.id
    assert is_map(session.encrypted_storage_state)
    refute inspect(session) =~ "cookie-secret"
    assert session.verified_at
    assert session.expires_at
    assert session.metadata["final_url"] == "https://www.bidnetdirect.com/private"
    refute Jason.encode!(session.metadata) =~ "source-secret"
    refute Jason.encode!(session.metadata) =~ "cookie-secret"
  end

  test "refreshes a BidNet session using Bitwarden-backed credentials" do
    original_cli = System.get_env("GARDEN_BITWARDEN_CLI")
    original_runner = Application.get_env(:gnome_garden, :bitwarden_command_runner)
    original_session = Application.get_env(:gnome_garden, :bitwarden_session)

    System.put_env("GARDEN_BITWARDEN_CLI", "/usr/local/bin/bitwarden")
    Application.put_env(:gnome_garden, :bitwarden_session, "test-session")

    Application.put_env(:gnome_garden, :bitwarden_command_runner, fn _command, _args, _opts ->
      item = %{
        "login" => %{
          "username" => "operator@example.com",
          "password" => "bitwarden-secret"
        }
      }

      {Jason.encode!(item), 0}
    end)

    on_exit(fn ->
      restore_env("GARDEN_BITWARDEN_CLI", original_cli)
      restore_app_env(:bitwarden_command_runner, original_runner)
      restore_app_env(:bitwarden_session, original_session)
    end)

    source = bidnet_source()

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :bidnet,
        credential_family: "bidnet",
        scope: :source,
        procurement_source_id: source.id,
        credential_storage: :bitwarden,
        username: "operator@example.com",
        bitwarden_item_name: "BidNet"
      })

    assert {:ok, _credential} =
             Procurement.mark_source_credential_manual_verification_required(credential, %{
               last_failure_reason: "Generic browser verifier cannot validate BidNet."
             })

    assert {:ok, session} =
             Procurement.refresh_bidnet_source_session(source, runner: SuccessfulRunner)

    assert_receive {:runner, :bidnet_login, payload, _runner_opts}
    refute Map.has_key?(payload, :username)
    refute Map.has_key?(payload, :password)
    assert session.source_credential_id == credential.id
  end

  test "invalid credentials fail once and invalidate the credential" do
    source = bidnet_source()
    credential = bidnet_credential(source)

    assert {:ok, _credential} =
             Procurement.mark_source_credential_manual_verification_required(credential, %{
               last_failure_reason: "Generic browser verifier cannot validate BidNet."
             })

    assert {:error,
            %{
              session: failed,
              reason: "BidNet rejected [REDACTED] for [REDACTED]."
            }} =
             Procurement.refresh_bidnet_source_session(source, runner: FailingRunner)

    assert_receive {:runner, :bidnet_login, payload, _runner_opts}
    refute Map.has_key?(payload, :password)
    refute_receive {:runner, :bidnet_login, _payload, _runner_opts}

    assert failed.status == :invalid
    assert failed.last_failure_reason == "BidNet rejected [REDACTED] for [REDACTED]."
    assert failed.metadata["failure_code"] == "invalid_credentials"
    refute inspect(failed.metadata) =~ "source-secret"

    assert {:ok, unchanged_credential} =
             Procurement.get_source_credential(credential.id, authorize?: false)

    assert unchanged_credential.status == :invalid
    assert unchanged_credential.test_status == :invalid

    assert unchanged_credential.last_failure_reason ==
             "BidNet rejected [REDACTED] for [REDACTED]."
  end

  test "transient failures retry within the configured bound" do
    source = bidnet_source()
    credential = bidnet_credential(source)

    assert {:ok, _credential} =
             Procurement.mark_source_credential_verified(credential, %{}, authorize?: false)

    assert {:ok, session} =
             Procurement.refresh_bidnet_source_session(source,
               runner: RetryRunner,
               max_attempts: 2
             )

    assert_receive {:runner_attempt, 1, :bidnet_login, _payload, _opts}
    assert_receive {:runner_attempt, 2, :bidnet_login, _payload, _opts}
    assert session.status == :valid
    assert session.metadata["attempt_count"] == 2
  end

  test "a refreshed session expires the previously valid session" do
    source = bidnet_source()
    credential = bidnet_credential(source)

    assert {:ok, _credential} =
             Procurement.mark_source_credential_verified(credential, %{}, authorize?: false)

    assert {:ok, first} =
             Procurement.refresh_bidnet_source_session(source, runner: SuccessfulRunner)

    assert {:ok, second} =
             Procurement.refresh_bidnet_source_session(source, runner: SuccessfulRunner)

    assert first.id != second.id

    assert {:ok, expired_first} =
             Procurement.get_source_browser_session(first.id, authorize?: false)

    assert expired_first.status == :expired
    refute expired_first.encrypted_storage_state

    assert {:ok, [valid]} =
             Procurement.list_valid_source_browser_sessions_for_source(source.id,
               authorize?: false
             )

    assert valid.id == second.id
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

  defp restore_app_env(key, nil), do: Application.delete_env(:gnome_garden, key)
  defp restore_app_env(key, value), do: Application.put_env(:gnome_garden, key, value)

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
