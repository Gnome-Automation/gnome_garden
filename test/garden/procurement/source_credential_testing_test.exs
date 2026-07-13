defmodule GnomeGarden.Procurement.SourceCredentialTestingTest do
  use GnomeGarden.DataCase, async: false
  use Oban.Testing, repo: GnomeGarden.Repo

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.SourceCredentialTesting
  alias GnomeGarden.Procurement.Workers.TestSourceCredential

  defmodule BrowserSuccess do
    def navigate(url, _opts), do: {:ok, %{url: url, title: "Login", status: :ok}}

    def evaluate(js) do
      send(Process.get(:test_pid), {:browser_script, js})
      count = Process.get({__MODULE__, :evaluate_count}, 0)
      Process.put({__MODULE__, :evaluate_count}, count + 1)

      case count do
        0 ->
          {:ok, %{"has_login_form" => true}}

        1 ->
          {:ok, %{"submitted" => true, "method" => "form_button"}}

        _ ->
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

    def type(selector, value) do
      send(Process.get(:test_pid), {:browser_type, selector, value})
      {:ok, %{}}
    end

    def click(_selector), do: {:ok, %{}}
  end

  defmodule BrowserInvalid do
    def navigate(url, _opts), do: {:ok, %{url: url, title: "Login", status: :ok}}

    def evaluate(_js) do
      count = Process.get({__MODULE__, :evaluate_count}, 0)
      Process.put({__MODULE__, :evaluate_count}, count + 1)

      case count do
        0 ->
          {:ok, %{"has_login_form" => true}}

        1 ->
          {:ok, %{"submitted" => true, "method" => "form_button"}}

        _ ->
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

    def type(_selector, _value), do: {:ok, %{}}
    def click(_selector), do: {:ok, %{}}
  end

  defmodule BrowserShouldNotRun do
    def navigate(_url, _opts), do: raise("BidNet must not use the generic browser verifier")

    def evaluate(_js), do: raise("BidNet must not use the generic browser verifier")
    def type(_selector, _value), do: raise("BidNet must not use the generic browser verifier")
    def click(_selector), do: raise("BidNet must not use the generic browser verifier")
  end

  defmodule SuccessfulBidNetRunner do
    def run(_action, payload, opts) do
      send(Process.get(:test_pid), {:bidnet_verification, payload, opts})

      {:ok,
       %{
         "finalUrl" => "https://www.bidnetdirect.com/private",
         "title" => "BidNet Direct",
         "status" => 200,
         secret_envelope:
           GnomeGarden.Procurement.PlaywrightRunner.envelope(%{
             "storageState" => %{
               "cookies" => [%{"name" => "sid", "value" => "verified-cookie"}]
             }
           })
       }}
    end
  end

  defmodule UnavailableBidNetRunner do
    def run(_action, _payload, _opts) do
      send(Process.get(:test_pid), :bidnet_verification_attempt)
      {:error, %{"code" => "timeout", "error" => "BidNet timed out."}}
    end
  end

  setup do
    Process.put(:test_pid, self())
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

    assert_receive {:browser_script, discovery_script}
    assert_receive {:browser_script, submit_script}
    assert_receive {:browser_script, result_script}
    refute discovery_script =~ "source-secret"
    refute submit_script =~ "source-secret"
    refute result_script =~ "source-secret"
    assert_receive {:browser_type, _selector, "source-secret"}
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

  test "worker verifies BidNet credentials by creating a browser session" do
    Application.put_env(:gnome_garden, :source_credential_browser, BrowserShouldNotRun)
    original_runner = Application.get_env(:gnome_garden, :bidnet_session_runner)
    Application.put_env(:gnome_garden, :bidnet_session_runner, SuccessfulBidNetRunner)
    on_exit(fn -> restore_app_env(:bidnet_session_runner, original_runner) end)

    source = bidnet_source()
    credential = bidnet_credential(source)

    assert :ok =
             TestSourceCredential.perform(%Oban.Job{
               args: %{
                 "source_credential_id" => credential.id,
                 "procurement_source_id" => source.id
               }
             })

    assert_receive {:bidnet_verification, payload, runner_opts}
    refute Map.has_key?(payload, :username)
    refute Map.has_key?(payload, :password)
    refute inspect(runner_opts) =~ "source-secret"

    assert {:ok, verified} =
             Procurement.get_source_credential(credential.id, authorize?: false)

    assert verified.status == :active
    assert verified.test_status == :verified
    assert verified.last_test_started_at
    assert verified.last_test_completed_at

    assert {:ok, [session]} =
             Procurement.list_valid_source_browser_sessions_for_source(source.id,
               authorize?: false
             )

    assert session.source_credential_id == credential.id
  end

  test "worker verifies untested BidNet Bitwarden credentials from the vault reference" do
    original_cli = System.get_env("GARDEN_BITWARDEN_CLI")
    original_runner = Application.get_env(:gnome_garden, :bitwarden_command_runner)
    original_session = Application.get_env(:gnome_garden, :bitwarden_session)

    System.put_env("GARDEN_BITWARDEN_CLI", "/usr/local/bin/bitwarden")
    Application.put_env(:gnome_garden, :bitwarden_session, "test-session")
    Application.put_env(:gnome_garden, :source_credential_browser, BrowserShouldNotRun)
    original_bidnet_runner = Application.get_env(:gnome_garden, :bidnet_session_runner)
    Application.put_env(:gnome_garden, :bidnet_session_runner, SuccessfulBidNetRunner)

    Application.put_env(:gnome_garden, :bitwarden_command_runner, fn command, args, opts ->
      send(self(), {:bitwarden_cli, command, args, opts})

      item = %{
        "login" => %{
          "username" => "bidnet-vault@example.com",
          "password" => "vault-secret"
        }
      }

      {Jason.encode!(item), 0}
    end)

    on_exit(fn ->
      restore_env("GARDEN_BITWARDEN_CLI", original_cli)
      restore_app_env(:bitwarden_command_runner, original_runner)
      restore_app_env(:bitwarden_session, original_session)
      restore_app_env(:bidnet_session_runner, original_bidnet_runner)
    end)

    source = bidnet_source()

    {:ok, credential} =
      Procurement.create_source_credential(%{
        provider: :bidnet,
        credential_family: "bidnet",
        procurement_source_id: source.id,
        credential_storage: :bitwarden,
        bitwarden_item_id: "bidnet-item-id"
      })

    assert :ok =
             TestSourceCredential.perform(%Oban.Job{
               args: %{
                 "source_credential_id" => credential.id,
                 "procurement_source_id" => source.id
               }
             })

    assert_received {:bitwarden_cli, "/usr/local/bin/bitwarden",
                     ["get", "item", "bidnet-item-id", "--session", "test-session"], opts}

    assert {"BW_SESSION", "test-session"} in Keyword.fetch!(opts, :env)

    assert_receive {:bidnet_verification, payload, runner_opts}
    refute Map.has_key?(payload, :username)
    refute Map.has_key?(payload, :password)
    refute inspect(runner_opts) =~ "vault-secret"

    assert {:ok, verified} =
             Procurement.get_source_credential(credential.id, authorize?: false)

    assert verified.status == :active
    assert verified.test_status == :verified
  end

  test "transient BidNet outages do not invalidate saved credentials" do
    original_runner = Application.get_env(:gnome_garden, :bidnet_session_runner)
    Application.put_env(:gnome_garden, :bidnet_session_runner, UnavailableBidNetRunner)
    on_exit(fn -> restore_app_env(:bidnet_session_runner, original_runner) end)

    source = bidnet_source()
    credential = bidnet_credential(source)

    assert :ok =
             TestSourceCredential.perform(%Oban.Job{
               args: %{
                 "source_credential_id" => credential.id,
                 "procurement_source_id" => source.id
               }
             })

    assert_receive :bidnet_verification_attempt
    assert_receive :bidnet_verification_attempt
    refute_receive :bidnet_verification_attempt

    assert {:ok, unavailable} =
             Procurement.get_source_credential(credential.id, authorize?: false)

    assert unavailable.status == :active
    assert unavailable.test_status == :unavailable
    assert unavailable.last_failure_reason =~ "Credential verification unavailable"
    assert GnomeGarden.Procurement.SourceCredentials.credential_status(source) == :pending
  end

  test "pre-session Bitwarden failures do not invalidate BidNet credentials" do
    original_cli = System.get_env("GARDEN_BITWARDEN_CLI")
    original_runner = Application.get_env(:gnome_garden, :bitwarden_command_runner)
    original_session = Application.get_env(:gnome_garden, :bitwarden_session)

    System.put_env("GARDEN_BITWARDEN_CLI", "/usr/local/bin/bitwarden")
    Application.put_env(:gnome_garden, :bitwarden_session, "test-session")

    Application.put_env(:gnome_garden, :bitwarden_command_runner, fn _command, _args, _opts ->
      {"vault unavailable", 1}
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
        bitwarden_item_id: "bidnet-item-id"
      })

    assert :ok =
             TestSourceCredential.perform(%Oban.Job{
               args: %{
                 "source_credential_id" => credential.id,
                 "procurement_source_id" => source.id
               }
             })

    assert {:ok, unavailable} =
             Procurement.get_source_credential(credential.id, authorize?: false)

    assert unavailable.status == :active
    assert unavailable.test_status == :unavailable
    assert unavailable.last_failure_reason =~ "Credential verification unavailable"
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
