defmodule GnomeGarden.Browser.SessionManager do
  @moduledoc "Supervised owner for caller-isolated browser sessions."

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def execute(client, session_opts, function, timeout) do
    GenServer.call(__MODULE__, {:execute, client, session_opts, function}, timeout)
  end

  @doc "End the browser session owned by the calling process."
  def close do
    GenServer.call(__MODULE__, :close)
  end

  @doc false
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts), do: {:ok, %{sessions: %{}, monitor_owners: %{}}}

  @impl true
  def handle_call({:execute, client, session_opts, function}, {owner, _tag}, state) do
    session_key = {client, session_opts}

    case ensure_session(state, owner, client, session_opts, session_key) do
      {:ok, entry, state} ->
        case invoke(function, client, entry.session) do
          {:ok, session, result} ->
            entry = %{entry | session: session}
            {:reply, {:ok, result}, put_in(state.sessions[owner], entry)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:close, {owner, _tag}, state) do
    {reply, state} = close_owner(state, owner, true)
    {:reply, reply, state}
  end

  def handle_call(:reset, _from, state) do
    state =
      Enum.reduce(Map.keys(state.sessions), state, fn owner, acc ->
        elem(close_owner(acc, owner, true), 1)
      end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, owner, _reason}, state) do
    case state.monitor_owners do
      %{^monitor_ref => ^owner} ->
        {_reply, state} = close_owner(state, owner, false)
        {:noreply, state}

      _other ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.sessions, fn {_owner, entry} -> safe_end_session(entry) end)
    :ok
  end

  defp ensure_session(state, owner, _client, _opts, session_key) do
    case state.sessions do
      %{^owner => %{session_key: ^session_key} = entry} -> {:ok, entry, state}
      %{^owner => _entry} -> restart_session(state, owner, session_key)
      _sessions -> start_session(state, owner, session_key)
    end
  end

  defp restart_session(state, owner, {client, session_opts} = session_key) do
    {_reply, state} = close_owner(state, owner, true)
    start_session(state, owner, session_key, client, session_opts)
  end

  defp start_session(state, owner, {client, session_opts} = session_key),
    do: start_session(state, owner, session_key, client, session_opts)

  defp start_session(state, owner, session_key, client, session_opts) do
    ensure_runtime_dir()

    case client.start_session(session_opts) do
      {:ok, session} ->
        monitor_ref = Process.monitor(owner)

        entry = %{
          client: client,
          session: session,
          session_key: session_key,
          monitor_ref: monitor_ref
        }

        state =
          state
          |> put_in([:sessions, owner], entry)
          |> put_in([:monitor_owners, monitor_ref], owner)

        {:ok, entry, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp close_owner(state, owner, demonitor?) do
    case Map.pop(state.sessions, owner) do
      {nil, _sessions} ->
        {:ok, state}

      {entry, sessions} ->
        if demonitor?, do: Process.demonitor(entry.monitor_ref, [:flush])
        reply = safe_end_session(entry)

        state = %{
          state
          | sessions: sessions,
            monitor_owners: Map.delete(state.monitor_owners, entry.monitor_ref)
        }

        {reply, state}
    end
  end

  defp safe_end_session(entry) do
    entry.client.end_session(entry.session)
  rescue
    exception -> {:error, exception}
  end

  defp invoke(function, client, session) do
    function.(client, session)
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp ensure_runtime_dir do
    dir =
      case System.get_env("AGENT_BROWSER_SOCKET_DIR") do
        value when is_binary(value) and value != "" -> value
        _value -> Path.join(System.tmp_dir!(), "gnome-garden-agent-browser")
      end

    File.mkdir_p!(dir)
    _ = File.chmod(dir, 0o700)
    System.put_env("AGENT_BROWSER_SOCKET_DIR", dir)
  end
end
