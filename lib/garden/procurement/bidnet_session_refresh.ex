defmodule GnomeGarden.Procurement.BidNetSessionRefresh do
  @moduledoc """
  Refreshes authenticated BidNet browser sessions with Playwright.

  This module owns external browser orchestration only. Durable state changes
  go through `SourceBrowserSession` Ash actions.
  """

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.ProcurementSource
  alias GnomeGarden.Procurement.PlaywrightRunner
  alias GnomeGarden.Procurement.SourceCredentials

  @session_ttl_seconds 7 * 24 * 60 * 60

  def refresh(source_or_id, opts \\ []) do
    with {:ok, source} <- fetch_source(source_or_id, opts),
         :ok <- require_bidnet(source),
         {:ok, credentials} <- SourceCredentials.credentials_for(source),
         {:ok, credential} <- credential_for_source(source, credentials),
         {:ok, session} <- create_session(source, credential, opts),
         {:ok, refreshing} <-
           Procurement.mark_source_browser_session_refreshing(
             session,
             %{source_credential_id: credential.id},
             authorize?: false
           ) do
      run_refresh(refreshing, source, credentials, opts)
    end
  end

  def session_base_dir do
    Application.get_env(
      :gnome_garden,
      :procurement_browser_session_dir,
      Path.join(System.tmp_dir!(), "gnome-garden-procurement-sessions")
    )
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
        status: :pending,
        browser_name: Keyword.get(opts, :browser_name, "chromium"),
        metadata: %{"source_url" => source.url}
      },
      authorize?: false
    )
  end

  defp run_refresh(session, source, credentials, opts) do
    paths = session_paths(session)

    runner =
      Keyword.get(
        opts,
        :runner,
        Application.get_env(:gnome_garden, :bidnet_session_runner, PlaywrightRunner)
      )

    payload = %{
      url: source.url,
      username: credentials.username,
      password: credentials.password,
      storage_state_path: paths.storage_state_path,
      trace_path: paths.trace_path,
      screenshot_path: paths.screenshot_path,
      headed: Keyword.get(opts, :headed, false)
    }

    case runner.run(:bidnet_login, payload, Keyword.take(opts, [:command_runner, :timeout_ms])) do
      {:ok, result} ->
        mark_valid(session, paths, result)

      {:error, reason} ->
        mark_failed(session, paths, reason)
    end
  end

  defp mark_valid(session, paths, result) do
    Procurement.mark_source_browser_session_valid(
      session,
      %{
        storage_state_path: result["storageStatePath"] || paths.storage_state_path,
        storage_state_fingerprint: result["storageStateFingerprint"],
        expires_at: DateTime.add(DateTime.utc_now(), @session_ttl_seconds, :second),
        trace_path: result["tracePath"] || paths.trace_path,
        screenshot_path: result["screenshotPath"] || paths.screenshot_path,
        metadata: %{
          "final_url" => result["finalUrl"],
          "title" => result["title"],
          "status" => result["status"]
        }
      },
      authorize?: false
    )
  end

  defp mark_failed(session, paths, reason) do
    message = failure_message(reason)

    with {:ok, failed} <-
           Procurement.mark_source_browser_session_failed(
             session,
             %{
               last_failure_reason: message,
               trace_path: paths.trace_path,
               screenshot_path: paths.screenshot_path,
               metadata: %{"failure_code" => failure_code(reason)}
             },
             authorize?: false
           ) do
      {:error, %{session: failed, reason: message}}
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

  defp credential_matches?(credential, credentials) do
    credential.status == :active and credential.password_present and
      credential.username == credentials.username
  end

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

  defp session_paths(session) do
    dir = Path.join([session_base_dir(), "bidnet", session.id])

    %{
      storage_state_path: Path.join(dir, "storage-state.json"),
      trace_path: Path.join(dir, "trace.zip"),
      screenshot_path: Path.join(dir, "session.png")
    }
  end

  defp failure_message(%{"error" => error}) when is_binary(error), do: error
  defp failure_message(%{error: error}) when is_binary(error), do: error
  defp failure_message(reason) when is_binary(reason), do: reason
  defp failure_message(reason), do: inspect(reason)

  defp failure_code(%{"code" => code}) when is_binary(code), do: code
  defp failure_code(%{code: code}) when is_atom(code), do: Atom.to_string(code)
  defp failure_code(_reason), do: "bidnet_session_refresh_failed"
end
