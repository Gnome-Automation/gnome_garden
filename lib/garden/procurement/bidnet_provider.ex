defmodule GnomeGarden.Procurement.BidNetProvider do
  @moduledoc "Owns BidNet credential readiness, browser-session refresh, and session reuse."

  alias GnomeGarden.Procurement
  alias GnomeGarden.Procurement.BrowserSessionCustody
  alias GnomeGarden.Procurement.SourceCredentials

  def with_session(source, context, function) when is_function(function, 1) do
    case current_session(source) do
      {:valid, session} -> materialize_or_refresh(session, source, context, function)
      {:expired, _session} -> refresh_or_continue(source, context, function)
      {:unavailable, _status} -> refresh_or_continue(source, context, function)
      :missing -> refresh_or_continue(source, context, function)
    end
  end

  defp materialize_or_refresh(session, source, context, function) do
    case materialize(session, context, function) do
      {:materialized, result} ->
        result

      {:error, _reason} ->
        expire(session, "BidNet browser session could not be decrypted or rebound.")
        refresh_or_continue(source, context, function)
    end
  end

  defp current_session(source) do
    case Procurement.list_valid_source_browser_sessions_for_source(source.id, authorize?: false) do
      {:ok, [session | _]} ->
        {:valid, session}

      _none ->
        latest_session_status(source)
    end
  end

  defp latest_session_status(source) do
    case Procurement.get_latest_source_browser_session_for_source(source.id, authorize?: false) do
      {:ok, %{status: :valid} = session} ->
        expire(session, "BidNet browser session expired.")
        {:expired, session}

      {:ok, session} ->
        {:unavailable, session.status}

      {:error, _reason} ->
        :missing
    end
  end

  defp refresh_or_continue(%{requires_login: false}, context, function), do: function.(context)

  defp refresh_or_continue(source, context, function) do
    case SourceCredentials.credential_status(source) do
      :verified -> refresh_and_materialize(source, context, function)
      :missing -> {:error, {:bidnet_credentials, :missing}}
      :invalid -> {:error, {:bidnet_credentials, :invalid}}
      :pending -> {:error, {:bidnet_credentials, :pending}}
      status -> {:error, {:bidnet_credentials, status}}
    end
  end

  defp refresh_and_materialize(source, context, function) do
    opts =
      [
        runner: context_value(context, :bidnet_session_runner),
        max_attempts: context_value(context, :bidnet_session_max_attempts) || 2,
        timeout_ms: context_value(context, :bidnet_session_timeout_ms) || 60_000
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    with {:ok, session} <- Procurement.refresh_bidnet_source_session(source, opts),
         {:materialized, result} <- materialize(session, context, function) do
      result
    end
  end

  defp materialize(session, context, function) do
    BrowserSessionCustody.with_materialized(session, fn path ->
      context =
        context
        |> Map.put(:bidnet_session_id, session.id)
        |> Map.put(:bidnet_storage_state_path, path)

      {:materialized, function.(context)}
    end)
  end

  defp expire(session, reason) do
    Procurement.expire_source_browser_session(
      session,
      %{last_failure_reason: reason},
      authorize?: false
    )
  end

  defp context_value(context, key) do
    Map.get(context, key) || Map.get(context, Atom.to_string(key))
  end
end
