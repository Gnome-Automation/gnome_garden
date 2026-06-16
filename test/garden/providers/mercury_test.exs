defmodule GnomeGarden.Providers.MercuryTest do
  use ExUnit.Case, async: false

  alias GnomeGarden.Providers.Mercury
  alias ReqMercury.Error

  test "delegates attach/2 to ReqMercury" do
    req = Req.new() |> Mercury.attach()

    assert :api_key in req.registered_options
    assert :sandbox? in req.registered_options
    assert :req_mercury_put_base_url in Keyword.keys(req.request_steps)
  end

  test "supports legacy Mercury option names through ReqMercury compatibility aliases" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.host == "backend-sandbox.mercury.com"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token:test"]
      Req.Test.json(conn, %{"accounts" => []})
    end)

    assert {:ok, %{"accounts" => []}} =
             Mercury.list_accounts(
               mercury_api_key: "secret-token:test",
               mercury_sandbox: true,
               plug: {Req.Test, __MODULE__}
             )
  end

  test "returns ReqMercury structured errors" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"errors" => %{"message" => "Bad token"}})
    end)

    assert {:error, %Error{reason: :unauthorized, status: 401}} =
             Mercury.list_accounts(
               mercury_api_key: "secret-token:test",
               plug: {Req.Test, __MODULE__}
             )
  end
end
