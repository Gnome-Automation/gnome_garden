defmodule GnomeGarden.Procurement.SourceCredentialTestingTest do
  use GnomeGarden.DataCase, async: false
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.SourceCredentialTesting
  alias GnomeGarden.Procurement.Workers.TestSourceCredential

  defmodule BrowserSuccess do
    def navigate(url, _opts), do: {:ok, %{url: url, title: "Login", status: :ok}}

    def evaluate(_js) do
      count = Process.get({__MODULE__, :evaluate_count}, 0)
      Process.put({__MODULE__, :evaluate_count}, count + 1)

      if count == 0 do
        {:ok, %{"submitted" => true}}
      else
        {:ok,
         %{
           "success" => true,
           "invalid" => false,
           "has_password" => false,
           "signal" => "Sign out",
           "url" => "https://vendors.planetbids.com/account",
           "title" => "Account"
         }}
      end
    end
  end

  defmodule BrowserInvalid do
    def navigate(url, _opts), do: {:ok, %{url: url, title: "Login", status: :ok}}

    def evaluate(_js) do
      count = Process.get({__MODULE__, :evaluate_count}, 0)
      Process.put({__MODULE__, :evaluate_count}, count + 1)

      if count == 0 do
        {:ok, %{"submitted" => true}}
      else
        {:ok,
         %{
           "success" => false,
           "invalid" => true,
           "has_password" => true,
           "reason" => "The portal rejected these credentials.",
           "url" => "https://vendors.planetbids.com/login",
           "title" => "Login"
         }}
      end
    end
  end

  defmodule BrowserShouldNotRun do
    def navigate(_url, _opts), do: raise("BidNet must not use the generic browser verifier")

    def evaluate(_js), do: raise("BidNet must not use the generic browser verifier")
  end

  setup do
    original_browser = Application.get_env(:gnome_garden, :source_credential_browser)
    original_wait = Application.get_env(:gnome_garden, :source_credential_login_wait_ms)

    Application.put_env(:gnome_garden, :source_credential_login_wait_ms, 0)

    on_exit(fn ->
      restore_app_env(:source_credential_browser, original_browser)
      restore_app_env(:source_credential_login_wait_ms, original_wait)
    end)

    :ok
  end

  test "queueing marks credentials queued and enqueues a browser test job" do
    source = procurement_source()
    credential = planetbids_credential()

    assert {:ok, queued} =
             SourceCredentialTesting.enqueue(credential, procurement_source_id: source.id)

    assert queued.test_status == :queued
    assert queued.last_test_procurement_source_id == source.id
    assert queued.last_test_queued_at

    assert_enqueued(
      worker: TestSourceCredential,
      args: %{
        "source_credential_id" => credential.id,
        "procurement_source_id" => source.id
      }
    )
  end

  test "worker verifies browser credentials through the browser facade" do
    Application.put_env(:gnome_garden, :source_credential_browser, BrowserSuccess)

    source = procurement_source()
    credential = planetbids_credential()

    assert :ok =
             TestSourceCredential.perform(%Oban.Job{
               args: %{
                 "source_credential_id" => credential.id,
                 "procurement_source_id" => source.id
               }
             })

    assert {:ok, verified} = Procurement.get_source_credential(credential.id, authorize?: false)
    assert verified.status == :active
    assert verified.test_status == :verified
    assert verified.last_verified_at
    assert verified.last_test_started_at
    assert verified.last_test_completed_at
    refute verified.last_failure_reason
  end

  test "worker marks rejected browser credentials invalid" do
    Application.put_env(:gnome_garden, :source_credential_browser, BrowserInvalid)

    source = procurement_source()
    credential = planetbids_credential()

    assert :ok =
             TestSourceCredential.perform(%Oban.Job{
               args: %{
                 "source_credential_id" => credential.id,
                 "procurement_source_id" => source.id
               }
             })

    assert {:ok, invalid} = Procurement.get_source_credential(credential.id, authorize?: false)
    assert invalid.status == :invalid
    assert invalid.test_status == :invalid
    assert invalid.last_test_started_at
    assert invalid.last_test_completed_at
    assert invalid.last_failure_reason == "The portal rejected these credentials."
  end

  test "worker leaves BidNet credentials active and skips generic browser verification" do
    Application.put_env(:gnome_garden, :source_credential_browser, BrowserShouldNotRun)

    source = bidnet_source()
    credential = bidnet_credential(source)

    assert :ok =
             TestSourceCredential.perform(%Oban.Job{
               args: %{
                 "source_credential_id" => credential.id,
                 "procurement_source_id" => source.id
               }
             })

    assert {:ok, manual_required} =
             Procurement.get_source_credential(credential.id, authorize?: false)

    assert manual_required.status == :active
    assert manual_required.test_status == :manual_required
    assert manual_required.last_test_started_at
    assert manual_required.last_test_completed_at

    assert manual_required.last_failure_reason ==
             "Use BidNet browser session refresh to verify browser access."
  end

  test "BidNet manual verification status still resolves saved credentials" do
    source = bidnet_source()
    credential = bidnet_credential(source)

    assert {:ok, _credential} =
             Procurement.mark_source_credential_manual_verification_required(credential, %{
               last_failure_reason: "Use BidNet browser session refresh to verify browser access."
             })

    assert GnomeGarden.Procurement.SourceCredentials.credentials_configured?(source)

    assert {:ok, %{username: "bidnet@example.com", password: "source-secret"}} =
             GnomeGarden.Procurement.SourceCredentials.credentials_for(source)
  end

  test "SAM.gov credentials are verified through the SAM API client" do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :sam_gov,
        credential_family: "sam_gov",
        api_key: "sam-secret"
      })

    http_get = fn _url, _opts -> {:ok, %{status: 200, body: %{"opportunitiesData" => []}}} end

    assert {:ok, %{provider: :sam_gov, verified?: true}} =
             SourceCredentialTesting.test_credential(credential, http_get: http_get)
  end

  test "SAM.gov Bitwarden credentials are verified through the SAM API client" do
    original_cli = System.get_env("GARDEN_BITWARDEN_CLI")
    original_runner = Application.get_env(:gnome_garden, :bitwarden_command_runner)
    original_session = Application.get_env(:gnome_garden, :bitwarden_session)

    System.put_env("GARDEN_BITWARDEN_CLI", "/usr/local/bin/bitwarden")
    Application.put_env(:gnome_garden, :bitwarden_session, "test-session")

    Application.put_env(:gnome_garden, :bitwarden_command_runner, fn command, args, opts ->
      send(self(), {:bitwarden_cli, command, args, opts})

      item = %{
        "fields" => [
          %{"name" => "SAM_GOV_API_KEY", "value" => "vault-sam-secret"}
        ]
      }

      {Jason.encode!(item), 0}
    end)

    on_exit(fn ->
      restore_env("GARDEN_BITWARDEN_CLI", original_cli)
      restore_app_env(:bitwarden_command_runner, original_runner)
      restore_app_env(:bitwarden_session, original_session)
    end)

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :sam_gov,
        credential_family: "sam_gov",
        credential_storage: :bitwarden,
        bitwarden_item_name: "SAM.gov"
      })

    http_get = fn _url, opts ->
      assert Keyword.fetch!(opts, :params).api_key == "vault-sam-secret"
      {:ok, %{status: 200, body: %{"opportunitiesData" => []}}}
    end

    assert {:ok, %{provider: :sam_gov, verified?: true}} =
             SourceCredentialTesting.test_credential(credential, http_get: http_get)

    assert_received {:bitwarden_cli, "/usr/local/bin/bitwarden",
                     ["get", "item", "SAM.gov", "--session", "test-session"], opts}

    assert {"BW_SESSION", "test-session"} in Keyword.fetch!(opts, :env)
  end

  defp procurement_source do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "Credential Test Portal #{System.unique_integer([:positive])}",
        url: "https://vendors.planetbids.com/portal/10000/bo/bo-search",
        source_type: :planetbids,
        portal_id: "10000",
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
      })

    source
  end

  defp planetbids_credential do
    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :planetbids,
        credential_family: "planetbids",
        username: "operator@example.com",
        password: "source-secret"
      })

    credential
  end

  defp bidnet_source do
    {:ok, source} =
      Procurement.create_procurement_source(%{
        name: "BidNet Test Portal #{System.unique_integer([:positive])}",
        url: "https://www.bidnetdirect.com/california/solicitations/open-bids",
        source_type: :bidnet,
        region: :ca,
        priority: :high,
        status: :approved,
        requires_login: true
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
        username: "bidnet@example.com",
        password: "source-secret"
      })

    credential
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:gnome_garden, key)
  defp restore_app_env(key, value), do: Application.put_env(:gnome_garden, key, value)

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
