defmodule GnomeGarden.Agents.RunFailure do
  @moduledoc """
  Normalizes runtime failure details for persisted agent runs.
  """

  @categories [
    :authorization,
    :cancelled,
    :exception,
    :runtime_exit,
    :runtime_start,
    :timeout,
    :tool_error,
    :unknown,
    :validation
  ]

  @spec format(term()) :: String.t()
  def format(exception) when is_exception(exception), do: Exception.message(exception)
  def format({kind, reason}), do: "#{kind}: #{inspect(reason, pretty: true)}"
  def format(reason) when is_binary(reason), do: reason
  def format(reason), do: inspect(reason, pretty: true)

  @spec details(term(), keyword()) :: map()
  def details(reason, opts \\ []) do
    phase = Keyword.get(opts, :phase, :runtime)
    category = classify(reason, phase)

    %{
      "category" => Atom.to_string(category),
      "message" => format(reason),
      "phase" => Atom.to_string(phase),
      "retryable" => retryable_category?(category)
    }
    |> Map.merge(raw_details(reason))
  end

  @spec category(map() | nil, String.t() | nil) :: atom() | nil
  def category(details, error \\ nil)

  def category(details, error) when is_map(details) do
    details
    |> metadata_value(:category)
    |> normalize_category()
    |> case do
      nil -> category_from_text(error)
      category -> category
    end
  end

  def category(_details, error), do: category_from_text(error)

  @spec retryable?(map() | nil, String.t() | nil) :: boolean()
  def retryable?(details, error \\ nil)

  def retryable?(details, error) when is_map(details) do
    case metadata_value(details, :retryable) do
      retryable when is_boolean(retryable) -> retryable
      "true" -> true
      "false" -> false
      _ -> details |> category(error) |> retryable_category?()
    end
  end

  def retryable?(_details, error), do: error |> category_from_text() |> retryable_category?()

  @spec label(atom() | String.t() | nil) :: String.t() | nil
  def label(nil), do: nil
  def label(:authorization), do: "Authorization"
  def label(:cancelled), do: "Cancelled"
  def label(:exception), do: "Exception"
  def label(:runtime_exit), do: "Runtime Exit"
  def label(:runtime_start), do: "Runtime Startup"
  def label(:timeout), do: "Timed Out"
  def label(:tool_error), do: "Tool Error"
  def label(:validation), do: "Validation"
  def label(:unknown), do: "Unknown"
  def label(value), do: value |> normalize_category() |> label()

  @spec recovery_hint(atom() | String.t() | nil) :: String.t() | nil
  def recovery_hint(nil), do: nil

  def recovery_hint(:authorization),
    do: "Check the operator, service token, or external credential used by this deployment."

  def recovery_hint(:cancelled),
    do: "Cancelled by request. Rerun only if the work is still needed."

  def recovery_hint(:exception),
    do: "Open the persisted messages and app logs for the stack context before rerunning."

  def recovery_hint(:runtime_exit),
    do: "Check runtime process logs and restart the worker or sidecar if it exited unexpectedly."

  def recovery_hint(:runtime_start),
    do:
      "Verify the runtime can start, required API keys exist, and the deployment template is valid."

  def recovery_hint(:timeout),
    do: "Reduce the task scope or increase the deployment timeout before rerunning."

  def recovery_hint(:tool_error),
    do: "Inspect the tool result, repair the source or credential, then rerun the deployment."

  def recovery_hint(:validation),
    do: "Fix the deployment configuration or task input before rerunning."

  def recovery_hint(:unknown),
    do:
      "Inspect run messages, app logs, and related worker logs before deciding whether to rerun."

  def recovery_hint(value), do: value |> normalize_category() |> recovery_hint()

  defp classify(exception, phase) when is_exception(exception) do
    type = inspect(exception.__struct__)
    message = Exception.message(exception)

    cond do
      timeout_text?(message) or String.contains?(type, "Timeout") -> :timeout
      String.contains?(type, "Forbidden") -> :authorization
      String.contains?(type, "Invalid") -> :validation
      phase == :startup -> :runtime_start
      true -> :exception
    end
  end

  defp classify({:timeout, _reason}, _phase), do: :timeout
  defp classify({:exit, _reason}, _phase), do: :runtime_exit
  defp classify({:throw, reason}, phase), do: classify(reason, phase)
  defp classify({:error, reason}, phase), do: classify(reason, phase)

  defp classify({kind, reason}, phase) when kind in [:EXIT, :exit] do
    classify({:exit, reason}, phase)
  end

  defp classify(reason, phase) when is_binary(reason) do
    category_from_text(reason) || fallback_category(phase)
  end

  defp classify(_reason, phase), do: fallback_category(phase)

  defp fallback_category(:startup), do: :runtime_start
  defp fallback_category(_phase), do: :unknown

  defp raw_details(exception) when is_exception(exception) do
    %{"type" => inspect(exception.__struct__)}
  end

  defp raw_details({kind, reason}) do
    %{
      "kind" => inspect(kind),
      "reason" => inspect(reason, pretty: true)
    }
  end

  defp raw_details(_reason), do: %{}

  defp category_from_text(value) when is_binary(value) do
    value = String.downcase(value)

    cond do
      timeout_text?(value) -> :timeout
      String.contains?(value, "unauthorized") -> :authorization
      String.contains?(value, "forbidden") -> :authorization
      String.contains?(value, "credential") -> :authorization
      String.contains?(value, "invalid") -> :validation
      String.contains?(value, "validation") -> :validation
      String.contains?(value, "cancel") -> :cancelled
      String.contains?(value, "tool") -> :tool_error
      true -> nil
    end
  end

  defp category_from_text(_value), do: nil

  defp timeout_text?(value) when is_binary(value) do
    String.contains?(value, "timeout") or String.contains?(value, "timed out")
  end

  defp timeout_text?(_value), do: false

  defp retryable_category?(category) when category in [:timeout, :runtime_exit, :runtime_start],
    do: true

  defp retryable_category?(category) when category in [:exception, :tool_error, :unknown],
    do: true

  defp retryable_category?(_category), do: false

  defp normalize_category(value) when is_atom(value) and value in @categories, do: value

  defp normalize_category(value) when is_binary(value) do
    value =
      value
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(@categories, &(Atom.to_string(&1) == value))
  end

  defp normalize_category(_value), do: nil

  defp metadata_value(metadata, key) do
    Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key))
  end
end
