defmodule GnomeHub.Agents.RequestTransformer do
  @moduledoc """
  Request transformer to normalize jido_ai context messages for ReqLLM compatibility.

  This fixes a compatibility issue where jido_ai's AIContext.build_assistant_content
  returns a list of content parts (thinking + text) for assistant messages with thinking,
  but ReqLLM's to_parts/1 only accepts binary strings.

  This transformer normalizes the content to be a plain string before sending to ReqLLM.
  """

  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  @impl true
  def transform_request(%{messages: messages} = _request, _state, _config, _runtime_context) do
    normalized_messages = Enum.map(messages, &normalize_message/1)
    {:ok, %{messages: normalized_messages}}
  end

  defp normalize_message(%{role: :assistant, content: content} = msg) when is_list(content) do
    # Extract text from content parts, ignore thinking (it's stored separately)
    text = Enum.find_value(content, "", fn
      %{type: :text, text: t} when is_binary(t) -> t
      %{"type" => "text", "text" => t} when is_binary(t) -> t
      _ -> nil
    end)

    %{msg | content: text || ""}
  end

  defp normalize_message(msg), do: msg
end
