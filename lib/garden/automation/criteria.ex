defmodule GnomeGarden.Automation.Criteria do
  @moduledoc """
  Typed field/op/value predicates evaluated against an event's data snapshot.

  Criteria are stored as JSONB on the rule: a list of
  `%{"field" => _, "op" => _, "value" => _}` maps combined with AND. Snapshot
  values are JSON-normalized (atoms and dates arrive as strings), so
  comparisons are done on the normalized forms.
  """

  @ops ~w(eq neq gt gte lt lte contains in is_nil not_nil)

  def ops, do: @ops

  def valid?(criteria) when is_list(criteria), do: Enum.all?(criteria, &valid_criterion?/1)
  def valid?(_criteria), do: false

  defp valid_criterion?(%{"field" => field, "op" => op} = criterion)
       when is_binary(field) and op in @ops do
    case op do
      op when op in ["is_nil", "not_nil"] -> true
      "in" -> is_list(criterion["value"])
      _op -> Map.has_key?(criterion, "value")
    end
  end

  defp valid_criterion?(_criterion), do: false

  def match?(criteria, data) when is_list(criteria) and is_map(data) do
    Enum.all?(criteria, fn criterion ->
      matches_criterion?(criterion, Map.get(data, criterion["field"]))
    end)
  end

  defp matches_criterion?(%{"op" => "is_nil"}, actual), do: is_nil(actual)
  defp matches_criterion?(%{"op" => "not_nil"}, actual), do: not is_nil(actual)
  defp matches_criterion?(%{"op" => "in", "value" => allowed}, actual), do: actual in allowed

  defp matches_criterion?(%{"op" => "contains", "value" => expected}, actual)
       when is_binary(actual) and is_binary(expected),
       do: String.contains?(String.downcase(actual), String.downcase(expected))

  defp matches_criterion?(%{"op" => "contains"}, _actual), do: false
  defp matches_criterion?(%{"op" => "eq", "value" => expected}, actual), do: actual == expected
  defp matches_criterion?(%{"op" => "neq", "value" => expected}, actual), do: actual != expected

  defp matches_criterion?(%{"op" => op, "value" => expected}, actual)
       when op in ["gt", "gte", "lt", "lte"] do
    with {:ok, left} <- number(actual),
         {:ok, right} <- number(expected) do
      case op do
        "gt" -> left > right
        "gte" -> left >= right
        "lt" -> left < right
        "lte" -> left <= right
      end
    else
      :error -> false
    end
  end

  defp matches_criterion?(_criterion, _actual), do: false

  defp number(value) when is_number(value), do: {:ok, value}

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _other -> :error
    end
  end

  defp number(_value), do: :error
end
