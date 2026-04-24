defmodule GnomeGarden.Providers.MercuryTest do
  use ExUnit.Case, async: false

  alias GnomeGarden.Providers.Mercury

  describe "attach/2" do
    test "registers :mercury_api_key as a valid option" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_api_key in req.registered_options
    end

    test "registers :mercury_sandbox as a valid option" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_sandbox in req.registered_options
    end

    test "adds mercury_put_base_url as a request step" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_put_base_url in Keyword.keys(req.request_steps)
    end

    test "adds mercury_put_auth as a request step" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_put_auth in Keyword.keys(req.request_steps)
    end

    test "mercury_put_base_url runs before mercury_put_auth" do
      req = Req.new() |> Mercury.attach()
      step_names = Keyword.keys(req.request_steps)
      base_url_pos = Enum.find_index(step_names, &(&1 == :mercury_put_base_url))
      auth_pos = Enum.find_index(step_names, &(&1 == :mercury_put_auth))
      assert base_url_pos < auth_pos,
             "Expected mercury_put_base_url (pos #{base_url_pos}) before mercury_put_auth (pos #{auth_pos})"
    end

    test "adds mercury_handle_errors as a response step" do
      req = Req.new() |> Mercury.attach()
      assert :mercury_handle_errors in Keyword.keys(req.response_steps)
    end

    test "merges caller-supplied options onto the request" do
      req = Req.new() |> Mercury.attach(mercury_sandbox: false)
      assert req.options[:mercury_sandbox] == false
    end
  end

  describe "mercury_put_base_url step" do
    setup do
      Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:test")
      on_exit(fn -> Application.delete_env(:gnome_garden, :mercury_api_key) end)
    end

    test "uses sandbox URL when mercury_sandbox: true" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == "backend-sandbox.mercury.com"
        Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
      end)

      assert {:ok, _} = Mercury.list_accounts(mercury_sandbox: true, plug: {Req.Test, __MODULE__})
    end

    test "uses production URL when mercury_sandbox: false" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == "api.mercury.com"
        Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
      end)

      assert {:ok, _} = Mercury.list_accounts(mercury_sandbox: false, plug: {Req.Test, __MODULE__})
    end

    test "defaults to sandbox when no option and no app config" do
      Application.delete_env(:gnome_garden, :mercury_sandbox)

      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == "backend-sandbox.mercury.com"
        Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
      end)

      assert {:ok, _} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
    end

    test "reads sandbox flag from app config when not passed as option" do
      Application.put_env(:gnome_garden, :mercury_sandbox, false)
      on_exit(fn -> Application.delete_env(:gnome_garden, :mercury_sandbox) end)

      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == "api.mercury.com"
        Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
      end)

      assert {:ok, _} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
    end
  end

  describe "mercury_put_auth step" do
    setup do
      Application.put_env(:gnome_garden, :mercury_sandbox, true)
      on_exit(fn ->
        Application.delete_env(:gnome_garden, :mercury_sandbox)
        Application.delete_env(:gnome_garden, :mercury_api_key)
      end)
    end

    test "sets Authorization: Bearer header from :mercury_api_key option" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token:from-opt"]
        Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
      end)

      assert {:ok, _} =
               Mercury.list_accounts(
                 mercury_api_key: "secret-token:from-opt",
                 plug: {Req.Test, __MODULE__}
               )
    end

    test "falls back to app config when :mercury_api_key option not given" do
      Application.put_env(:gnome_garden, :mercury_api_key, "secret-token:from-config")

      Req.Test.stub(__MODULE__, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token:from-config"]
        Req.Test.json(conn, %{"accounts" => [], "page" => %{}})
      end)

      assert {:ok, _} = Mercury.list_accounts(plug: {Req.Test, __MODULE__})
    end

    test "raises with a clear message when no key is available anywhere" do
      Application.delete_env(:gnome_garden, :mercury_api_key)

      assert_raise RuntimeError, ~r/Missing Mercury API key/, fn ->
        Mercury.list_accounts(plug: {Req.Test, __MODULE__})
      end
    end
  end
end
