defmodule GnomeGarden.Procurement.BidNetSessionRefresh do
  @moduledoc """
  Refreshes authenticated BidNet browser sessions with Playwright.

  This module owns external browser orchestration only. Durable state changes
  go through `SourceBrowserSession` Ash actions.
  """

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.PlaywrightRunner
  alias GnomeGarden.Procurement.SourceCredential
  alias GnomeGarden.Procurement.Actions.SourceCredentialResolution
  alias GnomeGarden.Procurement.SourceCredentials

  require Logger

  @session_ttl_seconds 7 * 24 * 60 * 60
  @default_max_attempts 2

  def refresh(source_or_id, opts \\ []) do
    with {:ok, source} <- fetch_source(source_or_id, opts),
         :ok <- require_bidnet(source),
         {:ok, credential, credentials} <- credential_and_credentials_for_refresh(source, opts),
         {:ok, session} <- create_session(source, credential, opts),
         {:ok, refreshing} <-
           Procurement.mark_source_browser_session_refreshing(
             session,
             %{source_credential_id: credential.id},
             authorize?: false
           ) do
      run_refresh(refreshing, source, credential, credentials, opts)
    end
  end

  defp fetch_source(%ProcurementSource{} = source, _opts), do: {:ok, source}

  defp fetch_source(source_id, opts) when is_binary(source_id) do
    Procurement.get_procurement_source(source_id,
      actor: Keyword.get(opts, :actor),
      authorize?: Keyword.get(opts, :authorize?, false)
    )
  end

  defp require_bidnet(%{source_type: :bidnet}), do: :ok

  defp require_bidnet(_source),
    do: {:error, "Only BidNet sources support BidNet session refresh."}

  defp create_session(source, credential, opts) do
    Procurement.create_source_browser_session(
      %{
        procurement_source_id: source.id,
        source_credential_id: credential.id,
        provider: :bidnet,
        session_family: "bidnet",
        browser_name: Keyword.get(opts, :browser_name, "chromium"),
        metadata: %{"source_url" => source.url}
      },
      authorize?: false
    )
  end

  defp run_refresh(session, source, credential, credentials, opts) do
    runner =
      Keyword.get(
        opts,
        :runner,
        Application.get_env(:gnome_garden, :bidnet_session_runner, PlaywrightRunner)
      )

    payload = %{
      url: source.url,
      headed: Keyword.get(opts, :headed, false)
    }

    runner_opts =
      opts
      |> Keyword.take([:command_runner, :timeout_ms])
      |> Keyword.put(
        :secret_envelope,
        PlaywrightRunner.envelope(%{
          username: credentials.username,
          password: credentials.password
        })
      )

    max_attempts = positive_integer(Keyword.get(opts, :max_attempts), @default_max_attempts)

    run_attempts(
      runner,
      payload,
      runner_opts,
      session,
      credential,
      [credentials.username, credentials.password],
      1,
      max_attempts
    )
  end

  defp run_attempts(
         runner,
         payload,
         runner_opts,
         session,
         credential,
         secrets,
         attempt,
         max_attempts
       ) do
    case runner.run(:bidnet_login, payload, runner_opts) do
      {:ok, result} ->
        mark_valid(session, result, attempt)

      {:error, reason} ->
        reason = redact_reason(reason, secrets)

        if retryable_failure?(reason) and attempt < max_attempts do
          run_attempts(
            runner,
            payload,
            runner_opts,
            session,
            credential,
            secrets,
            attempt + 1,
            max_attempts
          )
        else
          mark_failed(session, credential, reason, attempt)
        end
    end
  end

  defp mark_valid(session, result, attempt) do
    with storage_state when is_binary(storage_state) <-
           PlaywrightRunner.secret(result, "storageState") do
      case Procurement.mark_source_browser_session_valid(
             session,
             %{
               storage_state: storage_state,
               expires_at: DateTime.add(DateTime.utc_now(), @session_ttl_seconds, :second),
               metadata: %{
                 "final_url" => result["finalUrl"],
                 "title" => result["title"],
                 "status" => result["status"],
                 "attempt_count" => attempt
               }
             },
             authorize?: false
           ) do
        {:ok, valid} ->
          expire_superseded_sessions(valid)
          {:ok, valid}

        error ->
          error
      end
    else
      _missing_state -> mark_failed(session, nil, :browser_session_state_missing, attempt)
    end
  end

  defp mark_failed(session, credential, reason, attempt) do
    message = failure_message(reason)

    with {:ok, failed} <-
           Procurement.mark_source_browser_session_failed(
             session,
             %{
               last_failure_reason: message,
               metadata: %{
                 "failure_code" => failure_code(reason),
                 "attempt_count" => attempt
               }
             },
             authorize?: false
           ),
         :ok <- maybe_invalidate_credential(credential, reason, message) do
      {:error, %{session: failed, reason: message}}
    end
  end

  defp credential_and_credentials_for_refresh(source, opts) do
    case Keyword.get(opts, :credential) do
      %SourceCredential{} = credential ->
        with {:ok, credential} <- validate_credential_binding(credential, source),
             {:ok, credentials} <-
               SourceCredentialResolution.username_password_for_verification(credential) do
          {:ok, credential, credentials}
        end

      nil ->
        with {:ok, credentials} <- SourceCredentials.credentials_for(source),
             {:ok, credential} <- credential_for_source(source, credentials) do
          {:ok, credential, credentials}
        end
    end
  end

  defp validate_credential_binding(%{status: :disabled}, _source),
    do: {:error, "BidNet credentials are disabled."}

  defp validate_credential_binding(%{status: :invalid}, _source),
    do: {:error, "BidNet credentials are invalid."}

  defp validate_credential_binding(credential, source) do
    if credential.provider == :bidnet and
         (is_nil(credential.procurement_source_id) or
            credential.procurement_source_id == source.id) do
      {:ok, credential}
    else
      {:error, "BidNet credential does not apply to this source."}
    end
  end

  defp credential_for_source(source, credentials) do
    candidates =
      source_credentials(source.id) ++
        family_credentials(SourceCredentials.credential_family(source))

    case Enum.find(candidates, &credential_matches?(&1, credentials)) do
      nil -> {:error, "BidNet credential record could not be resolved."}
      credential -> {:ok, credential}
    end
  end

  defp credential_matches?(%{id: id}, %{credential_id: id}) when is_binary(id), do: true

  defp credential_matches?(credential, credentials) do
    credential.status == :active and credential_has_runtime_secret?(credential) and
      credential.username == credentials.username
  end

  defp credential_has_runtime_secret?(%{credential_storage: :bitwarden}), do: true
  defp credential_has_runtime_secret?(credential), do: credential.password_present

  defp source_credentials(source_id) do
    case Procurement.list_source_credentials_for_source(source_id, authorize?: false) do
      {:ok, credentials} -> credentials
      _ -> []
    end
  end

  defp family_credentials(family) do
    case Procurement.list_source_credentials_for_family(to_string(family), authorize?: false) do
      {:ok, credentials} -> credentials
      _ -> []
    end
  end

  defp failure_message(%{"error" => error}) when is_binary(error), do: error
  defp failure_message(%{error: error}) when is_binary(error), do: error
  defp failure_message(reason) when is_binary(reason), do: reason
  defp failure_message(reason), do: inspect(reason)

  defp failure_code(%{"code" => code}) when is_binary(code), do: code
  defp failure_code(%{code: code}) when is_atom(code), do: Atom.to_string(code)
  defp failure_code(_reason), do: "bidnet_session_refresh_failed"

  defp retryable_failure?(reason),
    do: failure_code(reason) not in ["invalid_credentials", "credentials_disabled"]

  defp maybe_invalidate_credential(nil, _reason, _message), do: :ok

  defp maybe_invalidate_credential(credential, reason, message) do
    if failure_code(reason) == "invalid_credentials" do
      case Procurement.mark_source_credential_failed(
             credential,
             %{last_failure_reason: message},
             authorize?: false
           ) do
        {:ok, _credential} -> :ok
        {:error, error} -> {:error, error}
      end
    else
      :ok
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp expire_superseded_sessions(valid) do
    case Procurement.list_valid_source_browser_sessions_for_source(
           valid.procurement_source_id,
           authorize?: false
         ) do
      {:ok, sessions} ->
        sessions
        |> Enum.reject(&(&1.id == valid.id))
        |> Enum.each(&expire_superseded_session/1)

      {:error, error} ->
        Logger.warning("Could not load superseded BidNet sessions", error: inspect(error))
    end
  end

  defp expire_superseded_session(session) do
    case Procurement.expire_source_browser_session(
           session,
           %{last_failure_reason: "Superseded by a newer BidNet browser session."},
           authorize?: false
         ) do
      {:ok, _expired} ->
        :ok

      {:error, error} ->
        Logger.warning("Could not expire superseded BidNet session", error: inspect(error))
    end
  end

  defp redact_reason(reason, secrets) when is_map(reason) do
    Map.new(reason, fn {key, value} -> {key, redact_reason(value, secrets)} end)
  end

  defp redact_reason(reason, secrets) when is_list(reason),
    do: Enum.map(reason, &redact_reason(&1, secrets))

  defp redact_reason(reason, secrets) when is_binary(reason) do
    Enum.reduce(secrets, reason, fn
      secret, result when is_binary(secret) and secret != "" ->
        String.replace(result, secret, "[REDACTED]")

      _secret, result ->
        result
    end)
  end

  defp redact_reason(reason, _secrets), do: reason
end
