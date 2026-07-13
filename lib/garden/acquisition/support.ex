defmodule GnomeGarden.Acquisition.Support do
  @moduledoc false

  def transact(resources, function) do
    case Ash.transact(resources, function) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, error}} -> {:error, error}
      result -> result
    end
  end

  def errors(%{errors: errors} = error) when is_list(errors),
    do: [error | Enum.flat_map(errors, &errors/1)]

  def errors(errors) when is_list(errors), do: Enum.flat_map(errors, &errors/1)
  def errors(error), do: [error]
end
