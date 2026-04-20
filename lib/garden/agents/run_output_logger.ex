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
    context
    |> candidate_run_ids()
    |> Enum.find(&persisted_run_id?/1)
  end

  defp run_id_from(_context), do: nil

  defp candidate_run_ids(context) do
    [
      nested_value(context, [:tool_context, :agent_run_id]),
      nested_value(context, [:tool_context, :runtime_instance_id]),
      nested_value(context, [:tool_context, :run_id]),
      nested_value(context, [:agent_run_id]),
      nested_value(context, [:runtime_instance_id]),
      nested_value(context, [:run_id])
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp persisted_run_id?(run_id) when is_binary(run_id) do
    match?({:ok, _run}, Agents.get_agent_run(run_id))
  end

  defp persisted_run_id?(_run_id), do: false

  defp nested_value(map, [key]) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp nested_value(map, [key | rest]) when is_map(map) do
    case nested_value(map, [key]) do
      %{} = nested -> nested_value(nested, rest)
      _ -> nil
    end
  end
end
