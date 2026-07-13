defmodule GnomeGarden.Browser.Error do
  @moduledoc "Structured browser-facade error."

  defexception [:operation, :reason, :message]

  def new(_operation, %__MODULE__{} = error), do: error

  def new(operation, reason) do
    %__MODULE__{
      operation: operation,
      reason: reason,
      message: "browser #{operation} failed: #{format_reason(reason)}"
    }
  end

  defp format_reason(%{message: message}) when is_binary(message), do: message
  defp format_reason(reason), do: inspect(reason)
end
