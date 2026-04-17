defmodule GnomeGarden.Agents.RunOutputLogger do
  @moduledoc false

  require Logger

  alias GnomeGarden.Agents

  @spec log(map(), map()) :: :ok
  def log(context, attrs) do
    case run_id_from(context) do
      run_id when is_binary(run_id) ->
        attrs
        |> Map.put(:agent_run_id, run_id)
        |> persist_output()

      _ ->
        :ok
    end
  end

  defp persist_output(attrs) do
    case Agents.create_agent_run_output(attrs) do
      {:ok, _output} ->
        :ok

      {:error, %Ash.Error.Invalid{} = error} ->
        if String.contains?(inspect(error), "unique_output_event") do
          :ok
        else
          Logger.warning("Failed to persist agent run output: #{inspect(error)}")
          :ok
        end

      {:error, error} ->
        Logger.warning("Failed to persist agent run output: #{inspect(error)}")
        :ok
    end
  end

  defp run_id_from(context) when is_map(context) do
    get_in(context, [:tool_context, :run_id]) || Map.get(context, :run_id)
  end

  defp run_id_from(_context), do: nil
end
