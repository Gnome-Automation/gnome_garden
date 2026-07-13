defmodule GnomeGarden.Procurement.SourceCredentialTesting do
  @moduledoc """
  Queues and executes credential verification probes for procurement sources.

  BidNet credentials are not verified with the generic form-login probe. BidNet
  access is validated by refreshing a persisted Playwright browser session.
  """

  alias GnomeGarden.Agents.Tools.Procurement.QuerySamGov
  alias GnomeGarden.Browser.LoginForm
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BitwardenCredentialResolver
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.SourceCredential
  alias GnomeGarden.Procurement.SourceCredentialCrypto

  @browser_wait_ms 3_500

  def enqueue(credential_or_id, opts \\ [])

  def enqueue(%SourceCredential{} = credential, opts) do
    procurement_source_id = Keyword.get(opts, :procurement_source_id)

    Procurement.mark_source_credential_test_queued(
      credential,
      %{last_test_procurement_source_id: procurement_source_id},
      authorize?: false
    )
  end

  def enqueue(credential_id, opts) when is_binary(credential_id) do
    with {:ok, credential} <- Procurement.get_source_credential(credential_id, authorize?: false) do
      enqueue(credential, opts)
    end
  end

  def test_credential(credential, opts \\ [])

  def test_credential(%SourceCredential{provider: :sam_gov} = credential, opts) do
    with {:ok, api_key} <- api_key_from_credential(credential),
         {:ok, _result} <-
           QuerySamGov.run(
             %{limit: 1},
             %{sam_gov_api_key: api_key, http_get: Keyword.get(opts, :http_get)}
           ) do
      {:ok, %{provider: :sam_gov, verified?: true}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def test_credential(%SourceCredential{provider: :bidnet} = credential, opts) do
    refresh_opts =
      [
        credential: credential,
        runner: Keyword.get(opts, :runner),
        max_attempts: Keyword.get(opts, :max_attempts, 2),
        timeout_ms: Keyword.get(opts, :timeout_ms, 60_000)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    with {:ok, source} <- source_for_test(credential, opts) do
      case Procurement.refresh_bidnet_source_session(source, refresh_opts) do
        {:ok, session} ->
          {:ok, %{provider: :bidnet, verified?: true, browser_session_id: session.id}}

        {:error, %{session: session, reason: reason}} ->
          if session.metadata["failure_code"] == "invalid_credentials" do
            {:error, reason}
          else
            {:error, {:verification_unavailable, reason}}
          end

        {:error, reason} ->
          {:error, {:verification_unavailable, reason}}
      end
    end
  end

  def test_credential(%SourceCredential{} = credential, opts) do
    with {:ok, source} <- source_for_test(credential, opts),
         {:ok, credentials} <- username_password_from_credential(credential),
         {:ok, result} <- browser_login_probe(source.url, credentials, opts) do
      {:ok, Map.merge(result, %{provider: credential.provider, verified?: true})}
    end
  end

  def manual_verification_required?({:manual_verification_required, _reason}), do: true
  def manual_verification_required?(_reason), do: false

  def manual_verification_reason({:manual_verification_required, reason}),
    do: format_reason(reason)

  def manual_verification_reason(reason), do: format_reason(reason)

  def format_reason({:manual_verification_required, reason}) do
    "Manual verification required: #{format_reason(reason)}"
  end

  def format_reason({:verification_unavailable, reason}) do
    "Credential verification unavailable: #{format_reason(reason)}"
  end

  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason(reason), do: inspect(reason)

  def verification_unavailable?({:verification_unavailable, _reason}), do: true
  def verification_unavailable?(_reason), do: false

  defp api_key_from_credential(%{encrypted_api_key: payload}) when is_map(payload) do
    {:ok, SourceCredentialCrypto.decrypt_secret!(payload)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp api_key_from_credential(%{credential_storage: :bitwarden} = credential) do
    BitwardenCredentialResolver.api_key(credential)
  end

  defp api_key_from_credential(_credential), do: {:error, "API key is missing."}

  defp username_password_from_credential(%{credential_storage: :bitwarden} = credential) do
    BitwardenCredentialResolver.username_password(credential)
  end

  defp username_password_from_credential(%{username: username, encrypted_password: payload})
       when is_binary(username) and is_map(payload) do
    {:ok, %{username: username, password: SourceCredentialCrypto.decrypt_secret!(payload)}}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp username_password_from_credential(_credential),
    do: {:error, "Username and password are required."}

  defp source_for_test(_credential, opts) do
    case Keyword.get(opts, :source) do
      %ProcurementSource{} = source ->
        {:ok, source}

      _ ->
        source_id = Keyword.get(opts, :procurement_source_id)

        if is_binary(source_id) do
          Procurement.get_procurement_source(source_id, authorize?: false)
        else
          {:error, "A source is required to test browser credentials."}
        end
    end
  end

  defp browser_login_probe(url, credentials, opts) do
    browser = Keyword.get(opts, :browser, browser())

    with {:ok, _navigation} <- browser.navigate(url, wait_for_network: true),
         {:ok, login_surface} <- browser.evaluate(LoginForm.surface_script()),
         :ok <- maybe_follow_login_link(browser, login_surface),
         {:ok, _typed} <- browser.type(LoginForm.username_selector(), credentials.username),
         {:ok, _typed} <- browser.type(LoginForm.password_selector(), credentials.password),
         {:ok, submit_result} <- browser.evaluate(LoginForm.submit_script()),
         :ok <- LoginForm.submitted?(submit_result),
         :ok <- wait_after_submit(opts),
         {:ok, result} <- browser.evaluate(login_result_js()) do
      interpret_login_result(result)
    end
  end

  defp maybe_follow_login_link(browser, %{"login_url" => login_url})
       when is_binary(login_url) and login_url != "" do
    case browser.navigate(login_url, wait_for_network: true) do
      {:ok, _navigation} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_follow_login_link(_browser, %{"has_login_form" => true}), do: :ok
  defp maybe_follow_login_link(_browser, %{"reason" => reason}), do: {:error, reason}
  defp maybe_follow_login_link(_browser, _surface), do: {:error, "Could not find a login form."}

  defp wait_after_submit(opts) do
    opts
    |> Keyword.get(
      :wait_ms,
      Application.get_env(:gnome_garden, :source_credential_login_wait_ms, @browser_wait_ms)
    )
    |> Process.sleep()

    :ok
  end

  defp interpret_login_result(%{"invalid" => true, "reason" => reason}) do
    {:error, reason || "The portal rejected these credentials."}
  end

  defp interpret_login_result(%{"success" => true} = result) do
    {:ok, %{url: result["url"], title: result["title"], signal: result["signal"]}}
  end

  defp interpret_login_result(%{"has_password" => false} = result) do
    {:ok, %{url: result["url"], title: result["title"], signal: "login_form_disappeared"}}
  end

  defp interpret_login_result(%{"reason" => reason}) when is_binary(reason) and reason != "",
    do: {:error, reason}

  defp interpret_login_result(_result), do: {:error, "Could not verify login success."}

  defp browser do
    Application.get_env(:gnome_garden, :source_credential_browser, GnomeGarden.Browser)
  end

  defp login_result_js do
    """
    (() => {
      const text = (document.body?.innerText || '').replace(/\\s+/g, ' ').trim();
      const invalid = /invalid|incorrect|wrong password|login failed|sign in failed|try again|unable to log/i.test(text);
      const successMatch = text.match(/sign out|log out|logout|my account|my profile|dashboard|welcome|account settings/i);
      const hasPassword = !!document.querySelector('input[type="password"]');

      return {
        success: !!successMatch && !invalid,
        invalid,
        has_password: hasPassword,
        signal: successMatch ? successMatch[0] : null,
        reason: invalid ? 'The portal rejected these credentials.' : null,
        url: window.location.href,
        title: document.title || ''
      };
    })()
    """
  end
end
