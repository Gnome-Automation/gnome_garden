defmodule GnomeGarden.Browser.SessionManager do
  @moduledoc "Registry and lifecycle manager for caller-isolated browser session owners."

  use GenServer

  alias GnomeGarden.Browser.SessionOwner

  @session_supervisor GnomeGarden.Browser.SessionSupervisor

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def execute(client, session_opts, function, timeout) do
    owner = self()

    with {:ok, session_owner} <- GenServer.call(__MODULE__, {:checkout, owner}) do
      SessionOwner.execute(session_owner, client, session_opts, function, timeout)
    end
  catch
    :exit, reason -> {:error, reason}
  end

  @doc "End the browser session owned by the calling process."
  def close do
    case GenServer.call(__MODULE__, {:take, self()}) do
      {:ok, nil} -> :ok
      {:ok, session_owner} -> terminate_session_owner(session_owner)
    end
  end

  @doc false
  def reset do
    session_owners = GenServer.call(__MODULE__, :take_all)
    Enum.each(session_owners, &terminate_session_owner/1)
    :ok
  end

  @impl true
  def init(_opts) do
    runtime_dir = ensure_runtime_dir()
    {:ok, %{runtime_dir: runtime_dir, owners: %{}, refs: %{}}}
  end

  @impl true
  def handle_call({:checkout, owner}, _from, state) do
    case state.owners do
      %{^owner => %{session_owner: session_owner}} when is_pid(session_owner) ->
        if Process.alive?(session_owner) do
          {:reply, {:ok, session_owner}, state}
        else
          start_session_owner(remove_owner(state, owner, false), owner)
        end

      _owners ->
        start_session_owner(state, owner)
    end
  end

  def handle_call({:take, owner}, _from, state) do
    case state.owners do
      %{^owner => %{session_owner: session_owner}} ->
        {:reply, {:ok, session_owner}, remove_owner(state, owner, true)}

      _owners ->
        {:reply, {:ok, nil}, state}
    end
  end

  def handle_call(:take_all, _from, state) do
    session_owners = Enum.map(state.owners, fn {_owner, entry} -> entry.session_owner end)

    Enum.each(state.owners, fn {_owner, entry} ->
      Process.demonitor(entry.owner_ref, [:flush])
      Process.demonitor(entry.session_ref, [:flush])
    end)

    {:reply, session_owners, %{state | owners: %{}, refs: %{}}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.refs, ref) do
      {:owner, owner} ->
        session_owner = get_in(state, [:owners, owner, :session_owner])
        state = remove_owner(state, owner, false)
        if is_pid(session_owner), do: terminate_session_owner_async(session_owner)
        {:noreply, state}

      {:session, owner} ->
        {:noreply, remove_owner(state, owner, true)}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.owners, fn {_owner, entry} ->
      terminate_session_owner(entry.session_owner)
    end)

    :ok
  end

  defp start_session_owner(state, owner) do
    child_spec = {SessionOwner, owner: owner, runtime_dir: state.runtime_dir}

    case DynamicSupervisor.start_child(@session_supervisor, child_spec) do
      {:ok, session_owner} ->
        owner_ref = Process.monitor(owner)
        session_ref = Process.monitor(session_owner)

        entry = %{
          session_owner: session_owner,
          owner_ref: owner_ref,
          session_ref: session_ref
        }

        state =
          state
          |> put_in([:owners, owner], entry)
          |> put_in([:refs, owner_ref], {:owner, owner})
          |> put_in([:refs, session_ref], {:session, owner})

        {:reply, {:ok, session_owner}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp remove_owner(state, owner, demonitor?) do
    case Map.pop(state.owners, owner) do
      {nil, _owners} ->
        state

      {entry, owners} ->
        if demonitor? do
          Process.demonitor(entry.owner_ref, [:flush])
          Process.demonitor(entry.session_ref, [:flush])
        end

        refs =
          state.refs
          |> Map.delete(entry.owner_ref)
          |> Map.delete(entry.session_ref)

        %{state | owners: owners, refs: refs}
    end
  end

  defp terminate_session_owner(session_owner) do
    case SessionOwner.close(session_owner) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, {:noproc, _details} -> :ok
    :exit, reason -> {:error, reason}
  end

  defp terminate_session_owner_async(session_owner) do
    Task.start(fn -> terminate_session_owner(session_owner) end)
    :ok
  end

  defp ensure_runtime_dir do
    dir =
      case System.get_env("AGENT_BROWSER_SOCKET_DIR") do
        value when is_binary(value) and value != "" -> value
        _value -> Path.join(System.tmp_dir!(), "gnome-garden-agent-browser")
      end

    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    System.put_env("AGENT_BROWSER_SOCKET_DIR", dir)
    dir
  end
end
