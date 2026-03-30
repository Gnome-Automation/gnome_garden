defmodule GnomeGarden.Agents.Tools.GetAgentResult do
  @moduledoc """
  Wait for a spawned child agent to finish and return the result.

  Use this after spawn_agent to collect the output.
  """

  use Jido.Action,
    name: "get_agent_result",
    description:
      "Wait for a spawned child agent to finish its task and return the result. Use this after spawn_agent to collect the output.",
    schema: [
      agent_id: [type: :string, required: true, doc: "The agent ID returned by spawn_agent"],
      timeout: [type: :integer, required: false, doc: "Max wait time in ms (default: 60000)"]
    ]

  alias GnomeGarden.Agents.AgentTracker

  @impl true
  def run(params, _context) do
    agent_id = Map.get(params, :agent_id) || Map.get(params, "agent_id")
    timeout = Map.get(params, :timeout) || Map.get(params, "timeout", 60_000)

    # Poll for completion
    wait_for_completion(agent_id, timeout)
  end

  defp wait_for_completion(agent_id, timeout) do
    start_time = System.monotonic_time(:millisecond)
    poll_interval = 500

    do_wait(agent_id, start_time, timeout, poll_interval)
  end

  defp do_wait(agent_id, start_time, timeout, poll_interval) do
    case AgentTracker.get_agent(agent_id) do
      nil ->
        {:error,
         "Agent '#{agent_id}' not found. It may have already completed and been cleaned up."}

      %{status: :running} = _entry ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        if elapsed >= timeout do
          {:ok,
           %{
             agent_id: agent_id,
             status: "still_running",
             message: "Agent hasn't finished yet. Try again later or increase timeout."
           }}
        else
          Process.sleep(poll_interval)
          do_wait(agent_id, start_time, timeout, poll_interval)
        end

      %{status: :done, result: result} ->
        {:ok,
         %{
           agent_id: agent_id,
           status: "completed",
           result: extract_result(result)
         }}

      %{status: :error, error: error, result: result} ->
        {:ok,
         %{
           agent_id: agent_id,
           status: "failed",
           error: error || extract_result(result)
         }}
    end
  end

  defp extract_result(%{last_answer: answer}) when is_binary(answer), do: answer
  defp extract_result(%{answer: answer}) when is_binary(answer), do: answer
  defp extract_result(%{text: text}) when is_binary(text), do: text
  defp extract_result(result) when is_binary(result), do: result
  defp extract_result(nil), do: nil
  defp extract_result(result), do: inspect(result, limit: :infinity, pretty: true)
end
