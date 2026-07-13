defmodule GnomeGarden.Acquisition.Errors.ProviderCapacityExceeded do
  @moduledoc false
  use Splode.Error, fields: [:field], class: :invalid

  def message(_error), do: "provider budget exceeded"
end
