defmodule GnomeHub.Agents.StreamingHandler do
  @moduledoc """
  Telemetry handler for capturing LLM streaming events.

  Attaches to Jido AI telemetry events and forwards streaming deltas
  to Phoenix PubSub for real-time UI updates.
  """

  require Logger

  @events [
    [:jido, :ai, :llm, :delta],
    [:jido, :ai, :llm, :complete],
    [:jido, :ai, :tool, :execute, :start],
    [:jido, :ai, :tool, :execute, :stop]
  ]

  def attach do
    :telemetry.attach_many(
      "gnome-hub-streaming-handler",
      @events,
      &__MODULE__.handle_event/4,
      %{}
    )

    # Also attach a debug handler for all jido.ai events
    :telemetry.attach(
      "gnome-hub-debug-handler",
      [:jido, :ai],
      &__MODULE__.debug_event/4,
      %{}
    )
  end

  def detach do
    :telemetry.detach("gnome-hub-streaming-handler")
    :telemetry.detach("gnome-hub-debug-handler")
  end

  # Debug handler to see all jido.ai events
  def debug_event(event, measurements, metadata, _config) do
    Logger.warning("[StreamingHandler DEBUG] Event: #{inspect(event)}, measurements_keys: #{inspect(Map.keys(measurements))}, metadata_keys: #{inspect(Map.keys(metadata))}")
  end

  # Handle streaming delta (token by token)
  def handle_event([:jido, :ai, :llm, :delta] = event, measurements, metadata, _config) do
    Logger.debug("[StreamingHandler] LLM delta event: #{inspect(event)}")
    Logger.debug("[StreamingHandler] measurements: #{inspect(measurements, limit: 3)}")
    Logger.debug("[StreamingHandler] metadata keys: #{inspect(Map.keys(metadata))}")

    agent_id = Map.get(metadata, :agent_id)
    delta = Map.get(measurements, :delta) || Map.get(metadata, :delta)

    Logger.debug("[StreamingHandler] agent_id=#{inspect(agent_id)}, delta=#{inspect(delta, limit: 50)}")

    if agent_id && delta do
      content = extract_delta_content(delta)
      Logger.info("[StreamingHandler] Broadcasting delta to agent_stream:#{agent_id}: #{inspect(content, limit: 50)}")
      broadcast_streaming(agent_id, {:llm_delta, content})
    end
  end

  # Handle complete LLM response
  def handle_event([:jido, :ai, :llm, :complete] = event, _measurements, metadata, _config) do
    Logger.debug("[StreamingHandler] LLM complete event: #{inspect(event)}")
    Logger.debug("[StreamingHandler] metadata keys: #{inspect(Map.keys(metadata))}")

    agent_id = Map.get(metadata, :agent_id)

    if agent_id do
      thinking = Map.get(metadata, :thinking_content)
      text = Map.get(metadata, :text)

      Logger.info("[StreamingHandler] LLM complete for #{agent_id}, thinking=#{inspect(thinking != nil)}, text_len=#{inspect(text && String.length(text))}")
      broadcast_streaming(agent_id, {:llm_complete, %{thinking: thinking, text: text}})
    end
  end

  # Handle tool execution start
  def handle_event([:jido, :ai, :tool, :execute, :start] = event, _measurements, metadata, _config) do
    Logger.debug("[StreamingHandler] Tool execute start event: #{inspect(event)}")

    agent_id = Map.get(metadata, :agent_id)
    tool_name = Map.get(metadata, :tool_name)

    Logger.info("[StreamingHandler] Tool start: #{tool_name} for agent #{agent_id}")

    if agent_id && tool_name do
      broadcast_streaming(agent_id, {:tool_start, tool_name})
    end
  end

  # Handle tool execution complete
  def handle_event([:jido, :ai, :tool, :execute, :stop] = event, measurements, metadata, _config) do
    Logger.debug("[StreamingHandler] Tool execute stop event: #{inspect(event)}")

    agent_id = Map.get(metadata, :agent_id)
    tool_name = Map.get(metadata, :tool_name)
    duration = Map.get(measurements, :duration) || Map.get(measurements, :duration_ms)

    Logger.info("[StreamingHandler] Tool complete: #{tool_name} for agent #{agent_id}, duration=#{inspect(duration)}")

    if agent_id && tool_name do
      result = Map.get(metadata, :result)
      duration_ms = cond do
        is_nil(duration) -> nil
        duration > 1_000_000 -> div(duration, 1_000_000)  # nanoseconds to ms
        true -> duration  # already in ms
      end
      broadcast_streaming(agent_id, {:tool_complete, %{
        name: tool_name,
        duration_ms: duration_ms,
        result: truncate_result(result)
      }})
    end
  end

  defp broadcast_streaming(agent_id, message) do
    Phoenix.PubSub.broadcast(
      GnomeHub.PubSub,
      "agent_stream:#{agent_id}",
      {:stream, message}
    )
  end

  defp extract_delta_content(delta) when is_binary(delta), do: delta
  defp extract_delta_content(%{content: content}) when is_binary(content), do: content
  defp extract_delta_content(%{text: text}) when is_binary(text), do: text
  defp extract_delta_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_delta_content(_), do: nil

  defp truncate_result(result) when is_binary(result), do: String.slice(result, 0, 200)
  defp truncate_result(result) when is_map(result), do: inspect(result, limit: 5, printable_limit: 200)
  defp truncate_result(result), do: inspect(result, limit: 5, printable_limit: 200)
end
