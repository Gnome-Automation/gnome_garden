defmodule GnomeGarden.Acquisition.ReviewReasons do
  @moduledoc """
  Shared reason categories for acquisition review decisions.
  """

  @categories [
    {"Stale", "stale"},
    {"Wrong service", "wrong_service"},
    {"Wrong geography", "wrong_geography"},
    {"Too big", "too_big"},
    {"Too small", "too_small"},
    {"Duplicate", "duplicate"},
    {"Missing docs", "missing_docs"},
    {"Not enough info", "not_enough_info"}
  ]

  @category_values MapSet.new(Enum.map(@categories, fn {_label, value} -> value end))

  @spec options() :: [{String.t(), String.t()}]
  def options, do: @categories

  @spec valid?(term()) :: boolean()
  def valid?(value) when is_binary(value), do: MapSet.member?(@category_values, value)
  def valid?(value) when is_atom(value), do: value |> Atom.to_string() |> valid?()
  def valid?(_value), do: false

  @spec label(term()) :: String.t() | nil
  def label(value) when is_binary(value) do
    Enum.find_value(@categories, fn {label, category} ->
      if category == value, do: label
    end)
  end

  def label(value) when is_atom(value), do: value |> Atom.to_string() |> label()
  def label(_value), do: nil

  @spec normalize(term()) :: String.t() | nil
  def normalize(value) when is_binary(value) do
    value = String.trim(value)
    if valid?(value), do: value
  end

  def normalize(value) when is_atom(value), do: value |> Atom.to_string() |> normalize()
  def normalize(_value), do: nil
end
