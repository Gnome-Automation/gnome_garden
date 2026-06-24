defmodule GnomeGarden.Procurement.PlaywrightRunnerTest do
  use ExUnit.Case, async: true

  alias GnomeGarden.Procurement.PlaywrightRunner

  test "runs the Node runner with JSON stdin and secret-free command args" do
    parent = self()

    command_runner = fn command, args, opts ->
      send(parent, {:command, command, args, opts})

      {Jason.encode!(%{
         ok: true,
         action: "probe",
         finalUrl: "https://www.bidnetdirect.com/private",
         storageStatePath: "/tmp/session/state.json"
       }), 0}
    end

    assert {:ok, result} =
             PlaywrightRunner.run(
               :probe,
               %{
                 url: "https://www.bidnetdirect.com",
                 storage_state_path: "/tmp/session/state.json",
                 credentials: %{username: "operator@example.com", password: "super-secret"}
               },
               command_runner: command_runner,
               timeout_ms: 12_000
             )

    assert result["storageStatePath"] == "/tmp/session/state.json"

    assert_receive {:command, command, [runner_path], opts}
    assert command == PlaywrightRunner.node_path()
    assert runner_path == PlaywrightRunner.runner_path()
    refute Enum.join([command | [runner_path]], " ") =~ "super-secret"

    assert {:ok, payload} = Jason.decode(Keyword.fetch!(opts, :input))
    assert payload["action"] == "probe"
    assert payload["timeoutMs"] == 12_000
    assert payload["credentials"]["password"] == "super-secret"
  end

  test "returns runner JSON failures without exposing the input payload" do
    command_runner = fn _command, _args, _opts ->
      {Jason.encode!(%{ok: false, code: "unsupported_action", error: "Unsupported action"}), 1}
    end

    assert {:error, error} =
             PlaywrightRunner.run(
               :unknown,
               %{password: "super-secret"},
               command_runner: command_runner
             )

    assert error["code"] == "unsupported_action"
    refute inspect(error) =~ "super-secret"
  end

  test "returns bounded error for invalid runner output" do
    command_runner = fn _command, _args, _opts -> {"not-json", 1} end

    assert {:error, "Playwright runner failed."} =
             PlaywrightRunner.run(:probe, %{url: "https://example.com"},
               command_runner: command_runner
             )
  end
end
