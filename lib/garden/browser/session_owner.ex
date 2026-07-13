defmodule GnomeGarden.Browser.SessionOwner do
  @moduledoc false

  use GenServer, restart: :temporary

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def execute(session_owner, client, session_opts, function, timeout) do
    GenServer.call(
      session_owner,
      {:execute, client, session_opts, function},
      timeout
    )
  end

  def close(session_owner), do: GenServer.call(session_owner, :close, :infinity)

  @impl true
  def init(opts) do
    download_dir =
      opts
      |> Keyword.fetch!(:runtime_dir)
      |> Path.join("downloads-#{Ecto.UUID.generate()}")

    File.mkdir_p!(download_dir)
    File.chmod!(download_dir, 0o700)

    {:ok,
     %{
       owner: Keyword.fetch!(opts, :owner),
       client: nil,
       session: nil,
       session_key: nil,
       download_dir: download_dir
     }}
  end

  @impl true
  def handle_call({:execute, client, session_opts, function}, _from, state) do
    session_key = {client, session_opts}

    with {:ok, state} <- ensure_session(state, client, session_opts, session_key),
         {:ok, session, result} <- invoke(function, client, state.session, state.download_dir) do
      {:reply, {:ok, result}, %{state | session: session}}
    else
      {:error, reason, state} -> {:reply, {:error, reason}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:close, _from, state) do
    safe_end_session(state)
    {:stop, :normal, :ok, %{state | client: nil, session: nil, session_key: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    safe_end_session(state)
    File.rm_rf(state.download_dir)
    :ok
  end

  defp ensure_session(
         %{session_key: session_key, session: session} = state,
         _client,
         _opts,
         session_key
       )
       when not is_nil(session),
       do: {:ok, state}

  defp ensure_session(state, client, session_opts, session_key) do
    safe_end_session(state)

    session_opts = Keyword.put_new(session_opts, :download_path, state.download_dir)

    case client.start_session(session_opts) do
      {:ok, session} ->
        {:ok, %{state | client: client, session: session, session_key: session_key}}

      {:error, reason} ->
        {:error, reason, %{state | client: nil, session: nil, session_key: nil}}
    end
  end

  defp safe_end_session(%{client: client, session: session})
       when not is_nil(client) and not is_nil(session) do
    client.end_session(session)
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp safe_end_session(_state), do: :ok

  defp invoke(function, client, session, download_dir) do
    context = %{download_dir: download_dir}

    case :erlang.fun_info(function, :arity) do
      {:arity, 2} -> function.(client, session)
      {:arity, 3} -> function.(client, session, context)
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
