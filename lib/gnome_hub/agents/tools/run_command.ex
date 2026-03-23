defmodule GnomeHub.Agents.Tools.RunCommand do
  @moduledoc """
  Execute a shell command and return its output.

  Falls back to System.cmd if no session manager is available.
  """

  use Jido.Action,
    name: "run_command",
    description: "Execute a shell command and return its output. Use for running tests, builds, scripts, etc.",
    schema: [
      command: [type: :string, required: true, doc: "The command to execute (passed to sh -c)"],
      timeout: [type: :integer, default: 30_000, doc: "Timeout in milliseconds"],
      workspace_id: [type: :string, default: "default", doc: "Session workspace for persistent shell state"]
    ]

  @max_output_chars 10_000

  @impl true
  def run(params, _context) do
    command = Map.get(params, :command) || Map.get(params, "command")
    timeout = Map.get(params, :timeout) || Map.get(params, "timeout", 30_000)

    task =
      Task.async(fn ->
        System.cmd("sh", ["-c", command], stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, exit_code}} ->
        {:ok, %{output: truncate(output), exit_code: exit_code}}

      nil ->
        {:error, "Command timed out after #{timeout}ms"}
    end
  end

  defp truncate(output) when byte_size(output) > @max_output_chars do
    String.slice(output, 0, @max_output_chars) <> "\n... (output truncated)"
  end

  defp truncate(output), do: output
end
