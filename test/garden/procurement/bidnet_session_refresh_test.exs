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
    assert payload.username == "operator@example.com"
    assert payload.password == "bitwarden-secret"
    assert session.source_credential_id == credential.id
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

  defp restore_app_env(key, nil), do: Application.delete_env(:gnome_garden, key)
  defp restore_app_env(key, value), do: Application.put_env(:gnome_garden, key, value)

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
