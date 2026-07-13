defmodule GnomeGarden.ProviderContract do
  @moduledoc """
  Versioned offline provider fixtures exposed through real transport boundaries.

  Tests load raw JSON or HTML and inject it through Req, HTTP getter, Jido, or
  Playwright command-runner seams. Provider implementations still execute their
  production parsing and normalization code.
  """

  defmodule Case do
    @enforce_keys [:provider, :operation, :scenario, :outcome, :transport, :provenance]
    defstruct [
      :provider,
      :operation,
      :scenario,
      :outcome,
      :transport,
      :status,
      :body,
      :fixture_path,
      :provenance
    ]
  end

  @root Path.expand("../fixtures/provider_contract/v1", __DIR__)
  @manifest_path Path.join(@root, "manifest.json")

  @required_scenarios ~w(success empty throttled auth schema_drift waf timeout malformed partial)a
  @contract_atoms ~w(
    exa sam_gov opengov bidnet jido playwright
    search contents projects listings web_fetch session provider_action
    success empty throttled auth schema_drift waf timeout malformed partial
    http command connection_refused
  )a
  @contract_atom_by_name Map.new(@contract_atoms, &{Atom.to_string(&1), &1})

  def version, do: manifest()["version"]
  def provenance, do: manifest()["provenance"]
  def required_scenarios, do: @required_scenarios

  def providers do
    manifest()["providers"]
    |> Map.keys()
    |> Enum.map(&contract_atom/1)
    |> Enum.sort()
  end

  def operations(provider) do
    manifest()
    |> get_in(["providers", to_string(provider)])
    |> Map.keys()
    |> Enum.map(&contract_atom/1)
    |> Enum.sort()
  end

  def load(provider, operation, scenario) when scenario in @required_scenarios do
    provider = to_string(provider)
    operation = to_string(operation)
    scenario = to_string(scenario)
    manifest = manifest()

    definition =
      get_in(manifest, ["providers", provider, operation, "cases", scenario]) ||
        get_in(manifest, ["defaults", scenario]) ||
        raise ArgumentError, "missing provider contract case #{provider}.#{operation}.#{scenario}"

    fixture_path = definition["fixture"] && Path.join(@root, definition["fixture"])

    %Case{
      provider: contract_atom(provider),
      operation: contract_atom(operation),
      scenario: contract_atom(scenario),
      outcome: contract_atom(definition["outcome"]),
      transport: contract_atom(definition["transport"]),
      status: definition["status"],
      body: load_body(fixture_path, definition),
      fixture_path: fixture_path,
      provenance: manifest["provenance"]
    }
  end

  def http_get(%Case{} = contract_case) do
    fn _url, _opts -> http_result(contract_case) end
  end

  def http_result(%Case{transport: :timeout}), do: {:error, :timeout}
  def http_result(%Case{transport: :connection_refused}), do: {:error, :econnrefused}

  def http_result(%Case{status: status, body: body}) when is_integer(status),
    do: {:ok, %{status: status, body: body}}

  def req_stub(%Case{} = contract_case) do
    fn conn -> req_response(conn, contract_case) end
  end

  def req_response(conn, %Case{transport: :timeout}) do
    Req.Test.transport_error(conn, :timeout)
  end

  def req_response(conn, %Case{status: status, body: body}) do
    conn = Plug.Conn.put_status(conn, status)

    if is_map(body) or is_list(body) do
      Req.Test.json(conn, body)
    else
      Plug.Conn.resp(conn, status, to_string(body || ""))
    end
  end

  def command_runner(%Case{} = contract_case) do
    fn _command, _args, _opts ->
      case contract_case do
        %Case{transport: :timeout} -> {"", 124}
        %Case{status: status, body: body} -> {encode_body(body), command_exit_status(status)}
      end
    end
  end

  def normalize(%Case{} = contract_case) do
    %{
      provider: contract_case.provider,
      operation: contract_case.operation,
      scenario: contract_case.scenario,
      outcome: contract_case.outcome,
      retryable: contract_case.outcome in [:throttled, :timeout],
      blocked: contract_case.outcome in [:auth, :waf],
      status: contract_case.status,
      payload: contract_case.body,
      provenance: contract_case.provenance
    }
  end

  defp manifest do
    @manifest_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp load_body(nil, definition), do: definition["body"]

  defp load_body(path, _definition) do
    case Path.extname(path) do
      ".json" -> path |> File.read!() |> Jason.decode!()
      _extension -> File.read!(path)
    end
  end

  defp encode_body(body) when is_binary(body), do: body
  defp encode_body(body), do: Jason.encode!(body)
  defp command_exit_status(status) when status in 200..299, do: 0
  defp command_exit_status(_status), do: 1

  defp contract_atom(value), do: Map.fetch!(@contract_atom_by_name, value)
end

defmodule GnomeGarden.ProviderContract.JidoClient do
  @moduledoc false

  alias GnomeGarden.ProviderContract

  def web_fetch(url, opts) do
    contract_case = Keyword.fetch!(opts, :contract_case)

    case ProviderContract.http_result(contract_case) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{url: url, content: body, format: Keyword.get(opts, :format, :html)}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule GnomeGarden.ProviderContract.JidoAdapter do
  @moduledoc false

  @behaviour Jido.Browser.Adapter

  alias GnomeGarden.ProviderContract
  alias Jido.Browser.Session

  @impl true
  def start_session(opts) do
    contract_case = Keyword.fetch!(opts, :contract_case)
    Session.new!(%{adapter: __MODULE__, connection: %{contract_case: contract_case}})
  end

  @impl true
  def end_session(_session), do: :ok

  @impl true
  def navigate(session, url, _opts) do
    case ProviderContract.http_result(contract_case(session)) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, session, %{"url" => value(body, "url") || url, "title" => value(body, "title")}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def evaluate(session, _script, _opts) do
    {:ok, session, %{"result" => contract_case(session).body}}
  end

  @impl true
  def click(session, _selector, _opts), do: {:ok, session, %{}}

  @impl true
  def type(session, _selector, _text, _opts), do: {:ok, session, %{}}

  @impl true
  def screenshot(session, _opts), do: {:ok, session, %{bytes: <<>>, mime: "image/png"}}

  @impl true
  def extract_content(session, _opts),
    do: {:ok, session, %{content: Jason.encode!(contract_case(session).body), format: :text}}

  defp contract_case(session), do: session.connection.contract_case
  defp value(map, key) when is_map(map), do: Map.get(map, key)
  defp value(_value, _key), do: nil
end
