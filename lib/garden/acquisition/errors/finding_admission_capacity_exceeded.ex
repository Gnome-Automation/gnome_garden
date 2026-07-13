defmodule GnomeGarden.Acquisition.Errors.FindingAdmissionCapacityExceeded do
  @moduledoc false
  use Splode.Error, fields: [:field], class: :invalid

  def message(_error), do: "finding admission capacity exceeded"
end
