defmodule GnomeGarden.Company.CapabilityGap do
  @moduledoc """
  Shared capability-gap vocabulary used by bid disposition, growth learning,
  and qualification-backed eligibility.

  These values are application invariants. Operator-entered evidence and
  qualification facts remain persisted data.
  """

  @definitions [
    missing_certification: %{
      label: "Missing certification",
      initiative_category: :certification,
      initiative_title: "Close certification gap",
      qualification_kinds: [:certification]
    },
    bond_capacity: %{
      label: "Bond capacity",
      initiative_category: :bonding,
      initiative_title: "Increase bonding capacity",
      qualification_kinds: [:bonding]
    },
    license_class: %{
      label: "License class",
      initiative_category: :licensing,
      initiative_title: "Expand license classifications",
      qualification_kinds: [:license]
    },
    insurance_limit: %{
      label: "Insurance limit",
      initiative_category: :insurance,
      initiative_title: "Raise insurance limits",
      qualification_kinds: [:insurance]
    },
    tech_platform: %{
      label: "Tech platform",
      initiative_category: :partner_program,
      initiative_title: "Add technology platform capability",
      qualification_kinds: [:partner_standing]
    }
  ]

  @values Keyword.keys(@definitions)
  @by_string Map.new(@values, &{Atom.to_string(&1), &1})

  def values, do: @values

  def options do
    Enum.map(@definitions, fn {value, definition} -> {definition.label, value} end)
  end

  def normalize(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(&split_value/1)
    |> Enum.map(&normalize_one/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def definition(value) do
    case normalize_one(value) do
      nil -> :error
      normalized -> Keyword.fetch(@definitions, normalized)
    end
  end

  def qualification_kinds(value) do
    case definition(value) do
      {:ok, definition} -> definition.qualification_kinds
      :error -> []
    end
  end

  defp split_value(value) when is_binary(value), do: String.split(value, [",", "\n"], trim: true)
  defp split_value(value), do: [value]

  defp normalize_one(value) when value in @values, do: value
  defp normalize_one(value) when is_binary(value), do: Map.get(@by_string, String.trim(value))
  defp normalize_one(_value), do: nil
end
