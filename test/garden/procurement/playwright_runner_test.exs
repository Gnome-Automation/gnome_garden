defmodule GnomeGarden.Procurement.PlaywrightRunnerTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Procurement.PlaywrightRunner
  alias GnomeGarden.ProviderContract

  test "splits public payload and secrets before invoking the Node runner" do
    parent = self()
    contract_case = ProviderContract.load(:playwright, :provider_action, :success)
    fixture_runner = ProviderContract.command_runner(contract_case)

    command_runner = fn command, args, opts ->
      send(parent, {:command, command, args, opts})
      fixture_runner.(command, args, opts)
    end

    assert {:ok, result} =
             PlaywrightRunner.run(
               :probe,
               %{
                 url: "https://www.bidnetdirect.com",
                 credentials: %{username: "operator@example.com", password: "super-secret"}
               },
               command_runner: command_runner,
               timeout_ms: 12_000
             )

    assert result["items"] == [%{"id" => "project-1", "title" => "Controls Upgrade"}]

    assert_receive {:command, command, [runner_path], opts}
    assert command == PlaywrightRunner.node_path()
    assert runner_path == PlaywrightRunner.runner_path()
    refute Enum.join([command | [runner_path]], " ") =~ "super-secret"

    assert {:ok, payload} = Jason.decode(Keyword.fetch!(opts, :input))
    assert payload["action"] == "probe"
    assert payload["timeoutMs"] == 12_000
    refute Map.has_key?(payload, "credentials")

    assert {:ok, secrets} = Jason.decode(Keyword.fetch!(opts, :secret_input))
    assert secrets["credentials"]["password"] == "super-secret"
    refute inspect(Keyword.delete(opts, :secret_input)) =~ "super-secret"
  end

  test "returns runner JSON failures without exposing the input payload" do
    contract_case = ProviderContract.load(:playwright, :provider_action, :auth)
    command_runner = ProviderContract.command_runner(contract_case)

    assert {:error, error} =
             PlaywrightRunner.run(
               :unknown,
               %{password: "super-secret"},
               command_runner: command_runner
             )

    assert error["code"] == "authentication_required"
    refute inspect(error) =~ "super-secret"
  end

  test "default runner keeps secrets out of the public payload file" do
    original_node_path = Application.get_env(:gnome_garden, :playwright_node_path)
    original_runner_path = Application.get_env(:gnome_garden, :procurement_playwright_runner_path)
    script_path = Path.join(System.tmp_dir!(), "garden-cat-#{System.unique_integer([:positive])}")

    File.write!(script_path, "#!/bin/sh\ncat \"$GARDEN_PROCUREMENT_RUNNER_PAYLOAD_PATH\"\n")
    File.chmod!(script_path, 0o755)

    Application.put_env(:gnome_garden, :playwright_node_path, script_path)
    Application.put_env(:gnome_garden, :procurement_playwright_runner_path, "ignored-runner")

    on_exit(fn ->
      File.rm(script_path)
      restore_app_env(:playwright_node_path, original_node_path)
      restore_app_env(:procurement_playwright_runner_path, original_runner_path)
    end)

    assert {:ok, result} =
             PlaywrightRunner.run(:probe, %{
               url: "https://www.bidnetdirect.com",
               password: "super-secret"
             })

    assert result["action"] == "probe"
    refute Map.has_key?(result, "password")
    refute inspect(result) =~ "super-secret"
  end

  test "returns secret output in a redacted envelope and scrubs echoed secrets" do
    command_runner = fn _command, _args, _opts ->
      {Jason.encode!(%{"ok" => true, "message" => "password=super-secret"}), 0,
       %{"storageState" => %{"cookies" => [%{"name" => "sid", "value" => "cookie-secret"}]}}}
    end

    assert {:ok, result} =
             PlaywrightRunner.run(:probe, %{url: "https://example.com", password: "super-secret"},
               command_runner: command_runner
             )

    assert result["message"] == "password=[REDACTED]"
    refute inspect(result) =~ "cookie-secret"
    assert PlaywrightRunner.secret(result, "storageState") =~ "cookie-secret"
  end

  test "returns bounded error for invalid runner output" do
    command_runner = fn _command, _args, _opts -> {"not-json", 1} end

    assert {:error, "Playwright runner failed."} =
             PlaywrightRunner.run(:probe, %{url: "https://example.com"},
               command_runner: command_runner
             )
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:gnome_garden, key)
  defp restore_app_env(key, value), do: Application.put_env(:gnome_garden, key, value)
end
