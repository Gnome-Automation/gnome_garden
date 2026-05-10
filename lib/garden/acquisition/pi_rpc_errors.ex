defmodule GnomeGarden.Acquisition.PiRpcErrors do
  @moduledoc """
  Renders Ash errors as the structured shape returned over the pi RPC channel.

  Each error becomes `%{type, field, message}`. Used by both the live
  controller and the dead-letter retry worker so they can log/respond
  identically.
  """

  @spec format(term()) :: [map()]
  def format(%Ash.Error.Invalid{errors: errors}), do: Enum.map(errors, &format_one/1)
  def format(%Ash.Error.Forbidden{errors: errors}), do: Enum.map(errors, &format_one/1)
  def format(%Ash.Error.Framework{errors: errors}), do: Enum.map(errors, &format_one/1)

  def format(error) when is_exception(error),
    do: [%{type: error_type(error), field: nil, message: Exception.message(error)}]

  def format(other), do: [%{type: "unknown", field: nil, message: inspect(other)}]

  defp format_one(%Ash.Error.Changes.InvalidAttribute{field: field, message: message}),
    do: %{type: "invalid_attribute", field: to_string(field), message: to_string(message)}

  defp format_one(%Ash.Error.Changes.InvalidArgument{field: field, message: message}),
    do: %{type: "invalid_argument", field: to_string(field), message: to_string(message)}

  defp format_one(%Ash.Error.Changes.Required{field: field}),
    do: %{type: "required", field: to_string(field), message: "is required"}

  defp format_one(%Ash.Error.Invalid.NoSuchInput{input: field}),
    do: %{type: "no_such_input", field: to_string(field), message: "unknown input"}

  defp format_one(error) when is_exception(error),
    do: %{type: error_type(error), field: nil, message: Exception.message(error)}

  defp format_one(other),
    do: %{type: "unknown", field: nil, message: inspect(other)}

  defp error_type(error) do
    error.__struct__
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
end
