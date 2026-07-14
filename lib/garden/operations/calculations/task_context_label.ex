defmodule GnomeGarden.Operations.Calculations.TaskContextLabel do
  @moduledoc """
  Human-readable label for the record a task is about.

  Prefers operator-entered origin provenance, then falls back to the most
  specific loaded context link so API- or automation-created tasks never
  render as "Manual task".
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [
      :origin_label,
      :origin_resource,
      bid: [:title],
      pursuit: [:name],
      work_item: [:title],
      work_order: [:title],
      project: [:name],
      procurement_source: [:name],
      finding: [:title],
      signal: [:title],
      organization: [:name],
      person: [:first_name, :last_name],
      company_growth_initiative: [:title],
      company_qualification: [:name]
    ]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &label/1)
  end

  defp label(task) do
    task.origin_label ||
      related(task.company_qualification, :name) ||
      related(task.company_growth_initiative, :title) ||
      related(task.bid, :title) ||
      related(task.pursuit, :name) ||
      related(task.work_item, :title) ||
      related(task.work_order, :title) ||
      related(task.project, :name) ||
      related(task.procurement_source, :name) ||
      related(task.finding, :title) ||
      related(task.signal, :title) ||
      related(task.organization, :name) ||
      person_name(task.person) ||
      task.origin_resource
  end

  defp related(%Ash.NotLoaded{}, _field), do: nil
  defp related(nil, _field), do: nil
  defp related(record, field), do: Map.get(record, field)

  defp person_name(%Ash.NotLoaded{}), do: nil
  defp person_name(nil), do: nil

  defp person_name(person) do
    case [person.first_name, person.last_name] |> Enum.reject(&is_nil/1) |> Enum.join(" ") do
      "" -> nil
      name -> name
    end
  end
end
