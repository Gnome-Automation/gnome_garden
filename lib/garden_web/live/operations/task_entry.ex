defmodule GnomeGardenWeb.Operations.TaskEntry do
  @moduledoc """
  Builds prefilled "New Task" paths for record show pages.

  Callers pass the origin provenance and context link ids for their record;
  nil and empty values are dropped before encoding.
  """

  def new_task_path(attrs) when is_map(attrs) do
    query =
      attrs
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> URI.encode_query()

    "/operations/tasks/new?#{query}"
  end
end
