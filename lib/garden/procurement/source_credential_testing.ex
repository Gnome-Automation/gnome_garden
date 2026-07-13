defmodule GnomeGarden.Procurement.SourceCredentialTesting do
  @moduledoc """
  Queues and executes credential verification probes for procurement sources.

  BidNet credentials are not verified with the generic form-login probe. BidNet
  access is validated by refreshing a persisted Playwright browser session.
  """

  alias GnomeGarden.Agents.Tools.Procurement.QuerySamGov
  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BitwardenCredentialResolver
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.SourceCredential
  alias GnomeGarden.Procurement.SourceCredentialCrypto

  @browser_wait_ms 3_500
  @bidnet_session_refresh_reason "Use BidNet browser session refresh to verify browser access."
  @username_selector "input[type='email'], input[name*='email' i], input[id*='email' i], input[name*='user' i], input[id*='user' i], input[type='text']"
  @password_selector "input[type='password'], input[name*='password' i], input[id*='password' i]"
  @submit_selector "button[type='submit'], input[type='submit'], input[type='button'], button"

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
    with {:ok, _source} <- source_for_test(credential, opts),
         {:ok, _credentials} <- username_password_from_credential(credential) do
      {:error, {:manual_verification_required, @bidnet_session_refresh_reason}}
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

  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason(reason), do: inspect(reason)

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
         {:ok, login_surface} <- browser.evaluate(login_surface_js()),
         :ok <- maybe_follow_login_link(browser, login_surface),
         {:ok, _typed} <- browser.type(@username_selector, credentials.username),
         {:ok, _typed} <- browser.type(@password_selector, credentials.password),
         {:ok, _clicked} <- browser.click(@submit_selector),
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

  defp login_surface_js do
    """
    (() => {
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const userInput = document.querySelector('input[type="email"], input[name*="email" i], input[id*="email" i], input[name*="user" i], input[id*="user" i], input[type="text"]');
      const passInput = document.querySelector('input[type="password"], input[name*="password" i], input[id*="password" i]');

      if (!userInput || !passInput) {
        const loginLink = Array.from(document.querySelectorAll('a[href], button')).find(element => {
          const text = clean(element.innerText || element.value || element.getAttribute('aria-label'));
          const href = element.href || '';
          return /login|log in|sign in|vendor|supplier|account/i.test(`${text} ${href}`);
        });

        return {
          has_login_form: false,
          login_url: loginLink && loginLink.href ? loginLink.href : null,
          reason: loginLink ? 'login_link_found' : 'no_login_form'
        };
      }

      return {has_login_form: true};
    })()
    """
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
