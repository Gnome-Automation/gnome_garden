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
end
